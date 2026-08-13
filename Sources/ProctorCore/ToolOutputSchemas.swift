import Foundation

// A per-tool `outputSchema`, so a host can machine-check the structured result a
// tool returns rather than parse prose. The schemas are deliberately permissive:
// each is an open object (extra provenance fields never make a valid result fail
// validation) documenting the top-level shape of a successful call. A failed call
// is returned as an MCP tool error (isError:true) carrying {code,message,remedy},
// which is a different shape by design and not what this schema describes.
//
// Kept out of ToolCatalogue.swift so the catalogue itself stays a small diff; the
// shim reads these when it builds each tool entry.

public extension ToolCatalogue {
    /// The advertised output schema for a tool. A tool with no bespoke schema gets
    /// an open object, which is honest — the result is structured, its exact shape
    /// unconstrained — rather than a claim the payload does not keep.
    static func outputSchema(for name: String) -> JSONValue {
        outputSchemas[name] ?? openObject(nil)
    }

    private static func property(_ type: String) -> JSONValue {
        .object(["type": .string(type)])
    }

    /// An object schema that documents known top-level fields but permits others.
    /// `additionalProperties` is left at its JSON-Schema default (true), so a
    /// richer-than-documented success payload validates.
    private static func openObject(_ description: String?,
                                   _ properties: [String: JSONValue] = [:]) -> JSONValue {
        var schema: [String: JSONValue] = ["type": .string("object")]
        if let description { schema["description"] = .string(description) }
        if !properties.isEmpty { schema["properties"] = .object(properties) }
        return .object(schema)
    }

    private static let outputSchemas: [String: JSONValue] = {
        let p = property

        return [
            "proctor_apps": openObject(
                "Enumeration (apps/attached/note), an attach (app/windows/provenance), or a detach (detached/windowsReleased).",
                ["apps": p("array"), "attached": p("array"), "note": p("string"),
                 "app": p("object"), "windows": p("array"), "provenance": p("object"),
                 "detached": p("string"), "windowsReleased": p("number")]),

            "proctor_snapshot": openObject(
                "A pruned accessibility tree, or a diff when sinceRevision was supplied.",
                ["window": p("string"), "revision": p("number"), "root": p("object"),
                 "diff": p("object"), "provenance": p("object"), "stateHash": p("string")]),

            "proctor_find": openObject(
                "The nodes matching a predicate.",
                ["window": p("string"), "predicate": p("string"), "count": p("number"),
                 "truncated": p("boolean"), "nodes": p("array")]),

            "proctor_act": openObject(
                "Per-step outcome for a batch of actions.",
                ["window": p("string"), "steps": p("array"), "completed": p("number"),
                 "failedAt": p("number"), "finalHash": p("string")]),

            "proctor_capture": openObject(
                "A window capture with its freshness metadata; the PNG is on disk at `path`, never inline.",
                ["window": p("string"), "path": p("string"), "width": p("number"),
                 "height": p("number"), "scale": p("number"), "status": p("string"),
                 "contentRect": p("object"), "dirtyRectCount": p("number"),
                 "dirtyArea": p("number"), "capturedAt": p("number"),
                 "framesWaited": p("number"), "trustworthy": p("boolean"),
                 "caveat": p("string"), "tileHashes": p("array"),
                 "normalization": p("object")]),

            "proctor_zoom": openObject(
                "A native-resolution crop of a region or element, with the same freshness metadata as a capture; the crop PNG is on disk at `path`, never inline, and `crop` names what was cut.",
                ["window": p("string"), "path": p("string"), "width": p("number"),
                 "height": p("number"), "scale": p("number"), "status": p("string"),
                 "contentRect": p("object"), "dirtyRectCount": p("number"),
                 "dirtyArea": p("number"), "capturedAt": p("number"),
                 "framesWaited": p("number"), "trustworthy": p("boolean"),
                 "caveat": p("string"), "crop": p("object")]),

            "proctor_wait": openObject(
                "Whether a named condition held, and the state when it resolved.",
                ["window": p("string"), "condition": p("string"), "ok": p("boolean"),
                 "timedOut": p("boolean"), "elapsedMs": p("number"), "polls": p("number"),
                 "observed": .object([:])]),

            "proctor_assert": openObject(
                "Per-assertion verdicts with observed values.",
                ["window": p("string"), "revision": p("number"), "stateHash": p("string"),
                 "assertions": p("array"), "passed": p("number"), "failed": p("number"),
                 "skipped": p("number")]),

            "proctor_flow": openObject(
                "A flow list (flows/directory), a show, a replay (flow/completed/steps/comparison), a start, or a delete.",
                ["flows": p("array"), "directory": p("string"), "name": p("string"),
                 "flow": p("string"), "window": p("string"), "completed": p("number"),
                 "steps": .object([:]), "comparison": p("array"),
                 "deleted": p("boolean")]),

            "proctor_stability": openObject(
                "firstDivergence and a per-step instability score across N replays.",
                ["flow": p("string"), "runs": p("number"), "stepCount": p("number"),
                 "firstDivergence": p("number"), "stepInstability": p("array"),
                 "deterministic": p("boolean"), "divergenceDetail": p("object"),
                 "notes": p("array")]),

            "proctor_inspect": openObject(
                "Resolved styles and layer geometry from an instrumented app.",
                ["window": p("string"), "hierarchy": .object([:]),
                 "renderRevision": p("number")]),

            "proctor_doctor": openObject(
                "Agent liveness, grants, attachments and observer health.",
                ["agentVersion": p("string"), "protocolVersion": p("number"),
                 "osVersion": p("string"), "agentRunning": p("boolean"),
                 "socketPath": p("string"), "grants": p("array"),
                 "attachedApps": p("array"), "observersLive": p("number"),
                 "secureEventInputActive": p("boolean"),
                 "shortcutsCLIAvailable": p("boolean"), "ready": p("boolean"),
                 "blockers": p("array")]),

            "proctor_unlock": openObject(
                "Lock/turn state (status), or the outcome of open/close/unlock/relock/lock.",
                ["screenLocked": p("boolean"), "turnAuthorized": p("boolean"),
                 "pluginInstalled": p("boolean"), "brokerSocket": p("string"),
                 "opened": p("boolean"), "closed": p("boolean"),
                 "relocked": p("boolean"), "locked": p("boolean"),
                 "ttlMs": p("number")]),

            "proctor_menu": openObject(
                "The menu bar flattened to rows, each with its path, enabled state and reconstructed key-equivalent.",
                ["app": p("string"), "itemCount": p("number"), "items": p("array"),
                 "note": p("string")]),
            "proctor_dictionary": openObject(
                "An app's parsed scripting dictionary: scriptability, a capability summary, per-suite structure and counts.",
                ["app": p("string"), "pid": p("number"), "name": p("string"),
                 "bundleId": p("string"), "scriptable": p("boolean"),
                 "summary": p("string"), "suites": p("array"), "counts": p("object"),
                 "cached": p("boolean"), "caveat": p("string")]),
            "proctor_policy": openObject(
                "Policy gate state (status), a configure result, an approve (token/expiresAt), a revoke, or recent audit lines.",
                ["allow": p("array"), "block": p("array"), "sensitive": p("array"),
                 "tokenLive": p("boolean"), "tokenExpiresAt": p("number"),
                 "tokenBundleId": p("string"), "auditPath": p("string"),
                 "auditCount": p("number"), "token": p("string"),
                 "expiresAt": p("number"), "ttlMs": p("number"),
                 "revoked": p("boolean"), "lines": p("array")]),
        ]
    }()
}
