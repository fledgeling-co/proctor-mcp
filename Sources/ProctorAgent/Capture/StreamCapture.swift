import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics
import ProctorCore

// The ScreenCaptureKit plumbing shared by one-shot capture and the long-lived
// quiet watch. CGWindowListCreateImage is obsoleted in the macOS 15+ SDK, so
// every path here is a stream, and every frame is read for the freshness
// metadata that tells a stale frame from a correct one.

// MARK: - Frame metadata

/// What one frame said about itself. Everything here comes off the sample
/// buffer's attachments rather than being inferred from the pixels.
struct FrameMeta: Sendable {
    var status: FrameStatus
    var contentRect: Rect?
    var dirtyRectCount: Int
    var dirtyArea: Double        // union of dirty rects over frame area, 0..1
    /// The rects themselves, in frame pixels. Kept rather than reduced to the
    /// number above, because a question about a sub-rectangle of the window
    /// cannot be answered from a whole-frame fraction.
    var dirtyRects: [Rect]
    var scaleFactor: Double
    var contentScale: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var receivedAt: Double

    static let empty = FrameMeta(status: .unknown, contentRect: nil, dirtyRectCount: 0,
                                 dirtyArea: 0, dirtyRects: [], scaleFactor: 1, contentScale: 1,
                                 pixelWidth: 0, pixelHeight: 0, receivedAt: 0)
}

/// Tightly packed BGRA bytes lifted out of the sample buffer. Copied because the
/// IOSurface behind a sample buffer is recycled the moment the callback returns.
struct FramePixels: Sendable {
    var data: Data
    var width: Int
    var height: Int
    var bytesPerRow: Int
}

enum FrameStatusRank {
    /// Higher is a more useful frame to fall back on when no complete one arrives.
    static func of(_ s: FrameStatus) -> Int {
        switch s {
        case .complete: return 5
        case .idle: return 4
        case .blank: return 3
        case .suspended: return 2
        case .stopped: return 1
        case .unknown: return 0
        }
    }
}

// MARK: - Sink

/// Receives frames on a dispatch queue and keeps the minimum needed. Lock-guarded
/// rather than actor-isolated because SCStreamOutput is a synchronous callback and
/// QuietWatch.poll() has to answer without suspending.
final class FrameSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let keepPixels: Bool

    private var frames = 0
    private var lastMeta: FrameMeta = .empty
    private var completeFrame: (FrameMeta, FramePixels?)?
    private var bestFrame: (FrameMeta, FramePixels?)?
    private var bestRank = -1
    private var stoppedFlag = false
    private var stopError: String?

    init(keepPixels: Bool) {
        self.keepPixels = keepPixels
        super.init()
    }

    struct Snapshot: Sendable {
        var frames: Int
        var last: FrameMeta
        var complete: (FrameMeta, FramePixels?)?
        var best: (FrameMeta, FramePixels?)?
        var stopped: Bool
        var stopError: String?
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(frames: frames, last: lastMeta, complete: completeFrame,
                        best: bestFrame, stopped: stoppedFlag, stopError: stopError)
    }

    /// The cheap read QuietWatch.poll() uses: no image data ever changes hands.
    func quietSnapshot() -> (dirtyArea: Double, status: FrameStatus, frames: Int, stopped: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (lastMeta.dirtyArea, stoppedFlag ? .stopped : lastMeta.status, frames, stoppedFlag)
    }

    /// The same read with the last frame's geometry intact, for a question about
    /// part of the window rather than all of it. Still no image data.
    func regionSnapshot() -> (meta: FrameMeta, frames: Int, stopped: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (lastMeta, frames, stoppedFlag)
    }

    func markStopped(_ reason: String?) {
        lock.lock(); defer { lock.unlock() }
        stoppedFlag = true
        if stopError == nil { stopError = reason }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let meta = FrameSink.readMeta(sampleBuffer, pixelBuffer: pixelBuffer)

        // Copying costs a full frame, so it happens only for a frame we would
        // actually return: the first complete one, or the best fallback so far.
        let rank = FrameStatusRank.of(meta.status)

        lock.lock()
        frames += 1
        lastMeta = meta
        let needComplete = keepPixels && meta.status == .complete && completeFrame == nil
        let needBest = keepPixels && rank > bestRank
        lock.unlock()

        var pixels: FramePixels?
        if needComplete || needBest, let pb = pixelBuffer {
            pixels = FrameSink.copyPixels(pb)
        }

        lock.lock()
        if meta.status == .complete && completeFrame == nil {
            completeFrame = (meta, pixels)
        }
        if rank > bestRank {
            bestRank = rank
            bestFrame = (meta, pixels ?? bestFrame?.1)
        }
        lock.unlock()
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        markStopped(error.localizedDescription)
    }

    // MARK: Attachment reading

    static func readMeta(_ sb: CMSampleBuffer, pixelBuffer: CVPixelBuffer?) -> FrameMeta {
        let now = Date().timeIntervalSince1970
        let pw = pixelBuffer.map { CVPixelBufferGetWidth($0) } ?? 0
        let ph = pixelBuffer.map { CVPixelBufferGetHeight($0) } ?? 0

        guard
            let raw = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false),
            let attachments = (raw as? [[SCStreamFrameInfo: Any]])?.first
        else {
            return FrameMeta(status: .unknown, contentRect: nil, dirtyRectCount: 0,
                             dirtyArea: 0, dirtyRects: [], scaleFactor: 1, contentScale: 1,
                             pixelWidth: pw, pixelHeight: ph, receivedAt: now)
        }

        var status = FrameStatus.unknown
        if let n = attachments[.status] as? Int, let s = SCFrameStatus(rawValue: n) {
            status = map(s)
        } else if let n = (attachments[.status] as? NSNumber)?.intValue,
                  let s = SCFrameStatus(rawValue: n) {
            status = map(s)
        }

        var contentRect: Rect?
        if let d = attachments[.contentRect] as? [String: Any],
           let r = CGRect(dictionaryRepresentation: d as CFDictionary) {
            contentRect = Rect(x: r.origin.x, y: r.origin.y, w: r.width, h: r.height)
        }

        var dirty: [Rect] = []
        if let list = attachments[.dirtyRects] as? [[String: Any]] {
            dirty = list.compactMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
                        .map { Rect(x: $0.origin.x, y: $0.origin.y, w: $0.width, h: $0.height) }
        }

        let scaleFactor = number(attachments[.scaleFactor]) ?? 1
        let contentScale = number(attachments[.contentScale]) ?? 1

        let frameArea = Double(pw * ph)
        var dirtyArea = 0.0
        if frameArea > 0 && !dirty.isEmpty {
            dirtyArea = min(1, max(0, RegionDirt.unionArea(dirty) / frameArea))
        }

        return FrameMeta(status: status, contentRect: contentRect, dirtyRectCount: dirty.count,
                         dirtyArea: dirtyArea, dirtyRects: dirty, scaleFactor: scaleFactor,
                         contentScale: contentScale, pixelWidth: pw, pixelHeight: ph,
                         receivedAt: now)
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let c = any as? CGFloat { return Double(c) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    static func map(_ s: SCFrameStatus) -> FrameStatus {
        switch s {
        case .complete: return .complete
        case .idle: return .idle
        case .blank: return .blank
        case .suspended: return .suspended
        case .stopped: return .stopped
        case .started: return .unknown
        @unknown default: return .unknown
        }
    }

    /// Repack to a tight BGRA buffer. The source row stride is padded for the GPU
    /// and every consumer downstream wants width * 4.
    static func copyPixels(_ pb: CVPixelBuffer) -> FramePixels? {
        guard CVPixelBufferLockBaseAddress(pb, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let srcStride = CVPixelBufferGetBytesPerRow(pb)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let dstStride = w * 4
        var out = Data(count: dstStride * h)
        out.withUnsafeMutableBytes { dst in
            guard let dstBase = dst.baseAddress else { return }
            for row in 0..<h {
                memcpy(dstBase.advanced(by: row * dstStride),
                       base.advanced(by: row * srcStride),
                       dstStride)
            }
        }
        return FramePixels(data: out, width: w, height: h, bytesPerRow: dstStride)
    }
}

// MARK: - Stream ownership

/// Holds an SCStream behind a lock so a Sendable wrapper can stop it from any
/// context without the stream itself ever crossing an isolation boundary.
final class StreamHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var stream: SCStream?
    private var stopped = false

    init(stream: SCStream) { self.stream = stream }

    var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    func stopNow() {
        lock.lock()
        let s = stream
        stream = nil
        stopped = true
        lock.unlock()
        s?.stopCapture { _ in }
    }
}

// MARK: - Shared construction

enum StreamBuilder {

    static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
        } catch {
            throw AgentError(
                code: .permissionScreenRecording,
                message: "ScreenCaptureKit would not list shareable content: \(error.localizedDescription)",
                remedy: Grants.screenRecordingFixText(osMajor: ProcessInfo.processInfo
                    .operatingSystemVersion.majorVersion))
        }
    }

    /// Locate the SCWindow behind a handle. A wrong window is worse than no
    /// window, so an ambiguous pid+frame match is refused rather than guessed.
    static func resolve(window: WindowHandle, in content: SCShareableContent) throws -> SCWindow {
        if let wid = window.cgWindowID {
            if let match = content.windows.first(where: { $0.windowID == wid }) { return match }
            throw AgentError(
                code: .windowNotFound,
                message: "No shareable window with CoreGraphics id \(wid). "
                       + "It has been closed, or it belongs to a process ScreenCaptureKit will not share.",
                remedy: "Re-enumerate windows for the app and capture with the fresh handle.")
        }

        guard let pid = pid(fromAppID: window.app) else {
            throw AgentError(
                code: .captureFailed,
                message: "The window handle carries no CoreGraphics window id and its app id "
                       + "'\(window.app)' does not parse to a pid, so the window cannot be identified.",
                remedy: "Re-attach the app so the handle carries a cgWindowID.")
        }

        let owned = content.windows.filter { $0.owningApplication?.processID == pid }
        let target = CGRect(x: window.frame.x, y: window.frame.y,
                            w: window.frame.w, h: window.frame.h)
        let candidates = owned.filter { close($0.frame, target, tolerance: 2) }

        if candidates.count == 1 { return candidates[0] }
        if candidates.isEmpty {
            throw AgentError(
                code: .windowNotFound,
                message: "Process \(pid) shares \(owned.count) window(s), none within 2pt of "
                       + "\(describe(target)). The window has moved, resized or closed.",
                remedy: "Re-enumerate windows for the app and capture with the fresh handle.")
        }
        throw AgentError(
            code: .captureFailed,
            message: "\(candidates.count) windows of process \(pid) sit within 2pt of "
                   + "\(describe(target)) and the handle carries no CoreGraphics window id, "
                   + "so the window cannot be identified. Capturing one of them would risk "
                   + "returning the wrong window's pixels.",
            remedy: "Re-attach the app so window handles carry a cgWindowID, or move the "
                  + "windows apart before capturing.",
            detail: .object([
                "pid": .number(Double(pid)),
                "candidateWindowIDs": .array(candidates.map { .number(Double($0.windowID)) }),
            ]))
    }

    static func configuration(for scWindow: SCWindow, scale: Double,
                              showsCursor: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.capturesAudio = false
        config.showsCursor = showsCursor
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // sRGB so sampled colours mean the same thing to the contrast maths as
        // they do to a person reading the PNG.
        config.colorSpaceName = CGColorSpace.sRGB
        config.scalesToFit = false
        let w = Int((scWindow.frame.width * scale).rounded())
        let h = Int((scWindow.frame.height * scale).rounded())
        config.width = min(max(w, 2), 16384)
        config.height = min(max(h, 2), 16384)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        return config
    }

    /// Backing scale of the display the window sits on. CGDisplayMode is used
    /// instead of NSScreen because NSScreen is main-actor bound and the agent
    /// may be running with its main thread busy.
    static func scaleFactor(for scWindow: SCWindow, in content: SCShareableContent) -> Double {
        let centre = CGPoint(x: scWindow.frame.midX, y: scWindow.frame.midY)
        let display = content.displays.first(where: { $0.frame.contains(centre) })
            ?? content.displays.max(by: {
                $0.frame.intersection(scWindow.frame).area < $1.frame.intersection(scWindow.frame).area
            })
        guard let id = display?.displayID,
              let mode = CGDisplayCopyDisplayMode(id),
              mode.width > 0 else { return 2 }
        let s = Double(mode.pixelWidth) / Double(mode.width)
        return s > 0 ? s : 2
    }

    static func pid(fromAppID id: String) -> pid_t? {
        // "app:<pid>:<epoch>"
        let parts = id.split(separator: ":")
        guard parts.count >= 2, let v = Int32(parts[1]) else { return nil }
        return pid_t(v)
    }

    private static func close(_ a: CGRect, _ b: CGRect, tolerance: Double) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func describe(_ r: CGRect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", r.origin.x, r.origin.y, r.width, r.height)
    }
}

extension CGRect {
    init(x: Double, y: Double, w: Double, h: Double) {
        self.init(x: x, y: y, width: w, height: h)
    }
    var area: CGFloat { isNull || isInfinite ? 0 : width * height }
}
