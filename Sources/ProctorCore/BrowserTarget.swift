import Foundation

// Which half of a browser window is Proctor's, and what to do about the other half.
//
// Proctor drives native macOS applications. A page inside a browser is not one:
// walking its accessibility tree trades the DOM, computed styles, the console,
// the network log and a selector that survives a re-render for a flattened tree
// and a set of coordinates. The operator's browser tool is Obscura, so a page is
// handed to Obscura rather than driven here.
//
// The handoff is a disclosure, never a refusal, and it discloses its own limits
// as well as Proctor's. Obscura runs its own engine with its own cookie jar, so
// following the advice restarts at a URL rather than continuing this window's
// session — said in words, in `continuity`, rather than left for a model to
// discover at a login wall.
//
// Everything here is pure. The agent supplies what it read from the accessibility
// tree as a `WebContentProbe`; this file decides.

// MARK: - The catalogue

/// What kind of window a bundle identifier names.
///
/// A per-site application — "install this site as an app", "open as window" — is
/// a browser's window in the sense that a browser renders it, and an application
/// window in every sense that decides what to do with it. Proctor drives it, and
/// this is the machine-readable half of saying so.
public enum BrowserSurface: String, Codable, Sendable, Equatable {
    /// A browser: tabs, an address field, many origins over its lifetime.
    case browserWindow
    /// One site, installed and opened as an application, with its own dock entry
    /// and its own session.
    case installedWebApp
}

/// Which side of the page boundary a step's state hash was taken over, for a
/// window a browser renders.
///
/// `Canonical.hash` walks the accessibility tree of a window. Inside a web area
/// that tree is the page's render tree; outside one it is the application's own
/// view hierarchy. The two are not the same measurement, and a determinism score
/// that folds them without saying which is which is the number `BrowserTarget.evidence`
/// has always warned about — stated, until now, on every surface except the one
/// that publishes the score.
///
/// Measured **at the step, while it ran**, never scanned before a sweep: a step's
/// target usually does not exist until the steps before it have run, so a flow that
/// opens a browser and then drives a page — the ordinary case here — would classify
/// as nothing at all.
///
/// **This marks where a step acted. It does not partition the score.** A state hash
/// is a walk of the whole window, so in a browser window the page's render tree is
/// inside every step's hash, `browserChrome` steps included. `browserChrome` means
/// the step's *target* lay outside the web area; it does not mean that step's number
/// is unaffected by the page. Read as a partition into an application half and a page
/// half, this would be a quieter version of the over-trust it exists to remove.
public enum HashSubject: String, Codable, Sendable, Equatable {
    /// The step's target lay inside a web area, so its hash is over the browser's
    /// render tree. The score is real; its subject is the page.
    case pageContent
    /// The step's target lay outside every web area — toolbar, tab bar, menu,
    /// sheet, downloads popover. The application's own tree, and Proctor's half
    /// of the boundary.
    case browserChrome
    /// A browser renders this window and the step named no target that resolved to
    /// a rectangle — a menu path, a keystroke — so which side it fell on was never
    /// established.
    ///
    /// **A value rather than an absence, and that is the point.** Absence has to
    /// mean exactly one thing, and here it means "no browser renders this window".
    /// Folding "not a browser" together with "a browser, but never classified"
    /// would let a page-churn number read as a native one.
    case unclassified
}

/// A browser Proctor recognises, identified by bundle identifier.
public struct KnownBrowser: Sendable, Equatable {
    public let name: String
    public let bundleId: String
    /// The internal scheme namespace this browser's own pages live in — `chrome`
    /// for Chrome and Chromium, `brave`, `edge`, `vivaldi`, `opera`, `arc` — or
    /// nil for a browser whose internal pages are `about:` pages, which is every
    /// WebKit and Gecko one here.
    ///
    /// **One fact per row where there used to be two.** `chromiumFamily` was a
    /// stored boolean beside the name, and a second fact per browser is a second
    /// fact to get wrong. What routing actually asks is whether the page in front
    /// of Proctor exists in the browser the second lane drives, and the namespace
    /// is the precise form of that question, so the boolean is computed from it
    /// and the two can no longer disagree.
    ///
    /// It does **not** make the answer drift-proof: a browser changing engine
    /// still needs somebody to edit this row. Measuring the engine from the app
    /// bundle was tried and rejected — the available probe matches framework
    /// names containing `Chrom`, `Edge` or `Brave`, and Vivaldi, Opera and Arc
    /// name their frameworks after themselves, so it would demote three browsers
    /// this table gets right. A real probe is logged as child work.
    public let internalScheme: String?
    public let surface: BrowserSurface

    /// Load-bearing for the second lane and for nothing else: browser-use drives
    /// a real Chromium, so on a WebKit or Gecko window it would be driving a
    /// *different* browser with a different session — PRO-0020's "success against
    /// a window it never touched", one level out.
    public var chromiumFamily: Bool { internalScheme != nil }

    public init(name: String, bundleId: String, internalScheme: String? = nil,
                surface: BrowserSurface = .browserWindow) {
        self.name = name; self.bundleId = bundleId
        self.internalScheme = internalScheme; self.surface = surface
    }
}

/// Known browsers, matched on bundle identifier and never inferred from the tree.
///
/// `AXEngineImpl.isChromiumBased` already sets this precedent, and for the same
/// reason: inferring "browser" from the presence of a web area would sweep in
/// every Electron application and every native app hosting a `WKWebView`, which
/// is exactly the boundary this feature exists to draw. A browser missing from
/// the table discloses nothing; adding one is a line here.
public enum BrowserCatalogue {

    /// Exact bundle identifiers, with the internal scheme namespace they own.
    static let exact: [String: (name: String, scheme: String?)] = [
        "com.apple.Safari": ("Safari", nil),
        "com.apple.SafariTechnologyPreview": ("Safari Technology Preview", nil),
        "org.chromium.Chromium": ("Chromium", "chrome"),
        "company.thebrowser.Browser": ("Arc", "arc"),
        "com.kagi.kagimacOS": ("Orion", nil),                 // WebKit
        "com.vivaldi.Vivaldi": ("Vivaldi", "vivaldi"),
        "app.zen-browser.zen": ("Zen", nil),                  // Gecko
        "com.duckduckgo.macos.browser": ("DuckDuckGo", nil),  // WebKit
        "com.operasoftware.Opera": ("Opera", "opera"),
        "com.operasoftware.OperaGX": ("Opera GX", "opera"),
        // Mozilla's developer channel runs the two words together rather than
        // adding a dotted segment, so the prefix rule below does not reach it and
        // it is named here. Matching on a bare prefix instead would sweep in
        // com.google.ChromeRemoteDesktop, which is not a browser.
        "org.mozilla.firefoxdeveloperedition": ("Firefox Developer Edition", nil)
    ]

    /// Prefix rules, which is how a product's release channels are covered without
    /// enumerating every one: `com.google.Chrome.canary`, `com.brave.Browser.beta`,
    /// `com.microsoft.edgemac.Dev` and their siblings all resolve here — and
    /// inherit the rule's scheme namespace with them.
    static let prefixes: [(prefix: String, name: String, scheme: String?)] = [
        ("com.google.Chrome", "Google Chrome", "chrome"),
        ("com.brave.Browser", "Brave", "brave"),
        ("com.microsoft.edgemac", "Microsoft Edge", "edge"),
        ("org.mozilla.firefox", "Firefox", nil),
        ("org.mozilla.nightly", "Firefox Nightly", nil)
    ]

    /// The components that mark a per-site application, compared case-insensitively
    /// because Safari spells its one `WebApp` and no identifier here has been
    /// measured on a real machine.
    static let webAppMarkers: Set<String> = ["app", "webapp"]

    /// Split a bundle identifier at its web-app marker.
    ///
    /// Chromium builds a shim's identifier as the **base** bundle id plus `.app.`
    /// plus the app id, and the base of a channel build is that channel's own id.
    /// So a Canary web app is `com.google.Chrome.canary.app.<hash>`: the marker is
    /// not the first component after the browser's prefix, and testing the start
    /// of the remainder would miss every web app on every channel — which is to
    /// say on the builds somebody doing this work actually runs.
    ///
    /// The scan starts at index **1** and that floor is load-bearing:
    /// `app.zen-browser.zen` opens with a component `app`, and scanning from zero
    /// would truncate Zen's identifier to nothing and stop recognising it.
    ///
    /// The split runs **before** the lookup rather than after it. Making the
    /// exact-match rows into prefixes so that `com.apple.Safari.WebApp.<uuid>`
    /// could reach Safari would also make every other descendant of an exact row
    /// resolve — `com.apple.Safari.SafeBrowsing.Service` would become Safari —
    /// which changes an answer for a window that is not a web app at all. Splitting
    /// first leaves every identifier without a marker on exactly the path it took
    /// before.
    static func splitAtWebAppMarker(_ bundleId: String) -> (base: String, isWebApp: Bool) {
        let parts = bundleId.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return (bundleId, false) }
        for index in 1..<parts.count where webAppMarkers.contains(parts[index].lowercased()) {
            return (parts[0..<index].joined(separator: "."), true)
        }
        return (bundleId, false)
    }

    /// The exact-then-prefix lookup, unchanged.
    static func lookUp(_ bundleId: String) -> (name: String, scheme: String?)? {
        if let hit = exact[bundleId] { return hit }
        for rule in prefixes where bundleId == rule.prefix || bundleId.hasPrefix(rule.prefix + ".") {
            return (rule.name, rule.scheme)
        }
        return nil
    }

    public static func identify(bundleId: String?) -> KnownBrowser? {
        // The marker split can only ever *add* an answer: it is tried first, and
        // an identifier whose truncated base matches nothing falls back to the
        // untouched lookup on the whole thing. No catalogue row today carries a
        // non-leading `app` component, but one could, and a split that can take an
        // identifier away from a row it would otherwise have matched is a rule that
        // breaks the day somebody adds a browser.
        guard let bundleId, !bundleId.isEmpty else { return nil }
        let split = splitAtWebAppMarker(bundleId)
        if split.isWebApp, let row = lookUp(split.base) {
            // The full identifier is reported, not the truncated base: it is what
            // the application says it is, and a reader comparing this against a
            // `proctor_apps` row needs the two to match.
            return KnownBrowser(name: row.name, bundleId: bundleId, internalScheme: row.scheme,
                                surface: .installedWebApp)
        }
        guard let row = lookUp(bundleId) else { return nil }
        return KnownBrowser(name: row.name, bundleId: bundleId, internalScheme: row.scheme,
                            surface: .browserWindow)
    }

    /// Every internal scheme namespace a catalogue row owns, deduplicated.
    static var ownedInternalSchemes: [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for scheme in exact.values.compactMap(\.scheme).sorted()
            + prefixes.compactMap(\.scheme).sorted() where seen.insert(scheme).inserted {
            out.append(scheme)
        }
        return out
    }
}


// MARK: - What the accessibility side reports

/// One web area found in a window: what it says its URL is, and where it sits.
///
/// The frame is what makes the boundary checkable for a target that is not a
/// named element — a `click` at a point, which is the case the brief calls out,
/// since a click at a point in a browser window proves less than a DOM assertion.
public struct WebArea: Sendable, Equatable {
    public var url: String?
    public var frame: Rect?
    public init(url: String? = nil, frame: Rect? = nil) {
        self.url = url; self.frame = frame
    }
}

/// A window's web content, as the accessibility tree describes it. A window with
/// no web content produces **no probe at all** rather than an empty one: absence
/// is the answer, and modelling it as a probe with a false flag invites a caller
/// to read "not page content" as "page content with nothing in it".
public struct WebContentProbe: Sendable, Equatable {
    public var areas: [WebArea]
    public init(areas: [WebArea]) { self.areas = areas }

    /// The areas that are actually showing something, which is what the URL
    /// decision reads.
    ///
    /// A real browser tree carries more web areas than the page a person is
    /// looking at — a docked DevTools pane, a preview, a print sheet, an area
    /// collapsed to nothing. Counting a zero-sized one as a second page would make
    /// "several web areas, Proctor does not pick one" the answer almost every
    /// time, which is a correct-sounding way of never answering. Discarding an
    /// area with no extent is not picking between pages; it is declining to count
    /// something nobody can see. When no area reports a usable frame at all, every
    /// area is kept, because then the frames are the thing that is missing rather
    /// than the content.
    public var rendered: [WebArea] {
        let framed = areas.filter { area in
            guard let f = area.frame else { return false }
            return f.w > 0 && f.h > 0
        }
        return framed.isEmpty ? areas : framed
    }

    /// Whether a rectangle lies inside any web area. Containment is geometric, so
    /// an overlay drawn over the page — a find bar, an autofill popover — reads as
    /// page content. That errs toward disclosing, which is the safe direction for
    /// an advisory that is never a refusal.
    public func contains(_ rect: Rect) -> Bool {
        areas.compactMap(\.frame).contains { area in
            rect.x >= area.x && rect.y >= area.y
                && rect.x + rect.w <= area.x + area.w
                && rect.y + rect.h <= area.y + area.h
        }
    }

    public func contains(x: Double, y: Double) -> Bool {
        contains(Rect(x: x, y: y, w: 0, h: 0))
    }
}

// MARK: - The lanes

/// The tool a handoff names. One at a time, never a menu: naming both lanes with
/// their trade-offs hands the decision back to the caller, which is the thing this
/// feature exists to stop doing. The raw value is the binary's own name, because
/// that is what the reader types.
public enum BrowserLane: String, Codable, Sendable, Equatable {
    case obscura = "obscura"
    case browserUse = "browser-use"
}

/// Whether the second lane may be named, and whether it is usable. Three states
/// rather than a boolean, because "you enabled a lane that is not installed" is a
/// real situation that has to reach the operator who caused it.
public enum SecondLaneState: String, Codable, Sendable, Equatable {
    /// `PROCTOR_SECOND_LANE` is unset. The name appears nowhere, whatever is on
    /// disk. This is the default, and it is this machine's standing instruction.
    case off
    /// Enabled and present.
    case enabled
    /// Enabled and not found. Named, but never recommended.
    case unavailable
}

/// What the machine offers, as one value. Built in exactly one place —
/// `BrowserLanes.make` — because the handoff, `proctor_doctor` and the status
/// window all need this answer, and three readers each interpreting an environment
/// variable and two stat results is three partial copies of one predicate that
/// will disagree.
public struct BrowserLanes: Sendable, Equatable {
    public var obscuraAvailable: Bool
    public var secondLane: SecondLaneState

    /// Obscura present, second lane off — a machine following the standing
    /// instruction. A named value used explicitly at a call site, never a default
    /// argument: a default is what lets a forgotten caller claim Obscura is
    /// installed when it is not.
    public static let obscuraOnly = BrowserLanes(obscuraAvailable: true, secondLane: .off)

    public init(obscuraAvailable: Bool, secondLane: SecondLaneState) {
        self.obscuraAvailable = obscuraAvailable; self.secondLane = secondLane
    }

    public static func make(obscura: ToolPresence, browserUse: ToolPresence,
                            environment: [String: String]) -> BrowserLanes {
        let named = BrowserUseTool.enabled(environment: environment)
        return BrowserLanes(
            obscuraAvailable: obscura.available,
            secondLane: !named ? .off : (browserUse.available ? .enabled : .unavailable))
    }
}

// MARK: - The handoff

/// What taking this handoff's advice commits the caller to, in a form a host can
/// gate on without reading English written for a person.
///
/// **The flags describe the instrument the handoff points at** — the lane it
/// names, or Proctor itself where the handoff says Proctor drives this window.
/// Putting them only on a named lane was the first draft, and it left the one path
/// that acts in the person's live signed-in session — Proctor driving their
/// installed mail window — carrying nothing at all, so a host refusing
/// `canActAsThisPerson` would have blocked the autonomous lane and waved that
/// through.
///
/// **Polarity is uniform: true means the fact is present and is one to weigh**, so
/// a host's rule is "refuse if any flag I care about is true" rather than a
/// per-flag lookup of which way round it reads. An object rather than an array of
/// set names, because a host reading `flags.autonomous` has to be able to tell
/// `false` from "this Proctor does not know that flag", and an array collapses the
/// two.
///
/// **Two limits, stated because a flag read as a verdict is worse than prose.** A
/// true flag is not a claim that the instrument is unsafe, and five false flags are
/// not a claim that one is safe. And these describe what Proctor *recommends*, not
/// everything that could happen: the handoff is advisory and never a refusal, so a
/// caller who ignores it and drives a signed-in tab through the accessibility plane
/// is doing something no flag here describes. A host whose policy is "nothing may
/// act in a live browser session" gates on the presence of a handoff, not on a flag.
public struct BrowserLaneFlags: Codable, Sendable, Equatable {
    /// It acts in its own browser rather than the window Proctor is attached to,
    /// so nothing it reports is evidence about this window.
    public var actsOutsideThisWindow: Bool
    /// It decides its own steps: what happens between the ask and the answer is
    /// not enumerated in advance and cannot be reviewed before it runs.
    public var autonomous: Bool
    /// It is **able** to act with the browser session of the person at this
    /// machine, on every origin they are signed in to. A capability rather than an
    /// assertion about this run: Proctor cannot see which profile an operator will
    /// give a tool, and a flag the same payload's own caveats falsify — they say to
    /// use an isolated profile — is worse than no flag.
    public var canActAsThisPerson: Bool
    /// Nothing it does appears in Proctor's audit trail, which records what Proctor
    /// did.
    public var outsideTheAuditTrail: Bool
    /// It needs a model credential and a run costs whatever that model costs.
    public var billed: Bool

    public init(actsOutsideThisWindow: Bool, autonomous: Bool, canActAsThisPerson: Bool,
                outsideTheAuditTrail: Bool, billed: Bool) {
        self.actsOutsideThisWindow = actsOutsideThisWindow
        self.autonomous = autonomous
        self.canActAsThisPerson = canActAsThisPerson
        self.outsideTheAuditTrail = outsideTheAuditTrail
        self.billed = billed
    }

    /// A bounded reader in its own engine with its own empty cookie jar.
    public static let obscura = BrowserLaneFlags(
        actsOutsideThisWindow: true, autonomous: false, canActAsThisPerson: false,
        outsideTheAuditTrail: true, billed: false)

    /// An autonomous agent that can attach to the running browser.
    public static let browserUse = BrowserLaneFlags(
        actsOutsideThisWindow: true, autonomous: true, canActAsThisPerson: true,
        outsideTheAuditTrail: true, billed: true)

    /// Proctor driving an installed web app window through the accessibility
    /// plane. It is this window, it is enumerated, it is audited, it is free — and
    /// it is the person's own signed-in session, which is the whole point of
    /// carrying a flag set here.
    public static let proctorNative = BrowserLaneFlags(
        actsOutsideThisWindow: false, autonomous: false, canActAsThisPerson: true,
        outsideTheAuditTrail: false, billed: false)
}

/// The advisory carried on a result whose target is a browser page.
///
/// Optional fields are omitted by `JSONEncoder`, which is how the brief form and
/// the full form differ on the wire: the full form is emitted once, at attach,
/// because repeating seven caveats on every step of a twenty-step batch is noise
/// that gets skimmed.
public struct BrowserHandoff: Codable, Sendable, Equatable {
    /// Leads at both detail levels, and is the same sentence at both. Attaching to
    /// a browser is not a reason to leave Proctor; it is a reason to know which
    /// half of the window is whose. Names whichever lane owns the page.
    public var boundary: String
    public var browser: String
    public var bundleId: String
    /// What kind of window this is, so a host does not parse a sentence to find
    /// out. `use == null` is not enough on its own: it means "no lane", and this
    /// says whether that is because nothing should drive the page or because
    /// Proctor drives this one itself.
    public var surface: BrowserSurface
    /// Absent when there is nothing either lane can open — naming a tool that will
    /// fail on this page is worse than naming none.
    public var use: String?
    /// Which rule chose that lane, as a sentence. This is what makes the advice
    /// checkable rather than oracular: a reader who disagrees knows what to
    /// disagree with. Present at both detail levels whenever a lane is named,
    /// including for the default, because "no measured limit applies here" is a
    /// claim Proctor is making and should stand behind. Also present on an
    /// installed web app, where the decision was to name no lane at all.
    public var why: String?
    /// The machine-readable half of `boundary`, `continuity` and `caveats`: what
    /// the instrument this handoff points at commits the caller to. Present exactly
    /// when there is such an instrument. See `BrowserLaneFlags` for what a host may
    /// and may not conclude.
    public var flags: BrowserLaneFlags?
    public var continuity: String
    public var evidence: String?
    public var url: String?
    public var urlUnavailable: String?
    /// Why there is no recommendation, or what is missing beside one: the tool it
    /// would have named is not on this machine. Singular, because a handoff names
    /// one lane at a time. Carries no shell command, deliberately. See
    /// `ToolAbsence`.
    public var toolUnavailable: ToolAbsence?
    /// Caveats that apply to *this* page and are therefore worth carrying even in
    /// the brief form, where the full list is omitted. Every one of them is a fact
    /// about Obscura, so they only appear on the Obscura lane.
    public var notes: [String]?
    public var commands: [String]?
    public var caveats: [String]?

    public init(boundary: String, browser: String, bundleId: String,
                surface: BrowserSurface = .browserWindow, use: String?,
                why: String? = nil, flags: BrowserLaneFlags? = nil, continuity: String,
                evidence: String? = nil,
                url: String? = nil, urlUnavailable: String? = nil,
                toolUnavailable: ToolAbsence? = nil, notes: [String]? = nil,
                commands: [String]? = nil, caveats: [String]? = nil) {
        self.boundary = boundary; self.browser = browser; self.bundleId = bundleId
        self.surface = surface
        self.use = use; self.why = why; self.flags = flags; self.continuity = continuity
        self.evidence = evidence
        self.url = url; self.urlUnavailable = urlUnavailable
        self.toolUnavailable = toolUnavailable; self.notes = notes
        self.commands = commands; self.caveats = caveats
    }
}

public enum BrowserTarget {

    /// The accessibility role that marks the start of web content. A node inside
    /// one is page content; everything outside one, in a browser window, is native
    /// chrome and stays Proctor's.
    public static let webAreaRole = "AXWebArea"

    public enum Detail: Sendable, Equatable {
        /// Emitted once, at the moment the instrument is chosen.
        case full
        /// Everywhere else.
        case brief
    }

    /// The Chromium schemes no single browser owns: every Chromium-family browser
    /// serves them, so requiring an owning catalogue row for these would mean
    /// inventing one. Kept separate from the per-row half for exactly that reason.
    static let sharedChromiumInternalSchemes = [
        "chrome", "chrome-extension", "chrome-untrusted", "chrome-search",
        "chrome-native", "chrome-error", "isolated-app", "devtools"
    ]

    /// Schemes that name a page inside the browser itself. A list rather than a
    /// "not http(s)" negation, for the same reason the catalogue is a list: a
    /// negation sweeps in everything nobody thought about, and here the things
    /// nobody thought about — `file:`, `data:` — are the ones that would point an
    /// agent holding a live profile somewhere it should not go.
    ///
    /// **Derived, in two parts.** The shared Chromium set above, plus every
    /// catalogue row's own namespace, so a browser cannot own a scheme the router
    /// has never heard of and adding a browser brings its scheme with it.
    ///
    /// **`about` is deliberately absent.** `about:blank` is the empty tab every
    /// browser opens, and starting an autonomous agent for one is absurd; it keeps
    /// PRO-0020's behaviour exactly.
    public static let internalSchemes =
        sharedChromiumInternalSchemes
        + BrowserCatalogue.ownedInternalSchemes.filter {
            !sharedChromiumInternalSchemes.contains($0)
        }

    /// Browser-internal pages that **no lane is recommended for**, however capable
    /// the lane is.
    ///
    /// The completeness critic found this and it is the sharpest thing it found:
    /// the second lane is an autonomous agent acting as the person sitting here,
    /// and these are that person's credential store, their extension list, their
    /// browsing history and the switches that govern all three. Handing an agent
    /// `chrome://password-manager` because Obscura cannot open it is a worse answer
    /// than the honest one, which is that this page is nobody's to drive on
    /// somebody's behalf.
    ///
    /// Matched on the host, so `chrome://settings/passwords` is covered by
    /// `settings`. `devtools:` is refused wholesale rather than by host: driving
    /// DevTools drives the page it is inspecting, which compounds the reach of
    /// anything that goes wrong there.
    public static let sensitiveInternalHosts = [
        "settings", "password-manager", "passwords", "extensions", "flags",
        "history", "net-internals", "wallet", "signin", "sync-internals",
        "policy", "management", "credits", "profile-internals"
    ]

    public static func isBrowserInternal(_ url: String) -> Bool {
        let lower = url.lowercased()
        return internalSchemes.contains { lower.hasPrefix($0 + ":") }
    }

    /// Whether this browser-internal page is one Proctor declines to route.
    public static func isSensitiveInternal(_ url: String) -> Bool {
        let lower = url.lowercased()
        if lower.hasPrefix("devtools:") { return true }
        guard let range = lower.range(of: "://") else { return false }
        let rest = lower[range.upperBound...]
        let host = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        return sensitiveInternalHosts.contains(String(host))
    }

    public static func boundary(for lane: BrowserLane) -> String {
        switch lane {
        case .obscura:
            return "The page belongs to Obscura. The native chrome around it — toolbar, tab "
                + "bar, menus, sheets, the downloads popover — stays Proctor's."
        case .browserUse:
            return "The page belongs to browser-use, which is not a command that does one "
                + "thing: it is an autonomous agent that decides its own steps in a real "
                + "browser. The native chrome around the page — toolbar, tab bar, menus, "
                + "sheets, the downloads popover — stays Proctor's."
        }
    }

    public static func continuity(for lane: BrowserLane) -> String {
        switch lane {
        case .obscura:
            return "Obscura runs its own engine with its own cookie jar, so this is a restart "
                + "at a URL rather than a continuation of this window's session. Any "
                + "signed-in, tab or in-page state has to be re-established there. Nothing it "
                + "does reaches Proctor's audit trail either, which records what Proctor did."
        case .browserUse:
            return "In its default local mode browser-use drives a real browser with real "
                + "credentials, so what it does is done as the person sitting here, on every "
                + "origin they are signed in to. It is still not this window: Proctor is "
                + "attached to this one and browser-use is not. And nothing it does reaches "
                + "Proctor's audit trail, which records what Proctor did — so the trail is "
                + "not a complete account of what happened to this page."
        }
    }

    public static let evidence =
        "A step into page content still travels the accessibility plane like any other, but its "
        + "state hash is taken over a browser's render tree rather than an app's view hierarchy, "
        + "so a determinism score across page content measures the page's own churn as much as "
        + "the app's."

    /// Command templates. The placeholder is literal and stays literal: a page URL
    /// is attacker-controlled text, and interpolating it into a command string a
    /// model may paste into a shell is a command-injection path. The URL travels in
    /// its own field instead, and never in a sentence either.
    public static let urlPlaceholder = "<url>"

    static let obscuraCommands = [
        "obscura fetch <url> --dump markdown",
        "obscura fetch <url> --screenshot page.png",
        "obscura fetch <url> --eval \"document.title\"",
        "obscura --allow-private-network fetch <url>   # required for localhost and 192.168.*",
        "obscura serve --port 9222   # CDP, when a promise or a viewport other than 1280x720 matters"
    ]

    /// Templates for the Obscura lane and **nothing** for the other one, absent
    /// rather than empty.
    ///
    /// The criterion, so the difference is a rule rather than an exception: a
    /// command template belongs in a tool result only when running it does exactly
    /// one bounded, read-shaped thing. `obscura fetch` meets it — one page, one
    /// read, no credential, no autonomy, and the tool is already installed.
    /// browser-use fails it three ways: its documented ephemeral invocation
    /// installs from PyPI as it runs, it needs a model credential, and it starts an
    /// agent on a live profile. Its guidance is prose in `caveats` instead, which
    /// constrains the invocation without composing one.
    public static func commands(for lane: BrowserLane) -> [String]? {
        lane == .obscura ? obscuraCommands : nil
    }

    /// The measured edges, carried as data so they are not rediscovered.
    static let obscuraCaveats = [
        "Localhost and private-network addresses are blocked unless --allow-private-network is "
        + "passed; a local dev server otherwise fails as an SSRF block that reads like a network error.",
        "CSS animations and transitions never execute, so there is no motion to observe.",
        "Emulation.setEmulatedMedia is accepted and inert, so there is no print pass and no "
        + "reduced-motion pass; matchMedia stays false.",
        "Web fonts never load, so font fidelity is unmeasurable rather than perfect.",
        "An empty computed value means not implemented, not unset, for boxShadow, backgroundImage, "
        + "textTransform, outline and flex.",
        "Read computed styles through longhand properties. Shorthands such as padding and margin "
        + "resolve to 0px even when the layout is correct, which passes a spacing assertion that "
        + "should fail.",
        "obscura fetch renders at a fixed 1280x720 and awaits no promise; use obscura serve plus "
        + "CDP when either matters."
    ]

    static let browserUseCaveats = [
        "Attaching to a browser already running needs its remote-debugging prompt approved, and "
        + "that is a latch rather than a one-off: the port stays open to every local process "
        + "until that browser quits.",
        "It chooses its own browser and that may not be the window Proctor is attached to, so a "
        + "job started here can land in a different browser with a different session.",
        "It needs a model credential, and a run costs whatever that model costs.",
        "Run it from an installed entry point rather than an installer that runs it, and give it "
        + "an isolated browser profile unless continuing this person's session is the point of "
        + "the job."
    ]

    public static func caveats(for lane: BrowserLane) -> [String] {
        lane == .obscura ? obscuraCaveats : browserUseCaveats
    }

    public static func flags(for lane: BrowserLane) -> BrowserLaneFlags {
        lane == .obscura ? .obscura : .browserUse
    }

    // MARK: - An installed web app

    /// An installed web app is a browser window in the sense that a browser
    /// renders it, and an application window in every sense that decides what to
    /// do with it. Proctor drives it, exactly as it drives Slack or VS Code —
    /// which are Chromium rendering one origin in a window with its own bundle id,
    /// its own dock entry and its own session, and which PRO-0020 already declines
    /// to route.
    ///
    /// The boundary itself does **not** change: a web app can show native chrome
    /// (Safari's web apps carry a navigation toolbar by default, and Chrome and
    /// Edge have a tabbed application mode), so inside the web area is the page
    /// and the frame around it stays Proctor's, exactly as in a browser window.
    public static let webAppBoundary =
        "This is an installed web app window rather than a browser window: one site opened as "
        + "an application, with its own dock entry and its own session. Proctor drives it as an "
        + "application. The boundary inside it is the usual one — the web area is the page, and "
        + "any toolbar or tab strip the app shows around it stays Proctor's."

    public static let webAppWhy =
        "No browser tool is named for it. A browser tool opens the address in its own engine "
        + "with an empty cookie jar, and a site is installed as an application because somebody "
        + "uses it signed in — so that would be a different, signed-out visit to the same site "
        + "rather than this window. What Proctor can prove about it is bounded the same way any "
        + "page content is: the tree here is a render tree, not an application's view hierarchy."

    public static let webAppContinuity =
        "The session lives in this window, so driving it here continues it. Any browser tool "
        + "would start somewhere else, signed out, and would not be this window."

    /// Carried in the brief form too, because it applies to the page in hand and a
    /// model that only ever sees the brief form would otherwise hand a dev server
    /// to Obscura and read the SSRF block as a network error. An Obscura fact, so
    /// it rides only on that lane.
    public static let privateNetworkNote =
        "This is a private-network address, so it needs --allow-private-network; without it "
        + "Obscura blocks the fetch and the failure reads like a network error."

    public static let pdfNote =
        "This URL is a PDF. Neither browser tool reads a PDF's structure — rendering one measures "
        + "the viewer rather than the document — so fetch the file and parse it instead."

    public static let noWindowNamed = "No window was named, so no page URL was read."
    public static let urlAbsent = "AXURL was absent or empty on the web area."
    public static let severalURLs =
        "The window holds several web areas with different URLs; Proctor does not pick one."
    public static let notOpenable =
        "The page's URL is not http or https, so Obscura cannot open it; there is no handoff "
        + "target. The page is still not a native surface, so what Proctor can prove about it "
        + "is limited whichever tool is used."
    public static let notAnInstrument =
        "This URL is a local file or an inline payload rather than a page on the network. "
        + "Neither browser tool is the instrument for it: read the file, or decode the payload, "
        + "directly."

    // MARK: - Why a lane was chosen

    public static let whyInternalScheme =
        "This page lives inside the browser itself and has no equivalent in Obscura's engine, so "
        + "Obscura cannot open it at all. browser-use drives a real Chromium, which is where such "
        + "a page exists. That it is reachable there is not a promise that it drives: several "
        + "browser-internal pages are shadow-DOM interfaces that resist automation, and an "
        + "extension page needs that extension loaded in the profile it opens."
    public static let sensitiveInternal =
        "This is one of the browser's own configuration, credential or history pages. Obscura "
        + "cannot open it, and Proctor does not point the other lane at it either: that lane is "
        + "an autonomous agent acting as the person sitting here, and this page is where their "
        + "saved passwords, extensions and history live. Drive it by hand, or not at all."
    public static let partialURLs =
        "Some web areas in this window did not report a URL, so Proctor cannot say that every "
        + "page here is a browser-internal one. It will not route a window it has only partly "
        + "read."
    public static let whyDefault =
        "This is the default lane. No measured Obscura limit applies to this page: the scheme is "
        + "one Obscura opens, and Proctor found nothing about this page that Obscura cannot do."

    /// What the ladder decided.
    struct Decision {
        var lane: BrowserLane?
        var why: String?
        var url: String?
        var urlUnavailable: String?
        var toolUnavailable: ToolAbsence?
        /// Which rule fired, as a token. `why` is the sentence a reader sees;
        /// this is the same fact in a form the audit trail can carry, since a
        /// trail full of prose is a trail nothing can answer questions about.
        /// Deliberately not on `BrowserHandoff`: putting it on the wire is
        /// PRO-0024's open child item, and this change does not pre-empt it.
        var rule: BrowserLaneRule?
    }

    /// Which rule in PRO-0024's routing table named the lane. Only the two rules
    /// that *name* one appear here — a handoff that recommends nothing is not a
    /// recommendation, and is not recorded.
    public enum BrowserLaneRule: String, Codable, Sendable, Equatable {
        /// Rule 1: the page has no equivalent in Obscura's engine.
        case internalScheme
        /// Rule 4: the default, with no measured Obscura limit against this page.
        case defaultLane = "default"
    }

    /// The lane, the rule that chose it and the address's scheme — the three
    /// facts the audit trail records about a recommendation, and deliberately
    /// nothing else. Nil when no lane was named.
    ///
    /// The scheme is taken here rather than by the caller so that the one place
    /// that knows about the URL is the only place that ever touches it: no host,
    /// path, query or fragment leaves this function, which is what keeps the
    /// trail from becoming a browsing history.
    public static func recommendation(for browser: KnownBrowser, probe: WebContentProbe?,
                                      lanes: BrowserLanes)
    -> (lane: BrowserLane, rule: BrowserLaneRule, scheme: String?)? {
        let d = decide(for: browser, probe: probe, lanes: lanes)
        guard let lane = d.lane, let rule = d.rule else { return nil }
        return (lane, rule, d.url.flatMap { URL(string: $0)?.scheme?.lowercased() })
    }

    /// Build the advisory.
    ///
    /// A `nil` probe is the app-level case — a browser was named but no window was,
    /// so no page URL was read; the ladder then answers on machine state alone.
    ///
    /// `lanes` has **no default**. A default of "Obscura present, second lane off"
    /// would make every call site that forgot to pass one claim Obscura is
    /// installed, which is the bug this parameter replaced a post-hoc patch to
    /// avoid, with the compiler silent about it.
    public static func handoff(for browser: KnownBrowser, probe: WebContentProbe?,
                               detail: Detail, lanes: BrowserLanes) -> BrowserHandoff {
        if browser.surface == .installedWebApp {
            return webAppHandoff(for: browser, probe: probe, detail: detail)
        }

        let d = decide(for: browser, probe: probe, lanes: lanes)
        let lane = d.lane

        return BrowserHandoff(
            boundary: boundary(for: lane ?? .obscura),
            browser: browser.name,
            bundleId: browser.bundleId,
            surface: .browserWindow,
            use: lane?.rawValue,
            why: lane == nil ? nil : d.why,
            flags: lane.map(flags(for:)),
            continuity: continuity(for: lane ?? .obscura),
            evidence: detail == .full ? evidence : nil,
            url: d.url,
            urlUnavailable: d.urlUnavailable,
            toolUnavailable: d.toolUnavailable,
            notes: lane == .obscura ? notes(url: d.url) : nil,
            commands: lane.flatMap { detail == .full ? commands(for: $0) : nil },
            caveats: detail == .full ? caveats(for: lane ?? .obscura) : nil)
    }

    /// An installed web app, which never reaches the ladder.
    ///
    /// It reads the URL through the **same** rule 0 as any other window rather
    /// than skipping it, which is what keeps the page-specific advice alive: a
    /// `file:` or `data:` address still gets the not-an-instrument reason and a
    /// PDF still gets its note, instead of an installed PDF viewer being driven
    /// through the accessibility plane with the honest answer suppressed.
    ///
    /// The URL is **kept** where it was readable. Suppressing it would follow the
    /// no-lane rule elsewhere in this file, but the reason that rule suppresses
    /// an address is that the address leads nowhere; here it leads to the site
    /// this window is, and withholding it forces a model that disagrees with
    /// Proctor back onto guessing.
    ///
    /// No `caveats`, because the seven measured edges are one lane's facts and no
    /// lane was named. The private-network note goes the same way: it is advice
    /// about a tool that is not being recommended.
    static func webAppHandoff(for browser: KnownBrowser, probe: WebContentProbe?,
                              detail: Detail) -> BrowserHandoff {
        let reading = readURL(probe)
        return BrowserHandoff(
            boundary: webAppBoundary,
            browser: browser.name,
            bundleId: browser.bundleId,
            surface: .installedWebApp,
            use: nil,
            why: webAppWhy,
            flags: .proctorNative,
            continuity: webAppContinuity,
            evidence: detail == .full ? evidence : nil,
            url: reading.url,
            urlUnavailable: reading.unavailable,
            toolUnavailable: nil,
            notes: pdfOnlyNotes(url: reading.url),
            commands: nil,
            caveats: nil)
    }

    /// Rule 0 — what URL, if any, this is about.
    ///
    /// Lifted verbatim out of `decide` so the installed-web-app path reads a URL
    /// the same way rather than re-implementing it. The routing baseline fixture
    /// is what proves the lift moved nothing.
    struct URLReading {
        var url: String?
        var unavailable: String?
        var internalPage = false
        var otherScheme = false
    }

    static func readURL(_ probe: WebContentProbe?) -> URLReading {
        guard let probe else { return URLReading(url: nil, unavailable: noWindowNamed) }

        var out = URLReading()
        let rendered = probe.rendered
        let distinct = distinctURLs(rendered.compactMap(\.url))
        let web = distinct.filter { isWebScheme($0) }
        // A window Proctor has only partly read is not a window it can say
        // anything universal about. Dropping the silent areas and then
        // concluding "every URL here is internal" is how one unlabelled
        // signed-in tab beside an extension frame would be routed as an
        // internal page.
        let everyAreaSpoke = rendered.allSatisfy { !($0.url ?? "").isEmpty }
        if !distinct.isEmpty && web.isEmpty {
            // Every URL in the window is something Obscura cannot open. A
            // window mixing a browser-internal page with a real one already
            // resolves to the real one below, which is right: that is the page
            // somebody is looking at.
            if everyAreaSpoke && distinct.allSatisfy(isBrowserInternal) {
                out.internalPage = true
                out.url = distinct[0]
            } else {
                out.otherScheme = true
            }
            out.unavailable = distinct.allSatisfy(isNotAPage) ? notAnInstrument
                : (everyAreaSpoke ? notOpenable : partialURLs)
        } else {
            switch web.count {
            case 0:  out.unavailable = urlAbsent
            case 1:  out.url = web[0]
            default: out.unavailable = severalURLs
            }
        }
        return out
    }

    /// The ladder, in one place, in the order the spec states it. The conditions
    /// are complete and non-overlapping, so no catch-all can name a tool that is
    /// not there.
    static func decide(for browser: KnownBrowser, probe: WebContentProbe?,
                       lanes: BrowserLanes) -> Decision {
        let reading = readURL(probe)
        let url = reading.url
        let unavailable = reading.unavailable

        // Rules 1-3 — the page's own scheme, when there is one. `url` survives
        // only where a lane can actually open it: PRO-0020 drops the address for a
        // page nothing here can reach, and that stays true.
        if reading.internalPage || reading.otherScheme {
            guard reading.internalPage, browser.chromiumFamily else {
                return Decision(lane: nil, why: nil, url: nil, urlUnavailable: unavailable)
            }
            switch lanes.secondLane {
            case .enabled:
                // The deny list is checked here rather than earlier, so that with
                // the lane off this whole branch is byte-for-byte what PRO-0020
                // emitted. It exists to stop a lane firing, not to reword a
                // refusal that was already happening.
                if let url, isSensitiveInternal(url) {
                    return Decision(lane: nil, why: nil, url: nil,
                                    urlUnavailable: sensitiveInternal)
                }
                return Decision(lane: .browserUse, why: whyInternalScheme, url: url,
                                urlUnavailable: nil, rule: .internalScheme)
            case .unavailable:
                return Decision(lane: nil, why: nil, url: nil, urlUnavailable: unavailable,
                                toolUnavailable: BrowserUseTool.absence)
            case .off:
                return Decision(lane: nil, why: nil, url: nil, urlUnavailable: unavailable)
            }
        }

        // Rules 4-5 — machine state, for an http(s) page or for no page at all.
        //
        // **The second lane is never the answer here**, and the completeness critic
        // is why. An earlier draft routed an ordinary page to it whenever Obscura
        // was missing. That made a credentialed autonomous agent the default for
        // every web page on a machine with no Obscura — the opposite of "keep
        // Obscura as the default" — and it did it on exactly the pages most likely
        // to be hostile, since that agent's loop ingests the page it is reading.
        // Obscura being uninstalled is a fact about the machine, not a capability
        // fact about the page, and it is not a reason to change instrument.
        if lanes.obscuraAvailable {
            return Decision(lane: .obscura, why: whyDefault, url: url,
                            urlUnavailable: unavailable, rule: .defaultLane)
        }
        return Decision(lane: nil, why: nil, url: url, urlUnavailable: unavailable,
                        toolUnavailable: ObscuraTool.absence)
    }

    /// Caveats about the page in hand. Every one is a fact about Obscura, so the
    /// caller only asks on that lane; a browser-use handoff warning about an SSRF
    /// block that lane does not have would be advice for the wrong tool.
    static func notes(url: String?) -> [String]? {
        guard let url else { return nil }
        var out: [String] = []
        if isPrivateNetwork(url) { out.append(privateNetworkNote) }
        if isPDF(url) { out.append(pdfNote) }
        return out.isEmpty ? nil : out
    }

    /// The subset that survives when no lane was named at all.
    ///
    /// The PDF note says *neither* browser tool reads a PDF's structure and that
    /// the answer is to fetch the file and parse it, which is true whatever the
    /// instrument. The private-network note is advice about how to invoke Obscura,
    /// so on a handoff that names no tool it would be answering a question nobody
    /// asked.
    static func pdfOnlyNotes(url: String?) -> [String]? {
        guard let url, isPDF(url) else { return nil }
        return [pdfNote]
    }

    /// A URL naming something that is not a page on the network at all.
    static func isNotAPage(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("file:") || lower.hasPrefix("data:")
    }

    /// Matched on the path, so a query string or a fragment does not hide it.
    public static func isPDF(_ url: String) -> Bool {
        guard let path = URL(string: url)?.path else { return false }
        return path.lowercased().hasSuffix(".pdf")
    }

    /// Distinct URLs, comparing on a normalised form so that a trailing slash or a
    /// fragment does not make one page look like two and trip the several-URLs
    /// rule. The first spelling seen is the one reported, because that is what the
    /// application actually said.
    static func distinctURLs(_ raw: [String]) -> [String] {
        var seenKeys: Set<String> = []
        var out: [String] = []
        for url in raw where !url.isEmpty {
            let key = normalisedKey(url)
            if seenKeys.insert(key).inserted { out.append(url) }
        }
        return out
    }

    static func normalisedKey(_ url: String) -> String {
        var s = url.lowercased()
        if let hash = s.firstIndex(of: "#") { s = String(s[s.startIndex..<hash]) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Whether Obscura can open this URL at all. Scheme comparison is
    /// case-insensitive because a URL's scheme is.
    public static func isWebScheme(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// Loopback, link-local and RFC1918, which are what Obscura blocks by default.
    public static func isPrivateNetwork(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if host == "::1" || host == "[::1]" { return true }
        if host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (127, _), (10, _), (192, 168):     return true
        case (169, 254):                        return true
        case (172, let second) where (16...31).contains(second): return true
        default:                                return false
        }
    }
}
