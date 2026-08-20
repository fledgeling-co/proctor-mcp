// Independent recorders for the campaign's effect-witness rung.
//
// WHY THIS EXISTS. An `effect-witness` case owes a recorder, and a recorder that
// lives inside the process under test is the product describing itself. Every
// mode here runs in a DIFFERENT process from the Proctor agent and reads a
// channel the agent does not write: the window server's own list, the session
// event stream through a tap of this process's own, another process's
// accessibility server, and the window server's per-session event counters.
//
// It also holds the one DRIVER the campaign needs: `post`, which puts an event
// into the session from outside the agent, so a tap firing on it proves the tap
// fired on something the agent did not produce.
//
// The tap this file installs is TAIL-APPENDED, deliberately. Proctor's input
// block head-inserts a `.defaultTap` that swallows what it does not recognise,
// so an event the block destroys never reaches a tail tap. That asymmetry is
// what turns "the agent says it swallowed 4" into a third party watching four
// events fail to arrive.
//
// Every mode prints ONE JSON object to stdout and nothing else, so the output is
// the artifact rather than a description of one.
//
//   swiftc -O witness_probe.swift -o /tmp/witness_probe
//   witness_probe observe <seconds> <out.json>
//   witness_probe post <count> [--tag] [--gap-ms N]
//   witness_probe postobserve <count> <seconds> <out.json> [--tag]
//   witness_probe windows <ownerNeedle> <out.json>
//   witness_probe axtree <pid> <out.json>
//   witness_probe axtext <pid> <out.json>
//   witness_probe axnotify <pid> <seconds> <out.json>
//   witness_probe capture <cgWindowID> <out.png> <out.json>

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// The tag Proctor stamps on its own event sources. Duplicated here as a literal
// rather than imported, because this program must be able to recognise the
// agent's events without linking the agent's code — a recorder that shares a
// constant's definition with the thing it observes still has one thing in
// common with it, and this is the cheapest one to give up.
let proctorTag: Int64 = 0x5052_4F43_544F_5200

/// This probe's own mark, so an event it posted is attributable in a session
/// that has other producers in it. It is NOT the Proctor tag, so
/// `InputBlock.isOurs` is false for it and the block treats it exactly as it
/// treats a hand at the keyboard. On the machine this was written for, a live
/// Screen Sharing agent was posting into the same session throughout, which is
/// precisely why a bare "untagged" count would not have been attributable.
let probeMark: Int64 = 0x5052_4F30_3037_3800

let watchedTypes: [CGEventType] = [.keyDown, .keyUp, .leftMouseDown, .leftMouseUp,
                                   .rightMouseDown, .rightMouseUp, .scrollWheel,
                                   .otherMouseDown, .otherMouseUp]

func typeName(_ t: CGEventType) -> String {
    switch t {
    case .keyDown: return "keyDown"
    case .keyUp: return "keyUp"
    case .leftMouseDown: return "leftMouseDown"
    case .leftMouseUp: return "leftMouseUp"
    case .rightMouseDown: return "rightMouseDown"
    case .rightMouseUp: return "rightMouseUp"
    case .scrollWheel: return "scrollWheel"
    case .otherMouseDown: return "otherMouseDown"
    case .otherMouseUp: return "otherMouseUp"
    case .tapDisabledByTimeout: return "tapDisabledByTimeout"
    case .tapDisabledByUserInput: return "tapDisabledByUserInput"
    default: return "other(\(t.rawValue))"
    }
}

func counters() -> [String: UInt32] {
    var out: [String: UInt32] = [:]
    for t in watchedTypes {
        out[typeName(t)] = CGEventSource.counterForEventType(.combinedSessionState, eventType: t)
    }
    return out
}

func emit(_ object: [String: Any], to path: String?) {
    let data = try! JSONSerialization.data(withJSONObject: object,
                                           options: [.prettyPrinted, .sortedKeys])
    if let path { try? data.write(to: URL(fileURLWithPath: path)) }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func die(_ message: String) -> Never {
    emit(["ok": false, "error": message], to: nil)
    exit(2)
}

// MARK: - The observing tap

final class Observer {
    var events: [[String: Any]] = []
    var tapCreated = false
    var tapFailure: String?
    private var port: CFMachPort?

    /// Tail-appended and listen-only. See the header: head-insertion would put
    /// this program in front of Proctor's block and destroy the very asymmetry
    /// the measurement depends on.
    func install() {
        let mask = watchedTypes.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<Observer>.fromOpaque(info).takeUnretainedValue()
            me.record(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                              place: .tailAppendEventTap,
                                              options: .listenOnly,
                                              eventsOfInterest: mask,
                                              callback: callback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            tapFailure = "CGEvent.tapCreate returned nil — this process is not approved for "
                       + "Input Monitoring, so nothing here observed anything"
            return
        }
        port = created
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        tapCreated = true
    }

    private func record(type: CGEventType, event: CGEvent) {
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        let data = event.getIntegerValueField(.eventSourceUserData)
        events.append([
            "type": typeName(type),
            "sourcePid": pid,
            "userData": data,
            "userDataIsProctorTag": data == proctorTag,
            "userDataIsProbeMark": data == probeMark,
            "at": Date().timeIntervalSince1970
        ])
    }
}

func run(seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        CFRunLoopRunInMode(.defaultMode, 0.05, false)
    }
}

// MARK: - The driver

/// A zero-delta scroll. Chosen because it sits in both the input block's mask
/// and the contention monitor's mask while changing nothing in whatever
/// application receives it, so a run that fails to swallow it costs the operator
/// nothing.
func postScroll(tagged: Bool) -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                              wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)
    else { return false }
    event.setIntegerValueField(.eventSourceUserData, value: tagged ? proctorTag : probeMark)
    event.post(tap: .cgSessionEventTap)
    return true
}

// MARK: - The window server's own list

func windowRows(needle: String) -> [[String: Any]] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    var rows: [[String: Any]] = []
    for dict in info {
        let owner = dict[kCGWindowOwnerName as String] as? String ?? ""
        guard needle.isEmpty || owner.localizedCaseInsensitiveContains(needle) else { continue }
        let boundsDict = dict[kCGWindowBounds as String] as? [String: Any] ?? [:]
        var bounds: [String: Double] = [:]
        for key in ["X", "Y", "Width", "Height"] {
            bounds[key] = (boundsDict[key] as? NSNumber)?.doubleValue ?? 0
        }
        rows.append([
            "ownerName": owner,
            "ownerPID": (dict[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0,
            "windowNumber": (dict[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0,
            "name": dict[kCGWindowName as String] as? String ?? "",
            "layer": (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            "alpha": (dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0,
            "sharingState": (dict[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? -1,
            "bounds": bounds
        ])
    }
    return rows
}

// MARK: - Another process's accessibility server, read by this process

/// Walks the target's tree with this program's own AX client, so the node count
/// is one this process obtained from the target rather than one Proctor reported.
/// Bounded in depth and breadth, because an unbounded walk of a large
/// application is a different measurement every time it runs.
func axWalk(element: AXUIElement, depth: Int, maxDepth: Int,
            reads: inout Int, errors: inout [String: Int], sample: inout [String]) -> Int {
    guard depth <= maxDepth else { return 0 }
    var nodes = 1
    var roleRef: CFTypeRef?
    let roleErr = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    reads += 1
    if roleErr == .success {
        let role = (roleRef as? String) ?? "?"
        var titleRef: CFTypeRef?
        let titleErr = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        reads += 1
        let title = titleErr == .success ? ((titleRef as? String) ?? "") : ""
        if sample.count < 40 { sample.append(title.isEmpty ? role : "\(role):\(title)") }
    } else {
        errors[String(describing: roleErr), default: 0] += 1
    }
    var childRef: CFTypeRef?
    let childErr = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childRef)
    reads += 1
    if childErr == .success, let kids = childRef as? [AXUIElement] {
        for kid in kids.prefix(60) {
            nodes += axWalk(element: kid, depth: depth + 1, maxDepth: maxDepth,
                            reads: &reads, errors: &errors, sample: &sample)
        }
    } else if childErr != .success && childErr != .attributeUnsupported && childErr != .noValue {
        errors[String(describing: childErr), default: 0] += 1
    }
    return nodes
}

// MARK: - Every string another process's AX tree exposes
//
// `axtree` records structure. This records the *text*, so a picture's subject
// can be proved against strings a third process read out of the target rather
// than against the picture's filename or its size. The strings come from
// AXValue, AXDescription and AXTitle, which is where a control's visible label
// lives depending on how the app was built.

func axStrings(element: AXUIElement, depth: Int, maxDepth: Int,
               reads: inout Int, out: inout [String]) -> Int {
    guard depth <= maxDepth else { return 0 }
    var nodes = 1
    for attr in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute] {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
        reads += 1
        if err == .success, let text = ref as? String, !text.isEmpty {
            out.append(text)
        }
    }
    var childRef: CFTypeRef?
    let childErr = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childRef)
    reads += 1
    if childErr == .success, let kids = childRef as? [AXUIElement] {
        for kid in kids.prefix(60) {
            nodes += axStrings(element: kid, depth: depth + 1, maxDepth: maxDepth,
                               reads: &reads, out: &out)
        }
    }
    return nodes
}

// MARK: - Another process's notifications, observed by this process

final class NotifySink {
    var received: [[String: Any]] = []
}

func axNotify(pid: pid_t, seconds: Double) -> [String: Any] {
    let sink = NotifySink()
    var observer: AXObserver?
    let callback: AXObserverCallback = { _, _, name, refcon in
        guard let refcon else { return }
        let sink = Unmanaged<NotifySink>.fromOpaque(refcon).takeUnretainedValue()
        sink.received.append(["name": name as String, "at": Date().timeIntervalSince1970])
    }
    let createErr = AXObserverCreate(pid, callback, &observer)
    guard createErr == .success, let observer else {
        return ["ok": false, "reason": "AXObserverCreate: \(createErr)", "count": 0]
    }
    let app = AXUIElementCreateApplication(pid)
    let wanted = [kAXValueChangedNotification, kAXFocusedUIElementChangedNotification,
                  kAXWindowMovedNotification, kAXWindowResizedNotification,
                  kAXTitleChangedNotification, kAXUIElementDestroyedNotification,
                  kAXCreatedNotification, kAXMainWindowChangedNotification,
                  kAXSelectedTextChangedNotification]
    var added: [String] = []
    var refused: [String: String] = [:]
    for name in wanted {
        let err = AXObserverAddNotification(observer, app, name as CFString,
                                            Unmanaged.passUnretained(sink).toOpaque())
        if err == .success { added.append(name) } else { refused[name] = String(describing: err) }
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    run(seconds: seconds)
    return ["ok": true, "registered": added, "refused": refused,
            "count": sink.received.count, "events": sink.received]
}

// MARK: - The window server's own picture of a window

/// `screencapture -l` is the system's own utility asking the window server for a
/// named window. It is not ScreenCaptureKit through Proctor's stream and it is
/// not this program compositing anything, which is the property that makes it
/// usable as a second channel against `SCFrameStatus`. It needs Screen Recording
/// for whichever process is responsible for this one, and a refusal is reported
/// rather than turned into a zero.
func captureWindow(id: CGWindowID, to path: String) -> [String: Any] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l", String(id), path]
    let err = Pipe()
    task.standardError = err
    do { try task.run() } catch {
        return ["ok": false, "reason": "screencapture could not be run: \(error)",
                "windowID": Int(id)]
    }
    task.waitUntilExit()
    let stderrText = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
    guard task.terminationStatus == 0,
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else {
        return ["ok": false, "windowID": Int(id),
                "exitCode": Int(task.terminationStatus),
                "reason": "screencapture -l wrote nothing: "
                        + (stderrText.isEmpty ? "no message on stderr" : stderrText)]
    }
    var width = 0, height = 0
    if data.count >= 24, data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) {
        width = Int(data[16]) << 24 | Int(data[17]) << 16 | Int(data[18]) << 8 | Int(data[19])
        height = Int(data[20]) << 24 | Int(data[21]) << 16 | Int(data[22]) << 8 | Int(data[23])
    }
    var buckets = [UInt64](repeating: 0, count: 16)
    for (i, byte) in data.enumerated() { buckets[i % 16] &+= UInt64(byte) }
    let signature = buckets.map { String($0 % 997) }.joined(separator: "-")
    return ["ok": true, "windowID": Int(id), "path": path, "bytes": data.count,
            "width": width, "height": height, "signature": signature,
            "channel": "screencapture -l, the system utility, run by this probe process"]
}

// MARK: - Entry

let argv = CommandLine.arguments
guard argv.count >= 2 else { die("usage: witness_probe <mode> …") }
let mode = argv[1]
let stamp = ISO8601DateFormatter().string(from: Date())
let me = ProcessInfo.processInfo.processIdentifier

switch mode {
case "observe":
    guard argv.count >= 4, let seconds = Double(argv[2]) else { die("observe <seconds> <out.json>") }
    let observer = Observer()
    observer.install()
    let before = counters()
    run(seconds: seconds)
    let after = counters()
    var delta: [String: Int] = [:]
    for (k, v) in after { delta[k] = Int(v) - Int(before[k] ?? 0) }
    emit(["mode": "observe", "at": stamp, "probePid": me, "seconds": seconds,
          "tapCreated": observer.tapCreated, "tapFailure": observer.tapFailure as Any,
          "observedCount": observer.events.count, "observed": observer.events,
          "sessionCountersBefore": before.mapValues { Int($0) },
          "sessionCountersAfter": after.mapValues { Int($0) },
          "sessionCounterDelta": delta], to: argv[3])

case "post":
    guard argv.count >= 3, let count = Int(argv[2]) else { die("post <count> [--tag] [--gap-ms N]") }
    let tagged = argv.contains("--tag")
    var gap = 120
    if let i = argv.firstIndex(of: "--gap-ms"), i + 1 < argv.count { gap = Int(argv[i + 1]) ?? gap }
    var posted = 0
    let before = counters()
    for _ in 0..<count {
        if postScroll(tagged: tagged) { posted += 1 }
        usleep(UInt32(gap) * 1000)
    }
    usleep(200_000)
    let after = counters()
    emit(["mode": "post", "at": stamp, "probePid": me, "tagged": tagged,
          "requested": count, "posted": posted,
          "sessionCounterDeltaScroll": Int(after["scrollWheel"] ?? 0) - Int(before["scrollWheel"] ?? 0)],
         to: nil)

case "postobserve":
    guard argv.count >= 5, let count = Int(argv[2]), let seconds = Double(argv[3])
    else { die("postobserve <count> <seconds> <out.json> [--tag]") }
    let tagged = argv.contains("--tag")
    let observer = Observer()
    observer.install()
    let before = counters()
    var posted = 0
    // Post first, then keep the loop alive so a delivered event has somewhere to
    // arrive. A tap with nothing servicing it is disabled by macOS, so the loop
    // runs between posts rather than only after them.
    for _ in 0..<count {
        if postScroll(tagged: tagged) { posted += 1 }
        run(seconds: 0.15)
    }
    run(seconds: seconds)
    let after = counters()
    let mine = observer.events.filter { ($0["userDataIsProbeMark"] as? Bool) == true }
    emit(["mode": "postobserve", "at": stamp, "probePid": me, "tagged": tagged,
          "tapCreated": observer.tapCreated, "tapFailure": observer.tapFailure as Any,
          "posted": posted,
          "survivedToTailTap": mine.count,
          "observedCount": observer.events.count,
          "observed": observer.events,
          "sessionCounterDeltaScroll": Int(after["scrollWheel"] ?? 0) - Int(before["scrollWheel"] ?? 0)],
         to: argv[4])

case "windows":
    guard argv.count >= 4 else { die("windows <ownerNeedle> <out.json>") }
    let front = NSWorkspace.shared.frontmostApplication
    emit(["mode": "windows", "at": stamp, "probePid": me, "needle": argv[2],
          "frontmostPid": front?.processIdentifier as Any,
          "frontmostName": front?.localizedName as Any,
          "frontmostBundleID": front?.bundleIdentifier as Any,
          "rows": windowRows(needle: argv[2])], to: argv[3])

case "axtree":
    guard argv.count >= 4, let pid = Int32(argv[2]) else { die("axtree <pid> <out.json>") }
    var reads = 0
    var errors: [String: Int] = [:]
    var sample: [String] = []
    let app = AXUIElementCreateApplication(pid)
    let nodes = axWalk(element: app, depth: 0, maxDepth: 8, reads: &reads,
                       errors: &errors, sample: &sample)
    var owner: pid_t = 0
    let pidErr = AXUIElementGetPid(app, &owner)
    emit(["mode": "axtree", "at": stamp, "probePid": me, "targetPid": Int(pid),
          "axTrusted": AXIsProcessTrusted(),
          "elementOwnerPid": Int(owner), "elementOwnerErr": String(describing: pidErr),
          "nodes": nodes, "attributeReads": reads, "errors": errors,
          "sample": sample], to: argv[3])

case "axtext":
    guard argv.count >= 4, let pid = Int32(argv[2]) else { die("axtext <pid> <out.json>") }
    var textReads = 0
    var strings: [String] = []
    let textApp = AXUIElementCreateApplication(pid)
    var textOwner: pid_t = 0
    let textPidErr = AXUIElementGetPid(textApp, &textOwner)
    let textNodes = axStrings(element: textApp, depth: 0, maxDepth: 8,
                              reads: &textReads, out: &strings)
    emit(["mode": "axtext", "at": stamp, "probePid": me, "targetPid": Int(pid),
          "axTrusted": AXIsProcessTrusted(),
          "elementOwnerPid": Int(textOwner), "elementOwnerErr": String(describing: textPidErr),
          "nodes": textNodes, "attributeReads": textReads,
          "stringCount": strings.count, "strings": strings], to: argv[3])

case "axnotify":
    guard argv.count >= 5, let pid = Int32(argv[2]), let seconds = Double(argv[3])
    else { die("axnotify <pid> <seconds> <out.json>") }
    var out = axNotify(pid: pid, seconds: seconds)
    out["mode"] = "axnotify"
    out["at"] = stamp
    out["probePid"] = me
    out["targetPid"] = Int(pid)
    out["axTrusted"] = AXIsProcessTrusted()
    emit(out, to: argv[4])

case "capture":
    guard argv.count >= 5, let wid = UInt32(argv[2]) else { die("capture <cgWindowID> <out.png> <out.json>") }
    var out = captureWindow(id: CGWindowID(wid), to: argv[3])
    out["mode"] = "capture"
    out["at"] = stamp
    out["probePid"] = me
    emit(out, to: argv[4])

default:
    die("unknown mode \(mode)")
}
