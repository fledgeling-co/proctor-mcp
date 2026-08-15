import Foundation

// PRO-0044, slice 3. Turning "the element Proctor resolved" into "the element a
// delegated backend is holding", without either side having to trust the other.
//
// This is pure and lives here rather than in the agent for two reasons. The
// dependency graph is the smaller one: `ProctorCoreTests` links Core alone, so a
// matcher defined in the agent could not be unit-tested against a table of
// candidates. The larger one is that the matching rules are the whole of what
// makes a delegated replay mean anything, and they deserve to be exercised
// exhaustively rather than through a subprocess.
//
// **The join key cannot be the durable one.** Apple documents
// `accessibilityIdentifier` as the attribute meant for testing — developer-set,
// invisible to the user — and Proctor reads it. A driver whose per-element
// record carries role, label, value, frame, parent index and depth has no field
// to compare it against. A cascade that starts with an identifier the other side
// does not have collapses, in one step, to matching on a rectangle, and matching
// on a rectangle is coordinate addressing wearing a different hat: it survives a
// replay by striking absolute positions, which is precisely what a layout change
// breaks.
//
// So the key is structural. `(role, label)` at the target, and the same pair for
// each ancestor up to the window, is a chain the other side can reconstruct from
// the parent index it does publish. Two "OK" buttons in one window differ by
// their chains; two that do not differ by their chains are genuinely ambiguous,
// and this file says so rather than picking one.

/// What Proctor knows about an element it resolved through its own tree, reduced
/// to the parts a second observer could also see.
public struct ElementIdentity: Sendable, Equatable {
    /// The `(role, label)` pairs from the window down to the element itself,
    /// target last. The join key.
    public var chain: [ElementStep]
    /// Read, recorded, and never used to match — see the note above. It is the
    /// best thing Proctor has for picking the right element on its OWN side, and
    /// a flow records it so a replay keeps it, but it cannot cross this boundary.
    public var axIdentifier: String?
    public var subrole: String?
    /// Corroborates a match. Never decides one alone.
    public var frame: Rect?

    public init(chain: [ElementStep], axIdentifier: String? = nil,
                subrole: String? = nil, frame: Rect? = nil) {
        self.chain = chain
        self.axIdentifier = axIdentifier
        self.subrole = subrole
        self.frame = frame
    }

    public var role: String? { chain.last?.role }
    public var label: String? { chain.last?.label }

    /// Build an identity for a node by finding it in a walked tree.
    ///
    /// The chain has to come from a downward walk because `AXNode` carries no
    /// parent link — a deliberate shape, since a tree that already holds its
    /// children needs no back-edges — so the ancestry is the path the search
    /// took to reach the node. Pure, and over a tree the session has already
    /// walked, so it costs no accessibility round trips.
    ///
    /// Nil when the node is not in this tree, rather than a partial identity:
    /// what survives after role and label is the frame, and a backend handed
    /// only a frame would match on position, which is the one thing the matcher
    /// refuses to do.
    public static func of(nodeID: String, in root: AXNode) -> ElementIdentity? {
        var path: [AXNode] = []
        guard find(nodeID, in: root, path: &path) else { return nil }
        guard let node = path.last else { return nil }
        return ElementIdentity(
            chain: path.map { ElementStep(role: $0.role, label: $0.label ?? $0.title) },
            axIdentifier: node.identifier,
            subrole: node.subrole,
            frame: node.frame)
    }

    private static func find(_ id: String, in node: AXNode, path: inout [AXNode]) -> Bool {
        path.append(node)
        if node.id == id { return true }
        for child in node.children ?? [] where find(id, in: child, path: &path) {
            return true
        }
        path.removeLast()
        return false
    }
}

/// One rung of the chain.
public struct ElementStep: Sendable, Equatable {
    public var role: String
    /// Title, description or value — whichever the observer uses as the visible
    /// name. Nil where an element has none, which is common for containers and
    /// is why a chain rung matches on role alone when both sides say nil.
    public var label: String?

    public init(role: String, label: String? = nil) {
        self.role = role
        self.label = label
    }
}

/// An element as a delegated backend reports it: a flat list with parent links,
/// which is the shape a driver that returns an indexed tree produces.
public struct ElementCandidate: Sendable, Equatable {
    public var index: Int
    public var role: String
    public var label: String?
    public var frame: Rect?
    /// Index of this element's parent in the same list, or nil at the root.
    public var parentIndex: Int?
    public var depth: Int

    public init(index: Int, role: String, label: String? = nil, frame: Rect? = nil,
                parentIndex: Int? = nil, depth: Int = 0) {
        self.index = index
        self.role = role
        self.label = label
        self.frame = frame
        self.parentIndex = parentIndex
        self.depth = depth
    }
}

public enum ElementMatchOutcome: Sendable, Equatable {
    /// Exactly one candidate carries the identity's chain.
    case matched(Int)
    /// Several did, or the view was truncated so uniqueness could not be
    /// established at all. Both refuse; neither is "it is not there".
    case ambiguous(reason: String, candidates: [Int])
    /// The view was complete and nothing in it carries the chain.
    case absent
}

public enum ElementMatch {

    /// How much two rectangles must overlap before they are believed to be the
    /// same element seen twice. Half is deliberately loose: two observers reading
    /// the same window disagree by a point or two at the edges and by more when
    /// one of them measured before a relayout, and a threshold tight enough to
    /// catch that would refuse working steps. It is tight enough for its actual
    /// job, which is catching a candidate in a different place on the screen.
    public static let frameAgreementThreshold = 0.5

    /// Find the candidate that carries this identity.
    ///
    /// `truncated` is a parameter rather than something inferred, because a
    /// backend that caps its snapshot by node count or depth returns a list in
    /// which the real target may simply be missing while a namesake survives.
    /// Reporting that as `absent` would say "it is not there" when the honest
    /// answer is "I could not finish looking", and the two lead a caller to
    /// opposite conclusions.
    public static func match(identity: ElementIdentity,
                             candidates: [ElementCandidate],
                             truncated: Bool = false) -> ElementMatchOutcome {
        guard !identity.chain.isEmpty else {
            return .ambiguous(reason: "the element carries no identity to match on",
                              candidates: [])
        }

        let byIndex = Dictionary(uniqueKeysWithValues: candidates.map { ($0.index, $0) })
        var hits = candidates.filter { carriesChain($0, identity.chain, byIndex) }

        if hits.isEmpty {
            // Nothing matched. Whether that means "absent" depends entirely on
            // whether the whole tree was on offer.
            return truncated
                ? .ambiguous(reason: "the backend's view of the window was truncated, so the "
                           + "element may have been cut from it rather than missing from it",
                             candidates: [])
                : .absent
        }
        if hits.count == 1 { return .matched(hits[0].index) }

        // Several carry the same chain. The frame may separate them — but a set
        // that ONLY the frame separates is a set being told apart by position,
        // which is the one thing this file will not do. So the frame narrows
        // only when it narrows to exactly one, and the refusal says why.
        if let frame = identity.frame {
            let near = hits.filter { candidate in
                guard let other = candidate.frame else { return false }
                return overlap(frame, other) >= frameAgreementThreshold
            }
            if near.count == 1 {
                return .ambiguous(
                    reason: "several elements carry the same role and label under the same "
                          + "parent, and only their positions differ, so the match would rest "
                          + "on a coordinate",
                    candidates: hits.map(\.index).sorted())
            }
        }
        hits.sort { $0.index < $1.index }
        return .ambiguous(reason: "several elements carry the same identity chain",
                          candidates: hits.map(\.index))
    }

    /// Do the two observers describe the same element? Role and label equal, and
    /// frames that overlap enough to be the same rectangle seen twice.
    ///
    /// This is the check that covers the FIRST attempt. A handle that goes stale
    /// raises an error a caller can retry, but a tree that mutates while the
    /// backend's view of it is still current raises nothing at all: the slot the
    /// handle points at simply has a new occupant. Retrying correctly protects
    /// the second attempt and not the one that did the damage, so the guard has
    /// to be an agreement test before the strike rather than an error test after.
    public static func agrees(identity: ElementIdentity,
                              candidate: ElementCandidate) -> Bool {
        guard identity.role == candidate.role else { return false }
        guard identity.label == candidate.label else { return false }
        guard let mine = identity.frame, let theirs = candidate.frame else {
            // Neither side offering a frame is not a disagreement. One side
            // offering one and the other not is also not: an element with no
            // geometry is a real thing, and refusing every one of them would
            // refuse most menu items.
            return true
        }
        return overlap(mine, theirs) >= frameAgreementThreshold
    }

    // MARK: - Internals

    private static func carriesChain(_ candidate: ElementCandidate,
                                     _ chain: [ElementStep],
                                     _ byIndex: [Int: ElementCandidate]) -> Bool {
        var rung = chain.count - 1
        var current: ElementCandidate? = candidate
        while rung >= 0, let node = current {
            let want = chain[rung]
            guard node.role == want.role, node.label == want.label else { return false }
            rung -= 1
            current = node.parentIndex.flatMap { byIndex[$0] }
        }
        // Every rung consumed. A chain deeper than the candidate's ancestry runs
        // out of parents first and fails, which is right: it is a different
        // element that happens to share a suffix.
        return rung < 0
    }

    /// Intersection over the smaller rectangle, so a small control inside a big
    /// container reads as agreement when it is genuinely the same element, and a
    /// container is not credited with containing something it merely overlaps.
    static func overlap(_ a: Rect, _ b: Rect) -> Double {
        let x = max(0, min(a.x + a.w, b.x + b.w) - max(a.x, b.x))
        let y = max(0, min(a.y + a.h, b.y + b.h) - max(a.y, b.y))
        let intersection = x * y
        let smaller = min(a.w * a.h, b.w * b.h)
        guard smaller > 0 else { return intersection > 0 ? 1 : 0 }
        return intersection / smaller
    }
}
