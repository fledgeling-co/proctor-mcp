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
        case invalidArguments
        case notImplemented
        case internalError
    }

    public init(code: Code, message: String, remedy: String? = nil, detail: JSONValue? = nil) {
        self.code = code; self.message = message; self.remedy = remedy; self.detail = detail
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
    public init(window: String, revision: Int, root: AXNode?, diff: SnapshotDiff?,
                provenance: TreeProvenance, stateHash: String) {
        self.window = window; self.revision = revision; self.root = root
        self.diff = diff; self.provenance = provenance; self.stateHash = stateHash
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

    public init(window: String, path: String, width: Int, height: Int, scale: Double,
                status: FrameStatus, contentRect: Rect?, dirtyRectCount: Int, dirtyArea: Double,
                capturedAt: Double, framesWaited: Int, trustworthy: Bool,
                caveat: String? = nil, tileHashes: [String]? = nil,
                annotation: MarkAnnotation? = nil,
                normalization: CaptureNormalization? = nil, crop: CropRegion? = nil) {
        self.window = window; self.path = path; self.width = width; self.height = height
        self.scale = scale; self.status = status; self.contentRect = contentRect
        self.dirtyRectCount = dirtyRectCount; self.dirtyArea = dirtyArea
        self.capturedAt = capturedAt; self.framesWaited = framesWaited
        self.trustworthy = trustworthy; self.caveat = caveat; self.tileHashes = tileHashes
        self.annotation = annotation; self.normalization = normalization; self.crop = crop
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
    public init(scale: Double, applied: Bool, originalWidth: Int, originalHeight: Int,
                width: Int, height: Int, maxLongEdge: Int, maxPixels: Int) {
        self.scale = scale; self.applied = applied
        self.originalWidth = originalWidth; self.originalHeight = originalHeight
        self.width = width; self.height = height
        self.maxLongEdge = maxLongEdge; self.maxPixels = maxPixels
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

    public enum Kind: String, Codable, Sendable {
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
    public var error: AgentError?
    public var settle: SettleReport?
    public var stateHash: String?
    public var diff: SnapshotDiff?
    public var elapsedMs: Int
    public init(index: Int, step: ActionStep, ok: Bool, plane: ActuationPlane?,
                error: AgentError?, settle: SettleReport?, stateHash: String?,
                diff: SnapshotDiff?, elapsedMs: Int) {
        self.index = index; self.step = step; self.ok = ok; self.plane = plane
        self.error = error; self.settle = settle; self.stateHash = stateHash
        self.diff = diff; self.elapsedMs = elapsedMs
    }
}

public struct ActResult: Codable, Sendable {
    public var window: String
    public var steps: [StepResult]
    public var completed: Int
    public var failedAt: Int?
    public var finalHash: String?
    public init(window: String, steps: [StepResult], completed: Int,
                failedAt: Int?, finalHash: String?) {
        self.window = window; self.steps = steps; self.completed = completed
        self.failedAt = failedAt; self.finalHash = finalHash
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
    public init(flow: String, runs: Int, stepCount: Int, firstDivergence: Int?,
                stepInstability: [Double], deterministic: Bool,
                divergenceDetail: [String: [String]]?, notes: [String]) {
        self.flow = flow; self.runs = runs; self.stepCount = stepCount
        self.firstDivergence = firstDivergence; self.stepInstability = stepInstability
        self.deterministic = deterministic; self.divergenceDetail = divergenceDetail
        self.notes = notes
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
    public var ready: Bool
    public var blockers: [String]

    public struct Grant: Codable, Sendable {
        public var name: String              // Accessibility, Screen Recording, Automation
        public var granted: Bool
        public var required: Bool
        public var howToFix: String
        public init(name: String, granted: Bool, required: Bool, howToFix: String) {
            self.name = name; self.granted = granted; self.required = required
            self.howToFix = howToFix
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
                ready: Bool, blockers: [String]) {
        self.agentVersion = agentVersion; self.protocolVersion = protocolVersion
        self.osVersion = osVersion; self.agentRunning = agentRunning
        self.socketPath = socketPath; self.grants = grants; self.attachedApps = attachedApps
        self.observersLive = observersLive; self.secureEventInputActive = secureEventInputActive
        self.shortcutsCLIAvailable = shortcutsCLIAvailable; self.ready = ready
        self.blockers = blockers
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
