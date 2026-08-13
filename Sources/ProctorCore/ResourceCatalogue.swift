import Foundation

// The read-only state a host can pull as an MCP resource instead of a tool call:
// the displays, the windows, the frontmost app, and the last capture. Each is a
// re-projection of state the agent already holds or can read without any TCC
// grant — resources add no new capability, only a second way to read what exists.
//
// `key` is the internal verb the shim forwards to the agent (proctor_resource);
// `uri` is what a host sees. The two are kept together so the shim maps one to the
// other without a second lookup table that could drift.

public struct ResourceSpec: Sendable {
    public let uri: String
    public let key: String
    public let name: String
    public let title: String
    public let description: String
    public let mimeType: String

    public init(uri: String, key: String, name: String, title: String,
                description: String, mimeType: String) {
        self.uri = uri; self.key = key; self.name = name; self.title = title
        self.description = description; self.mimeType = mimeType
    }
}

public enum ResourceCatalogue {
    public static let all: [ResourceSpec] = [display, windows, frontmost, screenshotLatest]

    public static func spec(uri: String) -> ResourceSpec? {
        all.first { $0.uri == uri }
    }

    public static func spec(key: String) -> ResourceSpec? {
        all.first { $0.key == key }
    }

    static let display = ResourceSpec(
        uri: "proctor://display",
        key: "display",
        name: "display",
        title: "Displays",
        description: "Attached displays with their frame, visible frame and backing scale. "
                   + "Read directly from the window server; needs no grant.",
        mimeType: "application/json")

    static let windows = ResourceSpec(
        uri: "proctor://windows",
        key: "windows",
        name: "windows",
        title: "Windows",
        description: "Running applications and, for the ones under test, their window handles "
                   + "with frames and Space membership. The same data proctor_apps(list) returns; "
                   + "window handles are listed for attached applications only.",
        mimeType: "application/json")

    static let frontmost = ResourceSpec(
        uri: "proctor://frontmost",
        key: "frontmost",
        name: "frontmost",
        title: "Frontmost application",
        description: "The application that currently owns the foreground, with its pid, bundle id "
                   + "and name — plus its main window handle when that app is attached.",
        mimeType: "application/json")

    static let screenshotLatest = ResourceSpec(
        uri: "proctor://screenshot/latest",
        key: "screenshot.latest",
        name: "screenshot/latest",
        title: "Latest capture",
        description: "The most recent proctor_capture result — its on-disk path and freshness "
                   + "metadata, never the bytes. Cache-only: reading it never triggers a new "
                   + "capture, so it needs no Screen Recording grant and returns {cached:false} "
                   + "until a capture has been taken.",
        mimeType: "application/json")
}
