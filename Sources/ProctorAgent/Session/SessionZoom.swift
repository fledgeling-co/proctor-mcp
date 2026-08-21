import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ProctorCore

// proctor_zoom: a native-resolution crop of a region or an accessibility element.
//
// The crop is layered on an ordinary window capture exactly as set-of-marks
// annotation is: run a normal native-scale capture, then cut the region out of
// the written PNG. The full capture's freshness metadata describes the very frame
// the crop came from, so it is passed through untouched rather than re-derived —
// a crop is a window onto a real capture and inherits its trustworthiness. The
// grant-free arithmetic (points -> native pixels, element frame -> region, clamp)
// lives in ProctorCore.RegionCrop; this method resolves the target, drives the
// capture, and writes the cut.

extension Session {

    func zoom(window id: String,
              region regionArg: [Double]?,
              node nodeId: String?,
              padding: Double,
              path: String?,
              waitForComplete: Bool,
              timeoutMs: Int,
              scale: Double?,
              includeCursor: Bool,
              encoding: ImageEncodingOptions = .default) async throws -> JSONValue {
        let window = try windowHandle(id)

        // Resolve the region in window points, from an explicit rect or a node's
        // accessibility frame, applying padding either way.
        let source: String
        let resolvedNode: String?
        let region: Rect
        if let nodeId, !nodeId.isEmpty {
            let element = try ax.node(id: nodeId)
            guard let frame = element.frame, frame.w > 0, frame.h > 0 else {
                throw AgentError(
                    code: .nodeNotFound,
                    message: "node \(nodeId) has no usable frame to zoom into",
                    remedy: "The element reports no geometry; re-snapshot the window, or pass an "
                          + "explicit region as [x, y, w, h] in window points.")
            }
            region = RegionCrop.regionForElement(elementFrame: frame,
                                                 window: window.frame, padding: padding)
            source = "element"
            resolvedNode = nodeId
        } else if let regionArg {
            guard regionArg.count == 4 else {
                throw AgentError(
                    code: .invalidArguments,
                    message: "region must be [x, y, w, h], got \(regionArg.count) values",
                    remedy: "Pass four numbers: x, y, width, height in points relative to the "
                          + "window's top-left corner.")
            }
            region = RegionCrop.pad(Rect(x: regionArg[0], y: regionArg[1],
                                         w: regionArg[2], h: regionArg[3]), by: padding)
            source = "region"
            resolvedNode = nil
        } else {
            throw AgentError(
                code: .invalidArguments,
                message: "proctor_zoom needs a region or a node",
                remedy: "Pass region as [x, y, w, h] in window points, or node as an id from "
                      + "proctor_find.")
        }

        // Capture the whole window at native scale; the crop is cut from it, and
        // the un-cropped PNG is kept alongside so the full context stays available.
        // The full-window frame the crop is cut from is always written lossless
        // and at native scale: it is the source of the cut, and re-encoding it
        // would put compression artefacts into the very pixels zoom exists to
        // preserve. Only the crop honours the caller's format.
        let cropPath = encoding.format.retarget(path ?? Session.defaultZoomPath(for: window))
        let fullPath = Session.fullPath(besideCrop: cropPath)
        let full = try await capture.capture(window: window, to: fullPath,
                                             waitForComplete: waitForComplete,
                                             timeoutMs: timeoutMs, scale: scale,
                                             tileHashes: false, includeCursor: includeCursor)

        let placement: RegionCrop.Placement
        switch RegionCrop.place(regionPoints: region, imageWidth: full.width,
                                imageHeight: full.height, scale: full.scale) {
        case .success(let p):
            placement = p
        case .failure(let why):
            throw Session.zoomFailure(why, region: region,
                                      width: full.width, height: full.height, scale: full.scale)
        }

        try Session.cropPNG(from: full.path, to: cropPath, pixelRect: placement.pixelRect,
                            format: encoding.format, quality: encoding.quality)

        // Freshness is the capture's own, unmodified: the crop is part of the same
        // frame, so its status, dirty coverage, frames waited and trustworthiness
        // are exactly what the whole-window capture reported.
        let crop = CropRegion(source: source, node: resolvedNode,
                              requestedRegion: region, pixelRect: placement.pixelRect,
                              clamped: placement.clamped, padding: max(0, padding),
                              fullPath: full.path)
        let result = CaptureResult(
            window: full.window, path: cropPath,
            width: Int(placement.pixelRect.w), height: Int(placement.pixelRect.h),
            scale: full.scale, status: full.status, contentRect: full.contentRect,
            dirtyRectCount: full.dirtyRectCount, dirtyArea: full.dirtyArea,
            capturedAt: full.capturedAt, framesWaited: full.framesWaited,
            trustworthy: full.trustworthy, caveat: full.caveat, crop: crop,
            // PRO-0088. A crop inherits its parent's freshness, and it inherits
            // its parent's emptiness for the same reason: it is a window onto
            // the same frame, so a crop of a frame with nothing in it has
            // nothing in it either.
            content: full.content, contentVerdict: full.contentVerdict)
        return try JSONValue.encode(result)
    }

    // MARK: - Failure mapping

    private static func zoomFailure(_ why: RegionCrop.Failure, region: Rect,
                                    width: Int, height: Int, scale: Double) -> AgentError {
        switch why {
        case .emptyRegion:
            return AgentError(
                code: .invalidArguments,
                message: "the region \(describe(region)) points has no area",
                remedy: "Give a region with a positive width and height.")
        case .noFrameGeometry:
            return AgentError(
                code: .captureFailed,
                message: "the capture reported no pixel dimensions, so nothing could be cropped",
                remedy: "Retry the capture; if it persists, check Screen Recording with proctor_doctor.")
        case .outsideFrame:
            return AgentError(
                code: .invalidArguments,
                message: "the region \(describe(region)) points falls outside the captured "
                       + "\(width)x\(height)px frame at scale \(scale)",
                remedy: "region is in points relative to the window's top-left corner; a node "
                      + "frame from proctor_find is in screen points, so subtract the window "
                      + "origin, or pass the node id and let zoom resolve it.")
        }
    }

    private static func describe(_ r: Rect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", r.x, r.y, r.w, r.h)
    }

    // MARK: - Output paths

    /// Where a zoom crop lands when the caller names no path. Distinct prefix from
    /// a plain capture so the two are not confused on disk.
    static func defaultZoomPath(for window: WindowHandle) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/Library/Application Support/app.fledgeling.procter/captures"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let safe = window.id.replacingOccurrences(of: ":", with: "-")
        return "\(dir)/\(safe)-zoom-\(stamp).png"
    }

    /// The full-window PNG written beside a crop, "<crop>.full.png", so the whole
    /// window stays available next to the zoomed detail.
    static func fullPath(besideCrop crop: String) -> String {
        let url = URL(fileURLWithPath: crop)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(stem).full.\(ext)").path
    }

    // MARK: - Cropping

    /// Cut a pixel rectangle out of the full-window capture on disk and write it
    /// as a new file. The source is the lossless native-scale capture, so the cut
    /// is the exact native pixels of the region — nothing is rescaled, which is
    /// the whole point of zooming rather than enlarging a normalised frame.
    static func cropPNG(from sourcePath: String, to destPath: String, pixelRect: Rect,
                        format: ImageFormat = .png, quality: Int? = nil) throws {
        let url = URL(fileURLWithPath: sourcePath)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw AgentError(code: .captureFailed,
                             message: "the captured image at \(sourcePath) could not be read back to crop",
                             remedy: "Retry; if it persists, check the capture directory is writable.")
        }
        let rect = CGRect(x: pixelRect.x, y: pixelRect.y, width: pixelRect.w, height: pixelRect.h)
            .integral
        guard let cropped = image.cropping(to: rect) else {
            throw AgentError(code: .internalError,
                             message: "cropping the frame to \(describe(pixelRect)) pixels failed")
        }
        try ImageWriter.write(cropped, to: destPath, format: format, quality: quality,
                              what: "crop")
    }
}
