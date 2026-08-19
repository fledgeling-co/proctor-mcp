import Foundation

// PRO-0065. What the fidelity harness can settle, as a value.
//
// The mock at `design/surfaces/proctor-surfaces.html` is the reference and the
// built app is the target, and the burden of proof is inverted: a difference is
// a defect until a citation proves it intentional. That discipline is
// mockup-fidelity's and it transfers here intact — but its instrument does not,
// and the gap is the whole reason this file exists.
//
// **A DOM differ cannot see SwiftUI, and neither can the Reflector, entirely.**
// macOS has no cross-process computed-style API (see docs/architecture.md), and
// `ProctorReflector`'s own README is explicit that an `NSHostingView` subtree
// walks as ordinary `NSView`s with no supported way to read a resolved SwiftUI
// modifier value from outside the framework. So a property this harness cannot
// read must resolve to `inconclusive` **by construction** rather than by a
// caller remembering to check — because a property the walker never saw and a
// property that matched look identical in a passing report, and that is the
// failure this whole item exists to prevent.

/// Which instrument can settle a class of property, and what it costs to trust.
public enum FidelityChannel: String, Sendable, CaseIterable {
    /// The accessibility tree. Durable, complete, and the same channel Proctor
    /// uses on other people's software.
    case tree
    /// `proctor_inspect` through an embedded Reflector. Reads AppKit views and
    /// resolved `CALayer` values, so it settles a SwiftUI property only where
    /// SwiftUI materialised it into a layer.
    case layer
    /// A window capture carrying `SCFrameStatus`, compared against a reference.
    case pixels
    /// Nothing here can settle it.
    case none
}

/// A class of property a surface can be compared on.
public enum FidelityProperty: String, Sendable, CaseIterable {
    case identifier, role, label, enabled, focused
    case frame, hitSize, alignment
    case cornerRadius, layerOpacity, layerBackground
    case fontFamily, fontSize, fontWeight, textColour
    /// A value SwiftUI resolves internally and never puts in a layer — spacing
    /// between stacked views, a `.padding` modifier, a shape style behind a
    /// material. Named rather than omitted, so the table says so out loud.
    case swiftUIModifier
    case renderedAppearance
}

public extension FidelityChannel {

    /// The channel that settles a property, or `.none`.
    ///
    /// `layer` is deliberately not promised as complete: it settles these
    /// properties **when** SwiftUI materialised them, and `FidelityVerdict`
    /// carries the not-materialised case for when it did not.
    static func settling(_ property: FidelityProperty) -> FidelityChannel {
        switch property {
        case .identifier, .role, .label, .enabled, .focused:
            return .tree
        case .frame, .hitSize, .alignment:
            return .tree
        case .cornerRadius, .layerOpacity, .layerBackground,
             .fontFamily, .fontSize, .fontWeight, .textColour:
            return .layer
        case .renderedAppearance:
            return .pixels
        case .swiftUIModifier:
            return .none
        }
    }
}

/// Why a comparison could not be made. Never a synonym for agreement.
public enum InconclusiveReason: String, Sendable, Equatable {
    /// No channel settles this property class at all.
    case noChannel
    /// The channel exists but SwiftUI did not put the value in a layer.
    case notMaterialisedInLayer
    /// The app is not running a Reflector — a release build, by design.
    case reflectorUnavailable
    /// The capture did not come back with a trustworthy frame.
    case frameNotComplete
    /// The mock has no counterpart for this element.
    case noAnchor
}

public enum FidelityVerdict: Sendable, Equatable {
    case matches(FidelityProperty)
    case differs(FidelityProperty, expected: String, measured: String)
    case inconclusive(FidelityProperty, InconclusiveReason)

    /// Only a genuine match counts as one. An inconclusive verdict is not a pass
    /// and there is no accessor that lets a caller treat it as one.
    public var isMatch: Bool {
        if case .matches = self { return true }
        return false
    }

    public var isInconclusive: Bool {
        if case .inconclusive = self { return true }
        return false
    }
}

/// One surface of the design of record, and the built surface converting it.
public struct SurfaceAnchor: Sendable, Equatable {
    /// The fragment in `design/surfaces/proctor-surfaces.html`, e.g. `mac/status/ready`.
    public let anchor: String
    /// The accessibility identifier the converted SwiftUI surface sets.
    public let identifier: String
    /// The wave item converting it.
    public let item: String

    public init(anchor: String, identifier: String, item: String) {
        self.anchor = anchor; self.identifier = identifier; self.item = item
    }
}

public enum SurfaceFidelity {

    /// Every mock surface, and the identifier of the surface converting it.
    ///
    /// An anchor whose identifier is absent from the built app fails, and that
    /// is what stops a surface being quietly skipped: the table is the
    /// enumeration, so a conversion that forgot a state cannot pass by omission.
    public static let anchors: [SurfaceAnchor] = [
        .init(anchor: "mac/walkthrough/intro",       identifier: "proctor.walkthrough.intro",       item: "PRO-0067"),
        .init(anchor: "mac/walkthrough/permissions", identifier: "proctor.walkthrough.permissions", item: "PRO-0067"),
        .init(anchor: "mac/walkthrough/granted",     identifier: "proctor.walkthrough.granted",     item: "PRO-0067"),
        .init(anchor: "mac/walkthrough/connect",     identifier: "proctor.walkthrough.connect",     item: "PRO-0067"),
        .init(anchor: "mac/status/ready",            identifier: "proctor.status.ready",            item: "PRO-0066"),
        .init(anchor: "mac/status/checking",         identifier: "proctor.status.checking",         item: "PRO-0066"),
        .init(anchor: "mac/status/partial",          identifier: "proctor.status.partial",          item: "PRO-0066"),
        .init(anchor: "mac/status/down",             identifier: "proctor.status.down",             item: "PRO-0066"),
        .init(anchor: "mac/menubar/idle",            identifier: "proctor.menubar.idle",            item: "PRO-0068"),
        .init(anchor: "mac/menubar/running",         identifier: "proctor.menubar.running",         item: "PRO-0068"),
        .init(anchor: "mac/menubar/foreground",      identifier: "proctor.menubar.foreground",      item: "PRO-0068"),
        .init(anchor: "mac/menubar/down",            identifier: "proctor.menubar.down",            item: "PRO-0068"),
        .init(anchor: "mac/menus/all",               identifier: "proctor.menus.all",               item: "PRO-0068"),
        .init(anchor: "mac/hud/idle",                identifier: "proctor.hud.idle",                item: "PRO-0069"),
        .init(anchor: "mac/hud/travelling",          identifier: "proctor.hud.travelling",          item: "PRO-0069"),
        .init(anchor: "mac/hud/acting",              identifier: "proctor.hud.acting",              item: "PRO-0069"),
        .init(anchor: "mac/hud/blocked",             identifier: "proctor.hud.blocked",             item: "PRO-0069"),
        .init(anchor: "mac/hud/paused",              identifier: "proctor.hud.paused",              item: "PRO-0069"),
        .init(anchor: "mac/hud/finished",            identifier: "proctor.hud.finished",            item: "PRO-0069"),
        .init(anchor: "mac/hud/error",               identifier: "proctor.hud.error",               item: "PRO-0069"),
        .init(anchor: "mac/takeover/armed",          identifier: "proctor.takeover.armed",          item: "PRO-0070"),
        .init(anchor: "mac/takeover/guest",          identifier: "proctor.takeover.guest",          item: "PRO-0070"),
        .init(anchor: "mac/history/ideal",           identifier: "proctor.history.ideal",           item: "PRO-0071"),
        .init(anchor: "mac/history/empty",           identifier: "proctor.history.empty",           item: "PRO-0071"),
        .init(anchor: "mac/consent/input",           identifier: "proctor.consent.input",           item: "PRO-0072"),
        .init(anchor: "mac/consent/pairing",         identifier: "proctor.consent.pairing",         item: "PRO-0072"),
        .init(anchor: "mac/consent/lane",            identifier: "proctor.consent.lane",            item: "PRO-0072"),
        .init(anchor: "mac/consent/unlock",          identifier: "proctor.consent.unlock",          item: "PRO-0072"),
    ]

    public static func anchor(for identifier: String) -> SurfaceAnchor? {
        anchors.first { $0.identifier == identifier }
    }

    public static func anchors(forItem item: String) -> [SurfaceAnchor] {
        anchors.filter { $0.item == item }
    }

    /// Compare one property, given what each channel could see.
    ///
    /// The signature is the guarantee: a property whose channel is `.none` can
    /// never reach `.matches`, because the caller has no way to supply a
    /// measurement for it. Correctness here is structural rather than a rule
    /// somebody has to remember.
    public static func compare(_ property: FidelityProperty,
                               expected: String,
                               measured: String?,
                               reflectorRunning: Bool = true,
                               frameComplete: Bool = true) -> FidelityVerdict {
        let channel = FidelityChannel.settling(property)
        switch channel {
        case .none:
            return .inconclusive(property, .noChannel)
        case .layer where !reflectorRunning:
            return .inconclusive(property, .reflectorUnavailable)
        case .pixels where !frameComplete:
            return .inconclusive(property, .frameNotComplete)
        default:
            break
        }
        guard let measured else {
            // The channel was available and returned nothing for this property.
            // For the layer channel that means SwiftUI never materialised it,
            // which is the common case and is not a defect in the build.
            return .inconclusive(property, channel == .layer ? .notMaterialisedInLayer : .noChannel)
        }
        return measured == expected
            ? .matches(property)
            : .differs(property, expected: expected, measured: measured)
    }

    /// A run's summary. `matched` counts only genuine matches; inconclusive
    /// results are carried separately and never folded into a pass rate.
    public struct Report: Sendable, Equatable {
        public var matched: Int = 0
        public var differed: Int = 0
        public var inconclusive: Int = 0

        public var isClean: Bool { differed == 0 }
        /// Deliberately not a percentage of the total: a denominator that
        /// includes what could not be measured reports coverage it never had.
        public var measured: Int { matched + differed }
    }

    public static func summarise(_ verdicts: [FidelityVerdict]) -> Report {
        var r = Report()
        for v in verdicts {
            switch v {
            case .matches: r.matched += 1
            case .differs: r.differed += 1
            case .inconclusive: r.inconclusive += 1
            }
        }
        return r
    }
}
