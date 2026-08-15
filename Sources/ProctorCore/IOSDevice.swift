import Foundation

// The iOS Simulator lane, decision half. Everything here is pure: no Process, no
// FileManager, no clock it is not given. The subprocesses and the actor state
// live in ProctorAgent/Session/SessionIOS.swift, which is what makes the whole
// verdict ladder provable on a machine with no Xcode and no booted device.
//
// The thing this file exists to prevent is a lane that reports "sent" as if it
// meant "arrived". Measured on 2026-08-15: the same `simctl openurl` run twice
// exited 0 both times with identical process state, and only the second one
// changed nothing on the device. Exit status alone cannot tell those apart, so
// no verdict here is computed from exit status alone.

// MARK: - Devices

/// One simulator, as `simctl list -j devices` describes it.
public struct IOSDevice: Codable, Sendable, Equatable {
    public var udid: String
    public var name: String
    /// Readable form — "iOS 18.2" — rendered from the runtime identifier.
    public var runtime: String
    /// The raw runtime identifier, kept because it is what `simctl` itself takes.
    public var runtimeIdentifier: String
    public var deviceTypeIdentifier: String?
    /// `Booted`, `Shutdown`, `Booting`, `Shutting Down` — CoreSimulator's own word.
    public var state: String
    /// Whether the runtime backing it is installed. A device that exists but is
    /// unavailable is a different answer from one that does not exist, so these
    /// are kept and marked rather than filtered out.
    public var isAvailable: Bool
    /// Whether *this session* booted it. Named for what it is: the marking lives
    /// in session memory and does not survive the agent restarting, so a device
    /// booted by a previous session is indistinguishable from one a person
    /// booted. A name promising more than that would be folklore.
    public var bootedByThisSession: Bool

    public init(udid: String, name: String, runtime: String, runtimeIdentifier: String,
                deviceTypeIdentifier: String? = nil, state: String, isAvailable: Bool,
                bootedByThisSession: Bool = false) {
        self.udid = udid; self.name = name; self.runtime = runtime
        self.runtimeIdentifier = runtimeIdentifier
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.state = state; self.isAvailable = isAvailable
        self.bootedByThisSession = bootedByThisSession
    }

    public var isBooted: Bool { state == "Booted" }

    /// The handle a caller holds. Deliberately **not** the shape of a window or
    /// app handle: the prefix is what every window-taking tool matches on to
    /// refuse it by name rather than failing somewhere deeper.
    public var handleID: String { IOSHandle.id(forUDID: udid) }
}

public enum IOSDeviceList {

    /// Decode `simctl list -j devices`.
    ///
    /// Runtime buckets with no devices are normal and are simply absent from the
    /// result; a device whose runtime is not installed is kept with
    /// `isAvailable: false`, because "there is a device here you cannot use" and
    /// "there is no device here" are different things to report.
    public static func parse(_ data: Data) throws -> [IOSDevice] {
        struct Payload: Decodable {
            struct Entry: Decodable {
                var udid: String
                var name: String
                var state: String
                var isAvailable: Bool?
                var deviceTypeIdentifier: String?
            }
            var devices: [String: [Entry]]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        var out: [IOSDevice] = []
        for (runtimeIdentifier, entries) in payload.devices {
            for entry in entries {
                out.append(IOSDevice(udid: entry.udid,
                                     name: entry.name,
                                     runtime: runtimeName(from: runtimeIdentifier),
                                     runtimeIdentifier: runtimeIdentifier,
                                     deviceTypeIdentifier: entry.deviceTypeIdentifier,
                                     state: entry.state,
                                     isAvailable: entry.isAvailable ?? true))
            }
        }
        // Stable order: runtime, then name, then udid. The dictionary the JSON
        // decodes into has none, and a list that reorders between two calls is a
        // list a caller cannot diff.
        return out.sorted {
            ($0.runtime, $0.name, $0.udid) < ($1.runtime, $1.name, $1.udid)
        }
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-18-2` → `iOS 18.2`. Anything that
    /// is not a CoreSimulator runtime identifier is returned exactly as it stands
    /// rather than mangled, because a wrong readable name is worse than a raw one
    /// — and a string with a dash in it is not evidence of anything.
    public static func runtimeName(from identifier: String) -> String {
        let marker = "SimRuntime."
        guard let range = identifier.range(of: marker) else { return identifier }
        let tail = String(identifier[range.upperBound...])
        let parts = tail.split(separator: "-")
        guard parts.count >= 2 else { return identifier }
        let platform = String(parts[0])
        let version = parts.dropFirst().joined(separator: ".")
        return "\(platform) \(version)"
    }
}

// MARK: - Handles

/// The device-handle namespace, and the refusal that goes with it.
///
/// Proctor's whole model is windows, and a simulator is a device holding apps.
/// Rather than dress one up as the other, a device gets its own handle shape and
/// every window-taking tool refuses it *by name*. The refusal is the load-bearing
/// part: a model that believes it can snapshot an iOS app because it holds a
/// handle would otherwise waste a campaign discovering otherwise one call at a
/// time.
public enum IOSHandle {

    public static let prefix = "dev-"

    public static func id(forUDID udid: String) -> String {
        prefix + udid.prefix(8).lowercased()
    }

    public static func isDeviceHandle(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    /// Why this handle cannot be used here, and what can. Names the route that
    /// works, because refusing an observation while Proctor is itself taking
    /// device screenshots for evidence would leave a campaign no way to look.
    public static func rejection(handle: String, tool: String) -> (message: String, remedy: String) {
        (message: "\(handle) is an iOS device handle and \(tool) needs a macOS window handle",
         remedy: "The Mac's accessibility API does not cross into a simulated device, so there is no "
               + "tree, no elements and no geometry to read for an iOS app. What is available: "
               + "proctor_ios action \"screenshot\" for the device surface, action \"open\" to drive "
               + "the app by deep link, and action \"list\" for what is booted. Window handles come "
               + "from proctor_apps.")
    }
}

// MARK: - simctl failures

public enum SimctlFailure {

    /// Turn a non-zero `simctl` exit into a sentence.
    ///
    /// Both classes were measured rather than guessed: an unclaimed scheme exits
    /// 194 with `NSOSStatusErrorDomain code=-10814`, and a shut-down device exits
    /// 149 with `com.apple.CoreSimulator.SimError code=405` and "Unable to lookup
    /// in current state: Shutdown". Matching on the stable substrings rather than
    /// the whole message keeps this working when Apple rewords the prose around
    /// them; anything unrecognised keeps its own text, because a failure reduced
    /// to a shrug is worse than a verbose one.
    public static func decode(exitCode: Int32, stderr: String) -> String {
        let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("-10814") || text.contains("kLSApplicationNotFoundErr") {
            return "no installed app claims this URL scheme"
        }
        if text.contains("Unable to lookup in current state")
            || (text.contains("SimError") && text.contains("405")) {
            return "the device is not booted"
        }
        if text.isEmpty {
            return "simctl exited \(exitCode) without explanation"
        }
        return "simctl exited \(exitCode): \(text)"
    }
}

// MARK: - Deep-link evidence and verdict

/// The pixel channel's calibration, in one place so the threshold and the numbers
/// behind it cannot drift apart.
public enum IOSPixel {
    /// Fraction of pixels that must differ before the screen counts as changed.
    ///
    /// Measured on an iPhone 16 Pro simulator, 2026-08-15, at a per-channel
    /// tolerance of 8/255:
    ///
    /// | case | changed fraction |
    /// |---|---|
    /// | idle device, nothing done | 0.00000 |
    /// | deep link that changed nothing | 0.00000 |
    /// | modest navigation (a page change) | 0.00204 |
    /// | app switch | 0.79822 |
    ///
    /// The idle floor measured exactly zero, so this sits an order of magnitude
    /// below the smallest real change rather than being tuned against noise.
    public static let changeThreshold: Double = 0.0005

    /// Per-channel difference, out of 255, before a pixel counts as changed.
    public static let channelTolerance: Int = 8

    /// What the pixel channel's own limit is, carried on every verdict that rests
    /// on it.
    ///
    /// This lane marks each device frame `trustworthy: false` because `simctl`
    /// reports no `SCFrameStatus`, and then uses a comparison of two such frames
    /// as the channel that decides `targetChanged` and `screenChanged`. That is a
    /// real tension and it is stated rather than left for a reader to notice: a
    /// frame whose freshness cannot be confirmed can in principle be stale, and a
    /// stale frame on either side moves the answer in either direction. The
    /// settle reduces it — a frame would have to be stale consistently across
    /// several samples to survive — but it does not remove it.
    public static let channelCaveat =
        "The screen-change channel compares two device frames, and a device frame carries no "
        + "SCFrameStatus, so neither one's freshness can be confirmed. A verdict resting on this "
        + "channel inherits that limit: it is the best evidence available for a simulated device, "
        + "not the same evidence a window capture carries."
}

/// What was observed around one `openurl`. Every field is what a channel
/// reported, never an inference from another channel.
public struct DeepLinkEvidence: Codable, Sendable, Equatable {
    public var delivered: Bool
    public var exitCode: Int32
    /// The bundle id the URL actually resolved to on the device, when it could be
    /// resolved. Nil for a universal link, whose handler depends on associated
    /// domains rather than on a scheme claim.
    public var handlerResolved: String?
    /// Whether the resolved target's job was present before and after. Nil when
    /// the liveness channel was unavailable or no handler was resolved.
    public var targetRunningBefore: Bool?
    public var targetRunningAfter: Bool?
    public var pidBefore: Int?
    public var pidAfter: Int?
    /// Fraction of the device screen that changed. **Nil means the channel did
    /// not report**, which is not the same as zero and is never read as one.
    public var changedFraction: Double?
    public var meanDifference: Double?
    /// The threshold this run was scored against. On the wire beside the
    /// measurement because a caller who raised it is reading a different verdict
    /// from the same number, and a result that reports one without the other
    /// cannot be re-judged later.
    public var changeThreshold: Double
    public var failureReason: String?

    public init(delivered: Bool, exitCode: Int32, handlerResolved: String? = nil,
                targetRunningBefore: Bool? = nil, targetRunningAfter: Bool? = nil,
                pidBefore: Int? = nil, pidAfter: Int? = nil,
                changedFraction: Double? = nil, meanDifference: Double? = nil,
                changeThreshold: Double = IOSPixel.changeThreshold,
                failureReason: String? = nil) {
        self.delivered = delivered; self.exitCode = exitCode
        self.handlerResolved = handlerResolved
        self.targetRunningBefore = targetRunningBefore
        self.targetRunningAfter = targetRunningAfter
        self.pidBefore = pidBefore; self.pidAfter = pidAfter
        self.changedFraction = changedFraction; self.meanDifference = meanDifference
        self.changeThreshold = changeThreshold
        self.failureReason = failureReason
    }

    /// Whether the screen changed, with "the channel said nothing" kept distinct
    /// from "the channel said nothing changed".
    public var screenChanged: Bool? {
        guard let changedFraction else { return nil }
        return changedFraction >= changeThreshold
    }

    /// Whether this call started the app, as opposed to finding it already warm.
    /// Reported beside the verdict rather than inside it: "this call started the
    /// app" and "the app is where the URL pointed" are different facts, and most
    /// deep links land on an app that is already running.
    public var launchedNow: Bool {
        guard let after = targetRunningAfter, after else { return false }
        if let before = targetRunningBefore, before { return false }
        if pidBefore == nil, pidAfter != nil { return true }
        return targetRunningBefore == false
    }
}

/// The verdict vocabulary. Every value is a claim this lane can defend from the
/// channels it actually has.
public enum DeepLinkVerdict: String, Codable, Sendable, Equatable {
    /// Delivered, the resolved target's job is present, and the screen changed.
    /// The only verdict that attributes the change to the app the URL named.
    case targetChanged
    /// Delivered and the screen changed, but the change cannot be attributed: no
    /// handler resolved, or the target's job is not present. A universal link
    /// Safari swallowed, a SpringBoard "Open in…?" sheet and a banner all land
    /// here, which is why it is separate from the verdict above rather than
    /// folded into it.
    case screenChanged
    /// Delivered, and nothing observable changed. **Not a failure**: a deep link
    /// to the screen the app is already on produces exactly this.
    case deliveredOnly
    /// Delivered, and the screen-change channel did not report at all. Separate
    /// from `deliveredOnly` on purpose: "nothing changed" and "nobody looked" are
    /// different facts, and folding them into one word is how a campaign comes to
    /// believe an unobserved run was an uneventful one.
    case deliveredUnobserved
    /// The target app was running before the URL was delivered and is gone after.
    /// A deep link that kills the app is the single most useful thing this lane
    /// can find, and it must never be filed under a screen that changed.
    case targetGone
    /// simctl refused it.
    case refused

    /// Whether this verdict is a positive claim about the app under test. A
    /// reader that only branches on a boolean gets the conservative answer.
    public var isAttributed: Bool { self == .targetChanged }

    /// Whether this verdict reports a fault in the app under test, as opposed to
    /// a refusal by the tooling.
    public var isAppFault: Bool { self == .targetGone }

    /// Decide, and say why. Pure, total, and never computed from exit status
    /// alone — which is the whole point of the lane.
    public static func decide(_ evidence: DeepLinkEvidence) -> (verdict: DeepLinkVerdict, note: String) {
        guard evidence.delivered else {
            return (.refused, evidence.failureReason
                    ?? SimctlFailure.decode(exitCode: evidence.exitCode, stderr: ""))
        }

        // A target that was running and is not running now outranks everything
        // else the channels say. The screen certainly changed — an app going away
        // changes it — and reporting that as a successful navigation would file a
        // crash as a pass.
        if evidence.targetRunningBefore == true, evidence.targetRunningAfter == false {
            return (.targetGone,
                    "The target app was running before the URL was delivered and is not running "
                    + "after it. The app went away while handling this deep link, which a screen "
                    + "change alone would have reported as success.")
        }

        switch evidence.screenChanged {
        case .none:
            return (.deliveredUnobserved,
                    "The URL was delivered. The screen-change channel did not report, so nothing "
                    + "here says whether the device moved: this is an absence of evidence, not "
                    + "evidence that nothing happened.")
        case .some(false):
            return (.deliveredOnly,
                    "The URL was delivered and nothing on the device screen changed. This is "
                    + "inconclusive rather than a failure: a deep link to the screen the app is "
                    + "already on is indistinguishable from one the app ignored.")
        case .some(true):
            if evidence.targetRunningAfter == true {
                return (.targetChanged,
                        "The URL was delivered, the target app is running, and the device screen "
                        + "changed. This does not establish which screen the app reached — the "
                        + "frontmost app on the device is not observable through this lane.")
            }
            if evidence.handlerResolved == nil {
                return (.screenChanged,
                        "The URL was delivered and the device screen changed, but no handler could "
                        + "be resolved for it, so the change is not attributed to any app. A "
                        + "universal link is handled through associated domains rather than a "
                        + "scheme claim and always lands here.")
            }
            return (.screenChanged,
                    "The URL was delivered and the device screen changed, but the resolved target "
                    + "app is not running, so the change is not attributed to it. A system sheet, a "
                    + "banner or another app answering the URL all look like this.")
        }
    }
}

// MARK: - URL splitting for the audit trail

/// A deep link, split into the half worth recording and the half worth hiding.
///
/// A deep link routinely carries a token in its query string. The trail records
/// the scheme and host in the clear — enough to know which app and which entry
/// point — and reduces the rest to length-plus-hash, which is the treatment
/// `type` text already gets. A trail that proved which screen was opened by
/// storing an auth token in plaintext would be the wrong trade.
public enum DeepLinkTarget {

    public static func split(url: String) -> (clear: String, redactable: String) {
        guard let range = url.range(of: "://") else {
            // No scheme separator: nothing can be safely called a host, so the
            // whole string is treated as the sensitive half.
            guard let colon = url.firstIndex(of: ":") else { return ("", url) }
            return (String(url[..<colon]) + ":", String(url[url.index(after: colon)...]))
        }
        let scheme = String(url[..<range.lowerBound])
        let rest = String(url[range.upperBound...])
        // The host runs to the first path, query or fragment delimiter.
        let delimiters: Set<Character> = ["/", "?", "#"]
        if let cut = rest.firstIndex(where: { delimiters.contains($0) }) {
            return (scheme + "://" + String(rest[..<cut]), String(rest[cut...]))
        }
        return (scheme + "://" + rest, "")
    }
}

// MARK: - Scheme resolution

/// Which app on the device claims a URL scheme.
///
/// The gate has to judge the app the URL actually reaches, never a name the
/// caller supplied — `SessionPolicy` already carries that rule for the macOS
/// lane, and gating a deep link on a caller-declared bundle id would reopen
/// exactly the hole it closed: allow-list one app, declare its name, open a URL
/// belonging to another.
///
/// The map is built from each installed app's `CFBundleURLTypes`. The caller does
/// the plist reading; this does the mapping.
public enum SchemeMap {

    /// Schemes that carry no handler claim. A universal link is routed through
    /// associated domains, which is not readable from a bundle, so Proctor says
    /// it cannot resolve one rather than guessing Safari.
    public static let unresolvableSchemes: Set<String> = ["http", "https"]

    /// Build the scheme → bundle id map. Lowercased throughout, because URL
    /// schemes are case-insensitive. First claim wins on a collision, and the
    /// order the caller supplies decides that.
    public static func build(apps: [(bundleId: String, schemes: [String])]) -> [String: String] {
        var out: [String: String] = [:]
        for app in apps {
            for scheme in app.schemes {
                let key = scheme.lowercased()
                guard !key.isEmpty, out[key] == nil else { continue }
                out[key] = app.bundleId
            }
        }
        return out
    }

    /// The scheme of a URL, lowercased, or nil when it has none.
    public static func scheme(of url: String) -> String? {
        guard let colon = url.firstIndex(of: ":") else { return nil }
        let scheme = String(url[..<colon]).lowercased()
        return scheme.isEmpty ? nil : scheme
    }

    /// Which app will receive this URL, when that is knowable.
    public static func handler(for url: String, in map: [String: String]) -> String? {
        guard let scheme = scheme(of: url), !unresolvableSchemes.contains(scheme) else { return nil }
        return map[scheme]
    }
}

// MARK: - The gate, qualified by platform

/// The policy decision for an iOS target.
///
/// `AppPolicy` keys on bundle identifier and an iOS app and a Mac app can share
/// one, so the rule is asymmetric on purpose:
///
/// - **Block** matches the bare bundle id *or* `ios:<bundleId>`. An operator who
///   blocked an app has blocked it on both platforms. Blocking more than intended
///   is safe.
/// - **Allow-list mode and the sensitive set** match `ios:<bundleId>` only. A Mac
///   app on the allow list never silently authorises the iOS app of the same
///   identifier. Allowing more than intended is not safe, so it does not happen
///   by omission.
public enum IOSPolicy {

    public static let qualifier = "ios:"

    public static func key(for bundleId: String) -> String { qualifier + bundleId }

    /// Decide for a resolved handler. A nil handler is an unidentifiable target
    /// and is refused whenever an allow list is in force, exactly as an
    /// unidentifiable Mac app is.
    public static func decide(handler: String?, policy: AppPolicy,
                              hasValidToken: Bool) -> PolicyDecision {
        guard let handler else {
            guard policy.allow.isEmpty else {
                return .blocked(reason:
                    "An allow list is in force and this URL could not be resolved to an app on the "
                    + "device; actuation is refused. A universal link is routed through associated "
                    + "domains rather than a scheme claim, so which app receives it is not knowable "
                    + "here.")
            }
            return .allow
        }
        // Block, on either spelling, and it wins over everything else.
        if policy.block.contains(handler) || policy.block.contains(key(for: handler)) {
            return .blocked(reason:
                "\(handler) is on the block list; actuation is refused.")
        }
        // Everything else judges the qualified key alone.
        return policy.decide(bundleId: key(for: handler), hasValidToken: hasValidToken)
    }
}
