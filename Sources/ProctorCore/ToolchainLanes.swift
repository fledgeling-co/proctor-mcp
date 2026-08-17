import Foundation

// PRO-0050. What this machine can actually do, and the posture of the gate that
// will refuse the next call — both derived, both pure.
//
// Deriving rather than reporting is the point. A lane that announced itself
// would be a third opinion beside the grants and the tool rows, free to disagree
// with either; computing it from both means a lane cannot claim to be ready
// while the thing it needs is missing. The same discipline runs through the
// posture: it is built from counts and booleans, and its parameters cannot carry
// a bundle id, a path or a token, so a rule cannot leak through this seam even
// if somebody later wires it carelessly.

public extension Toolchain {

    // MARK: - Lanes

    /// What each lane needs and whether this machine has it.
    ///
    /// `grants` decides the Mac lane, because that lane needs no external tool at
    /// all — what stops it is a permission. The three-state handling is the whole
    /// of PRO-0041's lesson applied one level up: a required grant that is
    /// `denied` makes a lane unavailable, one that is merely `unconfirmed` makes
    /// it unconfirmed, and the difference is whether there is anything for a
    /// person to go and fix.
    static func lanes(tools: [ToolPresence], grants: [DoctorReport.Grant],
                      secondLane: SecondLaneState,
                      cuaLaneSelected: Bool) -> [DoctorReport.Lane] {
        [macLaneRow(grants: grants, cuaLaneSelected: cuaLaneSelected),
         browserLaneRow(tools: tools, secondLane: secondLane),
         iosLaneRow(tools: tools),
         cuaLaneRow(tools: tools, selected: cuaLaneSelected),
         guestLaneRow(tools: tools)]
    }

    private static func macLaneRow(grants: [DoctorReport.Grant],
                                   cuaLaneSelected: Bool) -> DoctorReport.Lane {
        var blockers: [String] = []
        var denied = false
        var unconfirmed = false
        for grant in grants where grant.required {
            switch grant.resolvedState {
            case .granted:
                continue
            case .denied:
                denied = true
                blockers.append("\(grant.name) is not granted.")
            case .unconfirmed:
                unconfirmed = true
                blockers.append("\(grant.name) could not be confirmed, which is a fact about what "
                              + "Proctor established rather than about the permission.")
            }
        }
        let state = denied ? "unavailable" : (unconfirmed ? "unconfirmed" : "ready")
        return DoctorReport.Lane(
            lane: macLane, state: state, requires: [], blockers: blockers,
            note: cuaLaneSelected
                ? "PROCTOR_ACTUATION selects the Cua lane, so steps are delegated rather than "
                + "performed on these planes. Observation stays here either way."
                : nil)
    }

    private static func browserLaneRow(tools: [ToolPresence],
                                       secondLane: SecondLaneState) -> DoctorReport.Lane {
        // browser-use is named only when the operator named it. With the lane off
        // the string does not appear in a tool result at all, and that invariant
        // is total rather than about handoffs, so it holds here too.
        var requires = [ObscuraTool.binary]
        if secondLane != .off { requires.append(BrowserUseTool.binary) }
        let obscura = tools.first { $0.tool == ObscuraTool.binary }
        var blockers: [String] = []
        if obscura?.usability == .unusable {
            blockers.append(obscura?.detail.map { "Obscura: \($0)" }
                            ?? "Obscura is not usable on this machine.")
        }
        let state = laneState(from: [obscura])
        return DoctorReport.Lane(
            lane: browserLane, state: state, requires: requires, blockers: blockers,
            note: state == "unavailable"
                ? "Proctor drives native applications without a browser tool; this lane is only "
                + "about pages."
                : nil)
    }

    private static func iosLaneRow(tools: [ToolPresence]) -> DoctorReport.Lane {
        let simctl = tools.first { $0.tool == "simctl" }
        let maestro = tools.first { $0.tool == MaestroTool.binary }
        var blockers: [String] = []
        if simctl?.usability == .unusable {
            blockers.append("Xcode is not installed, or the selected developer directory has no "
                          + "simctl in it, so there is no iOS Simulator lane on this machine.")
        }
        // Maestro is deliberately not a blocker and not in `requires`: deep links
        // work without it. Naming it here is what stops the next reader probing
        // for it a second time.
        let note = maestro?.usability == .usable
            ? "Maestro is installed, so flow files can run beside the deep-link actions."
            : "Maestro is not installed. Deep links and screenshots are unaffected; only flow "
            + "files need it."
        return DoctorReport.Lane(lane: iosLane, state: laneState(from: [simctl]),
                                 requires: ["simctl"], blockers: blockers, note: note)
    }

    private static func cuaLaneRow(tools: [ToolPresence], selected: Bool) -> DoctorReport.Lane {
        let driver = tools.first { $0.tool == CuaDriverTool.binary }
        var blockers: [String] = []
        if driver?.usability == .unusable, let detail = driver?.detail {
            blockers.append(detail)
        }
        let state = laneState(from: [driver])
        var note: String
        if selected {
            note = "This is the actuation lane in force."
            if state == "unconfirmed" {
                note += " Its version, daemon and permissions are established the first time a "
                      + "step is delegated — a health check does not run the driver."
            }
        } else {
            note = "Not the actuation lane in force: Proctor's own planes are performing steps. "
                 + "This row reports whether the machine is ready for the delegated lane, not "
                 + "that anything is using it."
        }
        return DoctorReport.Lane(lane: cuaLane, state: state,
                                 requires: [CuaDriverTool.binary], blockers: blockers, note: note)
    }

    /// Either provider is enough. Both missing is unavailable; one usable is
    /// ready. The grant-once-then-clone recipe lives on the note rather than
    /// being automated: an install must never happen as a side effect of a
    /// tool call, and the same rule binds provisioning.
    private static func guestLaneRow(tools: [ToolPresence]) -> DoctorReport.Lane {
        let lume = tools.first { $0.tool == LumeTool.binary }
        let prlctl = tools.first { $0.tool == PrlctlTool.binary }
        let present = [lume, prlctl].compactMap { $0 }
        var blockers: [String] = []
        let usable = present.contains { $0.usability == .usable }
        let unconfirmed = present.contains { $0.usability == .unconfirmed }
        let state: String
        if usable {
            state = "ready"
        } else if unconfirmed {
            state = "unconfirmed"
        } else {
            state = "unavailable"
            if present.isEmpty || present.allSatisfy({ $0.usability == .unusable || $0.usability == nil }) {
                blockers.append("Neither lume nor prlctl is usable on this machine, so there is "
                              + "no guest lane.")
            }
        }
        return DoctorReport.Lane(
            lane: guestLane, state: state,
            requires: [LumeTool.binary, PrlctlTool.binary],
            blockers: blockers,
            note: "Either provider is enough. A person grants Accessibility and Screen Recording "
                + "once inside the guest's GUI session, then clone reproduces the grants; nothing "
                + "here provisions a guest as a side effect of a tool call. Tahoe guests currently "
                + "render no application windows (trycua/cua #870, Apple FB21748086); verify "
                + "against Sequoia.")
    }

    /// A lane is as established as the least established thing it needs. A tool
    /// row that is missing entirely reads as unavailable rather than unconfirmed:
    /// nothing was left unanswered, the answer is that it is not there.
    private static func laneState(from tools: [ToolPresence?]) -> String {
        var unconfirmed = false
        for tool in tools {
            guard let tool else { return "unavailable" }
            switch tool.usability {
            case .usable:            continue
            case .unusable, .none:   return "unavailable"
            case .unconfirmed:       unconfirmed = true
            }
        }
        return unconfirmed ? "unconfirmed" : "ready"
    }

    // MARK: - Policy posture

    static let postureNote =
        "Shape and posture only. The lists themselves, the filesystem roots, the trail's path and "
        + "any key or token are deliberately not reported here: proctor_doctor is called before "
        + "anything is established, and a health check is the wrong place to hand out "
        + "configuration. This is a convention rather than a boundary — proctor_policy action "
        + "\"status\" answers in full."

    /// Build the posture from counts and booleans.
    ///
    /// **The parameter list is the redaction.** There is no way to pass this
    /// function a bundle identifier, a filesystem root or a token, so the block
    /// cannot come to contain one by a later edit that was not thinking about it.
    /// The test that scans the encoded bytes for known secrets is the belt; this
    /// signature is the braces.
    static func posture(allowCount: Int, blockCount: Int, sensitiveCount: Int,
                        approvalTokenLive: Bool, fsRootCount: Int,
                        auditWritable: Bool, auditClean: Bool, auditKeyConfirmed: Bool,
                        auditEntries: Int, auditDropped: Int) -> DoctorReport.PolicyPosture {
        // Block-only and open are different postures with the same permissiveness
        // for most applications, and a caller that has just been refused needs to
        // tell them apart.
        let mode = allowCount > 0 ? "allowList" : (blockCount > 0 ? "blockOnly" : "open")
        return DoctorReport.PolicyPosture(
            mode: mode,
            allowCount: allowCount, blockCount: blockCount, sensitiveCount: sensitiveCount,
            approvalTokenLive: approvalTokenLive,
            fsJailDeclared: fsRootCount > 0, fsRootCount: fsRootCount,
            auditWritable: auditWritable,
            // Both are properties of how the trail is written rather than of this
            // machine's state, and both have been true since PRO-0013 and
            // PRO-0032. They are on the wire so a reader does not have to know
            // which version shipped which.
            auditSealed: true, auditSigned: true,
            auditClean: auditClean, auditKeyConfirmed: auditKeyConfirmed,
            auditEntries: auditEntries,
            auditDroppedThisRun: auditDropped > 0 ? auditDropped : nil,
            note: postureNote)
    }
}
