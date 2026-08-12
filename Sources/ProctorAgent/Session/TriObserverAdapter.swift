import Foundation
import ProctorCore

/// Adapts the capture side's `TriObserver` to the surface the assertion handler
/// needs. The comparison itself lives with the pixels; this only supplies the
/// frame each check is made against, so `agree`, `contrast` and `minHitSize`
/// all read the same instant.
final class TriObserverAdapter: TriObserving {

    private let capture: any CaptureEngine
    private let timeoutMs: Int

    init(capture: any CaptureEngine, timeoutMs: Int = 3000) {
        self.capture = capture
        self.timeoutMs = timeoutMs
    }

    private func frame(_ window: WindowHandle) async throws -> CaptureResult {
        let result = try await capture.capture(window: window, to: nil, waitForComplete: true,
                                               timeoutMs: timeoutMs, scale: nil,
                                               tileHashes: false, includeCursor: false)
        guard result.trustworthy else {
            throw AgentError(
                code: .captureStale,
                message: "the frame backing this check is not trustworthy"
                       + (result.caveat.map { " — \($0)" } ?? ""),
                remedy: "Raise the window or move the pointer onto its display and retry. An "
                      + "untrustworthy frame would produce a finding about the capture rather than "
                      + "about the UI.")
        }
        return result
    }

    func agree(window: WindowHandle, tree: AXNode) async throws -> [Disagreement] {
        let capture = try await frame(window)
        var findings = TriObserver.analyse(root: tree, window: window, geometry: nil,
                                           capture: capture, lastAXChangeAt: nil)
        findings += TriObserver.hitSizeFindings(root: tree)
        findings += TriObserver.contrastFindings(root: tree, window: window, capture: capture)
        return findings
    }

    func contrast(window: WindowHandle, node: AXNode) async throws -> Double {
        let capture = try await frame(window)
        guard let probe = PixelProbe(pngPath: capture.path) else {
            throw AgentError(code: .captureFailed,
                             message: "the captured frame at \(capture.path) could not be read")
        }
        guard let measurement = TriObserver.contrast(of: node, window: window,
                                                     capture: capture, probe: probe) else {
            throw AgentError(
                code: .captureFailed,
                message: "no contrasting colour could be sampled in \(node.role) — the region is "
                       + "smaller than 2x2 pixels, or a flat fill with no foreground to measure against")
        }
        return measurement.ratio
    }

    func hitSize(window: WindowHandle, node: AXNode) async throws -> Rect {
        guard let size = TriObserver.hitSize(of: node) else {
            throw AgentError(code: .nodeStale,
                             message: "\(node.role) exposes no frame, so it has no hit area")
        }
        let origin = node.frame ?? Rect(x: 0, y: 0, w: 0, h: 0)
        return Rect(x: origin.x, y: origin.y, w: size.w, h: size.h)
    }
}
