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
    /// Whether this browser's engine is Chromium. Load-bearing for the second
    /// lane and for nothing else: browser-use drives a real Chromium, so on a
    /// WebKit or Gecko window it would be driving a *different* browser with a
    /// different session — PRO-0020's "success against a window it never touched",
    /// one level out. A second fact per row that can drift (Opera and Edge have
    /// both changed engine); a wrong answer costs one lane recommendation for an
    /// internal page, which fails visibly.
    public let chromiumFamily: Bool
    public init(name: String, bundleId: String, chromiumFamily: Bool = false) {
        self.name = name; self.bundleId = bundleId; self.chromiumFamily = chromiumFamily
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

    /// Exact bundle identifiers, with whether the engine is Chromium.
    static let exact: [String: (name: String, chromium: Bool)] = [
        "com.apple.Safari": ("Safari", false),
        "com.apple.SafariTechnologyPreview": ("Safari Technology Preview", false),
        "org.chromium.Chromium": ("Chromium", true),
        "company.thebrowser.Browser": ("Arc", true),
        "com.kagi.kagimacOS": ("Orion", false),                 // WebKit
        "com.vivaldi.Vivaldi": ("Vivaldi", true),
        "app.zen-browser.zen": ("Zen", false),                  // Gecko
        "com.duckduckgo.macos.browser": ("DuckDuckGo", false),  // WebKit
        "com.operasoftware.Opera": ("Opera", true),
        "com.operasoftware.OperaGX": ("Opera GX", true),
        // Mozilla's developer channel runs the two words together rather than
        // adding a dotted segment, so the prefix rule below does not reach it and
        // it is named here. Matching on a bare prefix instead would sweep in
        // com.google.ChromeRemoteDesktop, which is not a browser.
        "org.mozilla.firefoxdeveloperedition": ("Firefox Developer Edition", false)
    ]

    /// Prefix rules, which is how a product's release channels are covered without
    /// enumerating every one: `com.google.Chrome.canary`, `com.brave.Browser.beta`,
    /// `com.microsoft.edgemac.Dev` and their siblings all resolve here — and
    /// inherit the rule's engine answer with them.
    static let prefixes: [(prefix: String, name: String, chromium: Bool)] = [
        ("com.google.Chrome", "Google Chrome", true),
        ("com.brave.Browser", "Brave", true),
        ("com.microsoft.edgemac", "Microsoft Edge", true),
        ("org.mozilla.firefox", "Firefox", false),
        ("org.mozilla.nightly", "Firefox Nightly", false)
    ]

    public static func identify(bundleId: String?) -> KnownBrowser? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        if let hit = exact[bundleId] {
            return KnownBrowser(name: hit.name, bundleId: bundleId, chromiumFamily: hit.chromium)
        }
        for rule in prefixes where bundleId == rule.prefix || bundleId.hasPrefix(rule.prefix + ".") {
            return KnownBrowser(name: rule.name, bundleId: bundleId, chromiumFamily: rule.chromium)
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
    /// Absent when there is nothing either lane can open — naming a tool that will
    /// fail on this page is worse than naming none.
    public var use: String?
    /// Which rule chose that lane, as a sentence. This is what makes the advice
    /// checkable rather than oracular: a reader who disagrees knows what to
    /// disagree with. Present at both detail levels whenever a lane is named,
    /// including for the default, because "no measured limit applies here" is a
    /// claim Proctor is making and should stand behind.
    public var why: String?
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

    public init(boundary: String, browser: String, bundleId: String, use: String?,
                why: String? = nil, continuity: String, evidence: String? = nil,
                url: String? = nil, urlUnavailable: String? = nil,
                toolUnavailable: ToolAbsence? = nil, notes: [String]? = nil,
                commands: [String]? = nil, caveats: [String]? = nil) {
        self.boundary = boundary; self.browser = browser; self.bundleId = bundleId
        self.use = use; self.why = why; self.continuity = continuity
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

    /// Schemes that name a page inside the browser itself. A list rather than a
    /// "not http(s)" negation, for the same reason the catalogue is a list: a
    /// negation sweeps in everything nobody thought about, and here the things
    /// nobody thought about — `file:`, `data:` — are the ones that would point an
    /// agent holding a live profile somewhere it should not go.
    ///
    /// **`about` is deliberately absent.** `about:blank` is the empty tab every
    /// browser opens, and starting an autonomous agent for one is absurd; it keeps
    /// PRO-0020's behaviour exactly.
    public static let internalSchemes = [
        "chrome", "chrome-extension", "chrome-untrusted", "chrome-search",
        "chrome-native", "chrome-error", "isolated-app",
        "devtools", "edge", "brave", "vivaldi", "opera", "arc"
    ]

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
                + "signed-in, tab or in-page state has to be re-established there."
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
        let d = decide(for: browser, probe: probe, lanes: lanes)
        let lane = d.lane

        return BrowserHandoff(
            boundary: boundary(for: lane ?? .obscura),
            browser: browser.name,
            bundleId: browser.bundleId,
            use: lane?.rawValue,
            why: lane == nil ? nil : d.why,
            continuity: continuity(for: lane ?? .obscura),
            evidence: detail == .full ? evidence : nil,
            url: d.url,
            urlUnavailable: d.urlUnavailable,
            toolUnavailable: d.toolUnavailable,
            notes: lane == .obscura ? notes(url: d.url) : nil,
            commands: lane.flatMap { detail == .full ? commands(for: $0) : nil },
            caveats: detail == .full ? caveats(for: lane ?? .obscura) : nil)
    }

    /// The ladder, in one place, in the order the spec states it. The conditions
    /// are complete and non-overlapping, so no catch-all can name a tool that is
    /// not there.
    static func decide(for browser: KnownBrowser, probe: WebContentProbe?,
                       lanes: BrowserLanes) -> Decision {
        // Rule 0 — what URL, if any, is this about.
        var url: String?
        var unavailable: String?
        var internalPage = false
        var otherScheme = false

        if let probe {
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
                    internalPage = true
                    url = distinct[0]
                } else {
                    otherScheme = true
                }
                unavailable = distinct.allSatisfy(isNotAPage) ? notAnInstrument
                    : (everyAreaSpoke ? notOpenable : partialURLs)
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

        // Rules 1-3 — the page's own scheme, when there is one. `url` survives
        // only where a lane can actually open it: PRO-0020 drops the address for a
        // page nothing here can reach, and that stays true.
        if internalPage || otherScheme {
            guard internalPage, browser.chromiumFamily else {
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
                                urlUnavailable: nil)
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
                            urlUnavailable: unavailable)
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
