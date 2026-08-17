import Foundation
import ProctorCore

// proctor_guest: VM lifecycle, impure half.
//
// A peer of the iOS lane behind the same Proctor surface. The decisions —
// how a listing decodes, what a platform means, which witness tier a guest
// carries — are pure and live in ProctorCore/GuestInventory.swift. This file
// runs the adapters, holds the injected providers, and wires the audit trail.
//
// Three things about it differ from every other lane, and each is deliberate:
//
// **No exclusive turn.** Starting or stopping a guest posts no events into
// the Mac's input system and raises no window, so taking the machine's turn
// from RunQueue would block Mac runs for contention that does not exist.
//
// **No implicit start.** Powering on is stateful and takes tens of seconds.
// Folding that into a later attach would make the timing meaningless and
// the audit record ambiguous. start is explicit.
//
// **Nothing provisions.** A guest that does not already exist is refused.
// Creating one, granting TCC inside it, and cloning the granted image are
// things a person does with the provider's own CLI.

extension Session {

    // MARK: - Entry point

    func guest(action: String, guest: String?, provider: String?,
               newName: String?) async throws -> JSONValue {
        switch action {
        case "list":
            return try await guestList()
        case "status":
            return try await guestStatus(guest: try requireGuest(guest),
                                         provider: provider)
        case "start":
            return try await guestMutate(action: "start",
                                         tool: AuditTool.guestStart,
                                         guest: try requireGuest(guest),
                                         provider: provider)
        case "stop":
            return try await guestMutate(action: "stop",
                                         tool: AuditTool.guestStop,
                                         guest: try requireGuest(guest),
                                         provider: provider)
        case "clone":
            guard let newName, !newName.isEmpty else {
                throw AgentError(code: .invalidArguments,
                                 message: "proctor_guest action \"clone\" requires newName",
                                 remedy: "Pass the name of the copy. The source is untouched.")
            }
            return try await guestClone(guest: try requireGuest(guest),
                                        provider: provider, newName: newName)
        default:
            throw AgentError(code: .invalidArguments,
                             message: "unknown guest action \(action.debugDescription)",
                             remedy: "Use list, status, start, stop or clone.")
        }
    }

    private func requireGuest(_ guest: String?) throws -> String {
        guard let guest, !guest.isEmpty else {
            throw AgentError(code: .invalidArguments,
                             message: "proctor_guest needs a guest for this action",
                             remedy: "Pass a gst- handle from action \"list\", or the name you type at lume or prlctl.")
        }
        return guest
    }

    // MARK: - list

    private func guestList() async throws -> JSONValue {
        let providers = try resolvedGuestProviders()
        var records: [GuestRecord] = []
        var errors: [String] = []
        for provider in providers {
            do {
                records.append(contentsOf: try await provider.list())
            } catch {
                errors.append("\(provider.id): \(describeGuestError(error))")
            }
        }
        records.sort {
            ($0.provider, $0.name) < ($1.provider, $1.name)
        }
        var out: [String: JSONValue] = [
            "guests": .array(try records.map { try JSONValue.encode($0) }),
            "count": .number(Double(records.count)),
            "capabilities": Session.guestCapabilities,
            "note": .string(
                "These are guest handles, not window handles. proctor_snapshot, proctor_find, "
                + "proctor_assert, proctor_act and proctor_capture do not work against one — a "
                + "guest is a different machine. Nothing here provisions a guest that does not "
                + "already exist.")
        ]
        if !errors.isEmpty {
            out["providerErrors"] = .array(errors.map(JSONValue.string))
        }
        return .object(out)
    }

    /// What this lane can and cannot do, stated once and carried on every listing.
    ///
    /// The ceiling belongs in the result rather than only in the tool description,
    /// because a model that reads a guest handle and reaches for a snapshot has
    /// already stopped reading descriptions.
    static let guestCapabilities: JSONValue = .object([
        "available": .array([
            .string("list, status, start, stop and clone (proctor_guest)"),
            .string("a macOS guest running a full Proctor is a native witness"),
            .string("a Linux or Windows guest is delegated: actuation and screenshots only")
        ]),
        "unavailable": .array([
            .string("window handles, the accessibility tree and geometry on this Mac"),
            .string("provisioning a guest that does not already exist"),
            .string("granting Accessibility or Screen Recording inside the guest")
        ]),
        "note": .string(
            "A person grants Accessibility and Screen Recording once inside the guest's GUI "
            + "session, then clone reproduces the grants. Tahoe guests currently render no "
            + "application windows (trycua/cua #870, Apple FB21748086); verify against Sequoia.")
    ])

    // MARK: - status / start / stop / clone

    private func guestStatus(guest: String, provider: String?) async throws -> JSONValue {
        let record = try await resolveGuest(guest, provider: provider)
        return .object([
            "guest": try JSONValue.encode(record),
            "machine": try JSONValue.encode(record.machine),
            "capabilities": Session.guestCapabilities
        ])
    }

    private func guestMutate(action: String, tool: String, guest: String,
                             provider: String?) async throws -> JSONValue {
        let (adapter, record) = try await resolveGuestWithProvider(guest, provider: provider)
        let context = AuditContext(tool: tool, app: nil,
                                   bundleId: "guest:\(record.provider):\(record.name)",
                                   window: nil)
        do {
            let after: GuestRecord
            switch action {
            case "start": after = try await adapter.start(name: record.name)
            case "stop":  after = try await adapter.stop(name: record.name)
            default:
                throw AgentError(code: .invalidArguments,
                                 message: "unknown guest mutation \(action)")
            }
            auditSink(AuditRecord(timestamp: clock(), tool: context.tool,
                                  bundleId: context.bundleId, kind: action,
                                  outcome: AuditRecord.Outcome.ok,
                                  reason: "\(record.name) is \(after.state)"))
            return .object([
                "guest": try JSONValue.encode(after),
                "machine": try JSONValue.encode(after.machine),
                "changed": .bool(after.state != record.state)
            ])
        } catch {
            let reason = describeGuestError(error)
            auditSink(AuditRecord(timestamp: clock(), tool: context.tool,
                                  bundleId: context.bundleId, kind: action,
                                  outcome: AuditRecord.Outcome.failed, reason: reason))
            throw mapGuestError(error, action: action, name: record.name)
        }
    }

    private func guestClone(guest: String, provider: String?,
                            newName: String) async throws -> JSONValue {
        let (adapter, record) = try await resolveGuestWithProvider(guest, provider: provider)
        let context = AuditContext(tool: AuditTool.guestClone, app: nil,
                                   bundleId: "guest:\(record.provider):\(record.name)",
                                   window: nil)
        do {
            let copy = try await adapter.clone(name: record.name, as: newName)
            auditSink(AuditRecord(timestamp: clock(), tool: context.tool,
                                  bundleId: context.bundleId, kind: "clone",
                                  outcome: AuditRecord.Outcome.ok,
                                  reason: "cloned \(record.name) as \(copy.name)"))
            return .object([
                "guest": try JSONValue.encode(copy),
                "source": try JSONValue.encode(record),
                "machine": try JSONValue.encode(copy.machine),
                "note": .string(
                    "The copy is a new guest. If the source had Accessibility and Screen "
                    + "Recording granted inside its GUI session, this clone carries them; "
                    + "otherwise grant them once in the copy before driving it.")
            ])
        } catch {
            let reason = describeGuestError(error)
            auditSink(AuditRecord(timestamp: clock(), tool: context.tool,
                                  bundleId: context.bundleId, kind: "clone",
                                  outcome: AuditRecord.Outcome.failed, reason: reason))
            throw mapGuestError(error, action: "clone", name: record.name)
        }
    }

    // MARK: - Resolution

    /// Resolve a caller's guest reference: a `gst-` handle, or a name, optionally
    /// scoped to a provider. Ambiguity is an error naming the candidates rather
    /// than a guess, because guessing which guest to start is how a campaign
    /// silently takes the wrong machine.
    func resolveGuest(_ reference: String, provider: String?) async throws -> GuestRecord {
        try await resolveGuestWithProvider(reference, provider: provider).1
    }

    private func resolveGuestWithProvider(_ reference: String, provider: String?)
        async throws -> (any GuestProvider, GuestRecord) {
        let providers = try resolvedGuestProviders()
        let scoped = try scopedProviders(providers, named: provider)
        var matches: [(any GuestProvider, GuestRecord)] = []
        var errors: [String] = []
        for adapter in scoped {
            do {
                let records = try await adapter.list()
                for record in records where recordMatches(record, reference: reference) {
                    matches.append((adapter, record))
                }
            } catch {
                errors.append("\(adapter.id): \(describeGuestError(error))")
            }
        }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty {
            var remedy = "Call proctor_guest action \"list\" and pass a gst- handle or a name from it."
            if !errors.isEmpty {
                remedy += " Providers that failed: \(errors.joined(separator: "; "))."
            }
            throw AgentError(code: .appNotFound,
                             message: "no guest matches \(reference.debugDescription)",
                             remedy: remedy)
        }
        let names = matches.map { "\($0.1.provider):\($0.1.name)" }.joined(separator: ", ")
        throw AgentError(
            code: .invalidArguments,
            message: "\(matches.count) guests match \(reference.debugDescription): \(names)",
            remedy: "Pass provider to pick one, or use the gst- handle from action \"list\", which is unique.")
    }

    private func recordMatches(_ record: GuestRecord, reference: String) -> Bool {
        if record.handle == reference { return true }
        if record.name == reference { return true }
        if let identifier = record.identifier, identifier == reference { return true }
        return false
    }

    private func scopedProviders(_ providers: [any GuestProvider],
                                 named provider: String?) throws -> [any GuestProvider] {
        guard let provider, !provider.isEmpty else { return providers }
        let scoped = providers.filter { $0.id == provider }
        guard !scoped.isEmpty else {
            throw AgentError(
                code: .invalidArguments,
                message: "unknown guest provider \(provider.debugDescription)",
                remedy: "Use lume or prlctl, matching a provider proctor_doctor reports as present.")
        }
        return scoped
    }

    // MARK: - Providers

    /// Injected adapters, or the live ones built from whatever the filesystem
    /// probe found. Empty-and-uninjected is a missing-tool refusal rather than
    /// an empty listing, because "neither CLI is here" and "both CLIs see no
    /// guests" are different facts.
    func resolvedGuestProviders() throws -> [any GuestProvider] {
        if let injected = injectedGuestProviders { return injected }
        var out: [any GuestProvider] = []
        let lume = tools.lume.presence()
        if lume.available, let path = lume.path {
            out.append(LumeProvider(executable: path))
        }
        let prlctl = tools.prlctl.presence()
        if prlctl.available, let path = prlctl.path {
            out.append(PrlctlProvider(executable: path))
        }
        guard !out.isEmpty else {
            throw AgentError(
                code: .notImplemented,
                message: "Neither lume nor prlctl is anywhere Proctor can see, so there is no guest lane.",
                remedy: "Install lume (https://github.com/trycua/lume) or Parallels Desktop. "
                      + "proctor_doctor reports every path it checked. Proctor will never install either.")
        }
        return out
    }

    func setGuestProviders(_ providers: [any GuestProvider]) {
        injectedGuestProviders = providers
    }

    private func describeGuestError(_ error: Error) -> String {
        if let error = error as? GuestProviderError {
            switch error {
            case .binaryMissing(let tool):
                return "\(tool) is not on this machine"
            case .commandFailed(_, let action, let exit, let stderr):
                let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return tail.isEmpty ? "\(action) exited \(exit)" : tail
            case .unparseable(_, let reason):
                return reason
            case .notFound(let name, let provider):
                return "\(provider) has no guest named \(name)"
            case .timedOut(_, let action):
                return "\(action) timed out"
            case .truncated(_, let action):
                return "\(action) output was truncated"
            }
        }
        return error.localizedDescription
    }

    private func mapGuestError(_ error: Error, action: String, name: String) -> AgentError {
        if let error = error as? AgentError { return error }
        return AgentError(code: .actionFailed,
                          message: "\(action) of \(name) failed: \(describeGuestError(error))",
                          remedy: "Check the guest with proctor_guest action \"status\". Nothing else was changed.")
    }
}
