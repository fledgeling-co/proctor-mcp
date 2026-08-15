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
        apps, snapshot, find, act, capture, zoom, wait, assert_, flow, stability, inspect, doctor, unlock,
        computer, openaiComputer, menu, dictionary, policy, kill, ios
    ]

    public static func spec(named name: String) -> ToolSpec? {
        all.first { $0.name == name }
    }

    // MARK: apps

    static let apps = ToolSpec(
        name: "proctor_apps",
        title: "List and attach applications",
        description: """
        Enumerate running applications and their windows, attach to the ones under test, and \
        bring one to the front.

        Attaching is what makes everything else work. It warms the accessibility tree, applies \
        AXManualAccessibility where the app is Chromium- or Electron-based, starts long-lived \
        observers, and begins retaining element references. A retained reference keeps resolving \
        when its window moves to another Space or behind other windows; a fresh enumeration will \
        not find it. Attach once per app at the start of a campaign and reuse the handles.

        Use activate when an app is running but reports no windows, or is not running at all. \
        Every actuating tool resolves a window handle first, so an app whose windows are all \
        closed cannot be driven, and the menu item that would reopen one cannot be reached \
        without the window it creates. activate launches or reopens the app the way a Dock click \
        does, waits for a window to appear, attaches, and returns the handles. It goes through \
        the same policy gate and audit trail as driving the app.

        activate also takes its turn now, because bringing an app to the front changes where \
        every other session's clicks land. If another run holds the machine it waits, and if it \
        is still waiting when the queue's ceiling fires, or a person drops it from the run HUD, \
        it comes back saying so rather than activating. Nothing is brought to the front on \
        either of those paths, so a busy-machine refusal is safe to send again while a \
        person's is a reason to ask first.

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
                    "enum": .array([.string("list"), .string("attach"), .string("activate"), .string("detach")]),
                    "description": .string("list enumerates without touching anything; attach begins a stateful session; activate brings the app to the front, launching or reopening it so it has a window, then attaches; detach releases refs and observers.")
                ]),
                "bundleId": .object(["type": .string("string"), "description": .string("Bundle identifier to attach or activate, e.g. com.apple.TextEdit.")]),
                "pid": .object(["type": .string("integer"), "description": .string("Process id, when the bundle identifier is ambiguous or absent.")]),
                "name": .object(["type": .string("string"), "description": .string("Localised application name, matched case-insensitively.")]),
                "app": .object(["type": .string("string"), "description": .string("An existing app handle, for detach or activate.")]),
                "timeoutMs": .object(["type": .string("integer"), "description": .string("activate only: how long to wait for a window to appear. Defaults to 5000.")]),
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
        Run a sequence of steps against a window, settling after each and returning per-step \
        outcome, the plane the action travelled, a post-state hash and a tree diff. A six-step \
        flow is one call.

        Steps use the process-directed plane by default (accessibility actions and Apple Events), \
        which reaches non-frontmost, occluded and other-Space windows without stealing focus and \
        survives Secure Event Input. The kinds dragPath, hover, click and key inject synthetic \
        events instead: they need the window foreground and report plane=syntheticEvent, so a \
        background-safe result is never faked. Reserve them for what accessibility cannot express \
        — drags, canvas surfaces, hover states, keyboard-focus behaviour itself. A refused \
        accessibility route fails rather than falling back silently.

        The result carries a foreground block: how many steps were known before the run to need \
        the app in front, how many might have, and how many actually travelled as synthetic \
        events. Read measured rather than re-deriving it from the kinds, because a type or scroll \
        into an element the accessibility plane cannot write falls back to the event stream and \
        no count made from the step list would show it. A run whose measured count is above zero \
        cannot be repeated unattended.

        Settling is a conjunction of quiet capture frames, quiet accessibility notifications and \
        the app's own idle signal where a reflector is embedded, bounded by a timeout — never a \
        sleep. On a step failure the batch stops and reports failedAt.
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
                "pointerMarks": .object(["type": .string("boolean"), "description": .string("With captureEach, composite a marker at each step's target point — where the step acted — onto that step's frame, written as a marked sibling PNG. It annotates the intended target, not a live cursor; Proctor does not move the system pointer. Defaults to false.")]),
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
        Screenshot one window with ScreenCaptureKit, window-scoped, so the result contains that \
        window alone rather than whatever is on top of it. The image is written to disk and the \
        path returned; bytes are never returned inline.

        Check trustworthy before believing the frame. A stale frame looks identical to a correct \
        one, so the freshness fields — status, contentRect, dirty-rectangle coverage, framesWaited \
        — are the only thing separating them, and caveat names the reason when one cannot be \
        confirmed. Off-screen windows may only emit complete frames when the pointer moves on \
        their display.

        normalize is on by default: the frame is scaled to fit ~1568px on the long edge and \
        ~1.15MP, and normalization.scale reports the exact factor. Map a model coordinate back \
        with native = normalised / scale. Pass normalize false for native pixels when asserting \
        against native geometry. Raise normalizeMaxLongEdge/normalizeMaxPixels for a model with a \
        larger ceiling, or set them to a provider's tile grid (768 for Gemini) to avoid paying for \
        a tile holding a sliver of screen.

        annotate burns numbered marks over interactable elements and returns a mark→node map, so \
        "click mark 7" resolves to a real element id; annotateAll marks everything with a frame, \
        grid overlays reference lines. The un-annotated image stays at path, the marked one at \
        annotation.annotatedPath.

        format defaults to png. jpeg is available for archiving many frames, and costs UI text: \
        measured against a native-resolution baseline, OCR recall fell from 94% (png) to 91% at \
        q85 and 78% at q50, with misread-as-different-word errors rising sixfold.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string")]),
                "path": .object(["type": .string("string"), "description": .string("Where to write the image. Defaults to a session temp directory.")]),
                "format": .object(["type": .string("string"), "enum": .array([.string("png"), .string("jpeg")]), "description": .string("Container. Defaults to png; jpeg costs UI-text accuracy.")]),
                "quality": .object(["type": .string("integer"), "description": .string("Lossy quality 60-100. Defaults to 90. Ignored for png.")]),
                "waitForComplete": .object(["type": .string("boolean"), "description": .string("Keep pulling frames until one is .complete or the timeout expires. Defaults to true.")]),
                "timeoutMs": .object(["type": .string("integer"), "description": .string("Defaults to 3000.")]),
                "scale": .object(["type": .string("number"), "description": .string("Output scale. Defaults to the display's backing scale.")]),
                "tileHashes": .object(["type": .string("boolean"), "description": .string("Also return per-tile perceptual hashes, for determinism comparison.")]),
                "includeCursor": .object(["type": .string("boolean"), "description": .string("Defaults to false, since a cursor in the frame is a source of false diffs.")]),
                "annotate": .object(["type": .string("boolean"), "description": .string("Burn numbered marks over interactable elements and return the mark→node map. Defaults to false.")]),
                "annotateAll": .object(["type": .string("boolean"), "description": .string("Mark every element carrying a frame. Implies annotate. Defaults to false.")]),
                "grid": .object(["type": .string("boolean"), "description": .string("Overlay reference grid lines. Independent of annotate. Defaults to false.")]),
                "gridSpacing": .object(["type": .string("number"), "description": .string("Points between grid lines. Defaults to 100.")]),
                "maxMarks": .object(["type": .string("integer"), "description": .string("Ceiling on marks drawn; the overflow is dropped in reading order and reported as truncated. Defaults to 150.")]),
                "normalize": .object(["type": .string("boolean"), "description": .string("Fit the frame to the vision ceiling and report the exact scale. Defaults to true; pass false for native pixels.")]),
                "normalizeMaxLongEdge": .object(["type": .string("integer"), "description": .string("Long-edge ceiling in pixels. Defaults to 1568.")]),
                "normalizeMaxPixels": .object(["type": .string("integer"), "description": .string("Total-pixel ceiling. Defaults to 1150000 (~1.15MP).")])
            ]),
            "required": .array([.string("window")])
        ]),
        readOnly: true
    )

    // MARK: zoom

    static let zoom = ToolSpec(
        name: "proctor_zoom",
        title: "Crop a region or element at native resolution",
        description: """
        Return a native-resolution crop of one region or one accessibility element, for reading \
        small text or fine detail a whole-window capture loses. proctor_capture normalises to the \
        vision ceiling by default, and the pixels a label, glyph or numeric field is written in do \
        not survive that downscale; this restores them without shipping a full 2x screenshot. \
        Published benchmarks put the gain large: iterative crop-and-zoom lifts GUI grounding \
        accuracy on high-resolution desktop software from roughly 19% to 48-73%.

        Give either region — [x, y, w, h] in points from the window's top-left, the space \
        proctor_wait uses — or node, an id from proctor_find whose frame is resolved for you. \
        padding adds context points on every side. Aim for a region around 1000px on its long \
        edge: much smaller and the model loses the surrounding context that disambiguates the \
        target. The compose path is find → zoom → assert.

        The crop is cut from a native-scale window capture, so it carries that capture's freshness \
        metadata unchanged — check trustworthy and caveat as with proctor_capture. The descriptor \
        names the pixel rect actually cut, whether it was clamped to the window, and the path to \
        the un-cropped full-window image. A region with no area, or one outside the frame, is an \
        error naming the reason rather than an empty image. Reading the text is left to the \
        caller; this restores the pixels, it does not OCR them.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window": .object(["type": .string("string"), "description": .string("Window handle from proctor_apps to capture and crop.")]),
                "region": .object(["type": .string("array"), "items": .object(["type": .string("number")]), "description": .string("[x, y, w, h] in points from the window's top-left. Supply this or node.")]),
                "node": .object(["type": .string("string"), "description": .string("A node id from proctor_find; its frame is resolved and cropped. Supply this or region.")]),
                "padding": .object(["type": .string("number"), "description": .string("Context points added on every side. Defaults to 0.")]),
                "path": .object(["type": .string("string"), "description": .string("Where to write the crop. Defaults to a session temp directory.")]),
                "format": .object(["type": .string("string"), "enum": .array([.string("png"), .string("jpeg")]), "description": .string("Container for the crop. Defaults to png, which is what makes small text readable.")]),
                "quality": .object(["type": .string("integer"), "description": .string("Lossy quality 60-100. Defaults to 90. Ignored for png.")]),
                "waitForComplete": .object(["type": .string("boolean"), "description": .string("Keep pulling frames until one is .complete or the timeout expires. Defaults to true.")]),
                "timeoutMs": .object(["type": .string("integer"), "description": .string("Defaults to 3000.")]),
                "scale": .object(["type": .string("number"), "description": .string("Capture scale. Defaults to the display's backing scale, which is what makes the crop native-resolution.")]),
                "includeCursor": .object(["type": .string("boolean"), "description": .string("Defaults to false, since a cursor in the frame is a source of false diffs.")])
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
        alignment against another, its placement inside its container), pixels (a region matches \
        a reference within tolerance), and accessibility auditing (every interactive node has a \
        label, contrast meets a threshold, hit targets meet a minimum size, focus order follows \
        visual order).

        The two alignment kinds answer different questions. kind=alignedWith measures between two \
        things you name: it returns the deltas on left, right, top, bottom, centerX and centerY, \
        and given expected={node, edge} it tests one of them. kind=horizontalAlignment classifies \
        one element inside its container — expected is left, center or right (leading, trailing \
        and centre are accepted) — and it rejects the other two placements rather than passing on \
        any single small delta. Give it `container` as a node id or [x,y,w,h]; with none it uses \
        the window frame, which usually carries content margins, so a left-aligned element inside \
        an inset area reads as custom until you name the content view. Its terms are physical \
        rather than layout-direction-aware: it compares screen x, so in a right-to-left app the \
        element you would call leading is reported right.

        Every geometry kind takes `tolerance` in points and defaults it to 1.0 — the distance at \
        which two coordinates count as the same. It means the same thing on all of them, so a \
        value you set on one assertion carries the same strictness to the next.

        An assertion that could not be evaluated comes back skipped with a reason, never as a \
        pass, and ok is false while anything is skipped. horizontalAlignment skips rather than \
        guesses when the container is too close in width to the element to tell its placements \
        apart, when a container you asked for has no readable frame, and when no expected is given \
        — the last still reports the placement it observed, so it doubles as a probe.

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
                                .string("containedIn"), .string("alignedWith"), .string("horizontalAlignment"), .string("minHitSize"),
                                .string("contrast"), .string("focusOrder"), .string("regionMatches"),
                                .string("agree")
                            ])]),
                            "node": .object(["type": .string("string")]),
                            "find": .object(["type": .string("object")]),
                            "expected": .object([:]),
                            "container": .object(["description": .string("The rectangle horizontalAlignment classifies against: a node id, or [x,y,w,h]. Defaults to the window frame.")]),
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

        Replay drives an application, so it passes the same policy gate and writes to the same \
        redacting audit trail as proctor_act: a blocked app, or a sensitive one with no current \
        approval token, is refused before the first step. The decision is made on the application \
        behind the window being driven now, not the one the recording names. Recording, listing, \
        showing and deleting drive nothing and are not gated.
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
                "pointerMarks": .object(["type": .string("boolean"), "description": .string("With captureEach on a replay, composite a marker at each step's target point — where the step acted — onto that step's frame. Annotates the intended target, not a live cursor. Defaults to false.")]),
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

        Every repeat replays the flow, so each one passes the policy gate and is written to the \
        redacting audit trail, resets included. Permission is re-checked before each repeat: an \
        approval token that expires part-way through stops the run there, and the report says how \
        many repeats it managed — a truncated run is never reported deterministic.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "flow": .object(["type": .string("string")]),
                "runs": .object(["type": .string("integer"), "description": .string("Defaults to 5.")]),
                "window": .object(["type": .string("string")]),
                "resetBetween": .object(["type": .string("object"), "description": .string("Steps to run between replays to return the app to its start state.")]),
                "includeTiles": .object(["type": .string("boolean"), "description": .string("Compare pixel tile hashes as well as the tree. Slower, catches rendering nondeterminism the tree cannot see.")]),
                StabilityCaptureOptions.captureEachArg: .object(["type": .string("boolean"), "description": .string("Write a PNG after every step that runs, in every replay, so a divergent step can be looked at rather than only scored. A replay that breaks mid-flow photographs the steps before the break and reports the rest as not attempted. Off by default: an opt-in run writes roughly runs × steps images (doubled where a marker is drawn), nothing cleans them up, and capturing after each step shifts the run's timings, which the report says so a score is never quietly compared against a run captured off.")]),
                StabilityCaptureOptions.pointerMarksArg: .object(["type": .string("boolean"), "description": .string("Composite a marker at each step's target point onto that step's frame, written as a marked sibling PNG. It annotates where the step acted, not a live cursor; Proctor does not move the system pointer. Turns captureEach on when it is off, and says so in the report, because a marker needs a frame to be drawn on. Defaults to false.")])
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

        Also reports the toolchain Proctor depends on but does not ship — Obscura, simctl and \
        Xcode, cua-driver, Maestro — with where each was found, whether it is usable, and what \
        established that; and which lanes this machine actually has, so a caller learns that \
        there is no iOS lane here before it tries to use one rather than after. **This call runs \
        none of those tools.** A usability of `unconfirmed` is a fact about what Proctor has \
        established, not a fault, and calling doctor again will not change it.

        The `policy` block is the gate's posture — its mode, the sizes of its lists, whether an \
        approval token is live, and whether the audit trail is writable and verifying clean. The \
        rules themselves are not here; proctor_policy answers those.

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
        window, so a model trained on that tool drives Proctor unchanged. Additive: the native \
        tools are unaffected.

        Maps: screenshot, left_click / double_click / triple_click, mouse_move, type, key (an \
        xdotool combo such as "cmd+s"), scroll (scroll_direction plus scroll_amount), \
        left_click_drag (needs start_coordinate, since the façade tracks no cursor), and wait. \
        Coordinates are read in the screenshot's own space, origin at the window's top-left, and \
        mapped to the global screen point; pass scale for a non-1x screenshot.

        These are synthetic events, so they need the window frontmost and report \
        plane=syntheticEvent; foreground defaults to true. right_click, middle_click and \
        cursor_position are refused with a reason rather than mis-actuated. Each step returns the \
        original action, its translation, the plane travelled and the post-state hash.
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
        Accept OpenAI `openai_computer` actions in their stock schema — a single action or a \
        batch array — and run them against a window in order, stopping at the first failure and \
        reporting failedAt. Additive and opt-in; the native surface is unchanged.

        Maps: screenshot, click (left button only), double_click, move, type, keypress (a keys \
        array such as ["ctrl","c"]), scroll (scroll_x / scroll_y at a point), drag (a path of \
        points), and wait. Coordinates are read in the screenshot's own space, origin at the \
        window's top-left; pass scale for a non-1x screenshot.

        Mapped actions are synthetic events: they need the window frontmost, report \
        plane=syntheticEvent, and foreground defaults to true. A non-left mouse button is refused \
        rather than turned into a left click. Each step carries the original action, its \
        translation and the post-state hash.
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
        Read an attached application's scripting definition — suites, commands, classes, \
        properties and enumerations — as structured data plus a one-line capability summary. This \
        makes the Apple-Events plane self-describing, so a caller picks the cheapest reliable route \
        per task: scripting where a command is exact, accessibility where it is not.

        Resolved from the running app's bundle with the standard suite already merged, and cached \
        per app handle; the cache invalidates on relaunch on its own, and refresh re-reads \
        regardless. An app exposing no scripting commands returns scriptable=false with a route \
        hint rather than an error — that is the signal to use proctor_snapshot and proctor_act.

        Read-only; actuation stays in proctor_act. summaryOnly returns the summary and counts \
        without the full suite listing.
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

    // MARK: policy (audit trail + policy gate)

    static let policy = ToolSpec(
        name: "proctor_policy",
        title: "Configure the app policy gate and read the redacting audit trail",
        description: """
        Operator-facing safety plumbing: a policy gate deciding which applications Proctor may \
        drive, and a redacting audit trail recording every action without storing what was typed.

        The gate is keyed by bundle identifier and fails closed. block is always refused. allow, \
        when non-empty, is an allow list — anything not on it, including an app whose bundle id \
        cannot be resolved, is refused. sensitive applications may be driven only while a \
        short-lived approval token is held, so a crashed caller leaves no standing authority.

        Actions: status reports the lists, whether a token is live and where the audit log lives; \
        configure replaces any of the sets you supply; approve mints a token, optionally scoped to \
        one bundle id, with a TTL; revoke drops it; audit returns recent JSONL lines. Typed values \
        and script bodies are stored as length plus SHA-256, never in the clear.

        The trail is encrypted at rest. Each entry is sealed on its own to a key held in this Mac's \
        login keychain, so the file is unreadable if it is copied off the machine, restored from a \
        backup, or opened by another account; reading it back through audit needs that keychain. \
        There is no recovery copy of that key and no export: if it is lost, so is the history. A \
        readable trail left by an earlier version is converted in place on first use, which removes \
        the last readable copy of it. status reports auditWritable, and an entry that cannot be \
        sealed is dropped rather than written readable, so a trail that has stopped is visible \
        rather than silent.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([.string("status"), .string("configure"), .string("approve"),
                                    .string("revoke"), .string("audit")]),
                    "description": .string("Defaults to status.")
                ]),
                "allow": .object([
                    "type": .string("array"), "items": .object(["type": .string("string")]),
                    "description": .string("For configure: bundle ids that may be driven. Non-empty turns on allow-list mode (everything else is refused). Supplying the key replaces the whole set.")
                ]),
                "block": .object([
                    "type": .string("array"), "items": .object(["type": .string("string")]),
                    "description": .string("For configure: bundle ids that are always refused. Wins over allow. Supplying the key replaces the whole set.")
                ]),
                "sensitive": .object([
                    "type": .string("array"), "items": .object(["type": .string("string")]),
                    "description": .string("For configure: bundle ids that require a current approval token before actuation. Supplying the key replaces the whole set.")
                ]),
                "bundleId": .object([
                    "type": .string("string"),
                    "description": .string("For approve: scope the token to one bundle id. Omit to authorize any sensitive app.")
                ]),
                "ttlMs": .object([
                    "type": .string("integer"),
                    "description": .string("For approve: how long the token stays valid. Defaults to 15000, like the unlock turn.")
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("For audit: how many of the most recent lines to return. Defaults to 50.")
                ])
            ])
        ]),
        readOnly: false
    )

    // MARK: kill (process list + terminate)

    static let kill = ToolSpec(
        name: "proctor_kill",
        title: "List and terminate processes for test setup and teardown",
        description: """
        List running processes and terminate the ones a query names, so a campaign can reset \
        state between runs. Match by bundle identifier, localised name, or process id; all supplied \
        conditions must hold, so name plus bundle id narrows rather than widens.

        Terminating is destructive and goes through the proctor_policy gate: a blocked application \
        is never killed, an allow list in force refuses anything it does not name — including a \
        bare pid with no resolvable bundle id — and a sensitive application requires a current \
        approval token. Every attempt, allowed or refused, is audited. The kernel, launchd and the \
        agent's own process are never signalled.

        list enumerates matches without touching anything; kill delivers a graceful terminate, or \
        a forced one when force is set, reporting per-target outcome so a partial teardown is \
        visible rather than reported as a whole success.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([.string("list"), .string("kill")]),
                    "description": .string("list enumerates matching processes and touches nothing; kill terminates them. Defaults to list.")
                ]),
                "bundleId": .object(["type": .string("string"), "description": .string("Bundle identifier to match, e.g. com.apple.TextEdit. Case-insensitive exact match.")]),
                "name": .object(["type": .string("string"), "description": .string("Localised application name to match, case-insensitively, per `match`.")]),
                "pid": .object(["type": .string("integer"), "description": .string("Process id to match exactly. A pid with no resolvable bundle id is refused whenever an allow list is in force.")]),
                "match": .object(["type": .string("string"), "enum": .array([.string("substring"), .string("exact")]), "description": .string("How `name` is matched. Defaults to substring.")]),
                "force": .object(["type": .string("boolean"), "description": .string("Send a forced termination (SIGKILL / forceTerminate) instead of a graceful one, for a hung target. Defaults to false.")])
            ])
        ]),
        readOnly: false,
        destructive: true, idempotent: false
    )

    // MARK: ios (Simulator device lane)

    static let ios = ToolSpec(
        name: "proctor_ios",
        title: "Target an iOS Simulator and drive an app by deep link",
        description: """
        Put an iOS app into a named state by opening a URL on a booted Simulator, and read back \
        what actually happened.

        **This is a device lane, not a window lane, and the difference is not cosmetic.** A device \
        handle looks like `dev-29fea02e` and is not a window handle: proctor_snapshot, \
        proctor_find, proctor_assert, proctor_act and proctor_capture do not work against one and \
        refuse it by name. The Mac's accessibility API does not cross into a simulated device, so \
        for an iOS app there is no tree, no elements, no geometry and no actuation steps. What \
        exists instead is three channels — whether the app's process is running, what the device \
        screen looks like, and what simctl said — and this tool reports each separately rather \
        than blending them into a single claim.

        **A zero exit means the URL was delivered, not that the app went anywhere.** Measured: the \
        same open, run twice, exits zero both times, and only the first one changes anything. So \
        `open` returns an evidence block and a verdict that says exactly what is supported: \
        `targetChanged` (delivered, the resolved app is running, and the screen changed — the \
        strongest claim available), `screenChanged` (the screen moved but the change cannot be \
        attributed to the app the URL named, which is where a universal link Safari swallowed or a \
        system sheet lands), `deliveredOnly` (nothing observable changed — inconclusive rather \
        than failed, because a deep link to the screen the app is already on looks exactly like \
        one the app ignored), and `refused`. None of them claims the app reached a particular \
        screen: the frontmost app on the device is not observable through this lane.

        A device screenshot carries no ScreenCaptureKit frame status, so unlike a window capture \
        its freshness cannot be established and it comes back marked untrustworthy with that \
        reason. The pixels are real; the guarantee that comes with a window capture is not.

        `open` never boots anything — it refuses a device that is not booted, because folding a \
        stateful minute-long side effect into a call whose result is "did this navigate" would \
        make both meaningless. `boot` is explicit, gated and audited. Nothing here ever shuts a \
        device down or reboots one; a device this session booted is marked in `list` so a person \
        can decide about it.

        Driving an app goes through the proctor_policy gate on the app the URL actually resolves \
        to on the device, never on a bundle id the caller supplied — that name is used only as a \
        consistency check. iOS targets are named `ios:<bundleId>` in an allow list or the \
        sensitive set, so a Mac app on the allow list does not silently authorise the iOS app of \
        the same identifier; a block on either spelling blocks both. The audit trail records the \
        scheme and host of the URL in the clear and reduces its path and query to a length and a \
        hash, because a deep link routinely carries a token.

        Action `flow` runs a **Maestro** flow file against the device and scores repeats of it. \
        Maestro is a separate binary that executes a whole file and reports at the end, so what \
        this proves is coarser than a Mac replay and the result says so rather than borrowing the \
        stronger words: `flowPassed` means the driver executed the sequence and reported success, \
        not that Proctor observed the app reach any state. Proctor did not run these commands and \
        has no independent observation of any of them; the only observer of the steps is Maestro. \
        Individual Maestro commands are never routed through proctor_act — a tool driving its own \
        engine is not driving what Proctor is attached to — so the unit here is the file.

        With `runs` above 1 the repeats are scored against **each other**: `firstDivergence` is \
        where two repeats stopped agreeing, indexed by Maestro's own sequence number, and it is \
        never a comparison against a recording because there is none. Maestro prepends two \
        commands that are in no flow file, and they are marked `injected` so an index is not \
        mistaken for a line of your YAML. The comparison is over each command's identity and \
        whether it completed; durations are reported beside the score and never folded into it, \
        because one unchanged command measured 634, 91, 88, 96 and 91 ms across five repeats. A \
        repeat that failed in the driver rather than the app — no per-command record, a failed \
        launch, a device that went away — is excluded from the score and makes the sweep \
        truncated, so driver flake is never published as the app's non-determinism. A five-run \
        sweep takes roughly 70 to 90 seconds, most of it driver start-up.

        The gate for a flow judges the apps the flow **declares**, which is weaker than the \
        device-resolved judgement `open` makes, and the result says `declared` for that reason. \
        Any construct Proctor cannot resolve — a script, an interpolated app id, an unreadable \
        include — is refused whenever an application policy is in force, and reported when none \
        is. An `openLink` inside a flow is gated on what the device resolves it to, not on the \
        file. The trail records the flow's path and a hash of its contents, so an entry attests to \
        the bytes that ran.

        Requires Xcode, which is where simctl lives. proctor_doctor carries a `simctl` row saying \
        whether this machine has a lane at all, and a `maestro` row for the flow action.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([.string("list"), .string("boot"), .string("open"),
                                    .string("screenshot"), .string("flow")]),
                    "description": .string(
                        "list enumerates simulators and touches nothing; boot starts a named one and "
                        + "waits for it; open delivers a URL to a booted one and reports the evidence; "
                        + "screenshot writes the device surface to disk; flow runs a Maestro flow file "
                        + "and, with runs above 1, scores the repeats against each other. Defaults to "
                        + "list.")
                ]),
                "device": .object([
                    "type": .string("string"),
                    "description": .string(
                        "Which simulator: a device handle from action \"list\", a udid, or a name "
                        + "like \"iPhone 16 Pro\". Omit for the single booted device when there is "
                        + "exactly one; ambiguity is an error naming the candidates rather than a guess.")
                ]),
                "url": .object([
                    "type": .string("string"),
                    "description": .string(
                        "The deep link to open. A custom scheme resolves to its handler on the device "
                        + "and is gated on that app. An https universal link cannot be resolved to a "
                        + "handler from a scheme claim, so it is refused whenever an allow list is in force.")
                ]),
                "bundleId": .object([
                    "type": .string("string"),
                    "description": .string(
                        "The app you expect to receive the URL. A consistency check, not the gate key: "
                        + "a disagreement with what the device resolved is reported. It also enables the "
                        + "process-liveness channel for an https URL, which has no resolvable handler.")
                ]),
                "pixelEvidence": .object([
                    "type": .string("boolean"),
                    "description": .string(
                        "Capture the device screen before and after the open and compare them. Defaults "
                        + "to true; this is the only channel that separates a deep link that moved the "
                        + "app from one that did nothing.")
                ]),
                "changeThreshold": .object([
                    "type": .string("number"),
                    "description": .string(
                        "Fraction of changed pixels before the screen counts as changed. Defaults to "
                        + "0.0005, calibrated against an idle floor measured at exactly 0 and a smallest "
                        + "real navigation at 0.002.")
                ]),
                "path": .object([
                    "type": .string("string"),
                    "description": .string(
                        "For screenshot, where to write it; defaults to a session temp directory. For "
                        + "flow, the absolute path of the Maestro flow file to run. A flow file is "
                        + "content Proctor executes, so it passes the filesystem jail and is scanned "
                        + "for the apps it declares before anything runs.")
                ]),
                "runs": .object([
                    "type": .string("integer"),
                    "description": .string(
                        "How many times to run the flow, for action flow. Defaults to 1, which "
                        + "executes and reports without a determinism claim — a single run cannot "
                        + "measure divergence. Above 1 the repeats are scored against each other. "
                        + "Each repeat costs roughly 8 seconds of driver start-up on top of the "
                        + "flow's own time.")
                ]),
                "timeoutMs": .object([
                    "type": .string("integer"),
                    "description": .string("Bound on the simctl call, and on boot's wait for the device to come up. Defaults to 15000, and 120000 for boot.")
                ])
            ])
        ]),
        readOnly: false,
        destructive: false, idempotent: false
    )
}
