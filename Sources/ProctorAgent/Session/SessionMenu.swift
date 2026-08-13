import Foundation
import ProctorCore

// proctor_menu: enumerate an attached app's menu bar with reconstructed
// key-equivalents. A pure accessibility read — the AX walk lives in MenuBarReader
// and the shortcut reconstruction in ProctorCore's MenuKeyEquivalent; this method
// only resolves the target app and shapes the response.

extension Session {

    func menuBar(app appId: String?, window windowId: String?) throws -> JSONValue {
        let resolvedApp: String
        if let appId, !appId.isEmpty {
            resolvedApp = appId
        } else if let windowId, !windowId.isEmpty {
            resolvedApp = try windowHandle(windowId).app
        } else {
            throw AgentError(
                code: .invalidArguments,
                message: "proctor_menu needs app or window",
                remedy: "Pass an app handle from proctor_apps (action \"attach\"), or a window "
                      + "handle whose owning app is read.")
        }

        guard let raw = try ax.menuBar(app: resolvedApp) else {
            throw AgentError(
                code: .actionUnsupported,
                message: "this application exposes no menu bar",
                remedy: "Agent-style and menu-bar-extra apps have no application menu bar; drive "
                      + "them through proctor_act accessibility steps instead.")
        }

        let items = MenuKeyEquivalent.flatten(bar: raw)
        var out: [String: JSONValue] = [
            "app": .string(resolvedApp),
            "itemCount": .number(Double(items.count)),
            "items": .array(try items.map { try JSONValue.encode($0) })
        ]
        // Only speak to lazy submenus when there actually is one, so a fully-read
        // menu bar carries no distracting caveat.
        if items.contains(where: { $0.hasSubmenu && !$0.submenuPopulated }) {
            out["note"] = .string(
                "Some submenus populate only when opened and are reported with submenuPopulated "
                + "false; open one with a menu or press step and re-read to see its contents.")
        }
        return .object(out)
    }
}
