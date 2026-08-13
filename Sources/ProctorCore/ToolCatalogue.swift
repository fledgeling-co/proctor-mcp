import Foundation

// The tools, defined once. The shim advertises these to the MCP host;
// the agent dispatches on the same names. Keeping the catalogue in shared code
// is what stops the two drifting.
//
// Granularity is one tool per decision, with actuation batched: a six-step
// login is one `act` call, not six round trips plus five settles.

public struct ToolSpec: Sendable {
    public let name: String
    public let title: String
    public let description: String
    public let inputSchema: JSONValue
    public let readOnly: Bool
    /// Whether a call can alter target-app or system state a host would want to
    /// gate behind its own confirmation. Meaningful only when `readOnly` is false
    /// (MCP treats `destructiveHint`/`idempotentHint` as ignorable for read-only
    /// tools), so read-only tools keep the harmless defaults.
    public let destructive: Bool
    /// Whether repeating the same call has no additional effect. Meaningful only
    /// when `readOnly` is false.
    public let idempotent: Bool

    public init(name: String, title: String, description: String, inputSchema: JSONValue,
                readOnly: Bool, destructive: Bool = false, idempotent: Bool = true) {
        self.name = name; self.title = title; self.description = description
        self.inputSchema = inputSchema; self.readOnly = readOnly
        self.destructive = destructive; self.idempotent = idempotent
    }
}

public enum ToolCatalogue {
    public static let all: [ToolSpec] = [
        apps, snapshot, find, act, capture, wait, assert_, flow, stability, inspect, doctor, unlock,
        computer, openaiComputer, menu, dictionary
    ]

    public static func spec(named name: String) -> ToolSpec? {
        all.first { $0.name == name }
    }

    // MARK: apps

    static let apps = ToolSpec(
        name: "proctor_apps",
        title: "List and attach applications",
        description: """
        Enumerate running applications and their windows, and attach to the ones under test.

        Attaching is what makes everything else work. It warms the accessibility tree, applies \
        AXManualAccessibility where the app is Chromium- or Electron-based, starts long-lived \
        observers, and begins retaining element references. A retained reference keeps resolving \
        when its window moves to another Space or behind other windows; a fresh enumeration will \
        not find it. Attach once per app at the start of a campaign and reuse the handles.

        Applying AXManualAccessibility is detectable by the target app and changes its \
        performance. The response reports whether it was applied so any methodology written on \
        this data can disclose it.

        Returns app handles, window handles with frames and Space membership, and the tree \
        provenance for each attachment.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([.string("list"), .string("attach"), .string("detach")]),
                    "description": .string("list enumerates without touching anything; attach begins a stateful session; detach releases refs and observers.")
                ]),
                "bundleId": .object(["type": .string("string"), "description": .string("Bundle identifier to attach, e.g. com.apple.TextEdit.")]),
                "pid": .object(["type": .string("integer"), "description": .string("Process id, when the bundle identifier is ambiguous or absent.")]),
                "name": .object(["type": .string("string"), "description": .string("Localised application name, matched case-insensitively.")]),
                "app": .object(["type": .string("string"), "description": .string("An existing app handle, for detach.")]),
                "includeWindowless": .object(["type": .string("boolean"), "description": .string("Include background applications with no windows. Defaults to false.")])
            ]),
            "required": .array([.string("action")])
        ]),
        readOnly: false
    )

    // MARK: snapshot

    static let snapshot = ToolSpec(
        name: "proctor_snapshot",
        title: "Read the accessibility tree of a window",
        description: """
        Return the pruned semantic accessibility tree for a window: role, subrole, title, label, \
        value, identifier, frame, enabled/focused/selected state, available actions and writable \
        attributes, with a stable node id on every node.

        Pass sinceRevision to get a diff instead of a full tree — added, removed and changed \
        nodes only. Repeated reads during a flow then cost tokens proportional to what actually \
        changed rather than to the size of the window.

        The response carries a canonical stateHash over the normalised tree with volatile fields \
        masked. Two snapshots with the same hash are the same state; that is the basis of \
        determinism measurement.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string"), "description": .string("Window handle from proctor_apps.")]),
                "sinceRevision": .object(["type": .string("integer"), "description": .string("Return a diff from this revision instead of the whole tree.")]),
                "maxDepth": .object(["type": .string("integer"), "description": .string("Depth limit. Defaults to 24; truncation is reported in provenance.")]),
                "maxNodes": .object(["type": .string("integer"), "description": .string("Node budget. Defaults to 600. A walk is also bounded by wall clock, because some applications answer each element more slowly the deeper into a large list you go — a wide icon-view list can cost tens of seconds where an ordinary window costs milliseconds. Both kinds of truncation are reported in provenance rather than passed off as a whole tree.")]),
                "includeInvisible": .object(["type": .string("boolean"), "description": .string("Keep zero-area and offscreen nodes. Defaults to false for reading, true when auditing.")]),
                "root": .object(["type": .string("string"), "description": .string("Walk from this node id instead of the window root.")])
            ]),
            "required": .array([.string("window")])
        ]),
        readOnly: true
    )

    // MARK: find

    static let find = ToolSpec(
        name: "proctor_find",
        title: "Query the accessibility tree by predicate",
        description: """
        Return only the nodes matching a predicate, so locating one button does not cost a whole \
        tree. Match on role, subrole, title, label, identifier, value substring, enabled state, \
        focus state, or any combination — all supplied conditions must hold.

        Prefer identifier when the app sets accessibilityIdentifier: it is the only selector a \
        developer controls deliberately, so it survives copy changes and localisation where a \
        title match does not.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string")]),
                "role": .object(["type": .string("string"), "description": .string("AX role, e.g. AXButton, AXTextField.")]),
                "subrole": .object(["type": .string("string")]),
                "title": .object(["type": .string("string"), "description": .string("Exact or substring title match, per `match`.")]),
                "label": .object(["type": .string("string")]),
                "identifier": .object(["type": .string("string"), "description": .string("AXIdentifier. The most durable selector available.")]),
                "valueContains": .object(["type": .string("string")]),
                "enabled": .object(["type": .string("boolean")]),
                "focused": .object(["type": .string("boolean")]),
                "hasAction": .object(["type": .string("string"), "description": .string("Only nodes offering this AX action, e.g. AXPress.")]),
                "match": .object(["type": .string("string"), "enum": .array([.string("substring"), .string("exact"), .string("regex")]), "description": .string("Defaults to substring.")]),
                "limit": .object(["type": .string("integer"), "description": .string("Defaults to 25.")])
            ]),
            "required": .array([.string("window")])
        ]),
        readOnly: true
    )

    // MARK: act

    static let act = ToolSpec(
        name: "proctor_act",
        title: "Perform a batch of actions, settling after each",
        description: """
        Run a sequence of steps against a window, settling after each one and returning per-step \
        outcome, the plane the action travelled through, a post-state hash and a tree diff. A \
        six-step flow is one call.

        Actions go through the process-directed plane by default — AXUIElementPerformAction, \
        AXUIElementSetAttributeValue, Apple Events — which reaches non-frontmost, occluded and \
        other-Space windows without stealing focus, and which Secure Event Input does not block. \
        The step kinds dragPath, hover, click and key use synthetic event injection instead; \
        those need the target foreground and are reported with plane=syntheticEvent so a result \
        is never mistaken for a background-safe one. A step whose accessibility route is refused \
        by the element fails rather than falling back to a synthetic event, since substituting \
        one silently would turn a background-safe request into a foreground action. Reserve them for what accessibility genuinely \
        cannot express: drag paths, canvas surfaces, hover-only states, and testing keyboard \
        focus behaviour as such.

        Settling is a conjunction of quiet capture frames, quiet accessibility notifications and \
        the app's own idle signal where a reflector is embedded, bounded by a timeout — never a \
        sleep. Each step reports which signals were available and which one ended the wait.

        On a step failure the batch stops and reports failedAt, so the model sees the state at \
        the point of failure rather than a cascade.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string")]),
                "steps": .object([
                    "type": .string("array"),
                    "description": .string("Ordered steps. Each has a kind and the fields that kind needs."),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "kind": .object(["type": .string("string"), "enum": .array([
                                .string("press"), .string("setValue"), .string("focus"), .string("menu"),
                                .string("type"), .string("key"), .string("scroll"), .string("increment"),
                                .string("decrement"), .string("pick"), .string("confirm"), .string("cancel"),
                                .string("raise"), .string("close"), .string("resize"), .string("move"),
                                .string("dragPath"), .string("hover"), .string("click"),
                                .string("shortcut"), .string("appleScript"), .string("waitFor")
                            ])]),
                            "node": .object(["type": .string("string")]),
                            "value": .object(["description": .string("New value for setValue.")]),
                            "menuPath": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "description": .string("Menu bar path, e.g. [\"File\",\"Save\"].")]),
                            "text": .object(["type": .string("string")]),
                            "key": .object(["type": .string("string"), "description": .string("Key name, e.g. return, tab, escape, a.")]),
                            "modifiers": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                            "delta": .object(["type": .string("array"), "items": .object(["type": .string("number")])]),
                            "point": .object(["type": .string("array"), "items": .object(["type": .string("number")])]),
                            "path": .object(["type": .string("array"), "items": .object(["type": .string("array"), "items": .object(["type": .string("number")])]), "description": .string("For dragPath: the route to drag along, as [[x,y], ...] in window coordinates. A press and a release at two positions is a click, so the gesture is interpolated to intermediate movements no more than 10 points apart and capped at 240 events. Omit it and the drag runs from point (or the node's centre) to point + delta.")]),
                            "durationMs": .object(["type": .string("integer"), "description": .string("For dragPath: how long the whole gesture should take, clamped to 30s. Defaults to 300. Events are spaced evenly across it with a 2ms floor per event, so a long path can take longer than asked; raise it for an application that drops fast drags.")]),
                            "label": .object(["type": .string("string"), "description": .string("Human name for this step, carried into reports.")]),
                            "settle": .object(["type": .string("object"), "description": .string("Per-step settle override.")])
                        ]),
                        "required": .array([.string("kind")])
                    ])
                ]),
                "settle": .object(["type": .string("object"), "description": .string("Default settle policy for every step: quietFrames, dirtyThreshold, axQuietMs, timeoutMs, requireReflectorIdle.")]),
                "foreground": .object(["type": .string("boolean"), "description": .string("Activate the app first. Required for synthetic-event step kinds; defaults to false so background windows stay in the background.")]),
                "captureEach": .object(["type": .string("boolean"), "description": .string("Capture a frame after every step. Defaults to false.")]),
                "diffEach": .object(["type": .string("boolean"), "description": .string("Return a tree diff after every step. Defaults to true.")]),
                "record": .object(["type": .string("string"), "description": .string("Append these steps to the named flow as they run.")])
            ]),
            "required": .array([.string("window"), .string("steps")])
        ]),
        readOnly: false,
        destructive: true, idempotent: false
    )

    // MARK: capture

    static let capture = ToolSpec(
        name: "proctor_capture",
        title: "Screenshot a window, with freshness metadata",
        description: """
        Capture a window with ScreenCaptureKit using a window-scoped filter, so the result \
        contains that window alone rather than whatever happens to be on top of it.

        Every capture reports its own trustworthiness: the frame status, the content rect, how \
        many dirty rectangles the compositor reported and what fraction of the frame they cover, \
        and how many frames were waited for. A stale frame looks identical to a correct one, so \
        the metadata is the only thing that separates them. Off-screen windows in particular may \
        emit complete frames only when the pointer moves on their display; when that happens the \
        result comes back with trustworthy=false and a caveat naming the reason.

        Set annotate to burn numbered marks over the window's interactable accessibility elements \
        (annotateAll marks every element with a frame, not just actionable ones). The marks are \
        derived from the same pruned AX geometry proctor_snapshot returns, and the response \
        carries a mark→node map so a vision model that references a numbered box — "click mark 7" \
        — resolves it to a real element id. Mark numbers run in reading order and are stable for a \
        given tree revision. Set grid to overlay reference lines every gridSpacing points. \
        Annotation is additive: the un-annotated PNG stays at path and its freshness metadata is \
        unchanged, while the marked PNG is written alongside it and named in annotation.annotatedPath.

        The PNG is written to disk and the path returned. Bytes are never returned inline.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string")]),
                "path": .object(["type": .string("string"), "description": .string("Where to write the PNG. Defaults to a session temp directory.")]),
                "waitForComplete": .object(["type": .string("boolean"), "description": .string("Keep pulling frames until one is .complete or the timeout expires. Defaults to true.")]),
                "timeoutMs": .object(["type": .string("integer"), "description": .string("Defaults to 3000.")]),
                "scale": .object(["type": .string("number"), "description": .string("Output scale. Defaults to the display's backing scale.")]),
                "tileHashes": .object(["type": .string("boolean"), "description": .string("Also return per-tile perceptual hashes, for determinism comparison.")]),
                "includeCursor": .object(["type": .string("boolean"), "description": .string("Defaults to false, since a cursor in the frame is a source of false diffs.")]),
                "annotate": .object(["type": .string("boolean"), "description": .string("Burn numbered marks over interactable elements and return the mark→node map. Writes the marked PNG alongside the un-annotated one. Defaults to false.")]),
                "annotateAll": .object(["type": .string("boolean"), "description": .string("Mark every element carrying a frame, not just actionable ones. Implies annotate. Defaults to false.")]),
                "grid": .object(["type": .string("boolean"), "description": .string("Overlay reference grid lines. Independent of annotate — a grid can be drawn without marks. Defaults to false.")]),
                "gridSpacing": .object(["type": .string("number"), "description": .string("Points between grid lines. Defaults to 100.")]),
                "maxMarks": .object(["type": .string("integer"), "description": .string("Ceiling on marks drawn on a dense window; the overflow is dropped in reading order and reported as truncated. Defaults to 150.")])
            ]),
            "required": .array([.string("window")])
        ]),
        readOnly: true
    )

    // MARK: wait

    static let wait = ToolSpec(
        name: "proctor_wait",
        title: "Wait for a named condition",
        description: """
        Block until a specific condition holds, bounded by a timeout. Use this when the thing \
        being waited for is not "the UI stopped moving" — settling already covers that after \
        every action — but something nameable: an element appearing or disappearing, a value \
        reaching a target, a region going quiet, or the app's own idle endpoint reporting done.

        Returns whether the condition held, how long it took, and the state when it resolved.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string")]),
                "condition": .object(["type": .string("string"), "enum": .array([
                    .string("nodeExists"), .string("nodeGone"), .string("valueEquals"),
                    .string("valueContains"), .string("enabled"), .string("focused"),
                    .string("regionQuiet"), .string("reflectorIdle")
                ])]),
                "node": .object(["type": .string("string")]),
                "find": .object(["type": .string("object"), "description": .string("A find predicate, when the node does not exist yet and so has no id.")]),
                "value": .object(["description": .string("Target value for valueEquals / valueContains.")]),
                "region": .object(["type": .string("array"), "items": .object(["type": .string("number")]), "description": .string("[x,y,w,h] for regionQuiet, in points relative to the window's top-left corner. Subtract the window frame's origin from a node frame to get one. The dirty rectangles the compositor reports are intersected with this rectangle, so the answer is the fraction of the region that changed, not of the window. A region that maps outside the captured frame, or that cannot be placed because the frame reports no geometry, comes back as an error naming the reason rather than as a quiet region. Omit it to wait on the whole window.")]),
                "timeoutMs": .object(["type": .string("integer"), "description": .string("Defaults to 10000.")]),
                "pollMs": .object(["type": .string("integer"), "description": .string("Defaults to 100.")])
            ]),
            "required": .array([.string("window"), .string("condition")])
        ]),
        readOnly: true
    )

    // MARK: assert

    static let assert_ = ToolSpec(
        name: "proctor_assert",
        title: "Check assertions and return a machine-readable verdict",
        description: """
        Evaluate a list of assertions against the current state and return pass/fail per \
        assertion with the observed value alongside the expected one. Separate from waiting \
        because a test needs a verdict, not a timeout.

        Assertion kinds cover the accessibility tree (a node exists, has a value, is enabled, is \
        focused, has a label), geometry (a node's frame, its containment in another, its \
        alignment), pixels (a region matches a reference within tolerance), and accessibility \
        auditing (every interactive node has a label, contrast meets a threshold, hit targets \
        meet a minimum size, focus order follows visual order).

        The tri-observer check is available here as kind=agree: where the accessibility tree, \
        the geometry source and the captured pixels disagree about the same instant, the delta \
        is returned as a finding — an unexposed control, a ghost node, an invisible-but-focusable \
        element, a stale frame or a wrong hit target — rather than smoothed away.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string")]),
                "assertions": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "kind": .object(["type": .string("string"), "enum": .array([
                                .string("exists"), .string("absent"), .string("valueEquals"),
                                .string("valueContains"), .string("enabled"), .string("disabled"),
                                .string("focused"), .string("hasLabel"), .string("frameEquals"),
                                .string("containedIn"), .string("alignedWith"), .string("minHitSize"),
                                .string("contrast"), .string("focusOrder"), .string("regionMatches"),
                                .string("agree")
                            ])]),
                            "node": .object(["type": .string("string")]),
                            "find": .object(["type": .string("object")]),
                            "expected": .object([:]),
                            "tolerance": .object(["type": .string("number")]),
                            "reference": .object(["type": .string("string"), "description": .string("Path to a reference PNG, for regionMatches.")]),
                            "label": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("kind")])
                    ])
                ]),
                "captureEvidence": .object(["type": .string("boolean"), "description": .string("Attach a capture to each failure. Defaults to true.")])
            ]),
            "required": .array([.string("window"), .string("assertions")])
        ]),
        readOnly: true
    )

    // MARK: flow

    static let flow = ToolSpec(
        name: "proctor_flow",
        title: "Record, list and replay named step sequences",
        description: """
        Manage named flows — the reusable unit of an end-to-end campaign. Record captures a step \
        sequence as it is performed; replay runs it again with per-step canonical hashing; list \
        and show read what is stored; delete removes one.

        A recorded flow stores the step list, the selector each step resolved through, and the \
        per-step state hashes from the recording run. Replay compares against those hashes, so a \
        replay that diverges says where and how, rather than only that it failed.

        Flows persist under the session directory, so a campaign survives the MCP host restarting.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object(["type": .string("string"), "enum": .array([
                    .string("start"), .string("stop"), .string("replay"),
                    .string("list"), .string("show"), .string("delete")
                ])]),
                "name": .object(["type": .string("string")]),
                "window": .object(["type": .string("string"), "description": .string("Target window for replay; the flow's recorded window otherwise.")]),
                "description": .object(["type": .string("string"), "description": .string("What this flow covers, carried into the report.")]),
                "captureEach": .object(["type": .string("boolean")]),
                "settle": .object(["type": .string("object")])
            ]),
            "required": .array([.string("action")])
        ]),
        readOnly: false,
        destructive: true, idempotent: false
    )

    // MARK: stability

    static let stability = ToolSpec(
        name: "proctor_stability",
        title: "Replay a flow N times and measure determinism",
        description: """
        Replay a flow repeatedly and report where the runs stopped agreeing. Returns \
        firstDivergence — the step index where the canonical state hashes first differed across \
        runs — and stepInstability, a 0-to-1 score per step measuring how many distinct states \
        that step produced.

        This is the instrument that separates a real defect from a flaky test. A step with \
        instability above zero is nondeterministic before anyone argues about whether it is \
        correct, and a flow whose firstDivergence is step 3 does not need its step 9 assertion \
        investigated.

        Three runs detects gross nondeterminism; five to ten is the useful range for a flow \
        about to be trusted as a gate.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "flow": .object(["type": .string("string")]),
                "runs": .object(["type": .string("integer"), "description": .string("Defaults to 5.")]),
                "window": .object(["type": .string("string")]),
                "resetBetween": .object(["type": .string("object"), "description": .string("Steps to run between replays to return the app to its start state.")]),
                "includeTiles": .object(["type": .string("boolean"), "description": .string("Compare pixel tile hashes as well as the tree. Slower, catches rendering nondeterminism the tree cannot see.")])
            ]),
            "required": .array([.string("flow")])
        ]),
        readOnly: false,
        destructive: true, idempotent: false
    )

    // MARK: inspect

    static let inspect = ToolSpec(
        name: "proctor_inspect",
        title: "Read resolved styles and layer geometry from an instrumented app",
        description: """
        Read the view and layer hierarchy of an app that embeds the ProctorReflector package: \
        resolved colours, fonts, corner radii, opacity, constraints, and both the CALayer model \
        values and the presentation values, with a monotonic render revision.

        This is the only route to anything resembling computed styles on macOS. There is no \
        cross-process equivalent of getComputedStyle: for an app you do not own, the ceiling is \
        the accessibility tree plus pixels, and this tool reports reflectorUnavailable rather \
        than approximating. Embedding the reflector behind #if DEBUG in your own app is what \
        turns fidelity checking from eyeballing into measurement.

        The model-versus-presentation split matters during animation: they differ exactly while \
        something is in flight, which is a settle signal in its own right.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string")]),
                "node": .object(["type": .string("string"), "description": .string("Accessibility node id to correlate; omit for the whole hierarchy.")]),
                "maxDepth": .object(["type": .string("integer")]),
                "includeConstraints": .object(["type": .string("boolean"), "description": .string("Defaults to false; layout constraint dumps are large.")]),
                "presentation": .object(["type": .string("boolean"), "description": .string("Include CALayer presentation values alongside model values. Defaults to true.")])
            ]),
            "required": .array([.string("window")])
        ]),
        readOnly: true
    )

    // MARK: doctor

    static let doctor = ToolSpec(
        name: "proctor_doctor",
        title: "Report readiness, grants and session health",
        description: """
        Report whether the agent is running, which TCC grants are in place, what is attached, \
        whether observers are alive, whether Secure Event Input is active, and whether the \
        shortcuts CLI is available.

        Each missing grant comes with the exact fix for the running OS version. Accessibility can \
        be granted by profile on macOS 26 but that path is removed in 27 in favour of declarative \
        App Settings; Screen Recording can never be granted silently on any version. Getting this \
        wrong presents as elements not being found, which a model will retry indefinitely, so \
        running doctor first is the cheapest step in any campaign.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "verbose": .object(["type": .string("boolean"), "description": .string("Include per-app observer and cache detail.")]),
                "requestAccessibility": .object([
                    "type": .string("boolean"),
                    "description": .string(
                        "Ask macOS to show its Accessibility consent dialog if the grant is missing. "
                        + "The dialog appears once per app identity; if the user has already answered it, "
                        + "macOS shows nothing and the grant must be changed in System Settings instead. "
                        + "Report the result from a fresh doctor call rather than assuming the prompt was seen.")
                ]),
                "requestScreenRecording": .object([
                    "type": .string("boolean"),
                    "description": .string(
                        "Ask macOS for the Screen Recording consent dialog. Shown once per app "
                        + "identity; afterwards it returns the recorded answer silently, so pair "
                        + "it with the System Settings route in any UI.")
                ])
            ])
        ]),
        readOnly: true
    )

    static let unlock = ToolSpec(
        name: "proctor_unlock",
        title: "Open, evaluate and end a screen-unlock turn",
        description: """
        Control the screen-unlock capability. This works only when the login-path authorization \
        plugin is installed and armed; without it the actions are inert and `status` says so.

        Actions: `status` reports lock state, whether a turn is authorized right now, and whether \
        the plugin is installed. `open` opens a short turn without touching the screen, which \
        proves the mechanism-to-broker handshake in isolation. `unlock` opens a turn and asks \
        macOS to evaluate the unlock right; the result states plainly whether the right was \
        granted and whether the lock screen actually dismissed, because the latter depends on \
        loginwindow behaviour that is not contractual. `relock` relocks immediately and ends the \
        turn. `close` ends a turn without relocking.

        The turn always carries a TTL, so a crashed caller cannot leave the screen unlockable, and \
        the authorization rule keeps the normal password prompt as a fallback so a person is never \
        locked out. Disclose in any test methodology that a run operated the machine while locked.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([.string("status"), .string("open"), .string("close"),
                                    .string("unlock"), .string("relock"), .string("lock")]),
                    "description": .string("Defaults to status.")
                ]),
                "ttlMs": .object([
                    "type": .string("integer"),
                    "description": .string("How long the turn stays authorized. Defaults to 15000.")
                ])
            ])
        ]),
        readOnly: false,
        destructive: true, idempotent: false
    )

    // MARK: computer (Anthropic façade)

    static let computer = ToolSpec(
        name: "proctor_computer",
        title: "Drive a window with the stock Anthropic computer-use schema",
        description: """
        Accept a single Anthropic `computer` action in its stock schema and run it against a \
        window, so a model trained on that tool drives Proctor with no prompt changes. This is an \
        additive adapter: the native eleven tools are unchanged, and a run that does not use this \
        tool is unaffected.

        Supported actions map onto Proctor's own step vocabulary: screenshot (a window capture), \
        left_click / double_click / triple_click, mouse_move, type, key (an xdotool combo such as \
        "cmd+s"), scroll (scroll_direction plus scroll_amount), left_click_drag (needs a \
        start_coordinate, since the façade tracks no cursor), and wait. Coordinates are read in \
        the screenshot's own space — the target window's top-left is the origin — and mapped to \
        the global screen point the actuation needs; pass scale for a screenshot taken at other \
        than 1x.

        These are synthetic-event actions: they need the window frontmost and are reported with \
        plane=syntheticEvent, never as a background-safe result. foreground therefore defaults to \
        true. right_click, middle_click and cursor_position have no faithful mapping today and are \
        refused with a reason rather than mis-actuated. Every step is returned with the original \
        action, what it became, the plane it travelled and the post-state hash, so a façade-driven \
        run is as auditable as a native one.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string"), "description": .string("Window handle from proctor_apps to drive and observe.")]),
                "action": .object([
                    "type": .string("object"),
                    "description": .string("One Anthropic computer action in its stock schema, e.g. {\"action\":\"left_click\",\"coordinate\":[x,y]}.")
                ]),
                "scale": .object(["type": .string("number"), "description": .string("Coordinate scale of the screenshot the model was shown. Defaults to 1 (point space); pass 2 for a 2x retina capture.")]),
                "foreground": .object(["type": .string("boolean"), "description": .string("Activate the app first. Defaults to true, because computer-use actions are synthetic events that need the window frontmost.")])
            ]),
            "required": .array([.string("window"), .string("action")])
        ]),
        readOnly: false
    )

    // MARK: openai_computer (OpenAI façade)

    static let openaiComputer = ToolSpec(
        name: "proctor_openai_computer",
        title: "Drive a window with the stock OpenAI computer-use schema",
        description: """
        Accept OpenAI `openai_computer` actions in their stock schema — a single action or a batch \
        array — and run them against a window in order, stopping on the first failure and \
        reporting per-step outcome, which is the shape an OpenAI computer-use agent expects. Like \
        its Anthropic counterpart this is additive and opt-in; the native tool surface is \
        unchanged.

        Supported action types map onto Proctor's step vocabulary: screenshot, click (left button \
        only), double_click, move, type, keypress (a keys array such as ["ctrl","c"]), scroll \
        (scroll_x / scroll_y at a point), drag (a path of points), and wait. Coordinates are read \
        in the screenshot's own space — the window's top-left is the origin — and mapped to the \
        global screen point actuation needs; pass scale for a non-1x screenshot.

        The mapped actions are synthetic events, so they need the window frontmost and are \
        reported with plane=syntheticEvent; foreground defaults to true. A non-left mouse button \
        has no faithful mapping today and is refused rather than turned into a left click. The \
        batch stops at the first failing step and reports failedAt, and every step carries the \
        original action, its translation and the post-state hash for audit.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string"), "description": .string("Window handle from proctor_apps to drive and observe.")]),
                "actions": .object([
                    "type": .string("array"),
                    "description": .string("An ordered batch of OpenAI computer actions in the stock schema, e.g. [{\"type\":\"click\",\"button\":\"left\",\"x\":..,\"y\":..}]. A single action object is also accepted."),
                    "items": .object(["type": .string("object")])
                ]),
                "scale": .object(["type": .string("number"), "description": .string("Coordinate scale of the screenshot the model was shown. Defaults to 1; pass 2 for a 2x retina capture.")]),
                "foreground": .object(["type": .string("boolean"), "description": .string("Activate the app first. Defaults to true, because computer-use actions are synthetic events that need the window frontmost.")])
            ]),
            "required": .array([.string("window"), .string("actions")])
        ]),
        readOnly: false
    )

    // MARK: menu

    static let menu = ToolSpec(
        name: "proctor_menu",
        title: "Enumerate the menu bar with key-equivalents",
        description: """
        Walk the attached application's menu bar and return every item with its menu path, title, \
        enabled state, and its keyboard shortcut — the key-equivalent reconstructed from the \
        accessibility attributes, e.g. cmd+shift+n. Pressing a known shortcut is faster and more \
        robust than walking AXMenuBar to a submenu item, which is slow, focus-sensitive and \
        brittle across localisations, so surfacing the shortcut lets a model choose the keystroke \
        path when one exists.

        Each item carries the shortcut two ways: the normalised string, and a key plus modifiers \
        pair in the exact shape the proctor_act `key` step reads — so an item can be invoked by \
        its shortcut straight from this enumeration. That `key` step is a synthetic event and needs \
        the app frontmost; for a background-safe invocation use the `menu` step with the menuPath \
        this tool returns, which actuates the same command through the accessibility plane without \
        stealing focus. Both routes come from the one walk.

        This is a pure accessibility read: no synthetic events, no new permission beyond the \
        Accessibility grant attach already required, and it reaches a background or other-Space \
        app. macOS builds some submenus only when they are opened; such a submenu is reported as a \
        single item with submenuPopulated false and is not descended into, rather than fabricating \
        contents that were never read. Open it with a menu or press step and re-read to see inside.

        Takes an app handle, or a window handle whose owning app is used.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "app": .object(["type": .string("string"), "description": .string("App handle from proctor_apps to read the menu bar of.")]),
                "window": .object(["type": .string("string"), "description": .string("A window handle, as an alternative to app; its owning application's menu bar is read.")])
            ])
        ]),
        readOnly: true
    )

    // MARK: dictionary

    static let dictionary = ToolSpec(
        name: "proctor_dictionary",
        title: "Read an app's scripting dictionary (sdef)",
        description: """
        Read an attached application's scripting definition — its suites, commands, classes, \
        properties and enumerations — and return it as structured data plus a one-line capability \
        summary. This makes the Apple-Events plane self-describing: instead of guessing whether an \
        app is scriptable or hard-coding AppleScript, a caller queries the app's own dictionary and \
        chooses the cheapest reliable route per task — scripting where a command is exact, \
        accessibility where it is not.

        The dictionary is resolved from the running app's bundle (via the same merge the `sdef` \
        tool performs, so the standard suite and terminology are already folded in) and cached per \
        app handle. Because a handle's identity changes when the app relaunches, the cache \
        invalidates on relaunch on its own; pass refresh to re-read regardless.

        An app that exposes no scripting commands is reported plainly with scriptable=false and a \
        route hint, not as an error — "not scriptable" is exactly the signal that tells a caller to \
        use proctor_snapshot and proctor_act instead. This tool only reads; actuation stays through \
        proctor_act (its appleScript and shortcut steps) with settle and provenance.

        Pass summaryOnly to get the capability summary and counts without the full suite listing.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "app": .object(["type": .string("string"), "description": .string("App handle from proctor_apps. Supply this or window.")]),
                "window": .object(["type": .string("string"), "description": .string("Window handle from proctor_apps; its owning app is used. Supply this or app.")]),
                "summaryOnly": .object(["type": .string("boolean"), "description": .string("Return the capability summary and counts without the full suite listing. Defaults to false.")]),
                "refresh": .object(["type": .string("boolean"), "description": .string("Re-read the sdef even if a cached dictionary exists for this app handle. Defaults to false.")])
            ])
        ]),
        readOnly: true
    )
}
