import Foundation
import CoreGraphics
import ImageIO
import ProctorCore

// The processes and the pixels behind proctor_ios: everything that touches the
// outside world, kept away from both the decision logic in ProctorCore and the
// actor state in SessionIOS.
//
// These are static and take everything they need, which is what lets the actor
// call them without holding isolation across a subprocess that can take seconds.

extension Session {

    // MARK: - Running simctl

    struct SimctlRun: Sendable {
        var exitCode: Int32
        var stdout: Data
        var stderr: String
        /// Set when the child was killed at the deadline rather than exiting.
        var timedOut: Bool
        /// Set when output exceeded the cap and was discarded past it. A caller
        /// that parses the output must treat this as a failed read rather than a
        /// short one: truncated JSON that happens to parse is worse than none.
        var truncated: Bool
    }

    /// Run simctl at an absolute path, bounded.
    ///
    /// Three things here are load-bearing and each is a bug that has been written
    /// before. **Both pipes are drained on their own queues before the wait**: a
    /// child whose output exceeds the pipe buffer blocks writing while the parent
    /// blocks waiting, and `simctl listapps` on a full device is far larger than
    /// one buffer. **The deadline terminates the child** rather than abandoning it,
    /// so a wedged simulator cannot leave a process behind for the life of the
    /// agent. **The cap discards rather than stops reading**: a drain that simply
    /// stopped at the cap would leave the child blocked on write until the
    /// watchdog killed it, turning a large output into a timeout.
    static func runSimctl(_ path: String, _ arguments: [String], timeoutMs: Int) -> SimctlRun {
        let maximumBytes = 8 * 1024 * 1024

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return SimctlRun(exitCode: -1, stdout: Data(),
                             stderr: "could not run \(path): \(error.localizedDescription)",
                             timedOut: false, truncated: false)
        }

        // Drain concurrently. readDataToEndOfFile on one pipe while the other
        // fills is the deadlock this avoids.
        let lock = NSLock()
        var outData = Data(), errData = Data()
        var overflowed = false
        let group = DispatchGroup()
        for (pipe, isStdout) in [(out, true), (err, false)] {
            group.enter()
            DispatchQueue.global().async {
                var buffer = Data()
                var over = false
                // Keep reading to EOF even after the cap, discarding the excess.
                // The child must never be left blocked on a write nobody is
                // reading.
                while let chunk = try? pipe.fileHandleForReading.read(upToCount: 64 * 1024),
                      !chunk.isEmpty {
                    if buffer.count < maximumBytes {
                        buffer.append(chunk)
                    } else {
                        over = true
                    }
                }
                lock.lock()
                if isStdout { outData = buffer } else { errData = buffer }
                overflowed = overflowed || over
                lock.unlock()
                group.leave()
            }
        }

        let deadline = DispatchTime.now() + .milliseconds(max(0, timeoutMs))
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: watchdog)

        process.waitUntilExit()
        watchdog.cancel()
        // A terminated child closes its pipes, so the drains finish; the wait is
        // bounded by that rather than by the deadline again.
        _ = group.wait(timeout: .now() + 5)

        lock.lock()
        let stdout = outData
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        let overflowedOutput = overflowed
        lock.unlock()

        let timedOut = process.terminationReason == .uncaughtSignal
        return SimctlRun(exitCode: process.terminationStatus, stdout: stdout,
                         stderr: timedOut && stderr.isEmpty
                            ? "simctl did not answer within \(timeoutMs)ms and was terminated"
                            : stderr,
                         timedOut: timedOut, truncated: overflowedOutput)
    }

    // MARK: - App liveness on the device

    /// Whether an app is running on the device, and its pid.
    ///
    /// Read from `simctl spawn <udid> launchctl list`, whose lines look like
    /// `31702  0  UIKitApplication:com.apple.mobilesafari[1161][rb-legacy]`. This
    /// is the softest dependency in the lane: it is read-only, and a failure
    /// degrades the rung to unavailable — reported as nil, never as "not running",
    /// because a channel that did not answer has not said the app is absent.
    static func appLiveness(simctl: String, udid: String,
                            bundleId: String) -> (running: Bool?, pid: Int?) {
        let run = runSimctl(simctl, ["spawn", udid, "launchctl", "list"], timeoutMs: 10_000)
        guard run.exitCode == 0, let text = String(data: run.stdout, encoding: .utf8) else {
            return (nil, nil)
        }
        let needle = "UIKitApplication:" + bundleId
        for line in text.split(separator: "\n") {
            // The job label is the third tab-separated column, and the bundle id
            // is followed by `[` — matching on the prefix alone would let
            // com.example.app match com.example.apple.
            let columns = line.split(separator: "\t")
            guard columns.count >= 3 else { continue }
            let label = String(columns[2])
            guard label == needle || label.hasPrefix(needle + "[") else { continue }
            // A job with no pid is registered but not running; launchctl prints
            // `-` for it, which is a real distinction and not a parse failure.
            let pid = Int(columns[0].trimmingCharacters(in: .whitespaces))
            return (pid != nil, pid)
        }
        return (false, nil)
    }

    // MARK: - Installed apps and their URL schemes

    struct InstalledApp: Sendable {
        var bundleId: String
        var bundlePath: String
    }

    /// The apps installed on a device, with where their bundles live.
    ///
    /// `simctl listapps` emits an old-style property list rather than JSON, so it
    /// is decoded with `PropertyListSerialization` rather than parsed by hand.
    static func installedApps(simctl: String, udid: String) -> [InstalledApp] {
        let run = runSimctl(simctl, ["listapps", udid], timeoutMs: 30_000)
        guard run.exitCode == 0,
              let plist = try? PropertyListSerialization.propertyList(
                from: run.stdout, options: [], format: nil) as? [String: Any]
        else { return [] }

        var out: [InstalledApp] = []
        for (bundleId, value) in plist {
            guard let entry = value as? [String: Any] else { continue }
            // `Bundle` is a file URL string, which has to be decoded before it can
            // be used as a path: a bundle called "My App.app" arrives percent
            // encoded and a raw substring would name nothing.
            guard let raw = entry["Bundle"] as? String,
                  let url = URL(string: raw), url.isFileURL else { continue }
            out.append(InstalledApp(bundleId: bundleId, bundlePath: url.path))
        }
        return out.sorted { $0.bundleId < $1.bundleId }
    }

    /// The URL schemes a bundle claims, from its own `Info.plist`.
    ///
    /// `simctl listapps` does not carry `CFBundleURLTypes` — measured — so the
    /// only route to a scheme claim is the bundle itself. A bundle that cannot be
    /// read contributes nothing rather than failing the map: one unreadable app
    /// must not make every other app's scheme unresolvable.
    static func urlSchemes(inBundleAt path: String) -> [String] {
        let plistPath = path.hasSuffix("/") ? path + "Info.plist" : path + "/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let types = plist["CFBundleURLTypes"] as? [[String: Any]]
        else { return [] }
        return types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
    }

    // MARK: - Device frames

    static func deviceFramePath(udid: String, label: String) throws -> String {
        let directory = NSHomeDirectory()
            + "/Library/Application Support/app.fledgeling.procter/captures"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        // A millisecond stamp alone collides when two samples land in the same
        // millisecond, and a clobbered frame is a comparison against the wrong
        // picture rather than a visible error.
        let salt = String(UInt32.random(in: 0..<0xFFFF), radix: 16)
        return "\(directory)/ios-\(udid.prefix(8).lowercased())-\(label)-\(stamp)-\(salt).png"
    }

    /// Wait for the device screen to stop changing, bounded.
    ///
    /// This is not an optimisation, it is what makes the after-sample mean
    /// anything. `simctl openurl` returns when SpringBoard has accepted the URL,
    /// which is well before the app has been woken, laid out or painted — so a
    /// screenshot taken on that return shows the screen as it was, and a real
    /// navigation is reported as `deliveredOnly`. The manual measurements behind
    /// this feature all slept two seconds before looking; a fixed sleep is the
    /// wrong shape, so this settles on the same principle the Mac lane uses:
    /// consecutive quiet frames rather than a guessed interval.
    ///
    /// Returns the last frame captured, which is the one the caller compares.
    static func settleDeviceScreen(simctl: String, udid: String, timeoutMs: Int,
                                   quietFrames: Int = 2,
                                   intervalMs: Int = 250) -> (path: String?, settled: Bool,
                                                              samples: Int, waitedMs: Int) {
        let started = Date()
        let deadline = started.addingTimeInterval(Double(max(0, timeoutMs)) / 1000)
        var previous: String?
        var quiet = 0
        var samples = 0

        repeat {
            guard let path = try? deviceFramePath(udid: udid, label: "settle"),
                  captureDeviceScreen(simctl: simctl, udid: udid, path: path,
                                      timeoutMs: 10_000).ok else {
                break
            }
            samples += 1
            if let previous {
                let changed = (try? PixelCompare.changedFraction(
                    previous, path, region: comparisonRegion(forFramePath: path),
                    channelTolerance: IOSPixel.channelTolerance)) ?? 1
                quiet = changed < IOSPixel.changeThreshold ? quiet + 1 : 0
                // The superseded frame is removed rather than accumulated: a
                // settle can take a dozen samples and each is a megabyte.
                try? FileManager.default.removeItem(atPath: previous)
            }
            previous = path
            if quiet >= quietFrames {
                return (path, true, samples, Int(Date().timeIntervalSince(started) * 1000))
            }
            Thread.sleep(forTimeInterval: Double(intervalMs) / 1000)
        } while Date() < deadline

        return (previous, false, samples, Int(Date().timeIntervalSince(started) * 1000))
    }

    /// The part of the device screen worth comparing: everything below the status
    /// bar.
    ///
    /// The status bar carries a clock, and on a device showing real time a digit
    /// changing at a minute boundary is a change nobody caused. Measured against
    /// the threshold it is small, but it is the same order of magnitude as the
    /// smallest real navigation, which makes it exactly the wrong kind of noise
    /// to leave in. Excluding the band removes the class rather than tuning
    /// around it. The height is in device pixels and scales with the frame, since
    /// an iPhone frame and an iPad frame are different sizes.
    static func comparisonRegion(forFramePath path: String) -> CGRect? {
        guard let size = imageSize(path) else { return nil }
        // ~5% of the height covers the status bar on both phone and tablet
        // layouts without eating into content on either.
        let inset = (size.height * 0.05).rounded()
        guard size.height - inset > 1 else { return nil }
        return CGRect(x: 0, y: inset, width: size.width, height: size.height - inset)
    }

    static func imageSize(_ path: String) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Capture the device surface. Works with Simulator.app closed, measured at
    /// roughly 140 ms on an iPhone 16 Pro.
    static func captureDeviceScreen(simctl: String, udid: String, path: String,
                                    timeoutMs: Int) -> (ok: Bool, reason: String?) {
        let run = runSimctl(simctl, ["io", udid, "screenshot", path], timeoutMs: timeoutMs)
        guard run.exitCode == 0 else {
            return (false, SimctlFailure.decode(exitCode: run.exitCode, stderr: run.stderr))
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return (false, "simctl reported success but wrote no file to \(path)")
        }
        return (true, nil)
    }

    /// Compare two device frames.
    ///
    /// Two numbers rather than one, because they answer different questions. The
    /// changed-pixel fraction is what the verdict turns on — it separates a deep
    /// link that moved the app from one that did nothing, and on an idle device it
    /// measured exactly zero. The mean difference is the same instrument
    /// `regionMatches` already uses, carried so a caller can compare the two lanes
    /// on one scale.
    static func compareDeviceFrames(_ a: String, _ b: String)
        -> (changedFraction: Double?, meanDifference: Double?) {
        let region = comparisonRegion(forFramePath: b)
        let mean = try? PixelCompare.meanDifference(a, b, region: region)
        let changed = try? PixelCompare.changedFraction(
            a, b, region: region, channelTolerance: IOSPixel.channelTolerance)
        return (changed, mean)
    }
}
