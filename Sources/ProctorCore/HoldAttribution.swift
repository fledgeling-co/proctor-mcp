import Foundation

// Who a hold belongs to.
//
// PRO-0018 taught a run to get out of the way when a person takes the machine
// back, and could say why but not whose. On a Mac running one session that is
// enough; on one running three it is the wrong half of the information — the
// menu bar shows the highest-precedence hold across every run and the queue bar
// has the rows, and nothing joined the two.
//
// This is the join, as a value: a hold, the session that read it, the
// application it was driving and the display that application was on. Pure, so
// the display arithmetic and the wording are provable with no window attached,
// which is the only way either gets tested at all.
//
// EVERY PART OF IT IS DERIVED. The session label comes from the peer process —
// never from anything the client said about itself — because a connection that
// could name itself could impersonate another one in the very UI a person uses
// to decide whether to stop it. The display comes from the driven window's own
// frame. Nothing here takes a name from the wire.

/// Which screen a hold belongs to.
///
/// Named plainly rather than by product. CoreGraphics gives bounds and an id;
/// a display's marketing name needs a main-actor hop into AppKit, and it is not
/// what somebody wants in a one-line hold anyway — "the main display" answers
/// "where do I look" and a model number does not.
public struct HoldDisplay: Codable, Sendable, Equatable {
    /// Index into the screen list the caller supplied, so the caller keeps its
    /// own handles — the same contract `RunHUDPlacement` uses.
    public var index: Int
    public var isMain: Bool
    public var name: String

    public init(index: Int, isMain: Bool, name: String) {
        self.index = index
        self.isMain = isMain
        self.name = name
    }

    /// `the main display`, or `display 2`. One-based for a person, because
    /// nobody calls their second screen "display 1".
    public static func name(index: Int, isMain: Bool) -> String {
        isMain ? "the main display" : "display \(index + 1)"
    }
}

/// One hold, attributed.
public struct HoldAttribution: Codable, Sendable, Equatable {
    public var reason: YieldReason
    /// `RunSessionIdentity.label` — `proctor-mcp a3f1`. Derived from the peer
    /// process, never supplied.
    public var session: String
    /// The application the held run was driving, when one is known.
    public var app: String?
    public var display: HoldDisplay?

    public init(reason: YieldReason, session: String, app: String? = nil,
                display: HoldDisplay? = nil) {
        self.reason = reason
        self.session = session
        self.app = app
        self.display = display
    }

    /// The whole sentence, composed here so one table owns the wording.
    ///
    /// `reason.line` is PRO-0018's settled vocabulary and is not rewritten — the
    /// panel's live line says exactly this much on its own, and what is added is
    /// only the part the live line has no room for.
    ///
    /// It degrades by dropping clauses rather than by printing an absence. A
    /// hold whose app could not be resolved says less; it never says "nil".
    public var line: String {
        var out = "\(reason.line) — \(session)"
        if let app, !app.isEmpty { out += " · \(app)" }
        if let display { out += " on \(display.name)" }
        return out
    }

    /// Which display a driven window is on.
    ///
    /// `RunHUDPlacement.screenIndex` is reused rather than re-derived: it already
    /// answers "which screen holds most of this rect", already falls back to the
    /// nearest for a window on a display that has just been unplugged, and is
    /// already tested with nothing plugged in. A second copy of that arithmetic
    /// here would be a second thing to keep true.
    ///
    /// `mainIndex` is the caller's, from `CGMainDisplayID()`, because Core does
    /// not read CoreGraphics.
    public static func display(for window: Rect?, in screens: [Rect],
                               mainIndex: Int?) -> HoldDisplay? {
        guard !screens.isEmpty,
              let index = RunHUDPlacement.screenIndex(for: window, in: screens) else { return nil }
        let isMain = mainIndex == index
        return HoldDisplay(index: index, isMain: isMain,
                           name: HoldDisplay.name(index: index, isMain: isMain))
    }
}
