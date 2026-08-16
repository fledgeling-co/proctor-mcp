import Foundation

// The wire contract between the permissionless shim and the privileged agent,
// and the shape of everything the agent returns to a model.
//
// One rule runs through all of it: nothing that could be stale, partial or
// negotiated is returned bare. A frame carries its freshness, a tree carries
// its revision and how it was obtained, an action carries what settled it.
// A value with no provenance is indistinguishable from a correct one, and
// that is the failure mode this whole server exists to remove.

// MARK: - Transport

public enum Wire {
    /// Fixed socket path. The agent binds it; the shim connects. Both derive it
    /// the same way so neither needs configuration. PROCTOR_SOCKET overrides it,
    /// which is how a test binds a throwaway socket instead of the real one.
    public static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["PROCTOR_SOCKET"],
           !override.isEmpty { return override }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/app.fledgeling.procter/agent.sock"
    }

    public static let bundleIdentifier = "app.fledgeling.procter"
    public static let agentLabel = "app.fledgeling.procter.agent"
    public static let protocolVersion = 1

    /// The agent's own LaunchServices identity, since PRO-0040.
    ///
    /// The agent is a second Mach-O inside Proctor.app, so it used to inherit the
    /// bundle's Info.plist and LaunchServices recorded it as a running instance of
    /// the application. `open -a Proctor` then activated a process with no window,
    /// exited 0, and showed nothing — which meant Proctor could not be opened at
    /// all while its own agent was up, which is nearly always. The agent binary now
    /// carries this identifier in a `__TEXT,__info_plist` section of its own, so
    /// LaunchServices no longer confuses the two.
    ///
    /// THIS IS NOT THE SIGNING IDENTIFIER, and the difference is the whole design.
    /// Every nested binary is still signed `-i app.fledgeling.procter`, because TCC
    /// matches a process against the recorded designated requirement — which names
    /// the signing identifier and the team, and contains no path and nothing drawn
    /// from this plist. Keeping the signature identical is what lets the agent keep
    /// Accessibility and Screen Recording across the upgrade instead of asking a
    /// person for them again. `scripts/build-app.sh` fails the build if either half
    /// of that ever stops being true.
    ///
    /// Deliberately the same string as `agentLabel`: launchd and LaunchServices
    /// should not know the agent by two different names. `WireIdentityTests` pins
    /// them together so an edit to one is caught rather than discovered.
    public static let agentBundleIdentifier = bundleIdentifier + ".agent"

    /// Whether a running application is one of Proctor's own.
    ///
    /// Read from these constants rather than from `Bundle.main.bundleIdentifier`:
    /// inside the agent that now resolves to the agent's own identity, which matches
    /// no running application, so inferring it would quietly stop recognising the
    /// menu-bar app. That matters because somebody opening Proctor's own menu to
    /// release a held run must not be read as a person taking the machine back — the
    /// run would hold itself again on the way out.
    public static func isProctor(bundleIdentifier id: String?) -> Bool {
        guard let id else { return false }
        return id == bundleIdentifier || id == agentBundleIdentifier
    }

    /// Length-prefixed JSON framing: 4-byte big-endian byte count, then payload.
    /// Newline framing loses to embedded newlines in captured text; this does not.
    public static let maxFrameBytes = 64 * 1024 * 1024
}

public struct AgentRequest: Codable, Sendable {
    public var id: String
    public var tool: String
    public var arguments: JSONValue
    public init(id: String, tool: String, arguments: JSONValue) {
        self.id = id; self.tool = tool; self.arguments = arguments
    }
}

public struct AgentResponse: Codable, Sendable {
    public var id: String
    public var ok: Bool
    public var result: JSONValue?
    public var error: AgentError?
    public init(id: String, ok: Bool, result: JSONValue? = nil, error: AgentError? = nil) {
        self.id = id; self.ok = ok; self.result = result; self.error = error
    }
}

/// Errors carry a remedy because the consumer is a model that will otherwise
/// retry a permission failure forever, reading it as a flaky element lookup.
public struct AgentError: Codable, Sendable, Error {
    public var code: Code
    public var message: String
    public var remedy: String?
    public var detail: JSONValue?

    // MARK: - What a delegated failure has to carry (PRO-0045)

    /// Whether the action may already have happened.
    ///
    /// **Set by the backend that failed, and never inferred from `code`.** The
    /// step loop needs to know whether to record `failed` — which asserts the
    /// action did not happen — or `indeterminate`, and only the backend knows
    /// whether the request may have been delivered before things went wrong.
    /// Reading it off a code would be reading an identity into a number: the same
    /// raw value can arrive from another domain, and the native backend can emit
    /// the one that would trigger it, which would silently flip a run between
    /// stopping and claiming a failure it cannot support.
    public var indeterminate: Bool = false
    /// The lane event this failure produced, when it produced one.
    ///
    /// It travels **on the error** rather than being accumulated for a later
    /// drain. `Session` is a reentrant actor, so an `await perform` followed by an
    /// `await drain` is two suspension points and a second batch finishing between
    /// them would have its events attributed to the first. Carrying the event with
    /// the thing that caused it leaves no gap between producing and taking.
    public var lane: LaneEvent?

    public enum Code: String, Codable, Sendable {
        case agentUnavailable          // socket not answering; agent not installed or not running
        case permissionAccessibility   // AX grant missing
        case permissionScreenRecording // SCK grant missing
        case permissionAutomation      // Apple Events grant missing for a specific target
        case appNotFound
        case windowNotFound
        case nodeNotFound              // stable id no longer resolves
        case nodeStale                 // resolved but the element has been invalidated
        case actionUnsupported         // AX reported the action is not available on this element
        case actionFailed
        case settleTimeout
        case captureFailed
        case captureStale              // a frame came back, but not a trustworthy one
        case reflectorUnavailable      // owned-app introspection asked for where none is embedded
        case secureInputActive         // synthetic-event mode blocked by Secure Event Input
        case policyDenied              // the app policy gate refused this actuation (blocked or needs a token)
        case haltedByPerson            // a person stopped or held the run from the run HUD — not a fault
        case queueBusy                 // another session held the lane and this run never started — nothing actuated
        // Delegated actuation. Every one of these is a refusal rather than a
        // guess: a delegated step that cannot be addressed with confidence is
        // stopped, because acting on whatever moved into place is how a run
        // corrupts the thing it was meant to verify.
        case targetMoved               // re-resolved to an element with a different identity
        case targetUnresolved          // the backend cannot see an element Proctor can
        case targetAmbiguous           // several candidates matched, or the backend's view was truncated
        case backendUnavailable        // the actuation backend could not be reached, or died mid-step
        case backendUnsupported        // version, signature or vocabulary outside what this build supports
        case actionNoOp                // the backend suspected a no-op and the post-state agrees nothing changed
        /// The backend stopped answering mid-step, so whether the action landed
        /// cannot be established from here. Distinct from `actionFailed`, which
        /// asserts the action did not happen — a claim only a caller that
        /// performed the action itself is entitled to make.
        case actionIndeterminate
        case invalidArguments
        case notImplemented
        case internalError
    }

    public init(code: Code, message: String, remedy: String? = nil, detail: JSONValue? = nil,
                indeterminate: Bool = false, lane: LaneEvent? = nil) {
        self.code = code; self.message = message; self.remedy = remedy; self.detail = detail
        self.indeterminate = indeterminate; self.lane = lane
    }
}

// MARK: - Identity

/// A handle to an attached application. Attachment is stateful: it warms the
/// AX tree, sets AXManualAccessibility where the app needs it, starts observers
/// and begins retaining element refs. A retained ref keeps working when its
/// window moves to another Space; a fresh enumeration will not find it.
public struct AppHandle: Codable, Sendable, Hashable {
    public var id: String            // "app:<pid>:<epoch>" — epoch changes if the app relaunches
    public var pid: Int32
    public var bundleId: String?
    public var name: String
    public init(id: String, pid: Int32, bundleId: String?, name: String) {
        self.id = id; self.pid = pid; self.bundleId = bundleId; self.name = name
    }
}

public struct WindowHandle: Codable, Sendable, Hashable {
    public var id: String            // "win:<appEpoch>:<ordinal>" — stable while the window lives
    public var app: String           // AppHandle.id
    public var title: String?
    public var frame: Rect
    public var isMain: Bool
    public var isMinimized: Bool
    public var isOnActiveSpace: Bool
    /// CoreGraphics window number, when one could be correlated. Capture needs it;
    /// AX does not always expose it, so it is optional and its absence is reported
    /// rather than guessed.
    public var cgWindowID: UInt32?
    public init(id: String, app: String, title: String?, frame: Rect, isMain: Bool,
                isMinimized: Bool, isOnActiveSpace: Bool, cgWindowID: UInt32?) {
        self.id = id; self.app = app; self.title = title; self.frame = frame
        self.isMain = isMain; self.isMinimized = isMinimized
        self.isOnActiveSpace = isOnActiveSpace; self.cgWindowID = cgWindowID
    }
}

public struct Rect: Codable, Sendable, Hashable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

// MARK: - The accessibility tree

/// How the tree was obtained, because for Chromium/Electron apps it is negotiated
/// state rather than a passive read. Setting AXManualAccessibility is detectable
/// by the target and changes its performance — an observer effect that any test
/// methodology built on this data has to disclose.
public struct TreeProvenance: Codable, Sendable {
    public var manualAccessibilityApplied: Bool
    public var enhancedUserInterfaceApplied: Bool
    public var warmupWalks: Int              // how many walks it took before the tree was non-empty
    public var truncatedAtDepth: Int?
    public var truncatedAtCount: Int?
    public var unsupportedAttributes: [String]
    public var elapsedMs: Int
    public init(manualAccessibilityApplied: Bool = false,
                enhancedUserInterfaceApplied: Bool = false,
                warmupWalks: Int = 1, truncatedAtDepth: Int? = nil,
                truncatedAtCount: Int? = nil, unsupportedAttributes: [String] = [],
                elapsedMs: Int = 0) {
        self.manualAccessibilityApplied = manualAccessibilityApplied
        self.enhancedUserInterfaceApplied = enhancedUserInterfaceApplied
        self.warmupWalks = warmupWalks
        self.truncatedAtDepth = truncatedAtDepth
        self.truncatedAtCount = truncatedAtCount
        self.unsupportedAttributes = unsupportedAttributes
        self.elapsedMs = elapsedMs
    }
}

public struct AXNode: Codable, Sendable {
    public var id: String            // stable within a session; survives re-walks
    public var role: String
    public var subrole: String?
    public var roleDescription: String?
    public var title: String?
    public var label: String?        // AXDescription
    public var value: JSONValue?
    public var help: String?
    public var identifier: String?   // AXIdentifier — the accessibilityIdentifier a developer set
    public var frame: Rect?
    public var enabled: Bool?
    public var focused: Bool?
    public var selected: Bool?
    public var actions: [String]
    public var writableAttributes: [String]
    public var children: [AXNode]?
    public var childCount: Int

    public init(id: String, role: String, subrole: String? = nil, roleDescription: String? = nil,
                title: String? = nil, label: String? = nil, value: JSONValue? = nil,
                help: String? = nil, identifier: String? = nil, frame: Rect? = nil,
                enabled: Bool? = nil, focused: Bool? = nil, selected: Bool? = nil,
                actions: [String] = [], writableAttributes: [String] = [],
                children: [AXNode]? = nil, childCount: Int = 0) {
        self.id = id; self.role = role; self.subrole = subrole
        self.roleDescription = roleDescription; self.title = title; self.label = label
        self.value = value; self.help = help; self.identifier = identifier; self.frame = frame
        self.enabled = enabled; self.focused = focused; self.selected = selected
        self.actions = actions; self.writableAttributes = writableAttributes
        self.children = children; self.childCount = childCount
    }
}

public struct Snapshot: Codable, Sendable {
    public var window: String        // WindowHandle.id
    public var revision: Int         // monotonic per window; the basis of since_revision diffs
    public var root: AXNode?
    public var diff: SnapshotDiff?   // present instead of root when since_revision was supplied
    public var provenance: TreeProvenance
    public var stateHash: String     // canonical hash of the normalised tree
    /// Present when this window is a browser showing a page. The page belongs to
    /// Obscura; the native chrome around it does not. See BrowserTarget.
    public var browser: BrowserHandoff?
    public init(window: String, revision: Int, root: AXNode?, diff: SnapshotDiff?,
                provenance: TreeProvenance, stateHash: String,
                browser: BrowserHandoff? = nil) {
        self.window = window; self.revision = revision; self.root = root
        self.diff = diff; self.provenance = provenance; self.stateHash = stateHash
        self.browser = browser
    }
}

public struct SnapshotDiff: Codable, Sendable {
    public var fromRevision: Int
    public var added: [AXNode]
    public var removed: [String]
    public var changed: [NodeChange]
    public var unchangedCount: Int
    public init(fromRevision: Int, added: [AXNode] = [], removed: [String] = [],
                changed: [NodeChange] = [], unchangedCount: Int = 0) {
        self.fromRevision = fromRevision; self.added = added
        self.removed = removed; self.changed = changed; self.unchangedCount = unchangedCount
    }
}

public struct NodeChange: Codable, Sendable {
    public var id: String
    public var fields: [String: FieldDelta]
    public init(id: String, fields: [String: FieldDelta]) { self.id = id; self.fields = fields }
}

public struct FieldDelta: Codable, Sendable {
    public var before: JSONValue?
    public var after: JSONValue?
    public init(before: JSONValue?, after: JSONValue?) { self.before = before; self.after = after }
}

// MARK: - Capture

/// A frame with no freshness metadata is indistinguishable from a correct one.
/// Off-screen windows in particular may emit complete frames only when the
/// mouse moves on their display, so every capture states what it actually got.
public struct CaptureResult: Codable, Sendable {
    public var window: String
    public var path: String              // PNG on disk; bytes are never returned inline
    public var width: Int
    public var height: Int
    public var scale: Double
    public var status: FrameStatus
    public var contentRect: Rect?
    public var dirtyRectCount: Int
    public var dirtyArea: Double         // fraction of the frame, 0..1
    public var capturedAt: Double        // seconds since epoch
    public var framesWaited: Int
    public var trustworthy: Bool         // .complete plus a real contentRect
    public var caveat: String?           // why not, when trustworthy is false
    public var tileHashes: [String]?     // for determinism comparison, when requested
    /// Present only when set-of-marks annotation was requested. Nil keeps the
    /// un-annotated result byte-identical to what it has always been, so the
    /// freshness metadata above is unchanged whether or not marks were drawn.
    public var annotation: MarkAnnotation?
    /// Present only when vision normalisation was requested. Nil keeps a raw
    /// capture byte-identical to what it has always been. When set, the PNG at
    /// `path` and the `width`/`height`/`scale` above describe the normalised
    /// frame, and this block carries the native dimensions and the exact factor
    /// needed to map a model's coordinates back onto native geometry.
    public var normalization: CaptureNormalization?
    /// Present only for a `proctor_zoom` crop. Nil keeps an ordinary capture
    /// byte-identical; when set, every field above still describes the frame the
    /// crop was cut from, because a crop is a window of a real capture and inherits
    /// its freshness rather than inventing its own.
    public var crop: CropRegion?
    /// Present only when a step's target point was composited onto a per-step
    /// capture (proctor_act / proctor_flow replay with pointerMarks). Nil keeps a
    /// plain capture byte-identical. When set, the un-marked PNG stays at `path`
    /// and the marked sibling is at `pointer.annotatedPath`, so both remain
    /// available. It marks where the step acted, not a live cursor.
    public var pointer: PointerOverlay?

    public init(window: String, path: String, width: Int, height: Int, scale: Double,
                status: FrameStatus, contentRect: Rect?, dirtyRectCount: Int, dirtyArea: Double,
                capturedAt: Double, framesWaited: Int, trustworthy: Bool,
                caveat: String? = nil, tileHashes: [String]? = nil,
                annotation: MarkAnnotation? = nil,
                normalization: CaptureNormalization? = nil, crop: CropRegion? = nil,
                pointer: PointerOverlay? = nil) {
        self.window = window; self.path = path; self.width = width; self.height = height
        self.scale = scale; self.status = status; self.contentRect = contentRect
        self.dirtyRectCount = dirtyRectCount; self.dirtyArea = dirtyArea
        self.capturedAt = capturedAt; self.framesWaited = framesWaited
        self.trustworthy = trustworthy; self.caveat = caveat; self.tileHashes = tileHashes
        self.annotation = annotation; self.normalization = normalization; self.crop = crop
        self.pointer = pointer
    }
}

/// A marker composited onto a per-step capture at the point the step acted on.
/// The un-marked PNG stays at `CaptureResult.path`; the marked one is written
/// alongside at `annotatedPath`. It is a pixel-plane annotation of the intended
/// target — where the step acted — not a picture of a live cursor: Proctor drives
/// through AX / Apple Events and does not move the system pointer.
public struct PointerOverlay: Codable, Sendable, Equatable {
    public var annotatedPath: String    // the marked PNG on disk; bytes are never returned inline
    public var pixelX: Double           // marker position in frame pixels
    public var pixelY: Double
    public var source: String           // "point" (explicit [x,y]) or "element" (acted node's centre)
    public var node: String?            // the AX node id acted on, when the target was an element
    public var onFrame: Bool            // false when the target fell outside the frame and was edge-clamped
    public init(annotatedPath: String, pixelX: Double, pixelY: Double,
                source: String, node: String?, onFrame: Bool) {
        self.annotatedPath = annotatedPath; self.pixelX = pixelX; self.pixelY = pixelY
        self.source = source; self.node = node; self.onFrame = onFrame
    }
}

/// What vision normalisation did to a capture. Reported whenever normalisation
/// was requested — including when the frame was already within the ceilings, so
/// a caller who asked always learns the factor (`scale == 1` then, not a missing
/// field). `scale` is the exact `out/in` factor a caller inverts to place a
/// model coordinate back in native space: `native = normalised / scale`.
public struct CaptureNormalization: Codable, Sendable, Equatable {
    public var scale: Double            // out/in, ≤ 1; 1 when nothing was scaled
    public var applied: Bool            // whether the frame actually needed shrinking
    public var originalWidth: Int       // native pixel width, before normalisation
    public var originalHeight: Int      // native pixel height, before normalisation
    public var width: Int               // normalised pixel width (== CaptureResult.width)
    public var height: Int              // normalised pixel height (== CaptureResult.height)
    public var maxLongEdge: Int         // the long-edge ceiling enforced
    public var maxPixels: Int           // the pixel-count ceiling enforced
    /// Which tier those ceilings came from: `targeting`, `verify` or `detail`.
    /// Nil when the caller named its own pixel ceiling, because then no tier
    /// describes what was enforced and printing one would be a label rather than
    /// a fact.
    public var purpose: String?
    /// Roughly what this frame costs a vision model, on Anthropic's published
    /// approximation of `width × height / 750`.
    ///
    /// Reported so the cost of a capture is visible where the capture is, rather
    /// than being something a reader has to derive from two dimensions. An
    /// estimate for one model family and never used to decide anything — the
    /// other two tokenise differently, and Gemini in particular charges by
    /// 768-pixel tiles, so it steps rather than scales.
    public var estimatedVisionTokens: Int?
    public init(scale: Double, applied: Bool, originalWidth: Int, originalHeight: Int,
                width: Int, height: Int, maxLongEdge: Int, maxPixels: Int,
                purpose: String? = nil, estimatedVisionTokens: Int? = nil) {
        self.scale = scale; self.applied = applied
        self.originalWidth = originalWidth; self.originalHeight = originalHeight
        self.width = width; self.height = height
        self.maxLongEdge = maxLongEdge; self.maxPixels = maxPixels
        self.purpose = purpose; self.estimatedVisionTokens = estimatedVisionTokens
    }
}

/// The region a `proctor_zoom` crop cut from a full-window capture. `pixelRect` is
/// what was actually cut, in frame pixels; `requestedRegion` is the caller's ask in
/// window points (after padding); `fullPath` is the un-cropped capture it came from,
/// so the whole window remains available alongside the zoomed detail.
public struct CropRegion: Codable, Sendable, Equatable {
    public var source: String            // "region" (a rect) or "element" (a resolved node)
    public var node: String?             // element mode: the AX node id the crop framed
    public var requestedRegion: Rect     // window points, top-left origin, padding applied
    public var pixelRect: Rect           // frame pixels actually cut, clamped and integer-aligned
    public var clamped: Bool             // the region reached past the frame and was trimmed
    public var padding: Double           // context points added on every side, 0 when none
    public var fullPath: String          // the un-cropped full-window PNG on disk
    public init(source: String, node: String? = nil, requestedRegion: Rect, pixelRect: Rect,
                clamped: Bool, padding: Double, fullPath: String) {
        self.source = source; self.node = node; self.requestedRegion = requestedRegion
        self.pixelRect = pixelRect; self.clamped = clamped; self.padding = padding
        self.fullPath = fullPath
    }
}

public enum FrameStatus: String, Codable, Sendable {
    case complete, idle, blank, suspended, stopped, unknown
}

// MARK: - Set-of-marks annotation

/// One numbered mark burned into an annotated capture. The number is what a
/// vision model references ("click mark 7"); `node` is the accessibility id that
/// number resolves to, so grounding by mark maps back to a real element.
public struct Mark: Codable, Sendable, Equatable {
    public var id: Int               // the number drawn into the pixels
    public var node: String          // AX node id this mark labels
    public var role: String
    public var label: String?        // title/label/identifier, for a human reading the map
    public var frame: Rect           // the element's frame in screen points, as AX reported it
    public var pixelRect: Rect       // where the box was drawn, in frame pixels, clamped to the image
    public init(id: Int, node: String, role: String, label: String?,
                frame: Rect, pixelRect: Rect) {
        self.id = id; self.node = node; self.role = role; self.label = label
        self.frame = frame; self.pixelRect = pixelRect
    }
}

/// Reference grid lines drawn over a capture, positions in frame pixels. A caller
/// reads a coordinate off a line as `position / scale` points from the window's
/// top-left corner.
public struct GridOverlay: Codable, Sendable, Equatable {
    public var spacingPoints: Double
    public var scale: Double
    public var verticals: [Double]      // x positions in frame pixels
    public var horizontals: [Double]    // y positions in frame pixels
    public init(spacingPoints: Double, scale: Double,
                verticals: [Double], horizontals: [Double]) {
        self.spacingPoints = spacingPoints; self.scale = scale
        self.verticals = verticals; self.horizontals = horizontals
    }
}

/// The annotation added to a capture on request. The un-annotated PNG stays at
/// `CaptureResult.path`; the marked one is written alongside it, so both the
/// grounding artifact and the original pixels remain available.
public struct MarkAnnotation: Codable, Sendable {
    public var annotatedPath: String    // the marked PNG on disk; bytes are never returned inline
    public var marks: [Mark]
    public var grid: GridOverlay?
    public var elementsConsidered: Int  // markable candidates handed in before culling
    public var markedCount: Int
    public var truncated: Bool          // more visible candidates than the mark cap allowed
    public init(annotatedPath: String, marks: [Mark], grid: GridOverlay?,
                elementsConsidered: Int, markedCount: Int, truncated: Bool) {
        self.annotatedPath = annotatedPath; self.marks = marks; self.grid = grid
        self.elementsConsidered = elementsConsidered
        self.markedCount = markedCount; self.truncated = truncated
    }
}

// MARK: - Settle

/// Settling is a conjunction, never a sleep. Each signal is ranked by how
/// honest it is about the app actually being done, and the result says which
/// ones fired so a flaky test can be diagnosed rather than re-run.
public struct SettleReport: Codable, Sendable {
    public var settled: Bool
    public var elapsedMs: Int
    public var reason: Reason
    public var quietFrames: Int
    public var lastDirtyArea: Double
    public var axNotificationsSeen: Int
    public var axQuietMs: Int
    public var reflectorIdle: Bool?      // nil when no reflector is embedded
    public var signals: [String]         // which conditions were actually available

    public enum Reason: String, Codable, Sendable {
        case allSignalsQuiet     // strongest
        case reflectorIdle       // app said so itself — the most honest signal available
        case axQuietOnly         // no capture signal was available
        case captureQuietOnly    // no AX notifications were available
        case timeout             // weakest; the result is reported, not hidden
    }

    public init(settled: Bool, elapsedMs: Int, reason: Reason, quietFrames: Int,
                lastDirtyArea: Double, axNotificationsSeen: Int, axQuietMs: Int,
                reflectorIdle: Bool?, signals: [String]) {
        self.settled = settled; self.elapsedMs = elapsedMs; self.reason = reason
        self.quietFrames = quietFrames; self.lastDirtyArea = lastDirtyArea
        self.axNotificationsSeen = axNotificationsSeen; self.axQuietMs = axQuietMs
        self.reflectorIdle = reflectorIdle; self.signals = signals
    }
}

// MARK: - Actuation

/// The plane an action travelled through. Process-directed actuation reaches
/// non-frontmost, occluded and other-Space windows without stealing focus;
/// synthetic events enter the single WindowServer stream and need the foreground.
/// Which one ran changes what the result proves, so it is always reported.
public enum ActuationPlane: String, Codable, Sendable {
    case declared        // AppleScript sdef / shortcuts CLI — the app's own contract
    case accessibility   // AXUIElementPerformAction / SetAttributeValue
    case appleEvents
    case syntheticEvent  // CGEventPost — foreground session only, flagged as a different mode
    /// An injected event delivered to one process rather than to the shared
    /// WindowServer stream. Background-safe, and not the accessibility plane.
    ///
    /// Proctor's own actuator cannot produce this: it has exactly two ways to
    /// move a pointer, and one of them is the shared stream. A delegated backend
    /// can, and neither existing word is true of it — `.accessibility` would lie
    /// about the mechanism, `.syntheticEvent` would report a run as having taken
    /// the machine when it never did. `ForegroundReport` does not count it.
    case routedEvent
    /// The step was performed and this build does not recognise the delivery
    /// mode the backend reported.
    ///
    /// One value rather than two for "a mode newer than this build" and "a
    /// response this build could not decode", because the consequence is
    /// identical: nothing here can say how the machine was driven. The backend's
    /// own word survives verbatim in `Actuation.reportedMode`, so the two stay
    /// distinguishable to a reader without splitting the enum. A run holding one
    /// of these is never described as background-safe.
    case unknown
}

/// Which actuation backend performed a step.
///
/// On every step result rather than only on the run, because a determinism score
/// computed across runs that used different actuation paths is measuring the
/// paths.
public enum ActuationBackendID: String, Codable, Sendable {
    case native
    case cua
}

/// Which operating system a machine runs. Named rather than inferred from the
/// provider, because one provider serves several: `prlctl` runs Windows and
/// Linux guests, and `lume` runs macOS and Linux ones.
public enum MachinePlatform: String, Codable, Sendable {
    case macos
    case linux
    case windows
}

/// HOW MUCH OF PROCTOR'S OBSERVATION a machine actually supports.
///
/// The one concept that stops a Linux target passing itself off as a macOS one.
/// Proctor's instruments are macOS APIs: `SCFrameStatus` on a capture, an
/// `AXUIElement` tree, and the tri-observer check that reports where the tree,
/// the geometry and the pixels disagree. In a guest running a full Proctor those
/// all exist. On a delegated lane none of them do, and what arrives instead is a
/// screenshot with no completeness signal and whatever the driver says it did.
///
/// A tier is not a quality rating and does not scale a score. It says which
/// assertions can be evaluated at all, and the ones that cannot are reported
/// **skipped with a reason**, never passed. That is the skill's existing rule —
/// an assertion that could not be evaluated is not an assertion that passed — and
/// this is the same rule applied to a whole substrate rather than to one call.
public enum WitnessTier: String, Codable, Sendable {
    /// A macOS machine running a full Proctor: frame status, the accessibility
    /// tree, the tri-observer check, fidelity and determinism.
    case native
    /// Actuation and screenshots, through another tool. No frame status, no
    /// accessibility tree, and therefore no third channel to check the other two
    /// against.
    case delegated
}

extension WitnessTier {

    /// The one assertion kind that reads pixels rather than the accessibility
    /// tree, and therefore the only one a delegated machine can attempt.
    ///
    /// A list of what survives rather than a list of what is refused, because the
    /// two fail in opposite directions: a kind added later and forgotten is
    /// refused by this shape, and silently permitted by the other. A refusal on a
    /// kind that would have worked is visible and reported; a permission on one
    /// that cannot be evaluated is a pass nobody measured.
    public static let pixelKinds: Set<String> = ["regionMatches"]

    /// Why this machine cannot evaluate an assertion kind, or nil when it can.
    public func cannotEvaluate(_ kind: String) -> String? {
        guard self == .delegated else { return nil }
        guard !Self.pixelKinds.contains(kind) else { return nil }
        return "\(kind) reads the accessibility tree, and this run is on a delegated "
             + "machine where there is none. Proctor's tree, geometry and frame-status "
             + "instruments are macOS APIs and do not cross into this target, so the "
             + "assertion is skipped rather than answered from weaker evidence. Run it "
             + "against a macOS machine, or assert on pixels with regionMatches."
    }

    /// What a pixel assertion on this tier is worth, or nil when there is nothing
    /// to qualify. Stated on the outcome rather than folded into it: the
    /// comparison genuinely ran, and what is missing is the guarantee that the
    /// frame it ran against was complete.
    public var pixelCaveat: String? {
        guard self == .delegated else { return nil }
        return "This comparison ran against a frame carrying no completeness signal. "
             + "Apple defines six SCFrameStatus values and makes checking them a "
             + "precondition of trusting a frame; a delegated capture reports none of "
             + "them, so a pass here does not exclude a partial or stale frame."
    }
}

///
/// Proctor has always had exactly one answer to this and therefore never said
/// it: every step landed on the Mac the agent was running on. A guest changes
/// that, and the change is not cosmetic. A result from a guest is about a
/// different OS build, a different display arrangement, a different set of
/// installed applications and none of the person's own data — so a reader who
/// assumes the host is reading a true statement about the wrong computer.
///
/// THIS LANDS BEFORE ANY ROUTING DOES, deliberately. PRO-0051 rejected automatic
/// fallback on the grounds that it "hands back a verdict that looks fine and
/// measures the plumbing", and routing a batch to a guest is the same move
/// wearing better clothes. It is safe only once every result, every audit entry
/// and the panel say which machine answered, so that is built first and the
/// routing is built on top of it.
///
/// Optional in the TYPE and always set on the wire, for the same two separate
/// reasons `backend` is: optional so a record written before this existed still
/// decodes, always set because `SessionAct` passes the session's machine
/// unconditionally. No default, because a default would let a construction site
/// that forgot to say encode `host` under a run that happened in a guest, and a
/// record asserting the wrong machine is worse than one that does not say.
public struct Machine: Codable, Sendable, Equatable {

    public enum Kind: String, Codable, Sendable {
        /// The Mac this agent is running on. Everything Proctor did before guests
        /// existed.
        case host
        /// A virtual machine, reached through a provider.
        case guest
    }

    public var kind: Kind
    /// The guest's name as its own provider knows it, so the name in a report is
    /// the name you can type at `lume` or `prlctl`. Nil for the host.
    public var name: String?
    /// Which adapter reached it — `lume`, `prlctl`. Nil for the host. Recorded
    /// because two providers can hold guests of the same name and a bare name
    /// would not identify one.
    public var provider: String?
    public var platform: MachinePlatform?
    /// How much of Proctor's observation this machine supports.
    ///
    /// NO DEFAULT, deliberately, and it is the one parameter here that has none.
    /// A default of `.native` would let a construction site that forgot to say
    /// describe a Linux guest as carrying a frame-status channel and an
    /// accessibility tree it does not have, and every assertion this gate exists
    /// to skip would then be evaluated against nothing and pass. The same
    /// argument `ActuationBackendID` makes about lanes: absent is detectable,
    /// wrong is not.
    public var tier: WitnessTier

    public init(kind: Kind, name: String? = nil, provider: String? = nil,
                platform: MachinePlatform? = nil, tier: WitnessTier) {
        self.kind = kind
        self.name = name
        self.provider = provider
        self.platform = platform
        self.tier = tier
    }

    /// The Mac the agent runs on. `platform` is stated rather than left nil: the
    /// host is always macOS, and a reader comparing a host result with a guest
    /// one should not have to know that to compare them.
    public static let host = Machine(kind: .host, platform: .macos, tier: .native)

    public var isGuest: Bool { kind == .guest }

    /// The trail's short form: `host`, or `guest:sequoia-seed`. Deliberately not
    /// `line` — the trail is grepped and diffed, so it wants one stable token per
    /// machine rather than a sentence whose clauses come and go with what was
    /// known at the time.
    public var auditToken: String {
        guard kind == .guest else { return "host" }
        return "guest:\(name ?? "unnamed")"
    }

    /// One phrase, for the panel and for any prose surface. Degrades by dropping
    /// clauses rather than printing an absence, exactly as `HoldAttribution.line`
    /// does: a guest whose provider is unknown says less, never "nil".
    public var line: String {
        guard kind == .guest else { return "this Mac" }
        var out = name ?? "a guest"
        if let platform { out += " · \(platform.rawValue)" }
        if let provider { out += " · \(provider)" }
        return out
    }
}

/// Whether a backend can perform a kind of step without the application in front.
///
/// This exists because the question is a property of the BACKEND, not of the
/// step. Proctor's native actuator can express a click only as CGEventPost into
/// the shared stream, so `.click` needs the foreground — but that is a fact
/// about Proctor, not about clicking. A delegated backend that routes an event
/// to one process answers differently, and a refusal built on a static list of
/// kinds would make its background clicks unreachable.
public enum BackgroundCapability: String, Codable, Sendable {
    /// Only ever the shared event stream: refuse when the caller asked to stay back.
    case never
    /// Decided at the element, so it is not knowable until the step is reached.
    case maybe
    /// Always reachable without the foreground.
    case yes
}

/// What a backend reports about whether its action landed.
///
/// A call that returns without an error is not evidence that anything happened:
/// a minimized window's keyboard commit reports success without committing, and
/// a canvas surface silently no-ops. Folding a no-error return straight into
/// `ok: true` reproduces the defect this repo exists to detect, so the claim is
/// carried and crossed with Proctor's own post-state hash.
public enum ActuationEffect: String, Codable, Sendable {
    case confirmed
    case unverifiable
    case suspectedNoOp
}

/// *How* a step travelled, where the plane says only *which side* it travelled.
///
/// The plane is the fact that matters to a caller deciding whether a run was
/// background-safe, and it stays coarse for that reason: `ForegroundReport`
/// counts `.syntheticEvent` on it, so splitting the plane would change what
/// "this run took the foreground" measures. But two steps can both report
/// `.accessibility` and have got there by different means — a value write, a
/// write into the selection when the value refused, an action, a scroll bar —
/// and the difference is exactly what "we found another route rather than
/// taking the foreground" looks like from outside.
public enum ActuationRoute: String, Codable, Sendable {
    case action          // AXUIElementPerformAction
    case valueWrite      // AXValue set
    case selectedText    // AXSelectedText set over the whole value
    case scrollBar       // a scroll bar's AXValue set
    case scrollAction    // AXScrollDownByPage and friends
    case eventStream     // CGEventPost
    case appleEvent
    case declared
}

/// Something that happened to the actuation lane itself, rather than to a step.
///
/// A delegated lane is a live thing with its own failure modes — it opens, it can
/// be refused, its build can move under it, it can die or stop answering — and
/// none of those are properties of the action that was in flight when they
/// happened. They are recorded as their own audit rows for that reason.
///
/// **These travel on the value returned by the call that produced them**, never
/// through a shared accumulator drained afterwards. `Session` is a reentrant
/// actor: `await perform` and a later `await drain` are two suspension points, so
/// a second batch completing between them would have its events attributed to the
/// first. Carrying them back with the result leaves no gap between producing and
/// taking.
public struct LaneEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        /// The lane was established and this is what it is.
        case opened
        /// Preflight refused it, naming the stage.
        case refused
        /// An unpinned lane's build moved between batches.
        case identityChanged
        /// The backend stopped answering mid-call.
        case died
        /// A call passed its deadline and the lane was closed.
        case timedOut
    }

    public var kind: Kind
    public var backend: ActuationBackendID
    public var laneId: String
    /// Proctor's own sentence. Never the driver's message: an application's text
    /// reaches that, and the trail does not widen for a lane event any more than
    /// it does for a step.
    public var reason: String

    public init(kind: Kind, backend: ActuationBackendID, laneId: String, reason: String) {
        self.kind = kind; self.backend = backend; self.laneId = laneId; self.reason = reason
    }

    /// How the row reads. A lane that died or timed out leaves whatever was in
    /// flight unknowable, so those two carry the same word the step does.
    public var outcome: String {
        switch kind {
        case .opened:                       return AuditRecord.Outcome.ok
        case .refused, .identityChanged:    return AuditRecord.Outcome.refused
        case .died, .timedOut:              return AuditRecord.Outcome.indeterminate
        }
    }
}

/// What one actuation did: the plane it travelled and the route it took there.
public struct Actuation: Sendable, Equatable {
    public var plane: ActuationPlane
    public var route: ActuationRoute?
    /// Which backend performed it. Defaulted, so every existing construction —
    /// all of them native — is unchanged.
    public var backend: ActuationBackendID
    /// The delegated backend's own word for how it delivered the step, verbatim.
    /// Carried so a reader can audit the mapping in `ActuationPlane` rather than
    /// trust it, and so an `.unknown` plane still says what it saw.
    public var reportedMode: String?
    /// What the backend claims about the action landing. Nil for the native
    /// backend, which has no equivalent concept: it judges a write by reading it
    /// back rather than by reporting a confidence.
    public var effect: ActuationEffect?
    /// The element handle went stale and was re-resolved before the step ran. A
    /// step whose target was moving is a determinism signal, not an
    /// implementation detail.
    public var retriedOnStale: Bool
    /// The backend escalated to the foreground for a step that asked to stay in
    /// the background. The machine was taken without warning, which the guards
    /// could not arm for, because a delegated post cannot be declared in advance
    /// by the process that did not make it.
    public var unrequestedForeground: Bool
    /// Round trip to the backend, in milliseconds. Its own field rather than
    /// folded into the step's elapsed time, which already includes settle.
    public var transportMs: Int?
    /// Which lane instance performed it, tying the step's row to the lane's own.
    public var laneId: String?
    /// Lane events this call produced, carried back rather than accumulated. See
    /// `LaneEvent` for why the drain-later shape is wrong on a reentrant actor.
    public var laneEvents: [LaneEvent]

    public init(_ plane: ActuationPlane, _ route: ActuationRoute? = nil,
                backend: ActuationBackendID = .native, reportedMode: String? = nil,
                effect: ActuationEffect? = nil, retriedOnStale: Bool = false,
                unrequestedForeground: Bool = false, transportMs: Int? = nil,
                laneId: String? = nil, laneEvents: [LaneEvent] = []) {
        self.plane = plane
        self.route = route
        self.backend = backend
        self.reportedMode = reportedMode
        self.effect = effect
        self.retriedOnStale = retriedOnStale
        self.unrequestedForeground = unrequestedForeground
        self.transportMs = transportMs
        self.laneId = laneId
        self.laneEvents = laneEvents
    }
}

public struct ActionStep: Codable, Sendable {
    public var kind: Kind
    public var node: String?
    public var value: JSONValue?
    public var menuPath: [String]?
    public var text: String?
    public var key: String?
    public var modifiers: [String]?
    public var delta: [Double]?
    public var point: [Double]?
    /// A path of [x, y] points in window coordinates, for dragPath. A start and
    /// a delta cannot describe a path, so a gesture that follows a shape says so
    /// here; absent, a drag runs from `point` to `point + delta`.
    public var path: [[Double]]?
    /// How long the whole gesture should take. Posting a gesture as fast as the
    /// loop runs outruns what many applications process, so the pacing is part
    /// of the step rather than a constant.
    public var durationMs: Int?
    public var settle: SettlePolicy?
    public var label: String?

    /// CaseIterable so a new kind cannot be added without the wording table in
    /// StepDescription growing a row for it — the test walks every case.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case press, setValue, focus, menu, type, key, scroll, increment, decrement
        case pick, confirm, cancel, raise, close, resize, move
        case dragPath, hover, click        // synthetic-event kinds; foreground mode only
        case shortcut                      // declared contract via the shortcuts CLI
        case appleScript
        case waitFor
    }

    public init(kind: Kind, node: String? = nil, value: JSONValue? = nil,
                menuPath: [String]? = nil, text: String? = nil, key: String? = nil,
                modifiers: [String]? = nil, delta: [Double]? = nil, point: [Double]? = nil,
                path: [[Double]]? = nil, durationMs: Int? = nil,
                settle: SettlePolicy? = nil, label: String? = nil) {
        self.kind = kind; self.node = node; self.value = value; self.menuPath = menuPath
        self.text = text; self.key = key; self.modifiers = modifiers; self.delta = delta
        self.point = point; self.path = path; self.durationMs = durationMs
        self.settle = settle; self.label = label
    }
}

public struct SettlePolicy: Codable, Sendable {
    public var quietFrames: Int
    public var dirtyThreshold: Double     // fraction of frame area below which a change is noise
    public var axQuietMs: Int
    public var timeoutMs: Int
    public var requireReflectorIdle: Bool
    public static let `default` = SettlePolicy(quietFrames: 2, dirtyThreshold: 0.002,
                                               axQuietMs: 250, timeoutMs: 5000,
                                               requireReflectorIdle: false)
    public init(quietFrames: Int, dirtyThreshold: Double, axQuietMs: Int,
                timeoutMs: Int, requireReflectorIdle: Bool) {
        self.quietFrames = quietFrames; self.dirtyThreshold = dirtyThreshold
        self.axQuietMs = axQuietMs; self.timeoutMs = timeoutMs
        self.requireReflectorIdle = requireReflectorIdle
    }
}

public struct StepResult: Codable, Sendable {
    public var index: Int
    public var step: ActionStep
    public var ok: Bool
    public var plane: ActuationPlane?
    /// How it got there. Absent for a step that never ran.
    public var route: ActuationRoute?
    public var error: AgentError?
    public var settle: SettleReport?
    public var stateHash: String?
    public var diff: SnapshotDiff?
    public var elapsedMs: Int
    /// Which backend performed it — present when the step actuated, absent when
    /// it never got that far.
    ///
    /// Note what this field does NOT do, because the comment here used to imply
    /// it: a native step is **not** silent. `Actuation.backend` is `.native` by
    /// default and `carry(_:)` copies it unconditionally, so an actuated native
    /// step encodes `"backend":"native"` and always has. Absence means the step
    /// refused before anything was actuated, which is a different fact and worth
    /// keeping distinguishable.
    public var backend: ActuationBackendID?
    /// Every field below this line is optional and omitted when nil, so a step
    /// the native backend ran encodes exactly as it did before any of this
    /// existed.
    public var reportedMode: String?
    public var effect: ActuationEffect?
    public var retriedOnStale: Bool?
    public var unrequestedForeground: Bool?
    public var transportMs: Int?
    /// Which side of the browser page boundary this step's target fell on,
    /// measured at the moment the step ran — and therefore which tree its state
    /// hash was taken over.
    ///
    /// Present exactly when a browser renders the window **and** the step got as
    /// far as acting. So it is absent on every step of a native application, which
    /// is what keeps an existing result byte-identical, and absent on a step the
    /// policy gate refused before it could be classified. Among the steps that
    /// ran, absence therefore means one thing: no browser renders this window.
    /// On a browser window a step that ran always carries a value, `unclassified`
    /// included. See `HashSubject`.
    ///
    /// Set through `init`, deliberately not through `carry(_:)`: that folds facts
    /// off `Actuation`, which is what the backend reported about performing the
    /// step, and this is what Proctor observed about where the step pointed.
    public var hashSubject: HashSubject?

    public init(index: Int, step: ActionStep, ok: Bool, plane: ActuationPlane?,
                error: AgentError?, settle: SettleReport?, stateHash: String?,
                diff: SnapshotDiff?, elapsedMs: Int, route: ActuationRoute? = nil,
                backend: ActuationBackendID? = nil, reportedMode: String? = nil,
                effect: ActuationEffect? = nil, retriedOnStale: Bool? = nil,
                unrequestedForeground: Bool? = nil, transportMs: Int? = nil,
                hashSubject: HashSubject? = nil) {
        self.index = index; self.step = step; self.ok = ok; self.plane = plane
        self.error = error; self.settle = settle; self.stateHash = stateHash
        self.diff = diff; self.elapsedMs = elapsedMs; self.route = route
        self.backend = backend; self.reportedMode = reportedMode
        self.effect = effect; self.retriedOnStale = retriedOnStale
        self.unrequestedForeground = unrequestedForeground
        self.transportMs = transportMs
        self.hashSubject = hashSubject
    }

    /// The delegated facts a finished actuation carries, folded onto the result.
    ///
    /// One place rather than six assignments at the call site, so a new fact on
    /// `Actuation` cannot reach the wire through one path and not another. The
    /// booleans are written only when true: a native step encodes no new keys
    /// at all, which is what keeps the existing golden output byte-identical.
    public mutating func carry(_ actuation: Actuation) {
        backend = actuation.backend
        reportedMode = actuation.reportedMode
        effect = actuation.effect
        retriedOnStale = actuation.retriedOnStale ? true : nil
        unrequestedForeground = actuation.unrequestedForeground ? true : nil
        transportMs = actuation.transportMs
    }
}

public struct ActResult: Codable, Sendable {
    public var window: String
    public var steps: [StepResult]
    public var completed: Int
    public var failedAt: Int?
    public var finalHash: String?
    /// How much of this run needed the application in front, measured from the
    /// planes its steps actually travelled. A caller deciding whether a suite
    /// can run unattended reads this rather than re-deriving it from the step
    /// list, and a suite that cannot is a fact about the suite rather than
    /// something you find out by watching it.
    public var foreground: ForegroundReport?
    /// Every time this run was held because somebody was using the machine.
    /// Nil when it never was, so a result from a run nothing contended with
    /// encodes exactly as it did before this existed — a slow suite has a reason
    /// in a field, and a normal one carries no new noise.
    public var yields: [YieldRecord]?
    /// What this run put on the screen while it held the front, and whether it
    /// held the person's input as well. Nil when it drew nothing, so a result
    /// from a run that took nothing encodes exactly as it did before this
    /// existed.
    public var takeover: TakeoverReport?
    /// Which actuation lane drove this run.
    ///
    /// Run-level rather than only per-step, because a run whose every step
    /// refused before actuation carries no backend on any step — and that is
    /// exactly the run a reader most needs to place. PRO-0051 keeps the native
    /// planes as a deliberately selected lane, so a record that does not name
    /// its lane is a record whose determinism claim cannot be read.
    ///
    /// Optional in the TYPE and always set on the wire, and the two are separate
    /// facts. Optional so a record written before this field existed still
    /// decodes — a guarantee `absentBlockDecodes` has always pinned. Always set
    /// because `SessionAct` passes the session's backend unconditionally. There
    /// is deliberately no default: a default would let a construction site that
    /// forgot to say encode `native` under a delegated run, which is a record
    /// asserting the wrong lane. Absent reads as "this build did not say" and is
    /// detectable; wrong is neither.
    public var backend: ActuationBackendID?
    /// Which pointer annotated this run, when it was not Proctor's own.
    ///
    /// Nil means Proctor drew, which is every native run and every delegated one
    /// whose driver could be asked to stand down — so a result from before this
    /// existed encodes identically. `deferredToDriver` says Proctor stood its own
    /// pointer down because the driver could not be asked to; whether the driver
    /// then drew anything is the driver's, and not something Proctor observed, so
    /// this names what Proctor decided rather than what appeared on screen.
    public var pointerDrawnBy: String?
    /// Which machine this run happened on. See `Machine` for why it is optional
    /// in the type and always set on the wire.
    public var machine: Machine?
    public init(window: String, steps: [StepResult], completed: Int,
                failedAt: Int?, finalHash: String?, foreground: ForegroundReport? = nil,
                yields: [YieldRecord]? = nil, takeover: TakeoverReport? = nil,
                backend: ActuationBackendID?, pointerDrawnBy: String? = nil,
                machine: Machine? = nil) {
        self.window = window; self.steps = steps; self.completed = completed
        self.failedAt = failedAt; self.finalHash = finalHash
        self.foreground = foreground
        self.yields = yields
        self.takeover = takeover
        self.backend = backend
        self.pointerDrawnBy = pointerDrawnBy
        self.machine = machine
    }
}

// MARK: - Determinism

public struct StabilityReport: Codable, Sendable {
    public var flow: String
    public var runs: Int
    public var stepCount: Int
    public var firstDivergence: Int?          // step index where runs first disagreed
    public var stepInstability: [Double]      // 0..1 per step
    public var deterministic: Bool
    public var divergenceDetail: [String: [String]]?   // step index -> distinct hashes seen
    public var notes: [String]
    /// Present only when per-step capture was switched on for the run. Nil keeps
    /// a default determinism run byte-identical to what it has always been. Every
    /// entry names its replay and its step, so one step can be compared across
    /// replays — which is what a determinism artifact is for.
    public var captures: [StabilityCapture]?
    /// Which actuation lane every pass in this report was measured on.
    ///
    /// A determinism verdict without its actuation path is the measurement the
    /// whole instrument is supposed to prevent, stated as a conclusion: run two
    /// halves of a comparison through different actuation paths and any
    /// divergence measures the paths rather than the application. `deterministic`
    /// and `firstDivergence` are unreadable without this beside them.
    ///
    /// One value for the whole report is honest because every pass folded into it
    /// runs inside one session and `Session.actuator` is immutable, so the passes
    /// cannot disagree. Same optionality rule as `ActResult.backend`, for the same
    /// two reasons.
    public var backend: ActuationBackendID?
    /// One entry per step, by index, saying what that step's number was taken
    /// over and what it was computed from.
    ///
    /// Present when there is anything to disclose — a browser rendered the window,
    /// or some repeat withheld a hash — and nil otherwise, so an ordinary native
    /// sweep encodes exactly as it did before this existed. When present it holds
    /// one entry for every step in `0..<stepCount`, so it reads in parallel with
    /// `stepInstability`.
    public var stepBasis: [StabilityStepBasis]?
    /// Present when at least one step, in at least one repeat, was measured over
    /// a browser's render tree. Says which browser, which steps, and what that
    /// does to their numbers.
    public var pageContent: PageContentDisclosure?
    /// Which machine the sweep ran on. A determinism score is a claim about a
    /// machine as much as about a flow: the same flow scored on a quiet guest and
    /// on a Mac somebody is using are two different measurements, and a reader
    /// comparing them needs to know which is which.
    public var machine: Machine?
    public init(flow: String, runs: Int, stepCount: Int, firstDivergence: Int?,
                stepInstability: [Double], deterministic: Bool,
                divergenceDetail: [String: [String]]?, notes: [String],
                captures: [StabilityCapture]? = nil,
                backend: ActuationBackendID?,
                stepBasis: [StabilityStepBasis]? = nil,
                pageContent: PageContentDisclosure? = nil,
                machine: Machine? = nil) {
        self.flow = flow; self.runs = runs; self.stepCount = stepCount
        self.firstDivergence = firstDivergence; self.stepInstability = stepInstability
        self.deterministic = deterministic; self.divergenceDetail = divergenceDetail
        self.notes = notes; self.captures = captures
        self.backend = backend
        self.stepBasis = stepBasis; self.pageContent = pageContent
        self.machine = machine
    }
}

/// What one step's determinism number was taken over, and what it was computed
/// from. Optional throughout for the reason `ActResult.backend` is: a field that
/// is absent decodes on a record written before it existed.
public struct StabilityStepBasis: Codable, Sendable, Equatable {
    public var step: Int
    /// Every distinct subject the repeats produced for this step, in first-seen
    /// order. Absent when no browser rendered the window.
    ///
    /// **More than one value is a finding, not noise.** It means the repeats
    /// disagreed about which side of the page boundary this step fell on, so the
    /// flow took two different paths — and this step's hashes are then over two
    /// different trees, which will score it unstable. That instability belongs to
    /// the flow rather than to the application, and this list is what says so.
    public var subjects: [HashSubject]?
    /// Repeats that contributed a hash to this step's score. Read from the fold's
    /// own column count and never recomputed here, so it cannot disagree with the
    /// number beside it.
    public var samples: Int
    /// Repeats whose hash was withheld from the score because Proctor could not
    /// vouch that the step happened. Omitted when none were.
    public var withheld: Int?
    /// This step's instability.
    ///
    /// **Absent below two samples rather than reported as zero.**
    /// `Canonical.instability` returns `0.0` for a column of one hash, so a step
    /// measured once would otherwise be indistinguishable from five repeats that
    /// agreed. `StabilityReport.stepInstability` keeps the `0.0` at that index for
    /// wire compatibility; this is the surface that does not overstate it.
    public var instability: Double?

    public init(step: Int, subjects: [HashSubject]? = nil, samples: Int,
                withheld: Int? = nil, instability: Double? = nil) {
        self.step = step; self.subjects = subjects; self.samples = samples
        self.withheld = withheld; self.instability = instability
    }
}

/// What a sweep that touched a page is entitled to claim, carried once rather
/// than repeated on every step that touched it.
public struct PageContentDisclosure: Codable, Sendable, Equatable {
    public var browser: String
    public var bundleId: String
    /// The steps measured over a render tree in **at least one** repeat.
    ///
    /// A step that was page content in one repeat and browser chrome in another
    /// appears here *and* carries two `subjects`, which is what says its number is
    /// attributable to neither side. Including it errs toward disclosing, which is
    /// the direction `BrowserTarget` already states as the safe one for an
    /// advisory that never refuses anything.
    public var steps: [Int]
    /// `BrowserTarget.evidence`, verbatim — the same sentence `proctor_act` has
    /// always emitted, rather than a second wording of one fact.
    public var evidence: String

    public init(browser: String, bundleId: String, steps: [Int], evidence: String) {
        self.browser = browser; self.bundleId = bundleId
        self.steps = steps; self.evidence = evidence
    }
}

// MARK: - Tri-observer disagreement

/// Where the AX tree, the geometry/layer source and the captured pixels disagree
/// about the same instant, that delta is a finding — an unexposed control, an
/// invisible-but-focusable element, a stale frame, a ghost node, a wrong hit
/// target — rather than noise to be smoothed away.
public struct Disagreement: Codable, Sendable {
    public var kind: Kind
    public var node: String?
    public var detail: String
    public var axSays: JSONValue?
    public var layerSays: JSONValue?
    public var pixelsSay: JSONValue?
    public var severity: Severity

    public enum Kind: String, Codable, Sendable {
        case unexposedControl        // pixels show a control the AX tree has no node for
        case ghostNode               // AX node with no corresponding pixels
        case invisibleButFocusable   // focusable, zero-area or fully occluded
        case frameMismatch           // AX frame and layer geometry disagree
        case staleFrame              // capture predates the last AX change
        case hitTargetMismatch       // node frame does not contain its own hit point
        case contrastBelowThreshold
        case missingLabel
    }
    public enum Severity: String, Codable, Sendable { case info, warning, defect }

    public init(kind: Kind, node: String?, detail: String, axSays: JSONValue?,
                layerSays: JSONValue?, pixelsSay: JSONValue?, severity: Severity) {
        self.kind = kind; self.node = node; self.detail = detail; self.axSays = axSays
        self.layerSays = layerSays; self.pixelsSay = pixelsSay; self.severity = severity
    }
}

// MARK: - Health

public struct DoctorReport: Codable, Sendable {
    public var agentVersion: String
    public var protocolVersion: Int
    public var osVersion: String
    public var agentRunning: Bool
    public var socketPath: String
    public var grants: [Grant]
    public var attachedApps: [AttachedAppHealth]
    public var observersLive: Int
    public var secureEventInputActive: Bool
    public var shortcutsCLIAvailable: Bool
    /// Which machine this agent's runs land on.
    ///
    /// On the doctor because it is the first call the Proctor skill tells a model
    /// to make, and because every other answer in this report is scoped by it: the
    /// grants, the attached applications, the observers and the secure-input state
    /// all describe whichever machine answered, and a reader assuming the host
    /// would be reading true statements about the wrong computer.
    public var machine: Machine?
    /// Whether Obscura — the tool the browser handoff recommends — is on this
    /// machine. Flat and top-level, in the shape `shortcutsCLIAvailable` already
    /// uses, so it does not have to be dug out of anything.
    public var obscuraAvailable: Bool
    /// The evidence behind that answer: where it was found and everywhere it was
    /// looked for. On the wire because a reader whose own shell disagrees with
    /// Proctor can only settle it by comparing paths. **Always present.**
    public var obscura: ToolPresence?
    /// What to do about it, present **exactly when `obscuraAvailable` is false**.
    /// The same object the browser handoff carries, so there is one description of
    /// this situation rather than two — and, like that one, it carries no shell
    /// commands.
    public var obscuraUnavailable: ToolAbsence?
    /// Every tool Proctor *locates* — obscura then browser-use — present or absent,
    /// always both. This is the growth surface: a fourth tool is an entry here
    /// rather than a fourth top-level boolean. `obscuraAvailable` and `obscura`
    /// above are the grandfathered spelling of this array's first entry and must
    /// agree with it; they stay because they are already consumed and breaking them
    /// would be a protocol change for a cosmetic win.
    ///
    /// `shortcutsCLIAvailable` is not in here, on merit rather than for
    /// compatibility: `/usr/bin/shortcuts` is an OS component at a fixed absolute
    /// path, with no search list, no candidates and no companions.
    public var tools: [ToolPresence]
    /// The second browser lane: `off`, `enabled` or `unavailable`. Three states
    /// because the two gates in front of it do different jobs — the environment
    /// variable decides whether the tool may be named at all, and the binary
    /// decides whether the lane is usable. An operator who enabled a lane that is
    /// not installed sees `unavailable` rather than a silence they cannot explain.
    public var secondLane: String
    /// Which build the agent is, in parts. `agentVersion` above is this object's
    /// `descriptor` and is the grandfathered spelling — it changed what it carries
    /// rather than keeping a hardcoded `0.1.0` and hiding the truth in here, because a
    /// reader who only reads that field is the reader who was being misled.
    ///
    /// Optional so a report from an older agent still decodes against a newer shim.
    public var agentBuild: BuildIdentity?
    /// What this machine can actually do, lane by lane: the Mac's own planes,
    /// the browser lane, the iOS lane and the delegated Cua lane.
    ///
    /// Derived from the grants and the tool rows rather than reported
    /// independently, so a lane cannot claim to be ready while the thing it needs
    /// is missing. Optional so an older agent's report still decodes.
    public var lanes: [Lane]?
    /// The posture of the gate that will refuse a caller's next action, and of
    /// the trail that will record it. **Shape and posture, never rules** — no
    /// bundle id, no path, no key id, no token. See `PolicyPosture`.
    public var policy: PolicyPosture?
    /// What the eight runtime switches are actually set to in THIS agent, and
    /// where each value came from.
    ///
    /// On the wire because the status window cannot work it out. The window is
    /// launched by Finder or LaunchServices and the agent by launchd, so the
    /// window's `ProcessInfo` describes a different process's environment — and
    /// would describe it plausibly, which is worse than not knowing. The agent is
    /// the only party that can answer, so it answers.
    ///
    /// Optional so an older agent's report still decodes against a newer window,
    /// following `lanes` and `policy`.
    public var switches: [SwitchState]?
    /// Untouched by Obscura either way: `ready` means Proctor can do its own job,
    /// and Proctor drives native applications without it. A health report that
    /// failed on an advisory tool would be lying about what is broken.
    ///
    /// Untouched by every entry in `lanes` for the same reason: Proctor drives
    /// native macOS applications with no Obscura, no Xcode, no cua-driver and no
    /// Maestro.
    public var ready: Bool
    public var blockers: [String]

    /// What one lane needs, and whether this machine has it.
    public struct Lane: Codable, Sendable, Equatable {
        /// `mac`, `browser`, `ios` or `cua`.
        public var lane: String
        /// `ready`, `unavailable` or `unconfirmed`. Three states for the reason
        /// PRO-0041 gave the grants: a lane nothing has established is not the
        /// same as a lane known to be broken, and sending somebody to fix the
        /// second when they have the first is the defect that item closed.
        public var state: String
        /// Whether this lane is **confirmed** usable. Derived from `state` and
        /// fail-closed: `unconfirmed` reads false, exactly as `denied` does.
        ///
        /// Spelled `ready` rather than `available` deliberately. A tool row's
        /// `available` means "a file of that name is there", and one word meaning
        /// two things across two rows of the same report is how a consumer comes
        /// to believe a lane works because a file exists.
        public var ready: Bool
        /// The tool rows this lane depends on.
        public var requires: [String]
        /// One line per reason it is not ready.
        public var blockers: [String]
        /// A standing qualification that is not a blocker.
        public var note: String?

        public init(lane: String, state: String, requires: [String] = [],
                    blockers: [String] = [], note: String? = nil) {
            self.lane = lane; self.state = state; self.requires = requires
            self.blockers = blockers; self.note = note
            self.ready = state == "ready"
        }
    }

    /// The gate's shape and the trail's health, with nothing in it that names an
    /// application, a path or a secret.
    ///
    /// `proctor_doctor` is called before anything is established, so reporting
    /// the gate's rules here would make a health check a way to read the
    /// configuration. What a model needs before its first call is whether it is
    /// likely to be refused and whether it will be recorded, and both are
    /// answerable from posture.
    ///
    /// **This is a convention, not a boundary, and saying otherwise would be a
    /// lie.** `proctor_policy` action `status` is ungated and returns the lists,
    /// the roots and the trail's path to any caller, and the gate's own refusals
    /// name the bundle id they refused. A count is also close to a rule at the
    /// extremes: an allow list with no entries refuses everything. Withholding
    /// here is still right — a health check is the wrong place to hand out
    /// configuration, and the day that tool narrows this will not have to change.
    public struct PolicyPosture: Codable, Sendable, Equatable {
        /// `allowList`, `blockOnly` or `open`.
        public var mode: String
        public var allowCount: Int
        public var blockCount: Int
        public var sensitiveCount: Int
        /// Whether an approval token is live right now. Never the token, and
        /// never the application it is scoped to — a scope is a rule.
        public var approvalTokenLive: Bool
        public var fsJailDeclared: Bool
        public var fsRootCount: Int
        public var auditWritable: Bool
        public var auditSealed: Bool
        public var auditSigned: Bool
        /// Whether the trail verifies clean. Sealing hides the contents; this is
        /// whether it is the trail Proctor wrote.
        public var auditClean: Bool
        public var auditKeyConfirmed: Bool
        public var auditEntries: Int
        /// Entries that could not be written this run. An action that was never
        /// recorded leaves no broken link to find, so a clean verdict beside a
        /// non-zero count here is not a complete trail.
        public var auditDroppedThisRun: Int?
        public var note: String

        public init(mode: String, allowCount: Int, blockCount: Int, sensitiveCount: Int,
                    approvalTokenLive: Bool, fsJailDeclared: Bool, fsRootCount: Int,
                    auditWritable: Bool, auditSealed: Bool, auditSigned: Bool,
                    auditClean: Bool, auditKeyConfirmed: Bool, auditEntries: Int,
                    auditDroppedThisRun: Int? = nil, note: String) {
            self.mode = mode; self.allowCount = allowCount; self.blockCount = blockCount
            self.sensitiveCount = sensitiveCount; self.approvalTokenLive = approvalTokenLive
            self.fsJailDeclared = fsJailDeclared; self.fsRootCount = fsRootCount
            self.auditWritable = auditWritable; self.auditSealed = auditSealed
            self.auditSigned = auditSigned; self.auditClean = auditClean
            self.auditKeyConfirmed = auditKeyConfirmed; self.auditEntries = auditEntries
            self.auditDroppedThisRun = auditDroppedThisRun; self.note = note
        }
    }

    public struct Grant: Codable, Sendable {
        public var name: String              // Accessibility, Screen Recording, Automation
        /// Whether this grant is **confirmed granted**.
        ///
        /// Derived from `state` and deliberately fail-closed: a grant Proctor could
        /// not confirm reads `false` here, exactly as a denied one does. That keeps
        /// every consumer that only reads the boolean as conservative as it always
        /// was. It also means the boolean cannot tell a denial from a non-answer —
        /// which is what `state` is for, and why the surfaces that put a *remedy* in
        /// front of somebody read that instead. Sending a person to System Settings
        /// for a permission they already granted is the defect PRO-0041 fixed.
        public var granted: Bool
        public var required: Bool
        public var howToFix: String
        /// What was actually established: `granted`, `denied`, or `unconfirmed`.
        ///
        /// A string on the wire in the shape `secondLane` already uses, and optional
        /// so a report from an older agent still decodes against a newer shim — it
        /// then resolves to the old two-state reading of `granted`.
        ///
        /// `unconfirmed` means the probe was bounded and the platform did not answer
        /// inside it. It is a fact about what Proctor knows, not about the
        /// permission: the grant may be perfectly in place.
        public var state: String?

        /// The state, with an older agent's two-state report read the old way.
        public var resolvedState: GrantState {
            state.flatMap(GrantState.init(rawValue:)) ?? (granted ? .granted : .denied)
        }

        public init(name: String, granted: Bool, required: Bool, howToFix: String) {
            self.name = name; self.granted = granted; self.required = required
            self.howToFix = howToFix
            self.state = (granted ? GrantState.granted : .denied).rawValue
        }

        /// The tri-state initialiser. `granted` is derived here so the boolean and
        /// the state cannot be set to disagree with each other.
        public init(name: String, state: GrantState, required: Bool, howToFix: String) {
            self.name = name
            self.granted = state.isConfirmedGranted
            self.required = required
            self.howToFix = howToFix
            self.state = state.rawValue
        }
    }

    public struct AttachedAppHealth: Codable, Sendable {
        public var app: String
        public var name: String
        public var windows: Int
        public var manualAccessibility: Bool
        public var observerAlive: Bool
        public var cachedRefs: Int
        public var reflectorConnected: Bool
        public init(app: String, name: String, windows: Int, manualAccessibility: Bool,
                    observerAlive: Bool, cachedRefs: Int, reflectorConnected: Bool) {
            self.app = app; self.name = name; self.windows = windows
            self.manualAccessibility = manualAccessibility; self.observerAlive = observerAlive
            self.cachedRefs = cachedRefs; self.reflectorConnected = reflectorConnected
        }
    }

    public init(agentVersion: String, protocolVersion: Int, osVersion: String,
                agentRunning: Bool, socketPath: String, grants: [Grant],
                attachedApps: [AttachedAppHealth], observersLive: Int,
                secureEventInputActive: Bool, shortcutsCLIAvailable: Bool,
                obscuraAvailable: Bool = false, obscura: ToolPresence? = nil,
                obscuraUnavailable: ToolAbsence? = nil,
                tools: [ToolPresence] = [], secondLane: String = SecondLaneState.off.rawValue,
                agentBuild: BuildIdentity? = nil,
                lanes: [Lane]? = nil, policy: PolicyPosture? = nil,
                switches: [SwitchState]? = nil,
                machine: Machine? = nil,
                ready: Bool, blockers: [String]) {
        self.agentVersion = agentVersion; self.protocolVersion = protocolVersion
        self.osVersion = osVersion; self.agentRunning = agentRunning
        self.socketPath = socketPath; self.grants = grants; self.attachedApps = attachedApps
        self.observersLive = observersLive; self.secureEventInputActive = secureEventInputActive
        self.shortcutsCLIAvailable = shortcutsCLIAvailable
        self.machine = machine
        self.obscuraAvailable = obscuraAvailable; self.obscura = obscura
        self.obscuraUnavailable = obscuraUnavailable
        self.tools = tools; self.secondLane = secondLane
        self.agentBuild = agentBuild
        self.lanes = lanes
        self.policy = policy
        self.switches = switches
        self.ready = ready
        self.blockers = blockers
    }
}

/// One runtime switch as the agent actually has it.
///
/// Deliberately carries the source and the lock separately from the value. A
/// window that only knew the value would have to guess where it came from, and
/// PRO-0029's whole point is that a toggle which silently loses to an environment
/// variable is worse than no toggle.
public struct SwitchState: Codable, Sendable, Equatable {
    /// The variable's name, which is also its identity.
    public var variable: String
    /// Whether it is on in this agent.
    public var on: Bool
    /// `environment`, `saved` or `builtInDefault`.
    public var source: String
    /// Whether the window's control should be disabled. Never true for a
    /// capability switch, so a person can always decline one.
    public var locked: Bool
    /// Whether a change lands now (`live`) or at the next agent start
    /// (`nextStart`).
    public var timing: String
    /// Present only when the pairing is one that needs saying — a capability
    /// armed with the thing that would announce it switched off.
    public var pairingWarning: String?

    public init(variable: String, on: Bool, source: String, locked: Bool,
                timing: String, pairingWarning: String? = nil) {
        self.variable = variable
        self.on = on
        self.source = source
        self.locked = locked
        self.timing = timing
        self.pairingWarning = pairingWarning
    }
}

// MARK: - JSONValue

/// A Codable any-JSON box. The tool surface is schema-driven at the edges but
/// values inside AX nodes are genuinely heterogeneous.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    public var intValue: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }; return nil
    }
    public subscript(key: String) -> JSONValue? { objectValue?[key] }

    public static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
