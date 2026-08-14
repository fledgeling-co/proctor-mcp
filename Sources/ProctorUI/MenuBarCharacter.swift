import AppKit
import SwiftUI
import ProctorCore

// The character, in the menu bar.
//
// The panel it normally lives in can be on a display nobody is looking at, and
// it can now be hidden outright. The menu bar is on every display and always
// there, so the character does its one job — making the run's state legible at a
// glance — from the surface a person actually sees.
//
// Nothing here decides what state Proctor is in. The phase arrives from the
// agent, out of the one `RunHUDState` it reduces, so the menu bar and the panel
// can never disagree about what is happening.
//
// TWO THINGS THIS DOES DIFFERENTLY FROM THE PANEL, both deliberate:
//
//   IT IS NOT A TEMPLATE IMAGE. A template keys off the alpha channel and paints
//   the whole silhouette in one tint, which would throw away the thing that makes
//   these states readable — vermilion carries acting, blocked, finished and
//   error, and grey belongs to paused alone, which is what lets paused be told
//   apart without relying on colour at all. It would also invert the character:
//   the case is white with a near-black outline, so as a template the case would
//   become the tint and the screen would become a hole. The cost accepted is that
//   the item does not adopt menu bar tinting.
//
//   IT IS STILL WHEN NOTHING IS RUNNING. The panel's idle is a slow one-pixel
//   bob, which is fine on something only on screen during a run. This is on
//   screen for as long as the Mac is, and a permanently moving menu bar item is
//   an irritation and a battery cost carrying no information. `RunHUDMotion`
//   holds that rule, in Core, where it is checkable without a display.

/// The menu bar pictures, decoded once.
///
/// One `NSImage` per frame carrying all three densities as representations, so
/// AppKit picks the right one per display rather than resampling pixel art onto
/// a fraction of a point. A missing picture yields nil and the menu bar falls
/// back to its status symbol — a smaller failure than an app that would not draw.
@MainActor
enum MenuBarSprites {

    private static var cache: [String: NSImage] = [:]
    private static var attempted = false
    private static var loaded = false

    /// Whether the whole set decoded. All-or-nothing on purpose, the same rule
    /// the panel's loader uses: half a character means a state silently drawing
    /// some other state's picture, which is a menu bar telling somebody the wrong
    /// thing about a run they are supervising.
    static var available: Bool {
        load()
        return loaded
    }

    static func image(named asset: String) -> NSImage? {
        load()
        return cache[asset]
    }

    private static func load() {
        guard !attempted else { return }
        attempted = true
        let side = CGFloat(RunHUDCharacter.menuBarSide)
        var built: [String: NSImage] = [:]
        for asset in RunHUDCharacter.assets {
            let image = NSImage(size: NSSize(width: side, height: side))
            var reps = 0
            for scale in RunHUDCharacter.densities {
                guard let url = RunHUDCharacter.menuBarAssetURL(asset: asset, scale: scale),
                      let data = try? Data(contentsOf: url),
                      let rep = NSBitmapImageRep(data: data) else { continue }
                // The representation reports the size it should draw at, in
                // points, not the pixel count it holds. Without this every
                // density would claim to be a different-sized picture and AppKit
                // would pick by area rather than by the display's scale.
                rep.size = NSSize(width: side, height: side)
                image.addRepresentation(rep)
                reps += 1
            }
            guard reps > 0 else { return }
            // Never a template. See this file's header.
            image.isTemplate = false
            built[asset] = image
        }
        cache = built
        loaded = true
    }
}

/// The clock behind the two states that move.
///
/// The panel hands its loop to the render server once and never draws a frame.
/// A menu bar item cannot, so this is a timer — and it exists only while
/// something is actually moving. An idle Proctor costs no timer at all, which is
/// the whole reason the menu bar's motion rule is narrower than the panel's.
@MainActor
@Observable
final class MenuBarCharacter {

    private(set) var phase: RunHUDPhase = .idle
    /// Bumped by the timer; the view reads it so a frame change redraws.
    private(set) var tick = 0

    private var timer: Timer?
    private var startedAt = Date()
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var motionObserver: NSObjectProtocol?

    init() {
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reduceMotion =
                        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    self.restart()
                }
            }
    }

    func show(_ phase: RunHUDPhase) {
        guard phase != self.phase else { return }
        self.phase = phase
        restart()
    }

    /// The picture to draw right now, or nil when the set could not be decoded.
    var image: NSImage? {
        guard MenuBarSprites.available else { return nil }
        let frames = RunHUDMotion.menuBar(for: phase, reduceMotion: reduceMotion)
        let elapsed = Date().timeIntervalSince(startedAt)
        let index = RunHUDMotion.frameIndex(in: frames, elapsed: elapsed)
        guard index < frames.count else { return nil }
        return MenuBarSprites.image(named: frames[index].asset)
    }

    private func restart() {
        timer?.invalidate(); timer = nil
        startedAt = Date()
        tick &+= 1
        let frames = RunHUDMotion.menuBar(for: phase, reduceMotion: reduceMotion)
        guard let interval = RunHUDMotion.menuBarTick(for: frames) else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick &+= 1 }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// The item itself: the character when there is nothing more urgent to say, and
/// the agent's own status symbol when there is.
///
/// Readiness outranks the character deliberately. A calm idle character over an
/// agent that is not answering, or one missing Accessibility, is a picture
/// telling somebody a falsehood about their machine — and the permission state is
/// the one thing that has to be true before anything else about Proctor works.
struct MenuBarLabel: View {
    let icon: MenuBarIcon
    let character: MenuBarCharacter

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
        case .character:
            // Reading `tick` is what subscribes this view to the frame clock.
            // The phase itself is pushed in by the poll, never set from a body —
            // a view that mutated the model while drawing would be changing state
            // during a view update.
            let _ = character.tick
            if let image = character.image {
                Image(nsImage: image)
                    // Original, not template: the colour is the state.
                    .renderingMode(.original)
                    // Nearest-neighbour, so a menu bar that is not exactly 22pt
                    // degrades to hard pixels rather than to a blur. Pixel art is
                    // the one thing about this character that makes it gain
                    // legibility as it shrinks.
                    .interpolation(.none)
                    .frame(width: CGFloat(RunHUDCharacter.menuBarSide),
                           height: CGFloat(RunHUDCharacter.menuBarSide))
            } else {
                // The pictures did not decode. Say Proctor is fine rather than
                // showing nothing at all.
                Image(systemName: "checkmark.seal")
            }
        }
    }
}
