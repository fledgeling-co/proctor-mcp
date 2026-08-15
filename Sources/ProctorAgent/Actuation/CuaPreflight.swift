import Foundation
import Security
import ProctorCore

// PRO-0044, slice 5. Establishing that the driver can be used at all, before a
// step is attempted rather than at the first schema error.
//
// **This file reverses a shipped rule, narrowly and on purpose.** `ToolPresence`
// records that detection reads the filesystem and NEVER runs the binary, because
// the directories that make a launchd agent's lookup work are user-writable, and
// executing whatever answers to a filename there — inside a process holding
// Accessibility — is a code-execution path opened on Proctor's own initiative.
// Its stated cost is that Proctor learns no version. Version pinning needs one.
//
// The rule survives because it was always about the side effects of UNRELATED
// calls. Probing for presence still executes nothing. Running the driver is not
// a side effect of a probe: it is the whole of what the lane does, and the lane
// is chosen by an operator. And before the first execution the binary is
// signature-checked, which closes the planted-file hole that made the rule right
// in the first place.
//
// "Is signed" would not be a policy. A valid Developer ID signature is carried by
// every notarised binary on the machine, so accepting one accepts all of them;
// the requirement has to pin the driver's own identity. Which anchor that is —
// and whether the driver's builds are Developer ID signed at all, rather than
// ad-hoc as a source or Homebrew build would be — is an external fact this repo
// cannot settle. So it is one constant with a fail-closed default and a stamped
// override: an operator resolving a visible refusal beats Proctor guessing.

/// Why a lane refused, in the order the checks run.
enum CuaPreflightStage: String, Sendable {
    case presence
    case signature
    case version
    case capabilities
    case grants
}

/// What preflight established, for the run record and for `proctor_doctor`.
struct CuaLaneReport: Sendable {
    var path: String?
    var version: CuaVersion?
    /// Overrides in force, stamped onto every record this lane touches. An
    /// escape hatch that hides itself is worse than none.
    var overrides: [String] = []
    /// The driver's own account of its permissions. **The driver's claim, not
    /// Proctor's finding** — and labelled that way wherever it is shown.
    ///
    /// It has to be asked for rather than read. The grants that do the work
    /// belong to the driver's own identity, not Proctor's, and macOS exposes no
    /// benign way to read another process's: the database needs Full Disk Access,
    /// a new grant and a scope widening this wave has no business requesting.
    var driverReportedGrants: [String: Bool] = [:]
    /// Delivery paths the installed build says it can report.
    var vocabulary: [String] = []
    /// Whether what was verified stays verified for the lane's life. See
    /// `CuaTransport.identityPinned`.
    var identityPinned: Bool = false
    /// Which client answered, for the lane record.
    var transport: String = "unknown"
    /// What was established about the running process, when the transport can
    /// support such a claim at all.
    var identity: CuaProcessIdentity?
    /// The pid the driver says does its posting, and whether the process bearing
    /// it is the program the lane verified. PRO-0046: the supervision guards
    /// recognise a delegated actuation by this, and a lane that has neither takes
    /// the exclusive queue lane rather than arming a hold it could not tell its
    /// own driver apart from a person.
    var actuatingPid: Int64?
    var pidCorroborated: Bool = false
    /// Whether the driver can be asked not to draw its own agent cursor.
    /// Defaults to false and fails closed: a build that says nothing counts as
    /// unable, so Proctor stands its own pointer down rather than risking two.
    var cursorSuppressible: Bool = false

    /// The pid the guards may recognise: claimed AND corroborated. Nil is what
    /// makes a lane serialise.
    var recognisedPid: Int64? { pidCorroborated ? actuatingPid : nil }
}

enum CuaPreflight {

    /// The signing identity the driver's own installation documentation names.
    /// One constant, so the anchor is changed in one place rather than found in
    /// five.
    static let expectedIdentifier = "com.trycua.driver"

    /// The requirement both checks are made against — the file before it is
    /// executed, and the running process afterwards. One string so the two cannot
    /// drift into checking different things under the same name.
    static var requirementText: String {
        "identifier \"\(expectedIdentifier)\" and anchor apple generic"
    }

    static let allowUnsignedEnv = "PROCTOR_CUA_ALLOW_UNSIGNED"
    static let allowUnsupportedEnv = "PROCTOR_CUA_ALLOW_UNSUPPORTED"

    /// Run the ordered checks. Each failure is its own refusal, naming what was
    /// found, what is supported and what to do — never a schema error three steps
    /// into a batch.
    ///
    /// `onRefusal` is told which check refused before the error is thrown.
    /// `CuaPreflightStage` was declared with this file and left unused; this is
    /// what it was for. `proctor_doctor` records the stage so a dead lane can be
    /// reported as dead *and say where*, without a health check re-running any of
    /// this — the refusal is remembered from the attempt that actually happened.
    static func run(path: String?, transport: any CuaTransport,
                    environment: [String: String] = ProcessInfo.processInfo.environment,
                    verifySignature: (String) -> SignatureVerdict = verifySignature,
                    corroborate: (Int64, String) -> Bool = liveCorroborate,
                    onRefusal: (CuaPreflightStage, AgentError) -> Void = { _, _ in })
    async throws -> CuaLaneReport {
        var report = CuaLaneReport()

        func refuse(_ stage: CuaPreflightStage, _ error: AgentError) -> AgentError {
            onRefusal(stage, error)
            return error
        }

        // 1. Presence. Executes nothing; this is the filesystem answer.
        guard let path, !path.isEmpty else {
            throw refuse(.presence, AgentError(
                code: .backendUnavailable,
                message: "the Cua actuation lane is selected but cua-driver was not found on "
                       + "this machine",
                remedy: "Install it and re-check with proctor_doctor, or unset PROCTOR_ACTUATION "
                      + "to use Proctor's own actuation planes. Proctor never installs anything "
                      + "on its own."))
        }
        report.path = path

        // 2. Signature, before the first execution.
        let verdict = verifySignature(path)
        if case .valid = verdict {
            // Proceed.
        } else if environment[allowUnsignedEnv] == "1" {
            report.overrides.append("unsignedBinaryAccepted")
        } else {
            throw refuse(.signature, AgentError(
                code: .backendUnsupported,
                message: "cua-driver at \(path) \(verdict.describe(expecting: expectedIdentifier)), "
                       + "so it was not executed",
                remedy: "Proctor holds the Accessibility grant, so it will not run an unverified "
                      + "binary from a user-writable directory. Install a signed build, or set "
                      + "\(allowUnsignedEnv)=1 to accept this one — which stamps every record "
                      + "the lane produces.",
                detail: .object(["path": .string(path),
                                 "expected": .string(expectedIdentifier)])))
        }

        // 3. Version. The driver's claim about itself.
        let versionReply = try await transport.send(CuaRequest(verb: .version))
        guard let raw = versionReply.version, let version = CuaVersion.parse(raw) else {
            throw refuse(.version, AgentError(
                code: .backendUnsupported,
                message: "cua-driver did not report a version this build could read",
                remedy: "A build whose version cannot be read is as unsupported as one outside "
                      + "the range \(CuaVersion.supportedRangeDescription).",
                detail: .object(["reported": .string(versionReply.version ?? "")])))
        }
        report.version = version
        if !version.isSupported {
            if environment[allowUnsupportedEnv] == "1" {
                report.overrides.append("unsupportedVersionForced")
            } else {
                throw refuse(.version, AgentError(
                    code: .backendUnsupported,
                    message: "cua-driver \(version) is outside the supported range "
                           + "\(CuaVersion.supportedRangeDescription)",
                    remedy: "Install a build inside that range, or set \(allowUnsupportedEnv)=1 "
                          + "to run anyway — which stamps every record the lane produces. The "
                          + "range is one minor version because the driver is pre-1.0 and ships "
                          + "daily.",
                    detail: .object(["found": .string(version.description),
                                     "supported": .string(CuaVersion.supportedRangeDescription)])))
            }
        }

        // 4. Capabilities. The version number is a claim; this is evidence.
        //    Everything this build believes about the driver's wire was read from
        //    documentation rather than from the binary, so the mapping table is
        //    compared against what the installed build actually reports — and a
        //    path outside it refuses HERE, where the message can say so, rather
        //    than arriving mid-run as an unmappable plane.
        let capabilities = try await transport.send(CuaRequest(verb: .capabilities))
        report.cursorSuppressible = capabilities.cursorSuppressible ?? false
        if let vocabulary = capabilities.vocabulary {
            report.vocabulary = vocabulary
            let unknown = vocabulary.filter { CuaVocabulary.planes[$0] == nil }
            if !unknown.isEmpty {
                throw refuse(.capabilities, AgentError(
                    code: .backendUnsupported,
                    message: "cua-driver reports delivery paths this build cannot map: "
                           + unknown.sorted().joined(separator: ", "),
                    remedy: "A path Proctor cannot map is a step whose plane it could not report "
                          + "honestly, and the plane is what tells a caller whether a run needed "
                          + "the machine. Upgrade Proctor, or pin cua-driver to a build inside "
                          + "\(CuaVersion.supportedRangeDescription).",
                    detail: .object(["unmapped": .array(unknown.sorted().map { .string($0) }),
                                     "known": .array(CuaVocabulary.planes.keys.sorted()
                                                                          .map { .string($0) })])))
            }
        }

        // 5. Grants, asked for rather than read. See the note on the field.
        let health = try await transport.send(CuaRequest(verb: .health))
        if !health.ok {
            throw refuse(.grants, AgentError(
                code: .backendUnavailable,
                message: "cua-driver reports it is not healthy enough to actuate: "
                       + (health.message ?? "no reason given"),
                remedy: "The grants that do the work belong to the driver's own identity, not "
                      + "Proctor's, so Proctor's own permissions being in order says nothing "
                      + "about this. Run the driver's own doctor."))
        }

        // 6. Which process actually posts, so the supervision guards can tell the
        //    driver's own actions from a person's (PRO-0046).
        //
        //    NEVER A REFUSAL. A driver that reports no pid, or one that does not
        //    corroborate, is perfectly able to actuate — what it cannot do is
        //    share a machine with an armed input block, because Proctor would
        //    have no way to tell its clicks from somebody's. So the lane runs and
        //    takes the exclusive queue lane instead, which is a scheduling cost
        //    rather than a refusal.
        if let claimed = health.actuatingPid.map(Int64.init) {
            report.actuatingPid = claimed
            report.pidCorroborated = corroborate(claimed, expectedIdentifier)
        }
        return report
    }

    /// Is the process bearing this pid the program the lane already verified?
    ///
    /// **A recognition rule, not an attestation, and the difference is stated
    /// rather than glossed.** The source pid on an event is set by the system on
    /// the ordinary posting path — measured twice in this repo, where Proctor's
    /// own posts carried Proctor's pid and hardware carried 0 — but a process
    /// that builds its own event can write that field, and a pid reused between
    /// this check and the event would also pass. Neither reaches the threat this
    /// guards: a program able to forge it is already a program able to post into
    /// the application directly, and PRO-0026 records that the block is partial
    /// and cannot lock anybody out of their Mac. This protects a run from a
    /// person; it was never a boundary against a program.
    ///
    /// It asks about the RUNNING code rather than a file on disk.
    /// `SecCodeCopyGuestWithAttributes` with a pid attribute is the API for
    /// exactly that question, and it answers for a plain helper as well as for a
    /// bundled app — where reading an executable path and checking the file would
    /// answer a subtly different question about a different artefact.
    /// Injected as a parameter rather than held as a mutable static, following
    /// `verifySignature` above. A process-wide `var` that tests reassign is the
    /// defect PRO-0053 spent a session on: swift-testing parallelises across
    /// suites, so two tests setting one static stomp each other and the failure
    /// reads as a logic error in whichever lost.
    static let liveCorroborate: @Sendable (Int64, String) -> Bool = {
        pid, identifier in
        guard pid > 0, pid <= Int64(Int32.max) else { return false }
        let attributes = [kSecGuestAttributePid: NSNumber(value: Int32(pid))] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }

        var requirement: SecRequirement?
        let text = "identifier \"\(identifier)\" and anchor apple generic" as CFString
        guard SecRequirementCreateWithString(text, [], &requirement) == errSecSuccess,
              let requirement else { return false }

        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    // MARK: - Signature

    enum SignatureVerdict: Sendable, Equatable {
        case valid
        case unsigned
        case adhoc
        case wrongIdentity(String?)
        case unreadable(String)

        func describe(expecting identifier: String) -> String {
            switch self {
            case .valid:                 return "is signed by \(identifier)"
            case .unsigned:              return "carries no code signature"
            case .adhoc:
                return "is ad-hoc signed, which a source or Homebrew build is"
            case .wrongIdentity(let found):
                return "is signed by \(found ?? "another identity") rather than \(identifier)"
            case .unreadable(let why):   return "could not be checked (\(why))"
            }
        }
    }

    /// Read the binary's signature and say what it is.
    ///
    /// Deliberately reports the KIND of failure rather than a bare no. An ad-hoc
    /// build and a wrong-identity build are different situations for the person
    /// reading the refusal: the first is usually their own `swift build`, the
    /// second is a file they should look at.
    static func verifySignature(path: String) -> SignatureVerdict {
        let url = URL(fileURLWithPath: path) as CFURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return .unreadable("the file could not be read as signed code")
        }

        var requirement: SecRequirement?
        let text = "identifier \"\(expectedIdentifier)\" and anchor apple generic" as CFString
        guard SecRequirementCreateWithString(text, [], &requirement) == errSecSuccess,
              let requirement else {
            return .unreadable("the signing requirement could not be built")
        }

        let status = SecStaticCodeCheckValidity(code, [], requirement)
        switch status {
        case errSecSuccess:
            return .valid
        case errSecCSUnsigned:
            return .unsigned
        default:
            // It has a signature that does not satisfy the requirement. Read the
            // identifier back so the refusal can name what is actually there.
            var info: CFDictionary?
            let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
            guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
                  let dictionary = info as? [String: Any] else {
                return .wrongIdentity(nil)
            }
            let found = dictionary[kSecCodeInfoIdentifier as String] as? String
            // An ad-hoc signature has no team identifier at all, which is what a
            // locally built binary looks like.
            if dictionary[kSecCodeInfoTeamIdentifier as String] == nil { return .adhoc }
            return .wrongIdentity(found)
        }
    }
}
