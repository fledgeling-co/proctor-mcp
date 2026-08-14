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

    /// The queue's own rows. The bar is the reference's `.qbar` — 9pt above and
    /// below a 15pt line — and the body is its header row plus one 28pt row per
    /// run. Both are zero when nothing is waiting: the queue costs nothing until
    /// there is contention, so the panel is exactly the size it was before.
    static let queueBar: CGFloat = 33
    static let queueHeader: CGFloat = 35   // 9 + 23 + 3
    static let queueRow: CGFloat = 28
    static let queueListPad: CGFloat = 12  // 2 above, 10 below

    static func queueBlock(_ queue: RunQueueModel) -> CGFloat {
        guard queue.visible else { return 0 }
        guard queue.expanded else { return queueBar }
        return queueBar + queueHeader + queueListPad + CGFloat(queue.rows.count) * queueRow
    }

    static func height(exception: Bool, queue: RunQueueModel = RunQueueModel()) -> CGFloat {
        lineRow + (exception ? exceptionRow : 0) + trailBlock + queueBlock(queue) + footBlock
    }

    /// Where the trail starts, which is the only thing the exception line moves.
    static func trailTop(exception: Bool) -> CGFloat {
        lineRow + (exception ? exceptionRow : 0)
    }

    /// Where the queue starts: straight after the trail, and straight before the
    /// footer. PRO-0015 left this slot open deliberately.
    static func queueTop(exception: Bool) -> CGFloat {
        trailTop(exception: exception) + trailBlock
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

    /// Everything a click can land on. Note which words are here and which are
    /// not: the run's controls are Pause and Stop, the queue's are Hold and
    /// Clear, and the two pairs never sit side by side and never share a word.
    /// Two controls both called "pause" is how somebody stops the wrong one.
    enum Control: Equatable {
        case pause, stop, grip
        case queueBar, hold, clear
        case drop(Int)
    }

    weak var owner: RunHUDPanel?
    var model = RunHUDModel()
    var elapsed: TimeInterval = 0

    private var hovered: Control?
    private var pressed: Control?
    private var dragAnchor: NSPoint?
    private var pauseRect: NSRect = .zero
    private var stopRect: NSRect = .zero
    private var gripRect: NSRect = .zero
    private var queueBarRect: NSRect = .zero
    private var holdRect: NSRect = .zero
    private var clearRect: NSRect = .zero
    /// One per drawn row, keyed by the scheduler's run id so a drop removes the
    /// run a person pointed at rather than whatever has since slid into that
    /// position.
    private var dropRects: [(rect: NSRect, run: Int)] = []

    /// The two things on this panel that move, as subviews rather than as
    /// sublayers: a subview's frame is unambiguously in this view's own flipped
    /// coordinates, where a raw sublayer's depends on whether AppKit flipped the
    /// backing layer's geometry — a difference nothing here could check without
    /// a display.
    private let character = RunHUDCharacterView(frame: .zero)
    private let railFill = RunHUDRailView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(character)
        addSubview(railFill)
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// Where the character sits: the bay, inset from the grip.
    static func bayRect() -> NSRect {
        let gripMaxX = RunHUDLayout.pad + 10
        return NSRect(x: gripMaxX + 11, y: 13,
                      width: RunHUDLayout.bay, height: RunHUDLayout.bay)
    }

    override func layout() {
        super.layout()
        character.frame = Self.bayRect()
        let width = bounds.width * CGFloat(model.progress)
        railFill.frame = NSRect(x: 0, y: bounds.height - RunHUDLayout.rail,
                                width: width, height: RunHUDLayout.rail)
    }

    /// Push the model into the two moving pieces. Separate from `needsDisplay`
    /// because a loop restarted on every 1 Hz clock tick is a twitch, not a
    /// motion, and because what moves is decided in Core rather than here.
    func syncAccessories() {
        needsLayout = true
        character.show(model.phase)
        railFill.apply(
            colour: palette.colour(for: model.tone),
            glow: RunHUDMotion.railGlow(
                for: model.phase,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
    }

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
            case .queueBar: owner?.toggleQueue()
            case .hold: owner?.toggleHold()
            case .clear: owner?.clearQueue()
            case .drop(let run): owner?.dropFromQueue(run)
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
        guard model.queue.visible else { return nil }
        if holdRect.contains(point) { return .hold }
        if clearRect.contains(point) { return .clear }
        for entry in dropRects where entry.rect.contains(point) { return .drop(entry.run) }
        // The bar itself is last, because the controls drawn inside the expanded
        // body sit within its column and would otherwise be swallowed by it.
        if queueBarRect.contains(point) { return .queueBar }
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
        let queueTop = RunHUDLayout.queueTop(exception: hasException)
        drawQueue(p: p, top: queueTop)
        drawFoot(p: p, live: live, top: queueTop + RunHUDLayout.queueBlock(model.queue))
        // Only the track. PRO-0017 moved the progress fill into `railFill`, a
        // hosted layer, so that it can pulse without the width transitioning.
        drawRail(p: p)
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

        // The character's bay. The well is drawn here and the sprite sits in it
        // as a subview, clipped to the same rounded rect — so a raised arm or a
        // trail of speed lines runs off the edge of the well rather than out
        // across the panel. The bay stays dark in both appearances because the
        // character is white-bodied and would vanish on the light panel.
        let bay = Self.bayRect()
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

    /// The queue bar, and the list it expands into.
    ///
    /// It sits between the trail and the run controls, which is the slot PRO-0015
    /// left open. When nothing is waiting it draws nothing at all and takes no
    /// height: the queue costs nothing until there is contention.
    ///
    /// Hold and Clear live in the list's own header. They are never adjacent to
    /// Pause and Stop and never share a word with them, because two controls both
    /// called "pause" is how somebody stops the wrong thing — the run they were
    /// watching instead of the line behind it.
    private func drawQueue(p: RunHUDPalette, top: CGFloat) {
        queueBarRect = .zero
        holdRect = .zero
        clearRect = .zero
        dropRects = []
        let queue = model.queue
        guard queue.visible else { return }

        p.separator.setFill()
        NSRect(x: 0, y: top, width: bounds.width, height: 0.5).fill()
        queueBarRect = NSRect(x: 0, y: top, width: bounds.width, height: RunHUDLayout.queueBar)
        if hovered == .queueBar {
            p.fill.setFill()
            queueBarRect.fill()
        }

        // The stack glyph: three bars, the reference's shorthand for a line of
        // work rather than an icon that needs learning.
        p.ink3.setFill()
        let stackX = RunHUDLayout.pad
        let stackY = top + 11
        for (row, inset) in [(0, 3.0), (1, 0.0), (2, 3.0)] {
            NSBezierPath(roundedRect: NSRect(x: stackX, y: stackY + CGFloat(row) * 4,
                                             width: 13 - inset, height: 3),
                         xRadius: 1, yRadius: 1).fill()
        }

        // "3 sessions waiting", with the count in the ink and tabular so it
        // cannot move the word beside it.
        let font = NSFont.systemFont(ofSize: 12)
        let countFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let labelY = top + 9
        if queue.waitingCount > 0 {
            let count = "\(queue.waitingCount)"
            let countWidth = ceil(NSAttributedString(string: count,
                                                     attributes: [.font: countFont]).size().width)
            draw(text: count, font: countFont, colour: p.ink,
                 in: NSRect(x: stackX + 22, y: labelY, width: countWidth + 2, height: 16))
            let rest = queue.waitingCount == 1 ? " session waiting" : " sessions waiting"
            draw(text: rest, font: font, colour: p.ink2,
                 in: NSRect(x: stackX + 22 + countWidth + 2, y: labelY,
                            width: RunHUDLayout.width - stackX - 22 - countWidth - 40, height: 16))
        } else {
            // Held with nothing waiting. The bar stays so Hold can be released;
            // it says what state the machine is in rather than showing a zero.
            draw(text: queue.label, font: font, colour: p.amber,
                 in: NSRect(x: stackX + 22, y: labelY,
                            width: RunHUDLayout.width - stackX - 62, height: 16),
                 truncates: true)
        }

        drawChevron(p: p, in: NSRect(x: RunHUDLayout.width - 12 - 10, y: top + 12,
                                     width: 10, height: 10), up: queue.expanded)

        guard queue.expanded else { return }

        let bodyTop = top + RunHUDLayout.queueBar
        p.separator.setFill()
        NSRect(x: 0, y: bodyTop, width: bounds.width, height: 0.5).fill()

        // The header: the section's name, then its two controls.
        draw(text: "QUEUE", font: .systemFont(ofSize: 10, weight: .bold), colour: p.ink3,
             in: NSRect(x: RunHUDLayout.pad, y: bodyTop + 14, width: 80, height: 14))

        let miniFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let clearWidth = Self.miniWidth("Clear", font: miniFont)
        clearRect = NSRect(x: RunHUDLayout.width - 12 - clearWidth, y: bodyTop + 9,
                           width: clearWidth, height: 23)
        let holdWidth = Self.miniWidth(queue.holdLabel, font: miniFont)
        holdRect = NSRect(x: clearRect.minX - 6 - holdWidth, y: bodyTop + 9,
                          width: holdWidth, height: 23)

        // Held is a state, and the button says so rather than looking the same
        // whether or not it is on.
        drawMini(holdRect, label: queue.holdLabel, font: miniFont,
                 ink: queue.held ? p.amber : p.ink2,
                 fill: queue.held ? p.amber.withAlphaComponent(0.20) : nil,
                 hoverFill: p.fill2, hoverInk: p.ink, control: .hold, palette: p)
        drawMini(clearRect, label: "Clear", font: miniFont, ink: p.ink2, fill: nil,
                 hoverFill: p.red.withAlphaComponent(0.20), hoverInk: p.red,
                 control: .clear, palette: p)

        // The rows. Every run the scheduler knows about except the one on the
        // live line: a run in another lane is running, not queued, and calling it
        // queued would understate what the scheduler can actually do.
        var y = bodyTop + RunHUDLayout.queueHeader + 2
        let posFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let whoFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let sidFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let waitFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        for row in queue.rows {
            let mark = row.position.map { "\($0)" } ?? "▸"
            draw(text: mark, font: posFont, colour: p.ink4,
                 in: NSRect(x: RunHUDLayout.pad, y: y + 8, width: 12, height: 13))

            let whoWidth = ceil(NSAttributedString(string: row.session,
                                                   attributes: [.font: whoFont]).size().width)
            draw(text: row.session, font: whoFont, colour: p.ink,
                 in: NSRect(x: RunHUDLayout.pad + 21, y: y + 6, width: min(whoWidth, 120),
                            height: 16), truncates: true)
            let sidX = RunHUDLayout.pad + 21 + min(whoWidth, 120) + 6
            draw(text: row.connection, font: sidFont, colour: p.ink3,
                 in: NSRect(x: sidX, y: y + 8, width: 34, height: 13))

            let waitWidth: CGFloat = 34
            let dropWidth: CGFloat = 19
            let waitX = RunHUDLayout.width - 12 - dropWidth - 6 - waitWidth
            draw(text: row.waited, font: waitFont, colour: p.ink3,
                 in: NSRect(x: waitX, y: y + 8, width: waitWidth, height: 13),
                 alignment: .right)

            let taskX = sidX + 38
            draw(text: row.summary, font: .systemFont(ofSize: 12), colour: p.ink3,
                 in: NSRect(x: taskX, y: y + 6, width: max(0, waitX - taskX - 8), height: 16),
                 truncates: true)

            // Only a waiting run can be dropped. A run that is already driving an
            // app is stopped from the run controls, not removed from a line it is
            // no longer in.
            if row.isWaiting {
                let dropRect = NSRect(x: RunHUDLayout.width - 12 - dropWidth,
                                      y: y + 4, width: dropWidth, height: dropWidth)
                dropRects.append((dropRect, row.run))
                let hot = hovered == .drop(row.run)
                if hot {
                    p.red.withAlphaComponent(0.20).setFill()
                    NSBezierPath(roundedRect: dropRect, xRadius: 5, yRadius: 5).fill()
                }
                (hot ? p.red : p.ink4).setStroke()
                let cross = NSBezierPath()
                cross.lineWidth = 1.6
                cross.lineCapStyle = .round
                let box = dropRect.insetBy(dx: 5.5, dy: 5.5)
                cross.move(to: NSPoint(x: box.minX, y: box.minY))
                cross.line(to: NSPoint(x: box.maxX, y: box.maxY))
                cross.move(to: NSPoint(x: box.maxX, y: box.minY))
                cross.line(to: NSPoint(x: box.minX, y: box.maxY))
                cross.stroke()
            }
            y += RunHUDLayout.queueRow
        }
    }

    private func drawChevron(p: RunHUDPalette, in rect: NSRect, up: Bool) {
        p.ink3.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if up {
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.maxY - 3.4))
            path.line(to: NSPoint(x: rect.midX, y: rect.minY + 3.4))
            path.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 3.4))
        } else {
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + 3.6))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 3.4))
            path.line(to: NSPoint(x: rect.maxX - 2, y: rect.minY + 3.6))
        }
        path.stroke()
    }

    private func drawMini(_ rect: NSRect, label: String, font: NSFont, ink: NSColor,
                          fill: NSColor?, hoverFill: NSColor, hoverInk: NSColor,
                          control: Control, palette p: RunHUDPalette) {
        let hot = hovered == control
        if let background = hot ? hoverFill : fill {
            background.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
        draw(text: label, font: font, colour: hot ? hoverInk : ink,
             in: NSRect(x: rect.minX, y: rect.midY - 8, width: rect.width, height: 16),
             alignment: .center)
    }

    private static func miniWidth(_ label: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: label, attributes: [.font: font]).size().width) + 18
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
    /// Only the track is drawn here. The filled part is a layer, so the
    /// reference's pulse while a run is moving is committed to the render server
    /// once rather than serviced by this process — and so a person's Reduce
    /// Motion setting can stop it by simply not adding the animation. Every
    /// state stays readable from its words and its colour with nothing moving,
    /// which is the property that has to hold either way.
    private func drawRail(p: RunHUDPalette) {
        let y = bounds.height - RunHUDLayout.rail
        p.fill.setFill()
        NSRect(x: 0, y: y, width: bounds.width, height: RunHUDLayout.rail).fill()
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
