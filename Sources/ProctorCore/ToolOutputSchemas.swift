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
                "Enumeration (apps/attached/note), an attach (app/windows/provenance), or a detach (detached/windowsReleased). `browser` is present when the target is a browser showing a page: the page belongs to Obscura, the native chrome around it does not. Its `toolUnavailable` says Obscura is not installed here, and then no command is recommended. `surface` is `browserWindow` or `installedWebApp` — an installed web app is one site opened as an application, which Proctor drives itself rather than handing to a browser tool, so `use == null` there means Proctor drives it rather than that nothing should. `flags` is present whenever the handoff points at an instrument and carries five booleans where true means the fact is present: `actsOutsideThisWindow`, `autonomous`, `canActAsThisPerson`, `outsideTheAuditTrail`, `billed`. They describe what Proctor recommends, not everything a caller could do — the handoff is advisory, so a policy that nothing may act in a live browser session gates on the presence of `browser`, not on a flag. The flag that answers may this act with the user own session is `canActAsThisPerson`; a rule built from `autonomous` and `billed` being false does not answer it, because Proctor driving an installed web app is neither autonomous nor billed and is that person session.",
                ["apps": p("array"), "attached": p("array"), "note": p("string"),
                 "app": p("object"), "windows": p("array"), "provenance": p("object"),
                 "detached": p("string"), "windowsReleased": p("number"),
                 "browser": p("object")]),

            "proctor_snapshot": openObject(
                "A pruned accessibility tree, or a diff when sinceRevision was supplied. `browser` is present when the target is a browser showing a page: the page belongs to Obscura, the native chrome around it does not. Its `toolUnavailable` says Obscura is not installed here, and then no command is recommended. `surface` is `browserWindow` or `installedWebApp` — an installed web app is one site opened as an application, which Proctor drives itself rather than handing to a browser tool, so `use == null` there means Proctor drives it rather than that nothing should. `flags` is present whenever the handoff points at an instrument and carries five booleans where true means the fact is present: `actsOutsideThisWindow`, `autonomous`, `canActAsThisPerson`, `outsideTheAuditTrail`, `billed`. They describe what Proctor recommends, not everything a caller could do — the handoff is advisory, so a policy that nothing may act in a live browser session gates on the presence of `browser`, not on a flag. The flag that answers may this act with the user own session is `canActAsThisPerson`; a rule built from `autonomous` and `billed` being false does not answer it, because Proctor driving an installed web app is neither autonomous nor billed and is that person session.",
                ["window": p("string"), "revision": p("number"), "root": p("object"),
                 "diff": p("object"), "provenance": p("object"), "stateHash": p("string"),
                 "browser": p("object")]),

            "proctor_find": openObject(
                "The nodes matching a predicate. `browser` is present when the target is a browser showing a page: the page belongs to Obscura, the native chrome around it does not. Its `toolUnavailable` says Obscura is not installed here, and then no command is recommended. `surface` is `browserWindow` or `installedWebApp` — an installed web app is one site opened as an application, which Proctor drives itself rather than handing to a browser tool, so `use == null` there means Proctor drives it rather than that nothing should. `flags` is present whenever the handoff points at an instrument and carries five booleans where true means the fact is present: `actsOutsideThisWindow`, `autonomous`, `canActAsThisPerson`, `outsideTheAuditTrail`, `billed`. They describe what Proctor recommends, not everything a caller could do — the handoff is advisory, so a policy that nothing may act in a live browser session gates on the presence of `browser`, not on a flag. The flag that answers may this act with the user own session is `canActAsThisPerson`; a rule built from `autonomous` and `billed` being false does not answer it, because Proctor driving an installed web app is neither autonomous nor billed and is that person session.",
                ["window": p("string"), "predicate": p("string"), "count": p("number"),
                 "truncated": p("boolean"), "nodes": p("array"), "browser": p("object")]),

            "proctor_act": openObject(
                "Per-step outcome for a batch of actions. `browser` is present when the target is a browser showing a page: the page belongs to Obscura, the native chrome around it does not. Its `toolUnavailable` says Obscura is not installed here, and then no command is recommended. `surface` is `browserWindow` or `installedWebApp` — an installed web app is one site opened as an application, which Proctor drives itself rather than handing to a browser tool, so `use == null` there means Proctor drives it rather than that nothing should. `flags` is present whenever the handoff points at an instrument and carries five booleans where true means the fact is present: `actsOutsideThisWindow`, `autonomous`, `canActAsThisPerson`, `outsideTheAuditTrail`, `billed`. They describe what Proctor recommends, not everything a caller could do — the handoff is advisory, so a policy that nothing may act in a live browser session gates on the presence of `browser`, not on a flag. The flag that answers may this act with the user own session is `canActAsThisPerson`; a rule built from `autonomous` and `billed` being false does not answer it, because Proctor driving an installed web app is neither autonomous nor billed and is that person session.",
                ["window": p("string"), "steps": p("array"), "completed": p("number"),
                 "failedAt": p("number"), "finalHash": p("string"),
                 "foreground": p("object"), "browser": p("object")]),

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
                 "notes": p("array"),
                 // Present only when per-step capture was on. Each entry is
                 // {run, step, path?, markedPath?, note?}: the replay and step it
                 // came from, the plain PNG, the marked sibling where one was
                 // drawn, and why either is missing when it is.
                 "captures": .object([
                    "type": .string("array"),
                    "items": openObject(
                        "One saved per-step frame, identified by which replay and which step produced it.",
                        ["run": p("number"), "step": p("number"), "path": p("string"),
                         "markedPath": p("string"), "note": p("string")])])]),

            "proctor_inspect": openObject(
                "Resolved styles and layer geometry from an instrumented app.",
                ["window": p("string"), "hierarchy": .object([:]),
                 "renderRevision": p("number")]),

            "proctor_doctor": openObject(
                "Agent liveness, grants, attachments and observer health. `agentVersion` identifies the build the agent actually is — `version+commit`, plus `.dirty` for uncommitted changes and `.debug` for a debug build — and `agentBuild` carries the same thing in parts, with `builtAt` for when that executable was written. `tools` lists every command-line tool Proctor looks for, with where it was found and everywhere it looked; `obscuraAvailable` and `obscura` are the grandfathered spelling of its first entry. `secondLane` is `off`, `enabled` or `unavailable` — the second browser lane is named only when PROCTOR_SECOND_LANE names it, and usable only when that tool is also installed. None of this affects `ready`, because Proctor drives native applications without any browser tool.",
                ["agentVersion": p("string"), "agentBuild": p("object"),
                 "protocolVersion": p("number"),
                 "osVersion": p("string"), "agentRunning": p("boolean"),
                 "socketPath": p("string"), "grants": p("array"),
                 "attachedApps": p("array"), "observersLive": p("number"),
                 "secureEventInputActive": p("boolean"),
                 "shortcutsCLIAvailable": p("boolean"),
                 "obscuraAvailable": p("boolean"), "obscura": p("object"),
                 "obscuraUnavailable": p("object"), "tools": p("array"),
                 "secondLane": p("string"), "ready": p("boolean"),
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
                "Policy gate state (status), a configure result, an approve (token/expiresAt), a revoke, or recent audit lines. The trail is encrypted at rest; an entry that cannot be unsealed comes back marked unreadable. It is also signed and chained, so auditVerdict says whether it is the trail Proctor wrote: clean, entries, verified, preChain, completeness and the first fault if there is one. Entries written before signing existed are reported as preChain rather than as faults, and droppedThisRun says how many entries could not be written at all, which leaves no hole in the chain to find. An audit line whose outcome is \"recommended\" carries a recommendation object (lane, rule, scheme): it records that Proctor named a browser tool for a page, and deliberately records no address, host, path or query.",
                ["allow": p("array"), "block": p("array"), "sensitive": p("array"),
                 "tokenLive": p("boolean"), "tokenExpiresAt": p("number"),
                 "tokenBundleId": p("string"), "auditPath": p("string"),
                 "auditCount": p("number"), "token": p("string"),
                 "auditEncrypted": p("boolean"), "auditWritable": p("boolean"),
                 "auditSigned": p("boolean"), "auditVerdict": p("object"),
                 "auditKeyId": p("string"), "auditError": p("string"),
                 "auditConverted": p("number"), "auditConvertedNote": p("string"),
                 "auditDropped": p("number"), "auditKeyMismatch": p("boolean"),
                 "auditKeyMismatchNote": p("string"),
                 "unreadableCount": p("number"),
                 "expiresAt": p("number"), "ttlMs": p("number"),
                 "revoked": p("boolean"), "lines": p("array")]),
        ]
    }()
}
