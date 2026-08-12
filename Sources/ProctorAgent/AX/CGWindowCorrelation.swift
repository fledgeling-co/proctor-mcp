import Foundation
import CoreGraphics
import ProctorCore

// Correlating an AX window with a CoreGraphics window number. Capture needs the
// number and AX does not expose it, so it is inferred from owner pid, frame and
// title. When more than one candidate fits, the number is reported as absent
// rather than guessed: a wrong window number captures the wrong window and
// nothing downstream can tell.

struct CGWindowRecord {
    var number: UInt32
    var pid: pid_t
    var bounds: CGRect
    var title: String?
    var layer: Int
}

enum CGWindowIndex {

    static let framePointTolerance: Double = 2.0

    static func records(option: CGWindowListOption, pid: pid_t? = nil) -> [CGWindowRecord] {
        guard let raw = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return raw.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? UInt32,
                  let owner = entry[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any]
            else { return nil }
            if let pid, owner != pid { return nil }
            let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) ?? .zero
            return CGWindowRecord(
                number: number,
                pid: owner,
                bounds: bounds,
                title: entry[kCGWindowName as String] as? String,
                layer: (entry[kCGWindowLayer as String] as? Int) ?? 0)
        }
    }

    /// Whether the app has anything on screen at all. This is what separates a
    /// genuinely windowless app from a Chromium app that has not built its tree.
    static func hasVisibleWindows(pid: pid_t) -> Bool {
        records(option: .optionOnScreenOnly, pid: pid).contains {
            $0.layer == 0 && $0.bounds.width > 1 && $0.bounds.height > 1
        }
    }

    static func correlate(frame: Rect, title: String?, in records: [CGWindowRecord]) -> UInt32? {
        let matches = records.filter { record in
            guard record.layer == 0 else { return false }
            guard close(Double(record.bounds.origin.x), frame.x),
                  close(Double(record.bounds.origin.y), frame.y),
                  close(Double(record.bounds.width), frame.w),
                  close(Double(record.bounds.height), frame.h) else { return false }
            return sameTitle(record.title, title)
        }
        return matches.count == 1 ? matches[0].number : nil
    }

    private static func close(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= framePointTolerance
    }

    private static func sameTitle(_ a: String?, _ b: String?) -> Bool {
        let left = a?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let right = b?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return left == right
    }
}
