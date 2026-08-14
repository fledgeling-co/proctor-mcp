import Foundation

// One line of English for one step, derived rather than supplied.
//
// The run HUD is a kill switch: it is the surface a person reads to decide
// whether to stop a run. Rendering `ActionStep.label` there would put the verb
// in the hands of the client being supervised, and the field is optional besides
// — the same agent passes it on some steps and omits it on others within one
// run. So the verb and the timing word are always Proctor's own, taken from
// `step.kind`, and the object is the element's own accessibility name, which the
// agent has already resolved. A caller-supplied `label` overrides the object and
// nothing else, and is sanitised on the way in.
//
// Every object is quoted, whoever it came from. The quotes are a fence, not a
// provenance marker: they stop a name that contains a full stop and a plausible
// second clause from reading as a second state announcement in a kill switch —
// `Pressing "OK. About to press Delete"` is one oddly-named control, where the
// unquoted form is two sentences. An app's own accessibility title can carry
// that payload exactly as a caller's label can, which is why the fence cannot be
// reserved for the half that arrived over the wire. `Object` still records where
// the name came from, so a renderer that can do better than punctuation — its own
// text run, which no character can escape — has what it needs.
//
// Pure, like PointerMarker, SetOfMarks and Policy: no window, no grant, no
// clock. Given a step and the node it resolved to, the line is a function of
// those two and testable without any of them.
//
// Two things deliberately never appear here: typed text and script bodies. The
// audit record reduces both to a length and a hash, and a description that
// reprinted them would defeat that redaction on the way past.
public enum StepDescription {

    /// Whether the step is about to happen or is happening. The HUD shows the
    /// prospective form while Proctor travels to the target and the present form
    /// while it actuates, from the same step object.
    public enum Timing: String, Sendable, Equatable {
        case prospective
        case present
    }

    /// How a step ended, for the after-the-fact line. The audit trail already
    /// distinguishes a refusal from a failure, so the wording does too; the
    /// reason belongs to whatever surface shows it.
    public enum Outcome: String, Sendable, Equatable {
        case refused
        case failed
    }

    /// The hard cut applied to every object, supplied or derived. The HUD's live
    /// line is designed never to ellipse, so the cap belongs at the source.
    public static let objectLimit = 48

    // MARK: - The lines

    /// The live line: "About to press Send invoice" / "Pressing Send invoice".
    public static func line(for step: ActionStep, node: AXNode?, timing: Timing) -> String {
        let verbs = wording(for: step.kind)
        guard let object = object(for: step, node: node) else {
            return timing == .present ? verbs.presentAlone : verbs.prospectiveAlone
        }
        let verb = timing == .present ? verbs.present : verbs.prospective
        return "\(verb) \(render(object))"
    }

    /// The after-the-fact line: "Hover refused", "Press \"Send invoice\" failed".
    /// The object is kept where there is one, so a turned-down `confirm` reads as
    /// the confirmation step being refused rather than as a person's own
    /// confirmation being denied.
    public static func line(for step: ActionStep, node: AXNode?, outcome: Outcome) -> String {
        let noun = wording(for: step.kind).noun
        guard let object = object(for: step, node: node) else {
            return "\(noun) \(outcome.rawValue)"
        }
        return "\(noun) \(render(object)) \(outcome.rawValue)"
    }

    /// The trail line, for a step that ran and settled: "Focused Amount",
    /// "Picked \"Net 30\" from Terms". Past tense because the trail is a record
    /// of what happened, where the live line is a statement of what is happening.
    public static func completedLine(for step: ActionStep, node: AXNode?) -> String {
        let verbs = wording(for: step.kind)
        guard let object = object(for: step, node: node) else { return verbs.pastAlone }
        return "\(verbs.past) \(render(object))"
    }

    /// The object alone, rendered the way a line would render it — quoted when
    /// the caller supplied it, bare when Proctor derived it. For a surface that
    /// needs its own verb in front of the same object, so the two never drift.
    public static func objectText(for step: ActionStep, node: AXNode?) -> String? {
        object(for: step, node: node).map(render)
    }

    // MARK: - Objects

    /// Where an object came from. A name the client supplied is display text it
    /// chose to have shown; a name Proctor derived is the machine's own reading
    /// of the screen. The line marks the difference rather than blending them.
    enum Object: Equatable {
        case supplied(String)
        case derived(String)

        var text: String {
            switch self {
            case .supplied(let s), .derived(let s): return s
            }
        }
    }

    /// Every object is fenced in quotes, supplied or derived. See the type comment
    /// for why the derived half is not exempt.
    private static func render(_ object: Object) -> String {
        return "\"\(object.text)\""
    }

    /// The object this step acts on, first non-empty candidate wins. Every
    /// candidate goes through `sanitised` — an app's own accessibility title can
    /// be as long, as multi-line and as markup-laden as anything a caller sends,
    /// so the cap and the strip apply wherever the name comes from.
    static func object(for step: ActionStep, node: AXNode?) -> Object? {
        // 1. The caller's override. Replaces the object and nothing else.
        if let supplied = sanitised(step.label) { return .supplied(supplied) }

        // A script has no nameable target and its body is redacted, so only an
        // explicit caller-supplied name can ever name one.
        if step.kind == .appleScript { return nil }

        // 2. Carried text, for the three kinds whose object is not the element
        //    they act through: the field a keystroke lands in is not what the
        //    keystroke *is*. This text comes from the client's own tool call rather
        //    than from the accessibility tree, so it is recorded as `supplied`.
        if let carried = carriedText(for: step) { return .supplied(carried) }

        // 3. The element's own readable name, in the order the agent already
        //    uses elsewhere.
        if let node {
            for candidate in [node.title, node.label, node.identifier] {
                if let name = sanitised(candidate) { return .derived(name) }
            }
        }

        // A freehand drag through a generic container reads better as the action
        // alone than as "Dragging AXGroup".
        if step.kind == .dragPath { return nil }

        guard let node else { return nil }

        // 4. The element's kind, in descending readability, then 5. its id. The
        //    line is never empty and always points at something.
        for candidate in [node.roleDescription, node.subrole, node.role, node.id] {
            if let name = sanitised(candidate) { return .derived(name) }
        }
        return nil
    }

    /// Text the step itself carries that names what is being acted on. Never the
    /// typed text of a `type` step, never a script body, never a `setValue`
    /// value — those are the fields the audit record reduces to a hash.
    private static func carriedText(for step: ActionStep) -> String? {
        switch step.kind {
        case .menu:
            return sanitised(step.menuPath?.last)
        case .key:
            guard let key = step.key, !key.isEmpty else { return nil }
            return sanitised(MenuKeyEquivalent.shortcutString(modifiers: step.modifiers ?? [],
                                                              key: key))
        case .shortcut:
            // Mirrors Actuator.shortcut's own resolution, minus `label` which the
            // override already covered, so the line names the shortcut that runs.
            // Each candidate is sanitised separately: an empty `text` must fall
            // through to `value` rather than block it, as it does in the actuator.
            return sanitised(step.text) ?? sanitised(step.value?.stringValue)
        default:
            return nil
        }
    }

    // MARK: - Sanitising

    /// One line, no control characters, no markup, trimmed, hard-cut at
    /// `objectLimit` graphemes with no ellipsis. Nil when nothing survives, so
    /// the caller falls through to the next candidate rather than printing a
    /// blank.
    public static func sanitised(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }

        var out = String()
        out.reserveCapacity(min(raw.count, objectLimit * 2))
        var pendingSpace = false

        for scalar in raw.unicodeScalars {
            // Whitespace is decided before the control strip, because a newline
            // and a tab are control characters that must become a space rather
            // than vanish and weld two words together.
            if isWhitespace(scalar) {
                if !out.isEmpty { pendingSpace = true }
                continue
            }
            // Angle brackets go, the text between them stays: a tag cannot
            // survive without a `<` to open it, and an app's own `<Untitled>`
            // window keeps its name instead of falling through to a role. The
            // bracket becomes a word break rather than nothing, so "5<10" does
            // not silently read as "510".
            if scalar == "<" || scalar == ">" {
                if !out.isEmpty { pendingSpace = true }
                continue
            }
            // Emphasis characters the consuming surfaces could interpret.
            if scalar == "*" || scalar == "_" || scalar == "`" { continue }
            // Control and format characters, including the bidi overrides that
            // can reorder a line against what it says. The joiners are spared:
            // dropping a ZWJ splits a family emoji into four people.
            if !isGraphemeJoiner(scalar), isControlOrFormat(scalar) { continue }

            if pendingSpace {
                out.unicodeScalars.append(" ")
                pendingSpace = false
            }
            // A double quote is folded to a single one so a supplied name cannot
            // close the quotation the line puts around it and append a clause.
            if isDoubleQuote(scalar) {
                out.unicodeScalars.append("'")
            } else {
                out.unicodeScalars.append(scalar)
            }

            // Stop scanning once no surviving scalar could still fall inside the
            // cut. A grapheme cluster is at most a handful of scalars, so this
            // bound is generous; without it a multi-megabyte accessibility title
            // is copied in full to produce 48 characters.
            if out.unicodeScalars.count > objectLimit * 16 { break }
        }

        // Cut by grapheme cluster, so a truncation can never split an emoji or a
        // combining sequence. No ellipsis: the HUD never ellipses.
        if out.count > objectLimit {
            out = String(out.prefix(objectLimit))
        }
        while out.last == " " { out.removeLast() }
        return out.isEmpty ? nil : out
    }

    private static func isControlOrFormat(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator,
             .surrogate, .privateUse, .unassigned:
            return true
        default:
            return false
        }
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }

    /// Zero-width joiner and the variation selectors. They are format characters
    /// but they build a single glyph out of several scalars, so removing them
    /// rewrites the name rather than cleaning it.
    private static func isGraphemeJoiner(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x200D || (0xFE00...0xFE0F).contains(scalar.value)
    }

    private static func isDoubleQuote(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\"" || scalar == "\u{201C}" || scalar == "\u{201D}" || scalar == "\u{201F}"
    }

    // MARK: - Wording

    /// The four forms one kind takes. Every kind is written out by hand, in both
    /// timings and with and without an object: printing the kind's raw value
    /// would read as "About to setValue" and "Menuing File".
    struct Wording {
        /// With an object: "Pressing" + " Send invoice".
        var present: String
        /// With an object: "About to press" + " Send invoice".
        var prospective: String
        /// No object, so no dangling preposition: "Typing", not "Typing into".
        var presentAlone: String
        var prospectiveAlone: String
        /// The action named as a thing, for the outcome line: "Hover refused".
        var noun: String
        /// With an object, after the fact: "Pressed" + " Send invoice".
        var past: String
        var pastAlone: String

        init(present: String, prospective: String, noun: String, past: String,
             presentAlone: String? = nil, prospectiveAlone: String? = nil,
             pastAlone: String? = nil) {
            self.present = present
            self.prospective = prospective
            self.noun = noun
            self.past = past
            self.presentAlone = presentAlone ?? present
            self.prospectiveAlone = prospectiveAlone ?? prospective
            self.pastAlone = pastAlone ?? past
        }
    }

    static func wording(for kind: ActionStep.Kind) -> Wording {
        switch kind {
        case .press:
            return Wording(present: "Pressing", prospective: "About to press",
                           noun: "Press", past: "Pressed")
        case .setValue:
            return Wording(present: "Setting", prospective: "About to set",
                           noun: "Set value", past: "Set", pastAlone: "Set a value")
        case .focus:
            return Wording(present: "Focusing", prospective: "About to focus",
                           noun: "Focus", past: "Focused")
        case .menu:
            return Wording(present: "Choosing", prospective: "About to choose",
                           noun: "Menu choice", past: "Chose",
                           presentAlone: "Choosing a menu item",
                           prospectiveAlone: "About to choose a menu item",
                           pastAlone: "Chose a menu item")
        case .type:
            return Wording(present: "Typing into", prospective: "About to type into",
                           noun: "Typing", past: "Typed into",
                           presentAlone: "Typing", prospectiveAlone: "About to type",
                           pastAlone: "Typed")
        case .key:
            return Wording(present: "Sending the keystroke",
                           prospective: "About to send the keystroke",
                           noun: "Keystroke", past: "Sent the keystroke",
                           presentAlone: "Sending a keystroke",
                           prospectiveAlone: "About to send a keystroke",
                           pastAlone: "Sent a keystroke")
        case .scroll:
            return Wording(present: "Scrolling", prospective: "About to scroll",
                           noun: "Scroll", past: "Scrolled")
        case .increment:
            return Wording(present: "Incrementing", prospective: "About to increment",
                           noun: "Increment", past: "Incremented")
        case .decrement:
            return Wording(present: "Decrementing", prospective: "About to decrement",
                           noun: "Decrement", past: "Decremented")
        case .pick:
            return Wording(present: "Picking", prospective: "About to pick",
                           noun: "Pick", past: "Picked")
        case .confirm:
            return Wording(present: "Confirming", prospective: "About to confirm",
                           noun: "Confirm", past: "Confirmed")
        case .cancel:
            return Wording(present: "Cancelling", prospective: "About to cancel",
                           noun: "Cancel", past: "Cancelled")
        case .raise:
            return Wording(present: "Raising", prospective: "About to raise",
                           noun: "Raise", past: "Raised")
        case .close:
            return Wording(present: "Closing", prospective: "About to close",
                           noun: "Close", past: "Closed")
        case .resize:
            return Wording(present: "Resizing", prospective: "About to resize",
                           noun: "Resize", past: "Resized")
        case .move:
            return Wording(present: "Moving", prospective: "About to move",
                           noun: "Move", past: "Moved")
        case .dragPath:
            return Wording(present: "Dragging", prospective: "About to drag",
                           noun: "Drag", past: "Dragged")
        case .hover:
            return Wording(present: "Hovering over", prospective: "About to hover over",
                           noun: "Hover", past: "Hovered over",
                           presentAlone: "Hovering", prospectiveAlone: "About to hover",
                           pastAlone: "Hovered")
        case .click:
            return Wording(present: "Clicking", prospective: "About to click",
                           noun: "Click", past: "Clicked")
        case .shortcut:
            return Wording(present: "Running the shortcut",
                           prospective: "About to run the shortcut",
                           noun: "Shortcut", past: "Ran the shortcut",
                           presentAlone: "Running a shortcut",
                           prospectiveAlone: "About to run a shortcut",
                           pastAlone: "Ran a shortcut")
        case .appleScript:
            return Wording(present: "Running the script",
                           prospective: "About to run the script",
                           noun: "Script", past: "Ran the script",
                           presentAlone: "Running a script",
                           prospectiveAlone: "About to run a script",
                           pastAlone: "Ran a script")
        case .waitFor:
            // Waiting reads as waiting *for* the thing, never as acting on it.
            return Wording(present: "Waiting for", prospective: "About to wait for",
                           noun: "Wait", past: "Waited for",
                           presentAlone: "Waiting", prospectiveAlone: "About to wait",
                           pastAlone: "Waited")
        }
    }
}
