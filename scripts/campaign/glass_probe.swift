// Window-server ground truth for the campaign's glass lane.
//
// The campaign needs to record what witnessed a process from the installed
// artifact reaching a display server. CGWindowListCopyWindowInfo is that
// witness: it is the window server's own list, so a process that never drew
// cannot appear in it.
//
// Prints one JSON object: every on-screen window, plus the accessibility-side
// window count for a named process, so the two planes can be compared. A
// window present in CG and absent from AX is the shape that makes a menu-bar
// app undriveable, and that difference is invisible from either plane alone.
//
// swift glass_probe.swift [ownerNameSubstring]

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let needle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Proctor"

struct WindowRow: Encodable {
    let ownerName: String
    let ownerPID: pid_t
    let windowNumber: Int
    let name: String
    let layer: Int
    let alpha: Double
    let sharingState: Int
    let bounds: [String: Double]
    let isOnscreen: Bool
}

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

var matched: [WindowRow] = []
for dict in info {
    let owner = dict[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.localizedCaseInsensitiveContains(needle) else { continue }
    let boundsDict = dict[kCGWindowBounds as String] as? [String: Any] ?? [:]
    var bounds: [String: Double] = [:]
    for key in ["X", "Y", "Width", "Height"] {
        bounds[key] = (boundsDict[key] as? NSNumber)?.doubleValue ?? 0
    }
    matched.append(WindowRow(
        ownerName: owner,
        ownerPID: (dict[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0,
        windowNumber: (dict[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0,
        name: dict[kCGWindowName as String] as? String ?? "",
        layer: (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
        alpha: (dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0,
        sharingState: (dict[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? -1,
        bounds: bounds,
        isOnscreen: (dict[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false))
}

// The accessibility plane, for the same processes. A window the window server
// draws and the accessibility tree does not expose cannot be actuated by any
// window-scoped tool, which is the whole reason both planes are read here.
struct AXRow: Encodable {
    let pid: pid_t
    let axWindowCount: Int
    let axWindowTitles: [String]
    let axTrusted: Bool
    let hasExtrasMenuBar: Bool
}

var axRows: [AXRow] = []
let pids = Set(matched.map(\.ownerPID)).union(
    NSWorkspace.shared.runningApplications
        .filter { ($0.localizedName ?? "").localizedCaseInsensitiveContains(needle) }
        .map(\.processIdentifier))

for pid in pids.sorted() {
    let app = AXUIElementCreateApplication(pid)
    var windowsValue: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)
    let windows = (err == .success ? windowsValue as? [AXUIElement] : nil) ?? []
    var titles: [String] = []
    for window in windows {
        var titleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String {
            titles.append(title)
        } else {
            titles.append("")
        }
    }
    var extrasValue: CFTypeRef?
    let extras = AXUIElementCopyAttributeValue(
        app, "AXExtrasMenuBar" as CFString, &extrasValue) == .success
    axRows.append(AXRow(pid: pid, axWindowCount: windows.count, axWindowTitles: titles,
                        axTrusted: AXIsProcessTrusted(), hasExtrasMenuBar: extras))
}

struct Report: Encodable {
    let needle: String
    let totalOnScreenWindows: Int
    let matchedWindows: [WindowRow]
    let accessibility: [AXRow]
    let displays: [[String: Double]]
}

var displays: [[String: Double]] = []
for screen in NSScreen.screens {
    displays.append([
        "x": screen.frame.origin.x, "y": screen.frame.origin.y,
        "width": screen.frame.width, "height": screen.frame.height,
        "backingScaleFactor": Double(screen.backingScaleFactor),
    ])
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(Report(
    needle: needle, totalOnScreenWindows: info.count,
    matchedWindows: matched, accessibility: axRows, displays: displays))
print(String(data: data, encoding: .utf8)!)
