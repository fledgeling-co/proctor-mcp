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

/// A browser Proctor recognises, identified by bundle identifier.
public struct KnownBrowser: Sendable, Equatable {
    public let name: String
    public let bundleId: String
    public init(name: String, bundleId: String) {
        self.name = name; self.bundleId = bundleId
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

    /// Exact bundle identifiers.
    static let exact: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.apple.SafariTechnologyPreview": "Safari Technology Preview",
        "org.chromium.Chromium": "Chromium",
        "company.thebrowser.Browser": "Arc",
        "com.kagi.kagimacOS": "Orion",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "app.zen-browser.zen": "Zen",
        "com.duckduckgo.macos.browser": "DuckDuckGo",
        "com.operasoftware.Opera": "Opera",
        "com.operasoftware.OperaGX": "Opera GX",
        // Mozilla's developer channel runs the two words together rather than
        // adding a dotted segment, so the prefix rule below does not reach it and
        // it is named here. Matching on a bare prefix instead would sweep in
        // com.google.ChromeRemoteDesktop, which is not a browser.
        "org.mozilla.firefoxdeveloperedition": "Firefox Developer Edition"
    ]

    /// Prefix rules, which is how a product's release channels are covered without
    /// enumerating every one: `com.google.Chrome.canary`, `com.brave.Browser.beta`,
    /// `com.microsoft.edgemac.Dev` and their siblings all resolve here.
    static let prefixes: [(prefix: String, name: String)] = [
        ("com.google.Chrome", "Google Chrome"),
        ("com.brave.Browser", "Brave"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("org.mozilla.firefox", "Firefox"),
        ("org.mozilla.nightly", "Firefox Nightly")
    ]

    public static func identify(bundleId: String?) -> KnownBrowser? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        if let name = exact[bundleId] {
            return KnownBrowser(name: name, bundleId: bundleId)
        }
        for rule in prefixes where bundleId == rule.prefix || bundleId.hasPrefix(rule.prefix + ".") {
            return KnownBrowser(name: rule.name, bundleId: bundleId)
        }
        return nil
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

// MARK: - The handoff

/// The advisory carried on a result whose target is a browser page.
///
/// Optional fields are omitted by `JSONEncoder`, which is how the brief form and
/// the full form differ on the wire: the full form is emitted once, at attach,
/// because repeating seven caveats on every step of a twenty-step batch is noise
/// that gets skimmed.
public struct BrowserHandoff: Codable, Sendable, Equatable {
    /// Leads at both detail levels, and is the same sentence at both. Attaching to
    /// a browser is not a reason to leave Proctor; it is a reason to know which
    /// half of the window is whose.
    public var boundary: String
    public var browser: String
    public var bundleId: String
    /// Absent when there is nothing Obscura can open — naming a tool that will
    /// fail on this page is worse than naming none.
    public var use: String?
    public var continuity: String
    public var evidence: String?
    public var url: String?
    public var urlUnavailable: String?
    /// Why there is no recommendation: the tool it would have named is not on
    /// this machine. Sits beside `urlUnavailable` because it is the same kind of
    /// fact — a reason the advice is not what it would otherwise be — and carries
    /// no shell command, deliberately. See `ToolAbsence`.
    public var toolUnavailable: ToolAbsence?
    /// A caveat that applies to *this* page and is therefore worth carrying even in
    /// the brief form, where the full list is omitted.
    public var note: String?
    public var commands: [String]?
    public var caveats: [String]?

    public init(boundary: String, browser: String, bundleId: String, use: String?,
                continuity: String, evidence: String? = nil, url: String? = nil,
                urlUnavailable: String? = nil, toolUnavailable: ToolAbsence? = nil,
                note: String? = nil, commands: [String]? = nil, caveats: [String]? = nil) {
        self.boundary = boundary; self.browser = browser; self.bundleId = bundleId
        self.use = use; self.continuity = continuity; self.evidence = evidence
        self.url = url; self.urlUnavailable = urlUnavailable
        self.toolUnavailable = toolUnavailable; self.note = note
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

    public static let boundary =
        "The page belongs to Obscura. The native chrome around it — toolbar, tab bar, menus, "
        + "sheets, the downloads popover — stays Proctor's."

    public static let continuity =
        "Obscura runs its own engine with its own cookie jar, so this is a restart at a URL "
        + "rather than a continuation of this window's session. Any signed-in, tab or in-page "
        + "state has to be re-established there."

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

    public static let commands = [
        "obscura fetch <url> --dump markdown",
        "obscura fetch <url> --screenshot page.png",
        "obscura fetch <url> --eval \"document.title\"",
        "obscura --allow-private-network fetch <url>   # required for localhost and 192.168.*",
        "obscura serve --port 9222   # CDP, when a promise or a viewport other than 1280x720 matters"
    ]

    /// The measured edges, carried as data so they are not rediscovered.
    public static let caveats = [
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

    /// Carried in the brief form too, because it applies to the page in hand and a
    /// model that only ever sees the brief form would otherwise hand a dev server
    /// to Obscura and read the SSRF block as a network error.
    public static let privateNetworkNote =
        "This is a private-network address, so it needs --allow-private-network; without it "
        + "Obscura blocks the fetch and the failure reads like a network error."

    static let noWindowNamed = "No window was named, so no page URL was read."
    static let urlAbsent = "AXURL was absent or empty on the web area."
    static let severalURLs =
        "The window holds several web areas with different URLs; Proctor does not pick one."
    static let notOpenable =
        "The page's URL is not http or https, so Obscura cannot open it; there is no handoff "
        + "target. The page is still not a native surface, so what Proctor can prove about it "
        + "is limited whichever tool is used."

    /// Build the advisory.
    ///
    /// A `nil` probe is the app-level case — a browser was named but no window was,
    /// so no page URL was read. A probe whose URLs are all schemes Obscura cannot
    /// open (`chrome://`, `about:`, `devtools://`, an extension page, the built-in
    /// PDF viewer) keeps the disclosure and drops the recommendation: no `use`, no
    /// `url`, no `commands`. Naming a tool that will fail there is worse advice
    /// than naming none, and staying silent would let a model drive that page
    /// believing Proctor had nothing to say about it.
    public static func handoff(for browser: KnownBrowser, probe: WebContentProbe?,
                               detail: Detail) -> BrowserHandoff {
        var url: String?
        var unavailable: String?
        var openable = true

        if let probe {
            let distinct = distinctURLs(probe.rendered.compactMap(\.url))
            let web = distinct.filter { isWebScheme($0) }
            if !distinct.isEmpty && web.isEmpty {
                openable = false
                unavailable = notOpenable
            } else {
                switch web.count {
                case 0:  unavailable = urlAbsent
                case 1:  url = web[0]
                default: unavailable = severalURLs
                }
            }
        } else {
            unavailable = noWindowNamed
        }

        let note = url.map(isPrivateNetwork) == true ? privateNetworkNote : nil

        return BrowserHandoff(
            boundary: boundary,
            browser: browser.name,
            bundleId: browser.bundleId,
            use: openable ? "obscura" : nil,
            continuity: continuity,
            evidence: detail == .full ? evidence : nil,
            url: url,
            urlUnavailable: unavailable,
            note: note,
            commands: openable && detail == .full ? commands : nil,
            caveats: detail == .full ? caveats : nil)
    }

    /// Fold the availability of the tool the handoff names into the handoff.
    ///
    /// A recommendation to run `obscura` on a machine with no `obscura` is worse
    /// than no recommendation: the handoff reads as an instruction from something
    /// that knows what it is talking about, and the person following it gets a
    /// confusing shell error instead of a fact. So `use` and `commands` go, and
    /// `toolUnavailable` says why.
    ///
    /// `url` stays. The address is a fact about the page rather than a
    /// recommendation, and it is what makes the advice actionable the moment the
    /// install finishes. `boundary`, `continuity`, `evidence` and `caveats` stay
    /// too: which half of a browser window is Proctor's does not depend on what
    /// happens to be installed.
    ///
    /// A handoff that recommended nothing in the first place — a `chrome://` page,
    /// or any other scheme Obscura cannot open — is returned untouched. There was
    /// no recommendation to repair, and naming a missing tool that would not help
    /// this page anyway is noise.
    public static func withTool(_ handoff: BrowserHandoff, available: Bool,
                                absence: ToolAbsence) -> BrowserHandoff {
        guard !available, handoff.use != nil else { return handoff }
        var out = handoff
        out.use = nil
        out.commands = nil
        out.toolUnavailable = absence
        return out
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
