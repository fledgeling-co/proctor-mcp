import Foundation

// What each control on the status window is called to something that cannot see
// it.
//
// Measured on the shipped window, 2026-08-19: `proctor_find` over the tree
// returned nine `AXCheckBox` elements with no title or label at all, and seven
// `AXButton` elements every one of which was called "Details". A screen reader
// reaching that surface is told there are sixteen controls and which one it is
// standing on for none of them.
//
// The rule lives here for the reason `StatusChecks` and `SwitchCatalogue` do:
// `Package.swift` declares no `ProctorUI` test target and `swift test` has no
// window server, so a name written inline in a view body is a name this repo
// cannot prove. The window renders what these functions return, and the tests
// hold the property that matters: on one surface, no two controls answer to the
// same name.
public enum AccessibilityNames {

    /// A switch's toggle. The title alone, because the variable is already its
    /// own element beside it and reading both would say every row twice.
    public static func switchToggle(title: String) -> String { title }

    /// The disclosure beside a tool row. "Details" is what the button says; the
    /// tool is what makes it answerable.
    public static func toolDisclosure(tool: String, expanded: Bool) -> String {
        "\(expanded ? "Hide" : "Show") details for \(tool)"
    }

    /// The two controls that repeat down the permissions list.
    public static func grantAction(_ action: GrantAction, grant: String) -> String {
        switch action {
        case .openSettings: return "Open Settings for \(grant)"
        case .how:          return "How to grant \(grant)"
        case .hideHow:      return "Hide how to grant \(grant)"
        }
    }

    public enum GrantAction: Sendable, Equatable, CaseIterable {
        case openSettings, how, hideHow
    }

    /// Whether a set of names can be told apart. The property the window has to
    /// keep, stated once so a test can hold it over the real catalogue rather
    /// than over an example.
    public static func allDistinct(_ names: [String]) -> Bool {
        !names.contains(where: \.isEmpty) && Set(names).count == names.count
    }
}
