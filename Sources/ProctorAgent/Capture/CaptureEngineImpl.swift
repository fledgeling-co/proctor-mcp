import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import ProctorCore

// One-shot window capture, and the long-lived dirty-area watch that settle uses.

final class CaptureEngineImpl: CaptureEngine {

    /// Where a capture lands when the caller names no path.
    let captureDirectory: String

    init(captureDirectory: String? = nil) {
        if let captureDirectory {
            self.captureDirectory = captureDirectory
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.captureDirectory = "\(home)/Library/Application Support/app.fledgeling.procter/captures"
        }
    }

    // MARK: - Capture

    func capture(window: WindowHandle, to path: String?, waitForComplete: Bool,
                 timeoutMs: Int, scale: Double?, tileHashes: Bool,
                 includeCursor: Bool) async throws -> CaptureResult {

        let content = try await StreamBuilder.shareableContent()
        let scWindow = try StreamBuilder.resolve(window: window, in: content)
        let effectiveScale = scale ?? StreamBuilder.scaleFactor(for: scWindow, in: content)

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = StreamBuilder.configuration(for: scWindow, scale: effectiveScale,
                                                 showsCursor: includeCursor)
        let sink = FrameSink(keepPixels: true)
        let stream = SCStream(filter: filter, configuration: config, delegate: sink)
        let queue = DispatchQueue(label: "app.fledgeling.procter.capture", qos: .userInitiated)

        do {
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            throw AgentError(
                code: .captureFailed,
                message: "Could not start a capture stream on window \(window.id): \(error.localizedDescription)",
                remedy: "Confirm Screen Recording is granted and the window still exists.")
        }

        let deadline = Date().addingTimeInterval(Double(max(timeoutMs, 1)) / 1000)
        var chosen: (FrameMeta, FramePixels?)?
        var timedOut = false

        while true {
            let s = sink.snapshot()
            if let complete = s.complete, complete.1 != nil { chosen = complete; break }
            if !waitForComplete, let best = s.best, best.1 != nil { chosen = best; break }
            if s.stopped, let best = s.best, best.1 != nil { chosen = best; break }
            if Date() >= deadline {
                timedOut = true
                chosen = s.best
                break
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        let framesWaited = sink.snapshot().frames
        let stopped = sink.snapshot().stopped
        try? await stream.stopCapture()

        guard let (meta, maybePixels) = chosen, let pixels = maybePixels else {
            throw AgentError(
                code: .captureFailed,
                message: "No frame arrived for window \(window.id) within \(timeoutMs)ms"
                       + (stopped ? "; the stream stopped before delivering one." : "."),
                remedy: window.isOnActiveSpace
                    ? "Raise the window or increase the timeout, then retry."
                    : "The window is not on the active Space. ScreenCaptureKit may only emit "
                    + "frames for it when the pointer moves on its display; bring the window "
                    + "to the active Space or retry with a longer timeout.")
        }

        let destination = path ?? defaultPath(for: window)
        try writePNG(pixels, to: destination)

        let contentRectIsReal = (meta.contentRect?.w ?? 0) > 0 && (meta.contentRect?.h ?? 0) > 0
        let trustworthy = meta.status == .complete && contentRectIsReal

        var caveat: String?
        if !trustworthy {
            if timedOut && !window.isOnActiveSpace {
                // Off-screen and occluded windows can go a long time without a
                // complete frame; ScreenCaptureKit has been observed to emit one
                // only once the pointer moves on that window's display. Returning
                // the idle frame with the reason beats throwing, and beats
                // passing it off as fresh.
                caveat = "Timed out after \(timeoutMs)ms with no complete frame. The window is "
                       + "not on the active Space, and ScreenCaptureKit may only emit complete "
                       + "frames for an off-screen or occluded window when the pointer moves on "
                       + "its display. Returned the best frame seen, status \(meta.status.rawValue)."
            } else if timedOut {
                caveat = "Timed out after \(timeoutMs)ms with no complete frame. Returned the "
                       + "best frame seen, status \(meta.status.rawValue)."
            } else if stopped {
                caveat = "The capture stream stopped before a complete frame arrived. Returned "
                       + "the best frame seen, status \(meta.status.rawValue)."
            } else if meta.status != .complete {
                caveat = "Frame status was \(meta.status.rawValue), not complete."
            } else {
                caveat = "Frame reported status complete with an empty content rect, which means "
                       + "the surface carried no content for this window."
            }
        }

        let effectivePixelScale = pixels.width > 0 && scWindow.frame.width > 0
            ? Double(pixels.width) / Double(scWindow.frame.width)
            : effectiveScale

        return CaptureResult(
            window: window.id,
            path: destination,
            width: pixels.width,
            height: pixels.height,
            scale: effectivePixelScale,
            status: meta.status,
            contentRect: meta.contentRect,
            dirtyRectCount: meta.dirtyRectCount,
            dirtyArea: meta.dirtyArea,
            capturedAt: meta.receivedAt > 0 ? meta.receivedAt : Date().timeIntervalSince1970,
            framesWaited: framesWaited,
            trustworthy: trustworthy,
            caveat: caveat,
            tileHashes: tileHashes ? CaptureEngineImpl.tileHashes(of: pixels) : nil)
    }

    // MARK: - Quiet watch

    func beginQuietWatch(window: WindowHandle) async throws -> QuietWatch {
        let content = try await StreamBuilder.shareableContent()
        let scWindow = try StreamBuilder.resolve(window: window, in: content)
        let scale = StreamBuilder.scaleFactor(for: scWindow, in: content)

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = StreamBuilder.configuration(for: scWindow, scale: scale, showsCursor: false)
        // Nothing is written to disk and no pixels are retained: the watch exists
        // to answer "how much changed" cheaply, many times a second.
        let sink = FrameSink(keepPixels: false)
        let stream = SCStream(filter: filter, configuration: config, delegate: sink)
        let queue = DispatchQueue(label: "app.fledgeling.procter.quietwatch", qos: .userInitiated)

        do {
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            throw AgentError(
                code: .captureFailed,
                message: "Could not start a quiet-watch stream on window \(window.id): "
                       + error.localizedDescription,
                remedy: "Confirm Screen Recording is granted and the window still exists.")
        }

        return QuietWatchImpl(sink: sink, holder: StreamHolder(stream: stream),
                              windowSize: Rect(x: scWindow.frame.origin.x,
                                               y: scWindow.frame.origin.y,
                                               w: scWindow.frame.width,
                                               h: scWindow.frame.height),
                              configuredScale: scale)
    }

    // MARK: - Output

    private func defaultPath(for window: WindowHandle) -> String {
        try? FileManager.default.createDirectory(atPath: captureDirectory,
                                                 withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let safe = window.id.replacingOccurrences(of: ":", with: "-")
        return "\(captureDirectory)/\(safe)-\(stamp).png"
    }

    private func writePNG(_ pixels: FramePixels, to path: String) throws {
        guard let image = CaptureEngineImpl.makeImage(pixels) else {
            throw AgentError(code: .captureFailed,
                             message: "The captured frame could not be turned into an image.")
        }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw AgentError(code: .captureFailed,
                             message: "Could not open \(path) for writing a PNG.",
                             remedy: "Check the directory exists and is writable.")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw AgentError(code: .captureFailed,
                             message: "Writing the PNG to \(path) failed.")
        }
    }

    static func makeImage(_ pixels: FramePixels) -> CGImage? {
        guard pixels.width > 0, pixels.height > 0,
              let provider = CGDataProvider(data: pixels.data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: pixels.width,
                       height: pixels.height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: pixels.bytesPerRow,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: bitmapInfo,
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    // MARK: - Tiles

    /// One hash per region rather than one for the whole frame, so a determinism
    /// comparison can say where two runs differ instead of only that they do.
    static func tileHashes(of pixels: FramePixels, maxTiles: Int = 16) -> [String] {
        let cols = max(1, min(maxTiles, pixels.width))
        let rows = max(1, min(maxTiles, pixels.height))
        var out: [String] = []
        out.reserveCapacity(cols * rows)

        pixels.data.withUnsafeBytes { raw -> Void in
            guard let base = raw.baseAddress else { return }
            for row in 0..<rows {
                let y0 = pixels.height * row / rows
                let y1 = pixels.height * (row + 1) / rows
                for col in 0..<cols {
                    let x0 = pixels.width * col / cols
                    let x1 = pixels.width * (col + 1) / cols
                    var tile = Data()
                    tile.reserveCapacity(max(0, (x1 - x0) * (y1 - y0) * 4))
                    for y in y0..<y1 {
                        let start = y * pixels.bytesPerRow + x0 * 4
                        let length = max(0, (x1 - x0) * 4)
                        if length == 0 { continue }
                        tile.append(Data(bytes: base.advanced(by: start), count: length))
                    }
                    out.append(Canonical.sha256(tile.base64EncodedString()))
                }
            }
        }
        return out
    }
}

// MARK: - QuietWatch

/// A running stream that keeps no images. Stored state is a Sendable holder and
/// a lock-guarded sink, so the whole wrapper is safely Sendable.
final class QuietWatchImpl: QuietWatch {
    private let sink: FrameSink
    private let holder: StreamHolder
    /// The window as the capture sees it, in points, and the scale the stream was
    /// configured at. Both are needed to place a window-coordinate rectangle in
    /// the frame, and neither can be read back off a frame alone.
    private let windowSize: Rect
    private let configuredScale: Double

    init(sink: FrameSink, holder: StreamHolder, windowSize: Rect, configuredScale: Double) {
        self.sink = sink
        self.holder = holder
        self.windowSize = windowSize
        self.configuredScale = configuredScale
    }

    func poll() -> (dirtyArea: Double, status: FrameStatus, frames: Int) {
        let s = sink.quietSnapshot()
        // A stopped stream reports itself as stopped rather than repeating its
        // last dirty area forever, which would read to a caller as quiet.
        if holder.isStopped || s.stopped {
            return (0, .stopped, s.frames)
        }
        return (s.dirtyArea, s.status, s.frames)
    }

    func poll(region: Rect) -> RegionQuietSample {
        let s = sink.regionSnapshot()
        let status: FrameStatus = (holder.isStopped || s.stopped) ? .stopped : s.meta.status

        func unmeasured(_ code: AgentError.Code, _ message: String,
                        remedy: String? = nil, pixels: Rect? = nil) -> RegionQuietSample {
            RegionQuietSample(dirtyArea: nil, status: status, frames: s.frames,
                              regionPixels: pixels,
                              error: AgentError(code: code, message: message, remedy: remedy))
        }

        if holder.isStopped || s.stopped {
            return unmeasured(.captureStale,
                              "the capture stream for this window has stopped, so nothing is "
                            + "being measured in the region",
                              remedy: "Start the wait again; if it keeps stopping, check the "
                                    + "Screen Recording grant with proctor_doctor.")
        }
        guard s.frames > 0 else {
            return unmeasured(.captureStale,
                              "no frame has arrived from the capture stream yet, so the region "
                            + "has not been measured",
                              remedy: "ScreenCaptureKit emits a frame when the window changes; "
                                    + "an off-screen window may emit none until the pointer moves "
                                    + "on its display.")
        }

        let scale = s.meta.pixelWidth > 0 && windowSize.w > 0
            ? Double(s.meta.pixelWidth) / windowSize.w
            : configuredScale
        guard scale > 0, s.meta.pixelWidth > 0, s.meta.pixelHeight > 0 else {
            return unmeasured(.captureFailed,
                              "the frame reports no pixel dimensions, so points cannot be "
                            + "converted to pixels and the region cannot be placed")
        }

        let origin = s.meta.contentRect ?? Rect(x: 0, y: 0, w: 0, h: 0)
        let wanted = Rect(x: (origin.x + region.x) * scale, y: (origin.y + region.y) * scale,
                          w: region.w * scale, h: region.h * scale)
        guard wanted.w > 0, wanted.h > 0 else {
            return unmeasured(.invalidArguments,
                              "the region is \(describe(wanted)) in frame pixels, which has no area",
                              remedy: "Give region as [x, y, w, h] with a positive width and height.",
                              pixels: wanted)
        }

        let frame = Rect(x: 0, y: 0, w: Double(s.meta.pixelWidth), h: Double(s.meta.pixelHeight))
        guard let visible = RegionDirt.intersection(wanted, frame),
              visible.w * visible.h >= wanted.w * wanted.h * 0.999 else {
            return unmeasured(.invalidArguments,
                              "the region maps to \(describe(wanted)) in frame pixels, which falls "
                            + "outside the captured frame of \(s.meta.pixelWidth)x\(s.meta.pixelHeight)",
                              remedy: "region is in points relative to the window's top-left corner; "
                                    + "subtract the window frame's origin from a node frame before "
                                    + "passing it.",
                              pixels: wanted)
        }
        guard let fraction = RegionDirt.dirtyFraction(s.meta.dirtyRects, in: visible) else {
            return unmeasured(.internalError,
                              "the region resolved to \(describe(visible)) in frame pixels and "
                            + "still had no measurable area",
                              pixels: visible)
        }
        return RegionQuietSample(dirtyArea: fraction, status: status, frames: s.frames,
                                 regionPixels: visible, error: nil)
    }

    func stop() {
        sink.markStopped("stopped by caller")
        holder.stopNow()
    }

    private func describe(_ r: Rect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", r.x, r.y, r.w, r.h)
    }
}
