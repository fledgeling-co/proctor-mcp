import Foundation
import AppKit
import ProctorCore

// proctor_dictionary, IO half. The parsing is pure and lives in ProctorCore
// (ScriptingDictionary); this resolves the sdef bytes for a running app and
// caches the parsed result, the same division SessionCUA keeps with CUAFacade.
//
// Resolving the bytes means asking `/usr/bin/sdef` to read the app's bundle,
// because sdef already resolves the standard-suite xi:include and merges any
// separate scripting terminology — reimplementing that merge would be a second
// source of truth for no gain. The result is cached by app handle id, which
// carries the launch epoch, so a relaunch is a cache miss and a fresh read.

extension Session {

    /// Read (or serve from cache) the scripting dictionary for an attached app.
    /// Either an app handle or a window handle names the target. A non-scriptable
    /// app is a normal result with scriptable=false, never an error — that is the
    /// signal a caller routes on.
    func dictionary(app appId: String?, window windowId: String?,
                    summaryOnly: Bool, refresh: Bool) async throws -> JSONValue {
        let handle = try resolveApp(appId: appId, windowId: windowId)

        if !refresh, let cached = dictionaryCache.value(for: handle) {
            return envelope(cached, handle: handle, summaryOnly: summaryOnly, cached: true)
        }

        let dict = readDictionary(for: handle)
        dictionaryCache.store(dict, for: handle)
        return envelope(dict, handle: handle, summaryOnly: summaryOnly, cached: false)
    }

    // MARK: - Resolution

    private func resolveApp(appId: String?, windowId: String?) throws -> AppHandle {
        if let appId {
            guard let handle = appHandle(id: appId) else {
                throw AgentError(code: .appNotFound,
                                 message: "\(appId) is not attached",
                                 remedy: "Attach it with proctor_apps (action \"attach\") first.")
            }
            return handle
        }
        let window = try windowHandle(try require(windowId, "window"))
        guard let handle = appHandle(forWindow: window) else {
            throw AgentError(code: .appNotFound,
                             message: "the app owning \(window.id) is no longer attached",
                             remedy: "Re-attach with proctor_apps.")
        }
        return handle
    }

    private func require(_ value: String?, _ name: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw AgentError(code: .invalidArguments, message: "proctor_dictionary requires \(name)")
        }
        return value
    }

    /// Resolve the bundle for the app's pid and parse its sdef. Any failure to
    /// reach a scriptable definition degrades to a not-scriptable result carrying
    /// the reason, so route selection always gets an answer.
    private func readDictionary(for handle: AppHandle) -> AppScriptingDictionary {
        guard let bundleURL = NSRunningApplication(processIdentifier: handle.pid)?.bundleURL else {
            return .notScriptable(appName: handle.name, reason: "no application bundle for this process")
        }
        guard let xml = Self.runSdef(bundlePath: bundleURL.path), !xml.isEmpty else {
            return .notScriptable(appName: handle.name, reason: "no scripting definition in the bundle")
        }
        return ScriptingDictionary.parse(sdefXML: xml, appName: handle.name)
    }

    /// Run `/usr/bin/sdef <bundle>` and return its stdout. The read drains the
    /// pipe to EOF before the wait, so a dictionary larger than the pipe buffer
    /// cannot deadlock. A non-zero exit (an app with no dictionary) is reported
    /// as no output rather than an error.
    private static func runSdef(bundlePath: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sdef")
        process.arguments = [bundlePath]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()   // discard sdef's diagnostics
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    // MARK: - Envelope

    private func envelope(_ dict: AppScriptingDictionary, handle: AppHandle,
                          summaryOnly: Bool, cached: Bool) -> JSONValue {
        let encoded = (try? JSONValue.encode(dict)) ?? .object([:])
        var out: [String: JSONValue] = [
            "app": .string(handle.id),
            "pid": .number(Double(handle.pid)),
            "name": .string(handle.name),
            "scriptable": .bool(dict.scriptable),
            "summary": .string(dict.summary),
            "counts": encoded["counts"] ?? .object([:]),
            "cached": .bool(cached)
        ]
        if let bundleId = handle.bundleId { out["bundleId"] = .string(bundleId) }
        if !summaryOnly { out["suites"] = encoded["suites"] ?? .array([]) }
        if !dict.scriptable { out["caveat"] = .string(dict.summary) }
        return .object(out)
    }
}
