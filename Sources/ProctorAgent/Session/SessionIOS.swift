import Foundation
import ProctorCore

// proctor_ios: the iOS Simulator lane, impure half.
//
// A peer of the macOS lane behind the same Proctor surface, not a port of it.
// The decisions — how a failure decodes, what a verdict may claim, which app the
// gate judges, how a URL is split for the trail — are pure and live in
// ProctorCore/IOSDevice.swift. This file runs the subprocesses, holds the
// session state, and wires the gate and the audit trail.
//
// Three things about it differ from every other lane, and each is deliberate:
//
// **No exclusive turn.** `openurl` and `io screenshot` both work with
// Simulator.app closed, post no events into the Mac's input system, and raise no
// window, so taking the machine's turn from RunQueue would block Mac runs for
// contention that does not exist.
//
// **No implicit boot.** Booting is stateful and takes tens of seconds. Folding
// that into a call whose result is "did this navigate" would make the timing
// meaningless and the audit record ambiguous.
//
// **No shutdown, anywhere.** A running simulator holds state somebody may be
// mid-way through, and discarding it is unrecoverable. This file constructs no
// `shutdown` argument; a test asserts that at the source level, because the
// promise is only worth what enforces it.

extension Session {

    // MARK: - Entry point

    func ios(action: String, device: String?, url: String?, bundleId: String?,
             pixelEvidence: Bool, changeThreshold: Double?, path: String?,
             timeoutMs: Int?, settleMs: Int?) async throws -> JSONValue {
        let simctl = try simctlPath()
        switch action {
        case "list":
            return try iosList(simctl: simctl)
        case "boot":
            return try await iosBoot(simctl: simctl, device: device,
                                     timeoutMs: timeoutMs ?? 120_000)
        case "screenshot":
            return try iosScreenshot(simctl: simctl, device: device, path: path,
                                     timeoutMs: timeoutMs ?? 15_000)
        default:
            guard let url, !url.isEmpty else {
                throw AgentError(code: .invalidArguments,
                                 message: "proctor_ios action \"open\" requires url",
                                 remedy: "Pass the deep link to open, e.g. \"myapp://home\".")
            }
            return try await iosOpen(simctl: simctl, device: device, url: url,
                                     bundleId: bundleId, pixelEvidence: pixelEvidence,
                                     changeThreshold: changeThreshold ?? IOSPixel.changeThreshold,
                                     timeoutMs: timeoutMs ?? 15_000,
                                     settleMs: settleMs ?? 4_000)
        }
    }

    /// Where simctl is, or the reason there is no lane on this machine at all.
    ///
    /// Reported as an absence with the searched paths rather than as a mysterious
    /// failure, because "Xcode is not installed" is a fact about the machine that
    /// a caller can act on and a failed subprocess is not.
    private func simctlPath() throws -> String {
        let presence = tools.simctl.presence()
        guard presence.available, let path = presence.path else {
            let absence = SimctlLocator.absence
            throw AgentError(
                code: .notImplemented,
                message: absence.missing,
                remedy: absence.askThePerson,
                detail: .object([
                    "searched": .array(presence.searched.map(JSONValue.string)),
                    "docs": .string(absence.docs)
                ]))
        }
        return path
    }

    // MARK: - list

    private func iosList(simctl: String) throws -> JSONValue {
        let devices = try readDevices(simctl: simctl)
        return .object([
            "devices": .array(try devices.map { try JSONValue.encode($0) }),
            "bootedCount": .number(Double(devices.filter(\.isBooted).count)),
            "capabilities": Session.iosCapabilities,
            "note": .string(
                "These are device handles, not window handles. proctor_snapshot, proctor_find, "
                + "proctor_assert, proctor_act and proctor_capture do not work against one — the "
                + "Mac's accessibility API does not cross into a simulated device.")
        ])
    }

    /// What this lane can and cannot do, stated once and carried on every listing.
    ///
    /// The ceiling belongs in the result rather than only in the tool description,
    /// because a model that reads a device handle and reaches for a snapshot has
    /// already stopped reading descriptions.
    static let iosCapabilities: JSONValue = .object([
        "available": .array([
            .string("deep-link navigation with evidence (proctor_ios action \"open\")"),
            .string("device-surface screenshots (action \"screenshot\")"),
            .string("app process liveness on the device"),
            .string("installed-app and device metadata")
        ]),
        "unavailable": .array([
            .string("accessibility tree — AXUIElement does not cross into a simulated device"),
            .string("element handles, geometry assertions and the accessibility audit"),
            .string("actuation steps: clicks, typing, scrolling and menus against an iOS app"),
            .string("which app is frontmost on the device")
        ]),
        "note": .string(
            "A device screenshot carries no ScreenCaptureKit frame status, so its freshness cannot "
            + "be established the way a window capture's can and it is marked untrustworthy for "
            + "that reason. The pixels are real; the guarantee is not.")
    ])

    private func readDevices(simctl: String) throws -> [IOSDevice] {
        let run = Session.runSimctl(simctl, ["list", "-j", "devices"], timeoutMs: 20_000)
        guard run.exitCode == 0 else {
            throw AgentError(
                code: .actionFailed,
                message: "simctl could not list devices: "
                       + SimctlFailure.decode(exitCode: run.exitCode, stderr: run.stderr),
                remedy: "Confirm Xcode is installed and its command-line tools are selected.")
        }
        var devices = try IOSDeviceList.parse(run.stdout)
        for index in devices.indices
        where bootedDevices.contains(devices[index].udid) && devices[index].isBooted {
            // Only while it is actually booted. A device this session started,
            // that somebody has since shut down, is not something Proctor left
            // running — and re-marking it after a person booted it again would
            // claim a provenance this session does not have.
            devices[index].bootedByThisSession = true
        }
        return devices
    }

    /// Resolve a caller's device reference: a `dev-` handle, a udid, or a name.
    ///
    /// Omitting it means "the booted one" and works only when exactly one is
    /// booted. Ambiguity is an error naming the candidates rather than a guess,
    /// because guessing which simulator to drive is how a campaign silently
    /// measures the wrong device.
    private func resolveDevice(_ reference: String?, in devices: [IOSDevice]) throws -> IOSDevice {
        guard let reference, !reference.isEmpty else {
            let booted = devices.filter(\.isBooted)
            if booted.count == 1 { return booted[0] }
            if booted.isEmpty {
                throw AgentError(
                    code: .appNotFound,
                    message: "no simulator is booted",
                    remedy: "Boot one with proctor_ios action \"boot\", naming a device from action "
                          + "\"list\". Proctor never boots a device implicitly.")
            }
            throw AgentError(
                code: .invalidArguments,
                message: "\(booted.count) simulators are booted, so `device` is required",
                remedy: "Name one: " + booted.map { "\($0.name) (\($0.handleID))" }
                    .joined(separator: ", "))
        }

        let lowered = reference.lowercased()
        let matches = devices.filter {
            $0.handleID == lowered
                || $0.udid.caseInsensitiveCompare(reference) == .orderedSame
                || $0.name.caseInsensitiveCompare(reference) == .orderedSame
        }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty {
            throw AgentError(
                code: .appNotFound,
                message: "no simulator matches \(reference.debugDescription)",
                remedy: "Call proctor_ios action \"list\" for the devices on this machine.")
        }
        // A device name repeats across runtimes — "iPhone 16 Pro" exists on every
        // installed iOS version — so a name that matches several is reported with
        // their handles rather than resolved to whichever sorted first.
        throw AgentError(
            code: .invalidArguments,
            message: "\(reference.debugDescription) matches \(matches.count) simulators",
            remedy: "Name one by handle or udid: "
                  + matches.map { "\($0.handleID) (\($0.runtime))" }.joined(separator: ", "))
    }

    // MARK: - boot

    /// Boot a named simulator and wait for it to come up.
    ///
    /// Gated on the device rather than on an app: no application is being driven,
    /// so judging one would be judging nothing. Audited either way, because a
    /// device coming up is a change to the machine somebody may have to explain.
    private func iosBoot(simctl: String, device: String?, timeoutMs: Int) async throws -> JSONValue {
        let devices = try readDevices(simctl: simctl)
        let target = try resolveDevice(device, in: devices)

        if target.isBooted {
            return .object([
                "device": try JSONValue.encode(target),
                "booted": .bool(true),
                "alreadyBooted": .bool(true),
                "note": .string("The device was already booted; nothing was started.")
            ])
        }

        let context = AuditContext(tool: "proctor_ios.boot", app: nil,
                                   bundleId: "ios-device:" + target.udid, window: nil)
        let run = Session.runSimctl(simctl, ["boot", target.udid], timeoutMs: timeoutMs)
        guard run.exitCode == 0 else {
            let reason = SimctlFailure.decode(exitCode: run.exitCode, stderr: run.stderr)
            auditSink(AuditRecord(timestamp: clock(), tool: context.tool,
                                  bundleId: context.bundleId, kind: "boot",
                                  outcome: AuditRecord.Outcome.failed, reason: reason))
            throw AgentError(code: .actionFailed,
                             message: "booting \(target.name) failed: \(reason)")
        }

        bootedDevices.insert(target.udid)

        // Booting returns before the device is usable, so poll rather than sleep a
        // fixed interval: a warm boot takes a second and a cold one takes tens.
        let deadline = Date().addingTimeInterval(Double(max(0, timeoutMs)) / 1000)
        var current = target
        var reachedBooted = false
        repeat {
            if let refreshed = (try? readDevices(simctl: simctl))?
                .first(where: { $0.udid == target.udid }) {
                current = refreshed
                if refreshed.isBooted { reachedBooted = true; break }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        } while Date() < deadline

        auditSink(AuditRecord(timestamp: clock(), tool: context.tool,
                              bundleId: context.bundleId, kind: "boot",
                              outcome: reachedBooted ? AuditRecord.Outcome.ok
                                                     : AuditRecord.Outcome.failed,
                              reason: reachedBooted ? "device booted"
                                                    : "device did not reach Booted within \(timeoutMs)ms"))

        var out: [String: JSONValue] = [
            "device": try JSONValue.encode(current),
            "booted": .bool(reachedBooted),
            "alreadyBooted": .bool(false)
        ]
        if !reachedBooted {
            out["note"] = .string(
                "simctl accepted the boot but the device still reports \(current.state) after "
                + "\(timeoutMs)ms. It may still be coming up; re-read with action \"list\". Nothing "
                + "was shut down.")
        }
        return .object(out)
    }

    // MARK: - screenshot

    private func iosScreenshot(simctl: String, device: String?, path: String?,
                               timeoutMs: Int) throws -> JSONValue {
        let devices = try readDevices(simctl: simctl)
        let target = try resolveDevice(device, in: devices)
        guard target.isBooted else {
            throw AgentError(
                code: .captureFailed,
                message: "\(target.name) is \(target.state), so there is no screen to capture",
                remedy: "Boot it with proctor_ios action \"boot\".")
        }
        let destination = try path ?? Session.deviceFramePath(udid: target.udid, label: "screen")
        let shot = Session.captureDeviceScreen(simctl: simctl, udid: target.udid,
                                               path: destination, timeoutMs: timeoutMs)
        guard shot.ok else {
            throw AgentError(code: .captureFailed,
                             message: "capturing \(target.name) failed: \(shot.reason ?? "unknown")")
        }
        return .object([
            "device": try JSONValue.encode(target),
            "path": .string(destination),
            "trustworthy": .bool(false),
            "caveat": .string(Session.deviceFrameCaveat)
        ])
    }

    /// Why a device frame is never trustworthy in the sense a window capture is.
    ///
    /// The wave's direction refuses to accept a screenshot with no frame status
    /// from Cua; the same refusal has to apply to Proctor's own device frames or
    /// the standard is about the vendor rather than about the evidence.
    static let deviceFrameCaveat =
        "Device-surface capture through simctl. Apple defines six SCFrameStatus values and makes "
        + "checking them a precondition of trusting a frame; this path reports none of them, and "
        + "carries no dirty-rectangle coverage or completeness signal, so the frame's freshness "
        + "cannot be established the way a window capture's can."

    // MARK: - open

    private func iosOpen(simctl: String, device: String?, url: String, bundleId: String?,
                         pixelEvidence: Bool, changeThreshold: Double,
                         timeoutMs: Int, settleMs: Int) async throws -> JSONValue {
        let devices = try readDevices(simctl: simctl)
        let target = try resolveDevice(device, in: devices)

        // No implicit boot, ever. The refusal names the state so the caller knows
        // which of the two things to do about it.
        guard target.isBooted else {
            throw AgentError(
                code: .actionFailed,
                message: "\(target.name) is \(target.state); a deep link needs a booted device",
                remedy: "Boot it with proctor_ios action \"boot\", or name a device that is already "
                      + "booted. proctor_ios never boots a device as a side effect of opening a URL, "
                      + "because a stateful minute-long boot inside a navigation call would make "
                      + "both results ambiguous.")
        }

        // The gate judges the app the URL actually reaches. A caller-supplied
        // bundle id is a consistency check and never the key — gating on a name
        // the caller chose would reopen exactly the hole the macOS gate closed.
        let map = try schemeMap(simctl: simctl, udid: target.udid)
        let resolved = SchemeMap.handler(for: url, in: map)
        var mismatch: String?
        if let bundleId, let resolved, bundleId != resolved {
            mismatch = "You named \(bundleId) but this device resolves \(url) to \(resolved)."
        }

        let gateKey = resolved
        let context = AuditContext(tool: "proctor_ios.open", app: nil,
                                   bundleId: gateKey.map(IOSPolicy.key(for:)), window: nil)
        let split = DeepLinkTarget.split(url: url)

        loadPolicyIfNeeded()
        let decision = IOSPolicy.decide(handler: gateKey, policy: policy,
                                        hasValidToken: approvalTokenIsValid(for: gateKey))
        if let refusal = decision.refusal {
            auditSink(AuditRecord(timestamp: clock(), tool: context.tool,
                                  bundleId: context.bundleId, kind: "open",
                                  outcome: AuditRecord.Outcome.refused,
                                  value: Redaction(of: split.redactable),
                                  reason: split.clear + " · " + refusal.reason))
            throw AgentError(code: .policyDenied, message: refusal.reason, remedy: refusal.remedy)
        }
        // A caller who expected a different app than the device resolved is
        // refused under an allow list: the list authorised one app and the URL is
        // about to reach another, which is precisely the substitution the gate
        // exists to catch.
        if let mismatch, !policy.allow.isEmpty {
            auditSink(AuditRecord(timestamp: clock(), tool: context.tool,
                                  bundleId: context.bundleId, kind: "open",
                                  outcome: AuditRecord.Outcome.refused,
                                  value: Redaction(of: split.redactable),
                                  reason: split.clear + " · handler mismatch"))
            throw AgentError(
                code: .policyDenied,
                message: mismatch + " An allow list is in force, so the disagreement is refused "
                       + "rather than resolved in either direction.",
                remedy: "Open the URL that belongs to the app you named, or name the app the device "
                      + "resolves it to.")
        }

        // The liveness channel needs a bundle id. The resolved handler is the
        // honest one; a caller-supplied id is accepted only when nothing resolved,
        // which is the universal-link case where a scheme claim decides nothing.
        let livenessTarget = resolved ?? bundleId

        // One iOS operation per device at a time. The before/after samples are
        // only evidence if nothing else drove the device between them, and this
        // actor is reentrant — a boot's poll loop or a second open would
        // otherwise interleave and the pixels would belong to whichever call
        // happened to be running. It bounds what Proctor did; a person tapping
        // the simulator is outside anybody's control and is why the verdict names
        // what it cannot attribute.
        guard !iosBusyDevices.contains(target.udid) else {
            throw AgentError(
                code: .queueBusy,
                message: "another proctor_ios call is already driving \(target.name)",
                remedy: "Wait for it to finish. Two deep links in flight against one device would "
                      + "make both sets of before/after evidence meaningless.")
        }
        iosBusyDevices.insert(target.udid)
        defer { iosBusyDevices.remove(target.udid) }

        let before = evidenceSample(simctl: simctl, udid: target.udid, bundleId: livenessTarget,
                                    pixels: pixelEvidence, label: "before")
        let run = Session.runSimctl(simctl, ["openurl", target.udid, url], timeoutMs: timeoutMs)
        let delivered = run.exitCode == 0
        let failureReason = delivered ? nil
            : SimctlFailure.decode(exitCode: run.exitCode, stderr: run.stderr)

        // Settle before looking. `openurl` returns when SpringBoard has accepted
        // the URL, which is before the app has been woken, laid out or painted —
        // sampling on that return reports a real navigation as `deliveredOnly`.
        var settleReport: (settled: Bool, samples: Int, waitedMs: Int)?
        var afterFrame: String?
        if pixelEvidence {
            let settle = Session.settleDeviceScreen(simctl: simctl, udid: target.udid,
                                                    timeoutMs: settleMs)
            settleReport = (settle.settled, settle.samples, settle.waitedMs)
            afterFrame = settle.path
        }

        // The after sample is taken even on a refusal: a failed open that still
        // moved the screen is a fact worth having, and skipping the sample would
        // make it unreportable.
        let after = evidenceSample(simctl: simctl, udid: target.udid, bundleId: livenessTarget,
                                   pixels: pixelEvidence && afterFrame == nil, label: "after")
        let afterFramePath = afterFrame ?? after.framePath

        var changedFraction: Double?
        var meanDifference: Double?
        if let a = before.framePath, let b = afterFramePath {
            let compared = Session.compareDeviceFrames(a, b)
            changedFraction = compared.changedFraction
            meanDifference = compared.meanDifference
        }

        let evidence = DeepLinkEvidence(
            delivered: delivered, exitCode: run.exitCode,
            handlerResolved: resolved,
            targetRunningBefore: before.running, targetRunningAfter: after.running,
            pidBefore: before.pid, pidAfter: after.pid,
            changedFraction: changedFraction, meanDifference: meanDifference,
            changeThreshold: changeThreshold,
            failureReason: failureReason)
        let outcome = DeepLinkVerdict.decide(evidence)

        auditSink(AuditRecord(
            timestamp: clock(), tool: context.tool, bundleId: context.bundleId, kind: "open",
            outcome: delivered ? AuditRecord.Outcome.ok : AuditRecord.Outcome.failed,
            value: Redaction(of: split.redactable),
            reason: split.clear + " · " + outcome.verdict.rawValue))

        var out: [String: JSONValue] = [
            "device": try JSONValue.encode(target),
            "url": .string(split.clear + (split.redactable.isEmpty ? "" : "…")),
            "verdict": .string(outcome.verdict.rawValue),
            "attributed": .bool(outcome.verdict.isAttributed),
            "note": .string(outcome.note),
            "launchedNow": .bool(evidence.launchedNow),
            "evidence": try JSONValue.encode(evidence),
            "changeThreshold": .number(changeThreshold)
        ]
        if let resolved { out["handler"] = .string(resolved) }
        if let mismatch { out["handlerMismatch"] = .string(mismatch) }
        if let path = before.framePath { out["frameBefore"] = .string(path) }
        if let path = afterFramePath { out["frameAfter"] = .string(path) }
        if before.framePath != nil {
            out["frameCaveat"] = .string(Session.deviceFrameCaveat)
            // The tension stated rather than left to be noticed: the frames this
            // verdict rests on are the same frames reported as untrustworthy.
            // Only attached when the channel actually ran, so it reads as a limit
            // on this answer rather than as boilerplate.
            out["evidenceCaveat"] = .string(IOSPixel.channelCaveat)
        }
        if let settleReport {
            out["settle"] = .object([
                "settled": .bool(settleReport.settled),
                "samples": .number(Double(settleReport.samples)),
                "waitedMs": .number(Double(settleReport.waitedMs))
            ])
            if !settleReport.settled {
                out["settleNote"] = .string(
                    "The device screen was still changing when the bound expired, so the frame "
                    + "compared here is a moving one. An animation that outlasts the settle reads "
                    + "as a change whether or not the deep link caused it.")
            }
        }
        if resolved == nil && SchemeMap.scheme(of: url).map(
            SchemeMap.unresolvableSchemes.contains) == true {
            out["handlerNote"] = .string(
                "An https link is routed through associated domains rather than a scheme claim, so "
                + "which app receives it cannot be read from the device. Pass bundleId to enable the "
                + "process-liveness channel for it.")
        }
        return .object(out)
    }

    /// One sample of every channel that is available.
    private func evidenceSample(simctl: String, udid: String, bundleId: String?, pixels: Bool,
                                label: String) -> (running: Bool?, pid: Int?, framePath: String?) {
        var running: Bool?
        var pid: Int?
        if let bundleId {
            let liveness = Session.appLiveness(simctl: simctl, udid: udid, bundleId: bundleId)
            running = liveness.running
            pid = liveness.pid
        }
        var framePath: String?
        if pixels, let path = try? Session.deviceFramePath(udid: udid, label: label),
           Session.captureDeviceScreen(simctl: simctl, udid: udid, path: path,
                                       timeoutMs: 10_000).ok {
            framePath = path
        }
        return (running, pid, framePath)
    }

    private func approvalTokenIsValid(for handler: String?) -> Bool {
        guard let token = approvalToken else { return false }
        return token.isValid(at: clock(), for: handler.map(IOSPolicy.key(for:)))
    }

    // MARK: - Scheme resolution

    /// The scheme → bundle id map for a device, cached.
    ///
    /// Built by reading each installed app's `CFBundleURLTypes` from its own
    /// `Info.plist`; `simctl listapps` gives the bundle paths but not the schemes.
    /// Cached per device because it costs one plist read per installed app, and
    /// invalidated when the set of installed apps changes.
    private func schemeMap(simctl: String, udid: String) throws -> [String: String] {
        let apps = Session.installedApps(simctl: simctl, udid: udid)
        let fingerprint = apps.map(\.bundleId).sorted().joined(separator: ",")
        if let cached = iosSchemeMaps[udid], cached.fingerprint == fingerprint {
            return cached.map
        }
        let entries: [(bundleId: String, schemes: [String])] = apps.map {
            ($0.bundleId, Session.urlSchemes(inBundleAt: $0.bundlePath))
        }
        let map = SchemeMap.build(apps: entries)
        iosSchemeMaps[udid] = (fingerprint: fingerprint, map: map)
        return map
    }
}
