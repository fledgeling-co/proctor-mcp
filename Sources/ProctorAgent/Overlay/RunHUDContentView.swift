import AppKit
import ProctorCore

// The panel's drawing and its mouse handling. Everything here is a rendering of
// `RunHUDModel` — no decisions live in this file, which is what lets the
// decisions be tested without a display.
//
// Geometry is the reference's, in points, laid out from the top because that is
// how the mock's CSS reads and because a layout that has to be mentally flipped
// is a layout that drifts from its reference.

enum RunHUDLayout {
    static let width: CGFloat = 352
    static let pad: CGFloat = 16
    static let lineRow: CGFloat = 64       // 13 + 38 bay + 13
    static let exceptionRow: CGFloat = 30  // 2 + 15 + 13
    static let trailRow: CGFloat = 24
    static let trailRows: Int = RunHUDState.trailDepth
    static let trailBlock: CGFloat = 6 + 24 * 3 + 8
    static let footBlock: CGFloat = 9 + 30 + 11
    static let bay: CGFloat = 38
    static let rail: CGFloat = 2

    static func height(exception: Bool) -> CGFloat {
        lineRow + (exception ? exceptionRow : 0) + trailBlock + footBlock
    }

    /// Where the trail starts, which is the only thing the exception line moves.
    static func trailTop(exception: Bool) -> CGFloat {
        lineRow + (exception ? exceptionRow : 0)
    }
}

/// The mock's two palettes. Neutral graphite and neutral white, with vermilion
/// as the only colour on the panel — a warm ground reads as mud over somebody
/// else's application.
struct RunHUDPalette {
    var hud: NSColor, border: NSColor
    var ink: NSColor, ink2: NSColor, ink3: NSColor, ink4: NSColor
    var fill: NSColor, fill2: NSColor, separator: NSColor
    var accent: NSColor, green: NSColor, amber: NSColor, red: NSColor
    var onAccent: NSColor, bay: NSColor

    static func white(_ v: CGFloat, _ a: CGFloat) -> NSColor {
        NSColor(calibratedWhite: v, alpha: a)
    }
    static func hex(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    static let dark = RunHUDPalette(
        hud: hex(24, 25, 28, 0.74), border: white(1, 0.13),
        ink: white(1, 0.95), ink2: white(1, 0.56), ink3: white(1, 0.34), ink4: white(1, 0.15),
        fill: white(1, 0.08), fill2: white(1, 0.13), separator: white(1, 0.10),
        accent: hex(255, 106, 61), green: hex(74, 222, 128),
        amber: hex(251, 191, 36), red: hex(255, 90, 84),
        onAccent: hex(26, 13, 7), bay: hex(19, 19, 21))

    static let light = RunHUDPalette(
        hud: hex(252, 252, 253, 0.78), border: white(0, 0.10),
        ink: hex(17, 18, 21, 0.94), ink2: hex(17, 18, 21, 0.56),
        ink3: hex(17, 18, 21, 0.36), ink4: hex(17, 18, 21, 0.16),
        fill: hex(17, 18, 21, 0.05), fill2: hex(17, 18, 21, 0.09),
        separator: hex(17, 18, 21, 0.09),
        accent: hex(226, 74, 24), green: hex(22, 163, 74),
        amber: hex(180, 83, 9), red: hex(220, 38, 38),
        onAccent: .white, bay: hex(19, 19, 21))

    func colour(for tone: RunHUDTone) -> NSColor {
        switch tone {
        case .accent: return accent
        case .amber: return amber
        case .red: return red
        case .green: return green
        case .quiet: return ink3
        }
    }
}

@MainActor
final class RunHUDContentView: NSView {

    enum Control { case pause, stop, grip }

    weak var owner: RunHUDPanel?
    var model = RunHUDModel()
    var elapsed: TimeInterval = 0

    private var hovered: Control?
    private var pressed: Control?
    private var dragAnchor: NSPoint?
    private var pauseRect: NSRect = .zero
    private var stopRect: NSRect = .zero
    private var gripRect: NSRect = .zero

    override var isFlipped: Bool { true }

    /// An application that is never frontmost gets the first click only if its
    /// view says it will take one. Without this the click that matters most —
    /// the first one, on Stop — is swallowed as an activation.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let was = hovered
        hovered = control(at: point)
        if was != hovered { needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if hovered != nil { hovered = nil; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressed = control(at: point)
        if pressed == .grip { dragAnchor = NSEvent.mouseLocation }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        // Moved by hand rather than by `performDrag(with:)`, which runs a nested
        // event loop. This process must not enter one of its own making: a
        // tracking loop is time the agent is not answering, and the settle
        // observers it depends on are the thing a nested loop starves.
        guard pressed == .grip, let anchor = dragAnchor else { return }
        let now = NSEvent.mouseLocation
        owner?.drag(by: CGSize(width: now.x - anchor.x, height: now.y - anchor.y))
        dragAnchor = now
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let release = control(at: point)
        if let pressed, pressed == release {
            switch pressed {
            case .pause: owner?.togglePause()
            case .stop: owner?.stop()
            case .grip: break
            }
        }
        pressed = nil
        dragAnchor = nil
        needsDisplay = true
    }

    private func control(at point: NSPoint) -> Control? {
        if pauseRect.contains(point) { return .pause }
        if stopRect.contains(point) { return .stop }
        if gripRect.contains(point) { return .grip }
        return nil
    }

    /// Only the grip and the two controls are live; nothing else on the panel
    /// reacts to a click. See the note on `RunHUDRootView` for what that does and
    /// does not buy: a click on the body is discarded rather than handed to the
    /// application underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return control(at: local) == nil ? nil : self
    }

    // MARK: - Drawing

    private var palette: RunHUDPalette {
        let match = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? .dark : .light
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = palette
        let live = p.colour(for: model.tone)
        let hasException = model.exception != nil

        // Ground and hairline. The blur behind it does the rest; with reduced
        // transparency there is no blur and this tint is the whole background,
        // which is why it is drawn either way.
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                xRadius: 16, yRadius: 16)
        (NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? p.hud.withAlphaComponent(1) : p.hud).setFill()
        body.fill()
        p.border.setStroke()
        body.lineWidth = 0.5
        body.stroke()

        drawLiveLine(p: p, live: live)
        if let exception = model.exception {
            draw(text: exception, font: .systemFont(ofSize: 12), colour: p.amber,
                 in: NSRect(x: RunHUDLayout.pad, y: RunHUDLayout.lineRow + 2,
                            width: RunHUDLayout.width - RunHUDLayout.pad * 2, height: 16))
        }
        drawTrail(p: p, top: RunHUDLayout.trailTop(exception: hasException))
        drawFoot(p: p, live: live, top: RunHUDLayout.trailTop(exception: hasException)
                 + RunHUDLayout.trailBlock)
        drawRail(p: p, live: live)
    }

    private func drawLiveLine(p: RunHUDPalette, live: NSColor) {
        // The grip.
        gripRect = NSRect(x: RunHUDLayout.pad, y: (RunHUDLayout.lineRow - 18) / 2,
                          width: 10, height: 18)
        p.ink4.setFill()
        for row in 0..<4 {
            for column in 0..<3 {
                let dot = NSRect(x: gripRect.minX + CGFloat(column) * 4 + 0.5,
                                 y: gripRect.minY + CGFloat(row) * 5 + 1,
                                 width: 1.8, height: 1.8)
                NSBezierPath(ovalIn: dot).fill()
            }
        }

        // The character's bay. Empty here by design: the sprite is PRO-0017, and
        // the bay stays dark in both appearances because the character is
        // white-bodied and would vanish on the light panel.
        let bay = NSRect(x: gripRect.maxX + 11, y: 13,
                         width: RunHUDLayout.bay, height: RunHUDLayout.bay)
        let bayPath = NSBezierPath(roundedRect: bay, xRadius: 9, yRadius: 9)
        p.bay.setFill()
        bayPath.fill()
        p.border.setStroke()
        bayPath.lineWidth = 0.5
        bayPath.stroke()

        // The count, fixed-width so a change never moves its neighbour.
        let countFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let countRect = NSRect(x: RunHUDLayout.width - 14 - 46, y: RunHUDLayout.lineRow / 2 - 8,
                               width: 46, height: 16)
        draw(text: model.counter, font: countFont, colour: p.ink3, in: countRect, alignment: .right)

        // One line, one size. The object is worn in the live colour so the panel
        // changes as one object; the verb stays in the ink.
        let sayRect = NSRect(x: bay.maxX + 11, y: RunHUDLayout.lineRow / 2 - 11,
                             width: countRect.minX - 11 - (bay.maxX + 11), height: 22)
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let say = NSMutableAttributedString(
            string: model.line,
            attributes: [.font: font, .foregroundColor: p.ink,
                         .paragraphStyle: paragraph(.left)])
        if let object = liveObjectRange() {
            say.addAttribute(.foregroundColor, value: live, range: object)
        }
        say.draw(in: sayRect)
    }

    /// The object's range in the live line, so it can be worn in the live colour.
    /// Derived from the line rather than passed alongside it, because the line is
    /// the thing on screen.
    private func liveObjectRange() -> NSRange? {
        guard !model.line.isEmpty else { return nil }
        let words = model.line as NSString
        // Every derived line is "<verb> <object>" or "<noun> <object> <outcome>".
        // The object is what is left once a known leading verb is taken off, so
        // the emphasis follows whatever `StepDescription` produced.
        for prefix in ["About to ", ""] where words.hasPrefix(prefix) {
            let rest = words.substring(from: prefix.count) as NSString
            let space = rest.range(of: " ")
            guard space.location != NSNotFound else { return nil }
            let start = prefix.count + space.location + 1
            guard start < words.length else { return nil }
            return NSRange(location: start, length: words.length - start)
        }
        return nil
    }

    private func drawTrail(p: RunHUDPalette, top: CGFloat) {
        p.separator.setFill()
        NSRect(x: 0, y: top, width: bounds.width, height: 0.5).fill()

        let font = NSFont.systemFont(ofSize: 12)
        let msFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        for index in 0..<RunHUDLayout.trailRows {
            guard index < model.trail.count else { continue }
            let row = model.trail[index]
            let y = top + 6 + CGFloat(index) * RunHUDLayout.trailRow
            let glyphColour: NSColor
            switch row.outcome {
            case .done: glyphColour = p.green
            case .refused: glyphColour = p.amber
            case .failed: glyphColour = p.red
            }
            drawGlyph(row.outcome, colour: glyphColour,
                      in: NSRect(x: RunHUDLayout.pad, y: y + 7, width: 10, height: 10))

            let ms = row.settleMs.map(Self.duration) ?? "—"
            let msWidth: CGFloat = 46
            draw(text: ms, font: msFont, colour: p.ink3,
                 in: NSRect(x: RunHUDLayout.width - RunHUDLayout.pad - msWidth, y: y + 5,
                            width: msWidth, height: 14), alignment: .right)
            draw(text: row.text, font: font, colour: p.ink3,
                 in: NSRect(x: RunHUDLayout.pad + 20, y: y + 4,
                            width: RunHUDLayout.width - RunHUDLayout.pad * 2 - 20 - msWidth - 10,
                            height: 16), truncates: true)
        }
    }

    private func drawFoot(p: RunHUDPalette, live: NSColor, top: CGFloat) {
        p.separator.setFill()
        NSRect(x: 0, y: top, width: bounds.width, height: 0.5).fill()

        let y = top + 9
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let stopWidth = Self.controlWidth("Stop", font: font)
        stopRect = NSRect(x: RunHUDLayout.width - 12 - stopWidth, y: y,
                          width: stopWidth, height: 30)
        let pauseWidth = Self.controlWidth(model.pauseLabel, font: font)
        pauseRect = NSRect(x: stopRect.minX - 8 - pauseWidth, y: y, width: pauseWidth, height: 30)

        draw(text: Self.clock(elapsed),
             font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
             colour: p.ink2, in: NSRect(x: RunHUDLayout.pad, y: y + 7, width: 60, height: 16))

        // Pause becomes Resume, and wears the accent while it is the way back —
        // the only moment the run controls are the brightest thing on the panel.
        let resuming = model.pauseLabel == "Resume"
        drawControl(pauseRect, label: model.pauseLabel, font: font,
                    fill: resuming ? p.accent : p.fill2,
                    ink: resuming ? p.onAccent : p.ink,
                    icon: resuming ? .play : .pause, control: .pause, palette: p)
        drawControl(stopRect, label: "Stop", font: font,
                    fill: p.red.withAlphaComponent(0.16), ink: p.red,
                    icon: .stop, control: .stop, palette: p)
    }

    private enum Icon { case pause, play, stop }

    private func drawControl(_ rect: NSRect, label: String, font: NSFont,
                             fill: NSColor, ink: NSColor, icon: Icon,
                             control: Control, palette p: RunHUDPalette) {
        var background = fill
        if hovered == control { background = fill.blended(withFraction: 0.22, of: p.ink) ?? fill }
        let path = NSBezierPath(roundedRect: pressed == control ? rect.insetBy(dx: 0.6, dy: 0.6)
                                                                : rect,
                                xRadius: 8, yRadius: 8)
        background.setFill()
        path.fill()

        let iconBox = NSRect(x: rect.minX + 12, y: rect.midY - 5.5, width: 11, height: 11)
        ink.setFill()
        switch icon {
        case .pause:
            NSBezierPath(roundedRect: NSRect(x: iconBox.minX + 1, y: iconBox.minY + 1,
                                             width: 3, height: 9),
                         xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: NSRect(x: iconBox.minX + 6.5, y: iconBox.minY + 1,
                                             width: 3, height: 9),
                         xRadius: 1, yRadius: 1).fill()
        case .play:
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: iconBox.minX + 2, y: iconBox.minY + 1))
            triangle.line(to: NSPoint(x: iconBox.maxX - 1, y: iconBox.midY))
            triangle.line(to: NSPoint(x: iconBox.minX + 2, y: iconBox.maxY - 1))
            triangle.close()
            triangle.fill()
        case .stop:
            NSBezierPath(roundedRect: iconBox.insetBy(dx: 1.4, dy: 1.4),
                         xRadius: 1.7, yRadius: 1.7).fill()
        }

        draw(text: label, font: font, colour: ink,
             in: NSRect(x: iconBox.maxX + 7, y: rect.midY - 8,
                        width: rect.maxX - iconBox.maxX - 7 - 12, height: 16))
    }

    /// The rail is the panel's own bottom edge, filled in the live colour.
    ///
    /// Nothing on this panel animates in this build — the reference's rail glow
    /// and the character's motion arrive with the sprite (PRO-0017) — so reduced
    /// motion has nothing to suppress here, and every state stays readable from
    /// its words and its colour alone, which is the property that has to hold
    /// whether or not anything moves.
    private func drawRail(p: RunHUDPalette, live: NSColor) {
        let y = bounds.height - RunHUDLayout.rail
        p.fill.setFill()
        NSRect(x: 0, y: y, width: bounds.width, height: RunHUDLayout.rail).fill()
        live.setFill()
        NSRect(x: 0, y: y, width: bounds.width * CGFloat(model.progress),
               height: RunHUDLayout.rail).fill()
    }

    private func drawGlyph(_ outcome: RunHUDModel.Row.Outcome, colour: NSColor, in rect: NSRect) {
        colour.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch outcome {
        case .done:
            path.move(to: NSPoint(x: rect.minX + 1.5, y: rect.minY + 5.2))
            path.line(to: NSPoint(x: rect.minX + 3.9, y: rect.minY + 7.6))
            path.line(to: NSPoint(x: rect.minX + 8.5, y: rect.minY + 2.6))
        case .refused, .failed:
            path.move(to: NSPoint(x: rect.midX, y: rect.minY + 1.6))
            path.line(to: NSPoint(x: rect.midX, y: rect.minY + 5.8))
            path.move(to: NSPoint(x: rect.midX, y: rect.minY + 8.2))
            path.line(to: NSPoint(x: rect.midX, y: rect.minY + 8.4))
        }
        path.stroke()
    }

    // MARK: - Text

    private func paragraph(_ alignment: NSTextAlignment,
                           truncates: Bool = false) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = truncates ? .byTruncatingTail : .byClipping
        return style
    }

    private func draw(text: String, font: NSFont, colour: NSColor, in rect: NSRect,
                      alignment: NSTextAlignment = .left, truncates: Bool = false) {
        NSAttributedString(string: text,
                           attributes: [.font: font, .foregroundColor: colour,
                                        .paragraphStyle: paragraph(alignment,
                                                                   truncates: truncates)])
            .draw(in: rect)
    }

    private static func controlWidth(_ label: String, font: NSFont) -> CGFloat {
        let text = NSAttributedString(string: label, attributes: [.font: font]).size().width
        return ceil(text) + 12 + 11 + 7 + 12
    }

    /// The mock's own duration forms: milliseconds under a second, seconds above.
    static func duration(_ ms: Int) -> String {
        ms < 1000 ? "\(ms)ms" : String(format: "%.1fs", Double(ms) / 1000)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
