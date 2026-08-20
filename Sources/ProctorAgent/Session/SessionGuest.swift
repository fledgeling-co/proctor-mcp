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
               newName: String?, host: String? = nil, user: String? = nil,
               remoteSocket: String? = nil, localSocket: String? = nil) async throws -> JSONValue {
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
        case "reach":
            return try await guestReach(guest: try requireGuest(guest),
                                        provider: provider, host: host,
                                        user: user, remoteSocket: remoteSocket,
                                        localSocket: localSocket)
        case "attach":
            return try await guestAttach(guest: try requireGuest(guest),
                                         provider: provider, localSocket: localSocket)
        case "detach":
            return try await guestDetach()
        default:
            throw AgentError(code: .invalidArguments,
                             message: "unknown guest action \(action.debugDescription)",
                             remedy: "Use list, status, start, stop, clone, reach, attach or detach.")
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
            .string("list, status, start, stop, clone and reach (proctor_guest)"),
            .string("a macOS guest running a full Proctor is a native witness"),
            .string("a Linux or Windows guest is delegated: actuation and screenshots only"),
            .string("reach describes an SSH StreamLocal tunnel onto a native guest's socket")
        ]),
        "unavailable": .array([
            .string("window handles, the accessibility tree and geometry on this Mac"),
            .string("provisioning a guest that does not already exist"),
            .string("granting Accessibility or Screen Recording inside the guest"),
            .string("opening the SSH tunnel — a person types that, Proctor does not")
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

    private func guestReach(guest: String, provider: String?, host: String?,
                            user: String?, remoteSocket: String?,
                            localSocket: String?) async throws -> JSONValue {
        let record = try await resolveGuest(guest, provider: provider)
        guard let host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError(code: .invalidArguments,
                             message: "proctor_guest action \"reach\" requires host",
                             remedy: "Pass a hostname, a Tailscale name, or the guest's IP. "
                                   + "Proctor does not open the tunnel.")
        }
        switch GuestReach.decide(machine: record.machine, host: host, user: user,
                                 remoteSocket: remoteSocket, localSocket: localSocket,
                                 handle: record.handle, home: NSHomeDirectory()) {
        case .refused(let why):
            throw AgentError(code: .notImplemented, message: why,
                             remedy: "Delegated guests go through Cua. A macOS guest running "
                                   + "a full Proctor is the one this path reaches.")
        case .recipe(let recipe):
            return .object([
                "guest": try JSONValue.encode(record),
                "machine": try JSONValue.encode(record.machine),
                "reach": try JSONValue.encode(recipe)
            ])
        }
    }

    private func guestClone(guest: String, provider: String?,
                            newName: String) async throws -> JSONValue {
        let (adapter, record) = try await resolveGuestWithProvider(guest, provider: provider)
        // PRO-0076. Cloning a stopped guest touches no slot; cloning one that a
        // session is attached to is not something the providers agree about, and
        // a copy taken from underneath a live attachment is a copy of a machine
        // mid-run. Refused with the reason rather than attempted.
        if let holder = guestAttachments.values.first(where: {
            $0.slotHeld && $0.provider == record.provider && $0.name == record.name
        }) {
            throw AgentError(
                code: .invalidArguments,
                message: "\(record.name) is attached by a session right now and holds a guest "
                       + "slot, so it was not cloned.",
                remedy: "Detach from it first with proctor_guest action \"detach\", or clone a "
                      + "guest nothing is driving. The providers do not agree about what cloning "
                      + "a running guest produces, and a copy taken from under a live attachment "
                      + "is a copy of a machine mid-run. It is still \(holder.machine.line).")
        }
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
                remedy: "Use lume, prlctl or tart, matching a provider proctor_doctor reports as present.")
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
        let tart = tools.tart.presence()
        if tart.available, let path = tart.path {
            out.append(TartProvider(executable: path))
        }
        guard !out.isEmpty else {
            throw AgentError(
                code: .notImplemented,
                message: "None of lume, prlctl or tart is anywhere Proctor can see, so there is no guest lane.",
                remedy: "Install lume (https://github.com/trycua/lume), tart (https://tart.run) or "
                      + "Parallels Desktop. proctor_doctor reports every path it checked. Proctor "
                      + "will never install any of them.")
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

// MARK: - PRO-0076: forwarding a call into an attached guest

extension Session {

    /// The guest's answer, or nil when this caller is not attached and the call
    /// is ordinary host work.
    ///
    /// **A2 lives here.** A caller attached to a guest never falls through to the
    /// host: either the guest answers, or the call is refused with the guest
    /// named. There is deliberately no branch that runs the batch on this Mac
    /// instead — PRO-0051 rejected that fallback because it "hands back a verdict
    /// that looks fine and measures the plumbing", and the absence of the branch
    /// is what makes the guarantee real rather than asserted.
    func forwardToGuestIfAttached(_ request: AgentRequest) async throws -> JSONValue? {
        guard let attachment = currentAttachment else { return nil }
        // The host keeps the tools that answer about THIS Mac: the pool, the
        // trail, the health report, the surfaces a person is looking at. A
        // denylist, so a tool added later forwards by default rather than
        // quietly running here. See `GuestForwarding`.
        guard GuestForwarding.shouldForward(request.tool) else { return nil }

        guard let link = guestLinks[SessionIdentity.current.key] else {
            throw GuestLinkRefusal.unreachable(machine: attachment.machine,
                                               socket: attachment.localSocket,
                                               underlying: "no link is open for this session")
        }

        let response: AgentResponse
        do {
            response = try await link.send(request)
        } catch {
            // The send failed, and the two reasons want different answers.
            //
            // A11 first: ask the provider whether the guest is still there. A
            // guest stopped from outside, a host that slept, a provider that
            // died — those are a DISAPPEARANCE, and saying "the tunnel is not
            // answering" would send the reader to check an SSH forward that is
            // fine. `guestVanishedError` releases the slot and names it.
            if let vanished = await guestVanishedError() { throw vanished }

            // Otherwise the guest is up and the link is not: the tunnel dropped.
            // Release what this attachment holds and refuse, rather than leaving
            // a slot held by nothing or running the steps here (A2).
            let reason = (error as? AgentError)?.message ?? "\(error)"
            await releaseGuestAttachment(reason: "The link failed: \(reason)")
            throw GuestLinkRefusal.unreachable(machine: attachment.machine,
                                               socket: attachment.localSocket,
                                               underlying: reason)
        }

        touchGuestAttachment()

        if let error = response.error { throw error }
        guard let result = response.result else {
            throw GuestLinkRefusal.unreachable(machine: attachment.machine,
                                               socket: attachment.localSocket,
                                               underlying: "the guest returned neither a result nor an error")
        }
        // Window ids that came back from inside the guest are recorded against
        // this session, so A4 can refuse them everywhere else.
        recordGuestMintedHandles(in: result, machine: attachment.machine)
        return result
    }

    /// Note that this attachment was used, for the idle ceiling.
    func touchGuestAttachment() {
        guestAttachments[SessionIdentity.current.key]?.lastUsedAt = clock()
    }

    /// Walk a guest's reply for window ids and remember who minted them.
    ///
    /// Ids are read out of the payload rather than being asked for, because the
    /// guest's Proctor is an ordinary Proctor and does not know it is being
    /// forwarded to — which is the property that keeps this side from having to
    /// re-implement its surface.
    func recordGuestMintedHandles(in value: JSONValue, machine: Machine) {
        let session = SessionIdentity.current.key
        let origin = GuestHandleScope.Origin.guest(session: session, machine: machine.line)
        func walk(_ node: JSONValue) {
            switch node {
            case .object(let fields):
                for (key, child) in fields {
                    if key == "id" || key == "window", case .string(let id) = child,
                       id.hasPrefix("win:") {
                        guestMintedHandles[id] = origin
                    }
                    walk(child)
                }
            case .array(let items):
                for item in items { walk(item) }
            default:
                break
            }
        }
        walk(value)
    }
}

// MARK: - PRO-0076: releasing what an attachment holds

extension Session {

    /// Drop this caller's attachment and give its slot back. **Idempotent.**
    ///
    /// Five things can release one attachment — an explicit detach, a link that
    /// failed, a guest that vanished, a peer process that went away, and the
    /// idle ceiling — and two of them firing on the same attachment must
    /// decrement the pool exactly once. A second decrement admits two waiters
    /// where one slot freed, and on the waiter side resuming a continuation
    /// twice traps the process. `slotHeld` on the attachment is the latch that
    /// makes the second call a no-op.
    ///
    /// `stopGuest` is honoured only when THIS agent started the guest. A guest a
    /// person started, or one another session holds, is never stopped to free a
    /// slot: stopping a running VM discards its state, and a scheduler that may
    /// do that can destroy work nobody asked it to risk (A10).
    @discardableResult
    func releaseGuestAttachment(reason: String?, stopGuest: Bool = false,
                                session: String? = nil) async -> Bool {
        let key = session ?? SessionIdentity.current.key
        guard var attachment = guestAttachments[key], attachment.slotHeld else {
            // Already released, or never attached. Clean up any remnants and say
            // nothing happened.
            guestAttachments.removeValue(forKey: key)
            if let link = guestLinks.removeValue(forKey: key) { await link.close() }
            guestTickets.removeValue(forKey: key)
            return false
        }

        attachment.slotHeld = false
        guestAttachments[key] = attachment

        if stopGuest && attachment.startedByThisAgent {
            // Through the same audited path a person's stop takes, so A9's
            // "both stay gated and recorded" holds for the pool's own stop.
            _ = try? await stopGuestForRelease(attachment)
        }

        if let link = guestLinks.removeValue(forKey: key) { await link.close() }
        if let ticket = guestTickets.removeValue(forKey: key) {
            await runScheduler.release(ticket)
        }
        guestAttachments.removeValue(forKey: key)
        // Handles minted inside that guest by this session stop resolving with
        // it, so a stale id is a named refusal rather than a lookup that misses.
        guestMintedHandles = guestMintedHandles.filter { _, origin in
            if case .guest(let owner, _) = origin { return owner != key }
            return true
        }
        if let reason, !reason.isEmpty {
            auditSink(AuditRecord(timestamp: clock(), tool: AuditTool.guestDetach,
                                  bundleId: "guest:\(attachment.provider):\(attachment.name)",
                                  kind: "release", outcome: AuditRecord.Outcome.ok,
                                  reason: reason))
        }
        return true
    }

    private func stopGuestForRelease(_ attachment: GuestAttachment) async throws -> GuestRecord? {
        let providers = try resolvedGuestProviders()
        guard let adapter = providers.first(where: { $0.id == attachment.provider }) else {
            return nil
        }
        do {
            let after = try await adapter.stop(name: attachment.name)
            auditSink(AuditRecord(timestamp: clock(), tool: AuditTool.guestStop,
                                  bundleId: "guest:\(attachment.provider):\(attachment.name)",
                                  kind: "stop", outcome: AuditRecord.Outcome.ok,
                                  reason: "\(attachment.name) is \(after.state); "
                                        + "this agent started it"))
            return after
        } catch {
            auditSink(AuditRecord(timestamp: clock(), tool: AuditTool.guestStop,
                                  bundleId: "guest:\(attachment.provider):\(attachment.name)",
                                  kind: "stop", outcome: AuditRecord.Outcome.failed,
                                  reason: "\(error)"))
            return nil
        }
    }
}

// MARK: - PRO-0076: attach and detach

extension Session {

    /// Attach this session to a guest, so its steps execute inside that guest.
    ///
    /// The order is deliberate and each step is placed where it is for a reason:
    ///
    ///   1. resolve the guest, and refuse one this path cannot drive;
    ///   2. TAKE THE SLOT, before anything is started. Booting first and counting
    ///      after lets a second attach arriving during the boot start a third
    ///      macOS guest before either has been counted;
    ///   3. start the guest if it is not up (A9), through the audited path;
    ///   4. open the link onto the socket a PERSON forwarded, and probe it.
    ///
    /// Any failure after step 2 gives the slot back, so a guest that would not
    /// boot or would not answer does not leave a slot held by nothing.
    func guestAttach(guest: String, provider: String?,
                     localSocket: String?) async throws -> JSONValue {
        let key = SessionIdentity.current.key

        if let existing = guestAttachments[key] {
            throw AgentError(
                code: .invalidArguments,
                message: "this session is already attached to \(existing.machine.line)",
                remedy: "Call proctor_guest action \"detach\" first. One session drives one "
                      + "machine at a time, so that the machine a result is about is never in "
                      + "question.")
        }

        // Reclaim before admitting, so a slot held by a session that went away
        // is free for this one rather than making it wait on nothing. Placed at
        // the moment a slot is actually wanted: there is no timer, and this is
        // the only point at which the answer changes anything.
        await reclaimAbandonedAttachments()

        let record = try await resolveGuest(guest, provider: provider)
        try requireAttachable(record)
        let platform = try requirePlatform(record)
        let machine = GuestAttachment.machine(for: record)

        // 2. The slot, before the boot. Goes through the same `acquire` every
        //    other lane uses, so the per-session waiting cap and the wait
        //    ceiling bind it with no new switch (A8).
        let ticket = try await runScheduler.acquire(
            lanes: LaneDemand.forGuest(provider: record.provider, name: record.name,
                                       platform: platform),
            identity: SessionIdentity.current,
            summary: "Attach · \(record.name)")

        var startedHere = false
        do {
            // 3. Admission may start the named guest (A9), through the gated and
            //    audited path rather than a raw adapter call.
            if !record.running {
                _ = try await guestMutate(action: "start", tool: AuditTool.guestStart,
                                          guest: record.name, provider: record.provider)
                startedHere = true
            }

            // 4. The link. Proctor does not open the tunnel — a person does, and
            //    `reach` describes it. This connects to the end of one.
            let socket = (localSocket?.isEmpty == false)
                ? localSocket!
                : GuestReach.defaultLocalSocket(handle: record.handle, home: NSHomeDirectory())
            let link = injectedGuestLink.map { $0(socket) } ?? SocketGuestLink(localSocket: socket)
            do {
                try await link.probe()
            } catch {
                throw GuestLinkRefusal.unreachable(
                    machine: machine, socket: socket,
                    underlying: (error as? AgentError)?.message ?? "\(error)")
            }

            let attachment = GuestAttachment(
                machine: machine, handle: record.handle, provider: record.provider,
                name: record.name, localSocket: socket,
                startedByThisAgent: startedHere, attachedAt: clock())
            guestAttachments[key] = attachment
            guestLinks[key] = link
            guestTickets[key] = ticket

            auditSink(AuditRecord(timestamp: clock(), tool: AuditTool.guestAttach,
                                  bundleId: "guest:\(record.provider):\(record.name)",
                                  kind: "attach", outcome: AuditRecord.Outcome.ok,
                                  reason: "\(record.name) · \(machine.tier.rawValue) · "
                                        + (startedHere ? "started here" : "already running")))

            return .object([
                "attached": .bool(true),
                "guest": try JSONValue.encode(record),
                "machine": try JSONValue.encode(machine),
                "localSocket": .string(socket),
                "startedByProctor": .bool(startedHere),
                "pool": await poolStatus(),
                "note": .string(
                    "Every tool call from this session now runs inside \(record.name). The "
                    + "Proctor there holds that machine's Accessibility and Screen Recording "
                    + "grants and talks to its window server; this Mac actuates nothing on its "
                    + "behalf. proctor_guest, proctor_doctor, proctor_policy and the history and "
                    + "queue verbs still answer about this Mac. Call action \"detach\" to drive "
                    + "this Mac again.")
            ])
        } catch {
            // Give the slot back on every failure after taking it, and stop the
            // guest only if this call is what started it.
            if startedHere {
                let attachment = GuestAttachment(
                    machine: machine, handle: record.handle, provider: record.provider,
                    name: record.name, localSocket: "", startedByThisAgent: true,
                    attachedAt: clock())
                _ = try? await stopGuestAfterFailedAttach(attachment)
            }
            await runScheduler.release(ticket)
            auditSink(AuditRecord(timestamp: clock(), tool: AuditTool.guestAttach,
                                  bundleId: "guest:\(record.provider):\(record.name)",
                                  kind: "attach", outcome: AuditRecord.Outcome.failed,
                                  reason: (error as? AgentError)?.message ?? "\(error)"))
            throw error
        }
    }

    /// Let go, and stop the guest only if this agent started it (A9 / A10).
    func guestDetach() async throws -> JSONValue {
        guard let attachment = currentAttachment else {
            throw AgentError(
                code: .invalidArguments,
                message: "this session is not attached to a guest",
                remedy: "Nothing to detach. proctor_guest action \"list\" shows the guests this "
                      + "Mac can reach.")
        }
        let stopped = attachment.startedByThisAgent
        await releaseGuestAttachment(reason: "detached by the session that attached it",
                                     stopGuest: true)
        return .object([
            "attached": .bool(false),
            "machine": try JSONValue.encode(attachment.machine),
            "guestStopped": .bool(stopped),
            "pool": await poolStatus(),
            "note": .string(Self.detachNote(name: attachment.name, stopped: stopped))
        ])
    }

    /// Refuse a guest this path cannot drive, before a slot is taken for it.
    private func requireAttachable(_ record: GuestRecord) throws {
        if let why = GuestReach.cannotReach(record.machine) {
            throw AgentError(
                code: .notImplemented, message: why,
                remedy: "Delegated guests go through Cua. A macOS guest running a full Proctor "
                      + "is the one this path attaches to.")
        }
    }

    /// The platform, or a refusal.
    ///
    /// **An unread platform is refused rather than admitted, and the direction
    /// matters.** A guest whose provider did not say which OS it runs maps to the
    /// delegated tier, which is fail-CLOSED for actuation — but it is fail-OPEN
    /// for the cap, because a delegated guest is not counted against the macOS
    /// pool. A macOS VM admitted that way would boot outside Apple's two without
    /// anything noticing. So the missing fact is an error, not a default.
    private func requirePlatform(_ record: GuestRecord) throws -> MachinePlatform {
        guard let platform = record.platform else {
            throw AgentError(
                code: .invalidArguments,
                message: "\(record.provider) did not say which operating system \(record.name) "
                       + "runs, so Proctor cannot tell which guest pool it belongs to and will "
                       + "not attach to it.",
                remedy: "At most two macOS guests may run on this host, which is Apple's rule, "
                      + "and a guest of unknown platform would sit outside that count. Check the "
                      + "guest reads a platform in proctor_guest action \"status\". Proctor will "
                      + "not infer one from the guest's name, because a name is not a fact about "
                      + "what is installed.")
        }
        return platform
    }

    private func stopGuestAfterFailedAttach(_ attachment: GuestAttachment) async throws {
        let providers = try resolvedGuestProviders()
        guard let adapter = providers.first(where: { $0.id == attachment.provider }) else { return }
        _ = try? await adapter.stop(name: attachment.name)
        auditSink(AuditRecord(timestamp: clock(), tool: AuditTool.guestStop,
                              bundleId: "guest:\(attachment.provider):\(attachment.name)",
                              kind: "stop", outcome: AuditRecord.Outcome.ok,
                              reason: "the attach that started \(attachment.name) failed, so it "
                                    + "was stopped again"))
    }
}

// MARK: - PRO-0076 A12: what the pool looks like from outside

extension Session {

    private static func detachNote(name: String, stopped: Bool) -> String {
        if stopped {
            return "\(name) was started by Proctor for this attachment, so it was stopped again "
                 + "and its slot released."
        }
        return "\(name) was already running when this session attached, so it was left running. "
             + "Proctor only stops a guest it started."
    }

    /// The guest pool, for `proctor_doctor` and for the attach/detach replies.
    ///
    /// **Built from the scheduler's own snapshot, which is host state, so this
    /// costs no VM.** A12 keeps the rule the guest lane has had since PRO-0058:
    /// a health check locates the provider CLIs by reading the filesystem and
    /// executes none of them. Nothing in here runs `lume`, `prlctl` or `tart`.
    func poolStatus() async -> JSONValue {
        let snapshot = await runScheduler.snapshot()
        let occupancy = RunQueuePlan.occupancy(of: snapshot.active)

        var pools: [JSONValue] = []
        for platform in [MachinePlatform.macos, .linux, .windows] {
            let key = GuestPool.key(for: platform)
            let capacity = GuestPool.capacity(for: platform)
            let held = occupancy[key] ?? 0
            // A pool nobody is using and nobody is waiting for is not reported,
            // so the common case reads as one line about macOS rather than three
            // about platforms this Mac has no guests of.
            let waiting = snapshot.waiting.filter { $0.lanes.contains(.pool(key)) }.count
            guard held > 0 || waiting > 0 || platform == .macos else { continue }
            pools.append(.object([
                "platform": .string(key),
                "capacity": capacity == GuestPool.unbounded ? .null : .number(Double(capacity)),
                "held": .number(Double(held)),
                "waiting": .number(Double(waiting)),
                "reason": .string(platform == .macos
                    ? "macOS on Apple silicon permits at most two concurrently running macOS "
                    + "guests per host. This is Apple's rule, not a Proctor setting."
                    : "No platform rule is known here, so Proctor does not cap this pool; the "
                    + "provider is the limit.")
            ]))
        }

        // Which sessions hold which guests. The join a person needs to answer
        // "who is holding the machine I want" without reading two reports.
        var holders: [JSONValue] = []
        for run in snapshot.active {
            for lane in run.lanes {
                guard case .guest(let guestKey) = lane else { continue }
                holders.append(.object([
                    "guest": .string(guestKey),
                    "session": .string(run.identity.label),
                    "heldForSeconds": .number((Date().timeIntervalSince1970 - run.since).rounded())
                ]))
            }
        }

        var waitingFor: [JSONValue] = []
        for run in snapshot.waiting {
            for lane in run.lanes {
                guard case .guest(let guestKey) = lane else { continue }
                waitingFor.append(.object([
                    "guest": .string(guestKey),
                    "session": .string(run.identity.label)
                ]))
            }
        }

        return .object([
            "pools": .array(pools),
            "held": .array(holders),
            "waiting": .array(waitingFor),
            "note": .string(
                "Counted from Proctor's own scheduler, which is state on this Mac, so reading "
                + "this runs no provider and starts no VM. A guest a person started outside "
                + "Proctor is not in this count and is never stopped to free a slot.")
        ])
    }
}

// MARK: - PRO-0076 A11 / D4: when a slot comes back without anybody asking

extension Session {

    /// How long an attachment may sit unused before its slot is reclaimed.
    ///
    /// **Deliberately not the queue's wait limit.** `RunQueuePlan.waitLimit` is
    /// 45 seconds because a host cuts a tool call off around a minute, and a
    /// waiting call has to fail inside that. Reusing it here would tear down a
    /// healthy attachment in the middle of a campaign. This bounds a HOLDER,
    /// which is a different question with a different right answer.
    static let attachIdleLimitEnv = "PROCTOR_GUEST_ATTACH_IDLE"
    static let defaultAttachIdleLimit: TimeInterval = 30 * 60

    static func attachIdleLimit(from environment: [String: String]) -> TimeInterval {
        guard let raw = environment[attachIdleLimitEnv],
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              seconds > 0 else { return defaultAttachIdleLimit }
        return seconds
    }

    /// Reclaim every slot whose holder is gone, and report what was reclaimed.
    ///
    /// **This exists because "session end" is not an event this agent receives.**
    /// One `Session` serves every client; a peer that attaches and then dies
    /// calls no detach, and the queue's wait ceiling expires WAITERS rather than
    /// HOLDERS — so without this, two dead attachments would occupy Apple's two
    /// forever and the third guest would wait on nothing.
    ///
    /// Two rules, and the first is the real one:
    ///
    ///   the peer process is gone — read from the identity the attachment was
    ///   made under, which already carries the pid and its start time, so this
    ///   needs no timer and no heartbeat;
    ///
    ///   the attachment has sat unused past the idle ceiling — the backstop for
    ///   a peer that is alive but has forgotten it holds a machine.
    @discardableResult
    func reclaimAbandonedAttachments(peerIsAlive: (String) -> Bool = Session.peerIsAlive)
        async -> [String] {
        let limit = Session.attachIdleLimit(from: tools.environment)
        let now = clock()
        var reclaimed: [String] = []
        for (key, attachment) in guestAttachments where attachment.slotHeld {
            let dead = !peerIsAlive(key)
            let idle = (now - attachment.lastUsedAt) > limit
            guard dead || idle else { continue }
            let why = dead
                ? "the session holding it went away"
                : "it sat unused for longer than \(Int(limit))s"
            // A guest this agent started is stopped; one a person started is
            // left running, because stopping a running VM discards its state.
            await releaseGuestAttachment(
                reason: "slot reclaimed: \(why)",
                stopGuest: attachment.startedByThisAgent, session: key)
            reclaimed.append(attachment.name)
        }
        return reclaimed
    }

    /// Whether the process behind an identity key is still there.
    ///
    /// The key is `pid:startTime`, minted by `SessionIdentity.fromPeer`. Both
    /// halves are checked: a pid alone would be reused by an unrelated process
    /// and keep a dead session's slot alive forever.
    static func peerIsAlive(_ key: String) -> Bool {
        let parts = key.split(separator: ":")
        guard parts.count == 2, let pid = Int32(parts[0]),
              let started = UInt64(parts[1]) else {
            // An identity this build cannot parse — the unattributed one, or a
            // test's own key. Treated as alive, because reclaiming a slot on the
            // strength of a string we could not read would be worse than
            // holding it.
            return true
        }
        guard kill(pid, 0) == 0 else { return false }
        // The key stores the start time truncated the same way it was minted.
        return UInt64(SessionIdentity.startTime(of: pid)) == started
    }

    /// A11. Confirm the guest a session holds is still there, and give the slot
    /// back naming the disappearance when it is not.
    ///
    /// Returns the error to hand the caller, or nil when all is well. Separate
    /// from the link's own failure path because a guest can vanish while nothing
    /// is being sent — the host slept, a person ran `tart stop`, the provider
    /// went away — and a slot held by nothing is exactly what A11 closes.
    func guestVanishedError() async -> AgentError? {
        guard let attachment = currentAttachment else { return nil }
        let providers = try? resolvedGuestProviders()
        guard let adapter = providers?.first(where: { $0.id == attachment.provider }) else {
            return nil
        }
        let stillRunning: Bool
        do {
            stillRunning = try await adapter.status(name: attachment.name).running
        } catch {
            stillRunning = false
        }
        guard !stillRunning else { return nil }
        await releaseGuestAttachment(
            reason: "the guest is no longer running; slot released",
            stopGuest: false)   // it is already down: nothing to stop
        return GuestLinkRefusal.vanished(
            machine: attachment.machine,
            reason: "It was running when this session attached and is not now.")
    }
}
