import Foundation
import ProctorCore

/// The tri-observer surface the assertion handler needs: the three assertions
/// that cannot be answered from the accessibility tree alone.
///
/// It is a protocol rather than a concrete dependency because the honest
/// behaviour when no implementation is wired is to report those assertions
/// `skipped`, and only an optional can express that. A concrete type would have
/// to invent an answer.
protocol TriObserving: AnyObject, Sendable {
    /// Compare what the accessibility tree, the geometry source and the pixels
    /// say about the same instant, and return the deltas as findings.
    func agree(window: WindowHandle, tree: AXNode) async throws -> [Disagreement]

    /// Contrast ratio of the node's foreground against its background, read
    /// from pixels.
    func contrast(window: WindowHandle, node: AXNode) async throws -> Double

    /// The node's effective hit area — its frame reduced by occlusion and
    /// clipping — which is what a minimum-target-size check is actually about.
    func hitSize(window: WindowHandle, node: AXNode) async throws -> Rect
}
