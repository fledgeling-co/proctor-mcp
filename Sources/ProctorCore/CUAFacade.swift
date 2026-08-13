import Foundation

// The CUA (computer-use agent) schema façade, translation half.
//
// A model trained on Anthropic's `computer` tool, or OpenAI's `openai_computer`
// batched tool, emits actions in a fixed schema — `left_click` at a coordinate,
// `type` some text, `key` an xdotool combo. This file maps those actions onto
// Proctor's own ActionStep vocabulary so such a model drives Proctor unmodified.
// It is deliberately pure: given an action and the target window's frame it
// yields a plan, with no side effects and no dependency on the agent. That is
// what makes the mapping testable in isolation, and the mapping is the whole
// feature — everything downstream is the existing act/capture machinery.
//
// Two facts shape every mapping here:
//
//  - CUA coordinates are relative to the screenshot the model was shown. The
//    façade screenshots a single window, so the origin is that window's
//    top-left. Proctor synthetic events take global screen points, so a CUA
//    point is mapped `global = windowOrigin + cuaPoint / scale`.
//  - The mapped kinds (click, hover, dragPath, key) are Proctor's synthetic
//    kinds, which only travel through the foreground event stream. A façade run
//    is frontmost-screen driving by definition, so this is correct — and it is
//    reported honestly as `plane: syntheticEvent`, never dressed up as a
//    background-safe result.

public enum CUASchema: String, Sendable, Codable {
    case anthropic
    case openai
}

/// One CUA action translated to a single unit of work. An action can expand to
/// several steps (a double-click is two clicks), so a translation is always a
/// list of these.
public struct CUAStep: Sendable {
    public enum Operation: Sendable {
        case act(ActionStep)     // run through the act path — settle, hash, plane and all
        case screenshot          // map to proctor_capture on the target window
        case wait(ms: Int)       // a bounded pause; the app is left to settle
    }
    public var operation: Operation
    /// The CUA action name, carried into the result so a façade-driven run is
    /// auditable against the schema it claimed to speak.
    public var action: String
    /// What the action became, in one human-readable line.
    public var summary: String

    public init(operation: Operation, action: String, summary: String) {
        self.operation = operation
        self.action = action
        self.summary = summary
    }
}

public enum CUATranslator {

    // MARK: - Coordinate mapping

    /// A CUA point (window-relative, in the screenshot's own space) to a global
    /// screen point. `scale` divides the CUA offset first, so a model handed a
    /// 2x screenshot still lands on the right point.
    public static func globalPoint(_ p: [Double], in frame: Rect, scale: Double) -> [Double] {
        let s = scale > 0 ? scale : 1
        return [frame.x + p[0] / s, frame.y + p[1] / s]
    }

    // MARK: - Key parsing

    private static let modifierTokens: Set<String> = [
        "ctrl", "control", "alt", "option", "opt", "shift",
        "cmd", "command", "meta", "super", "fn", "function"
    ]

    /// Normalise one modifier token to Proctor's modifier vocabulary
    /// (KeyCodes.modifiers). Returns nil for a token that is not a modifier.
    private static func canonicalModifier(_ token: String) -> String? {
        switch token {
        case "ctrl", "control": return "ctrl"
        case "alt", "option", "opt": return "alt"
        case "shift": return "shift"
        case "cmd", "command", "meta", "super": return "cmd"
        case "fn", "function": return "fn"
        default: return nil
        }
    }

    /// Normalise a key token to a name KeyCodes will recognise. xdotool and CUA
    /// harnesses spell keys as `Return`, `Page_Down`, `BackSpace`; Proctor's
    /// table is lower-case and unpunctuated, so `page_down` and `pagedown` both
    /// have to land on the same key.
    private static func canonicalKey(_ token: String) -> String {
        let lower = token.lowercased()
        switch lower {
        case "return", "enter", "\n": return "return"
        case "esc", "escape": return "escape"
        case "del", "delete": return "delete"
        case "backspace", "back_space": return "backspace"
        case "page_up", "pageup", "pgup", "prior": return "pageup"
        case "page_down", "pagedown", "pgdn", "next": return "pagedown"
        case "arrowleft", "arrow_left": return "left"
        case "arrowright", "arrow_right": return "right"
        case "arrowup", "arrow_up": return "up"
        case "arrowdown", "arrow_down": return "down"
        default:
            // Strip separators a harness may use, e.g. a stray underscore, but
            // keep single punctuation keys ("-", "/") intact.
            return lower.count > 1 ? lower.replacingOccurrences(of: "_", with: "") : lower
        }
    }

    /// An xdotool-style combo ("ctrl+s", "cmd+shift+t", "Return") to a key name
    /// plus its modifiers. The last `+`-separated token is the key; the rest are
    /// modifiers. A token that is a modifier name is never treated as the key
    /// unless it is the only one.
    public static func parseKeyCombo(_ combo: String) -> (key: String, modifiers: [String]) {
        let tokens = combo.split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return partition(tokens)
    }

    /// An OpenAI `keypress` keys array (["ctrl","c"], ["ENTER"]) to a key name
    /// plus its modifiers.
    public static func parseKeys(_ keys: [String]) -> (key: String, modifiers: [String])? {
        let tokens = keys.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard !tokens.isEmpty else { return nil }
        return partition(tokens)
    }

    /// Split tokens into (key, modifiers). The key is the last non-modifier
    /// token; if every token is a modifier, the last token is the key so a bare
    /// modifier press still resolves to something. Modifiers are de-duplicated
    /// in first-seen order.
    private static func partition(_ tokens: [String]) -> (key: String, modifiers: [String]) {
        guard !tokens.isEmpty else { return ("", []) }
        let nonMods = tokens.filter { !modifierTokens.contains($0) }
        let keyToken: String
        let modSource: [String]
        if let last = nonMods.last {
            keyToken = last
            modSource = tokens.filter { modifierTokens.contains($0) }
        } else {
            keyToken = tokens.last!
            modSource = Array(tokens.dropLast())
        }
        var mods: [String] = []
        var seen = Set<String>()
        for token in modSource {
            if let m = canonicalModifier(token), seen.insert(m).inserted { mods.append(m) }
        }
        return (canonicalKey(keyToken), mods)
    }

    // MARK: - Anthropic `computer`

    /// Translate one Anthropic `computer` action. One action yields one or more
    /// steps: `double_click` is two clicks, `triple_click` three.
    public static func anthropic(_ action: JSONValue, windowFrame: Rect,
                                 scale: Double = 1) throws -> [CUAStep] {
        guard let name = action["action"]?.stringValue ?? action["type"]?.stringValue else {
            throw invalid("an Anthropic computer action needs an `action` field",
                          remedy: "Send the stock schema, e.g. {\"action\":\"left_click\",\"coordinate\":[x,y]}.")
        }

        switch name {
        case "screenshot":
            return [CUAStep(operation: .screenshot, action: name,
                            summary: "screenshot → window capture")]

        case "cursor_position":
            // A read that returns the pointer location. The façade tracks no
            // cursor, so it cannot answer, and a made-up coordinate is worse
            // than a clear refusal.
            throw unsupported(name, why: "the façade tracks no cursor position",
                              child: "cursor tracking")

        case "wait":
            let ms = durationMs(action)
            return [CUAStep(operation: .wait(ms: ms), action: name,
                            summary: "wait \(ms)ms")]

        case "type":
            let text = action["text"]?.stringValue ?? ""
            return [CUAStep(operation: .act(ActionStep(kind: .type, text: text)),
                            action: name, summary: "type \(text.debugDescription)")]

        case "key":
            guard let combo = action["text"]?.stringValue, !combo.isEmpty else {
                throw invalid("Anthropic `key` needs `text` with the key combo",
                              remedy: "e.g. {\"action\":\"key\",\"text\":\"ctrl+s\"}.")
            }
            let (key, mods) = parseKeyCombo(combo)
            return [CUAStep(operation: .act(ActionStep(kind: .key, key: key, modifiers: mods)),
                            action: name,
                            summary: "key \(combo.debugDescription) → \(key)\(mods.isEmpty ? "" : " + " + mods.joined(separator: "+"))")]

        case "mouse_move":
            let g = try point(action, windowFrame: windowFrame, scale: scale, for: name)
            return [CUAStep(operation: .act(ActionStep(kind: .hover, point: g)),
                            action: name, summary: "mouse_move → hover at \(fmt(g))")]

        case "left_click":
            let g = try point(action, windowFrame: windowFrame, scale: scale, for: name)
            return [clickStep(at: g, action: name, count: 1)]

        case "double_click":
            let g = try point(action, windowFrame: windowFrame, scale: scale, for: name)
            return clicks(at: g, action: name, count: 2)

        case "triple_click":
            let g = try point(action, windowFrame: windowFrame, scale: scale, for: name)
            return clicks(at: g, action: name, count: 3)

        case "right_click", "middle_click":
            // Proctor's synthetic click is left-button only (Actuator.pointer
            // posts on .left). Left-clicking where a right-click was asked opens
            // the wrong thing, so this refuses rather than mis-actuates.
            throw unsupported(name, why: "Proctor synthetic click is left-button only",
                              child: "non-left mouse buttons")

        case "left_click_drag":
            return [try dragStep(action, windowFrame: windowFrame, scale: scale, for: name)]

        case "scroll":
            return [try anthropicScroll(action, for: name)]

        default:
            throw unsupported(name, why: "no mapping onto a Proctor step",
                              child: "action \(name)")
        }
    }

    // MARK: - OpenAI `openai_computer`

    /// Translate an OpenAI computer-use payload: a single action object, or a
    /// batch array. The batch is flattened into one plan; the caller runs it and
    /// stops on the first failure, which is the zavora/OpenAI shape.
    public static func openai(_ payload: JSONValue, windowFrame: Rect,
                              scale: Double = 1) throws -> [CUAStep] {
        let actions: [JSONValue]
        if let array = payload.arrayValue {
            actions = array
        } else if let inner = payload["actions"]?.arrayValue {
            actions = inner
        } else if payload["type"] != nil {
            actions = [payload]
        } else {
            throw invalid("an OpenAI computer payload needs an action, or an array of them",
                          remedy: "Send {\"type\":\"click\",\"x\":..,\"y\":..} or a list of such objects.")
        }
        guard !actions.isEmpty else {
            throw invalid("the OpenAI action batch is empty",
                          remedy: "Include at least one action.")
        }
        return try actions.flatMap { try openaiAction($0, windowFrame: windowFrame, scale: scale) }
    }

    private static func openaiAction(_ action: JSONValue, windowFrame: Rect,
                                     scale: Double) throws -> [CUAStep] {
        guard let name = action["type"]?.stringValue else {
            throw invalid("each OpenAI action needs a `type`",
                          remedy: "e.g. {\"type\":\"click\",\"button\":\"left\",\"x\":..,\"y\":..}.")
        }

        switch name {
        case "screenshot":
            return [CUAStep(operation: .screenshot, action: name,
                            summary: "screenshot → window capture")]

        case "wait":
            let ms = action["ms"]?.intValue ?? durationMs(action, default: 1000)
            return [CUAStep(operation: .wait(ms: ms), action: name, summary: "wait \(ms)ms")]

        case "type":
            let text = action["text"]?.stringValue ?? ""
            return [CUAStep(operation: .act(ActionStep(kind: .type, text: text)),
                            action: name, summary: "type \(text.debugDescription)")]

        case "keypress":
            let keys = action["keys"]?.arrayValue?.compactMap(\.stringValue) ?? []
            guard let (key, mods) = parseKeys(keys), !key.isEmpty else {
                throw invalid("OpenAI `keypress` needs a non-empty `keys` array",
                              remedy: "e.g. {\"type\":\"keypress\",\"keys\":[\"ctrl\",\"c\"]}.")
            }
            return [CUAStep(operation: .act(ActionStep(kind: .key, key: key, modifiers: mods)),
                            action: name,
                            summary: "keypress \(keys) → \(key)\(mods.isEmpty ? "" : " + " + mods.joined(separator: "+"))")]

        case "move":
            let g = try point(action, windowFrame: windowFrame, scale: scale, for: name)
            return [CUAStep(operation: .act(ActionStep(kind: .hover, point: g)),
                            action: name, summary: "move → hover at \(fmt(g))")]

        case "click":
            let button = action["button"]?.stringValue ?? "left"
            guard button == "left" else {
                throw unsupported("click(button:\(button))",
                                  why: "Proctor synthetic click is left-button only",
                                  child: "non-left mouse buttons")
            }
            let g = try point(action, windowFrame: windowFrame, scale: scale, for: name)
            return [clickStep(at: g, action: name, count: 1)]

        case "double_click":
            let g = try point(action, windowFrame: windowFrame, scale: scale, for: name)
            return clicks(at: g, action: name, count: 2)

        case "scroll":
            let g = try point(action, windowFrame: windowFrame, scale: scale, for: name)
            // OpenAI positive scroll_y means scrolling the content down; Proctor
            // reads a negative dy as "scroll down" (Actuator), so the sign flips.
            let sx = action["scroll_x"]?.doubleValue ?? 0
            let sy = action["scroll_y"]?.doubleValue ?? 0
            return [CUAStep(operation: .act(ActionStep(kind: .scroll, delta: [-sx, -sy], point: g)),
                            action: name, summary: "scroll (\(sx),\(sy)) at \(fmt(g))")]

        case "drag":
            let raw = action["path"]?.arrayValue ?? []
            let pts = try raw.map { entry -> [Double] in
                if let arr = entry.arrayValue?.compactMap(\.doubleValue), arr.count >= 2 {
                    return globalPoint(arr, in: windowFrame, scale: scale)
                }
                if let x = entry["x"]?.doubleValue, let y = entry["y"]?.doubleValue {
                    return globalPoint([x, y], in: windowFrame, scale: scale)
                }
                throw invalid("each OpenAI drag path entry needs x and y",
                              remedy: "Send path as [{\"x\":..,\"y\":..}, ...].")
            }
            guard pts.count >= 2 else {
                throw invalid("an OpenAI drag needs a path of at least two points",
                              remedy: "Include the start and end of the drag.")
            }
            return [CUAStep(operation: .act(ActionStep(kind: .dragPath, path: pts)),
                            action: name, summary: "drag along \(pts.count) points")]

        default:
            throw unsupported(name, why: "no mapping onto a Proctor step",
                              child: "action \(name)")
        }
    }

    // MARK: - Shared builders

    private static func clickStep(at g: [Double], action: String, count: Int) -> CUAStep {
        CUAStep(operation: .act(ActionStep(kind: .click, point: g)),
                action: action, summary: "\(action) → click at \(fmt(g))")
    }

    private static func clicks(at g: [Double], action: String, count: Int) -> [CUAStep] {
        (0..<count).map { i in
            CUAStep(operation: .act(ActionStep(kind: .click, point: g)),
                    action: action,
                    summary: "\(action) → click \(i + 1)/\(count) at \(fmt(g))")
        }
    }

    private static func dragStep(_ action: JSONValue, windowFrame: Rect, scale: Double,
                                 for name: String) throws -> CUAStep {
        // The 2024 schema's left_click_drag drags from the current cursor to
        // `coordinate`; the façade does not track the cursor, so a start is
        // required — `start_coordinate` when the schema supplies it.
        guard let startRaw = action["start_coordinate"]?.arrayValue?.compactMap(\.doubleValue),
              startRaw.count >= 2 else {
            throw invalid("left_click_drag needs a `start_coordinate` (the façade tracks no cursor)",
                          remedy: "Send start_coordinate:[x,y] and coordinate:[x,y] for the drag ends.")
        }
        let endRaw = try coordinate(action, for: name)
        let start = globalPoint(startRaw, in: windowFrame, scale: scale)
        let end = globalPoint(endRaw, in: windowFrame, scale: scale)
        return CUAStep(operation: .act(ActionStep(kind: .dragPath, path: [start, end])),
                       action: name, summary: "left_click_drag \(fmt(start)) → \(fmt(end))")
    }

    private static func anthropicScroll(_ action: JSONValue, for name: String) throws -> CUAStep {
        let amount = action["scroll_amount"]?.doubleValue ?? 3
        let direction = (action["scroll_direction"]?.stringValue ?? "down").lowercased()
        // Actuator reads dy<0 as down, dy>0 as up, dx<0 as right, dx>0 as left.
        let delta: [Double]
        switch direction {
        case "up": delta = [0, amount]
        case "down": delta = [0, -amount]
        case "left": delta = [amount, 0]
        case "right": delta = [-amount, 0]
        default:
            throw invalid("scroll_direction must be up, down, left or right, not \(direction.debugDescription)",
                          remedy: nil)
        }
        return CUAStep(operation: .act(ActionStep(kind: .scroll, delta: delta)),
                       action: name, summary: "scroll \(direction) \(Int(amount))")
    }

    // MARK: - Coordinate readers

    /// Read a CUA action's coordinate — `coordinate:[x,y]` (Anthropic) or `x`/`y`
    /// scalars (OpenAI) — as a raw window-relative point.
    private static func coordinate(_ action: JSONValue, for name: String) throws -> [Double] {
        if let arr = action["coordinate"]?.arrayValue?.compactMap(\.doubleValue), arr.count >= 2 {
            return [arr[0], arr[1]]
        }
        if let x = action["x"]?.doubleValue, let y = action["y"]?.doubleValue {
            return [x, y]
        }
        throw invalid("\(name) needs a coordinate",
                      remedy: "Send coordinate:[x,y] (Anthropic) or x and y (OpenAI).")
    }

    private static func point(_ action: JSONValue, windowFrame: Rect, scale: Double,
                              for name: String) throws -> [Double] {
        globalPoint(try coordinate(action, for: name), in: windowFrame, scale: scale)
    }

    private static func durationMs(_ action: JSONValue, default fallback: Int = 1000) -> Int {
        if let ms = action["ms"]?.intValue { return max(0, ms) }
        // Anthropic `wait` gives `duration` in seconds.
        if let seconds = action["duration"]?.doubleValue { return max(0, Int(seconds * 1000)) }
        return fallback
    }

    // MARK: - Formatting and errors

    private static func fmt(_ p: [Double]) -> String {
        guard p.count >= 2 else { return "[?]" }
        return "[\(Int(p[0].rounded())),\(Int(p[1].rounded()))]"
    }

    private static func invalid(_ message: String, remedy: String?) -> AgentError {
        AgentError(code: .invalidArguments, message: message, remedy: remedy)
    }

    private static func unsupported(_ name: String, why: String, child: String) -> AgentError {
        AgentError(code: .invalidArguments,
                   message: "the CUA action \(name.debugDescription) has no Proctor mapping: \(why)",
                   remedy: "Use the native proctor_act tool for this, or track it as a façade "
                         + "follow-up (\(child)).")
    }
}
