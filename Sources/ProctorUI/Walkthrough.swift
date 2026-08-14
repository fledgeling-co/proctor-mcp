import SwiftUI
import AppKit

/// First-run walkthrough.
///
/// Three steps: what Proctor is, the two grants as one hero sheet, and the
/// connect snippet. The permission step asks macOS for the real consent dialog
/// rather than only linking to Settings, plays the grant back the moment it
/// lands, and advances on its own once both are granted so nobody has to work
/// out whether it took.
struct Walkthrough: View {
    let model: AgentModel
    let finish: () -> Void

    @State private var step: Step = .intro
    /// The step just left, so the entrance can slide from the correct side.
    @State private var goingBack = false
    /// Which permission most recently flipped to granted, so its row plays the
    /// success animation once rather than on every redraw.
    @State private var justGranted: String?
    /// Auto-advance is a convenience for someone already working the grants.
    /// Letting it fire before that skips the step that says what Proctor is.
    @State private var started = false
    @AppStorage("walkthroughCompleted") private var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Int, CaseIterable {
        case intro, permissions, connect
        var title: String {
            switch self {
            case .intro:       return "What Proctor does"
            case .permissions: return ""          // the hero carries its own title
            case .connect:     return "Point a model at it"
            }
        }
    }

    private var motion: Animation? { reduceMotion ? nil : Motion.step }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressDots(current: step.rawValue, count: Step.allCases.count)
                .padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !step.title.isEmpty {
                        Text(step.title).font(.system(size: 22, weight: .semibold))
                    }
                    content
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(reduceMotion ? .opacity
                            : .slideNudge(from: goingBack ? .leading : .trailing))
            }

            Divider()
            HStack {
                if step != .intro {
                    Button("Back") { back() }
                }
                Spacer()
                if step != .connect {
                    Button("Skip setup") { complete() }
                        .buttonStyle(.borderless)
                }
                Button(step == .connect ? "Finish" : "Continue") { advance() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 30).padding(.vertical, 16)
        }
        .frame(width: 620, height: 540)
        .onChange(of: granted("Accessibility")) { _, ok in onGrant("Accessibility", ok) }
        .onChange(of: granted("Screen Recording")) { _, ok in onGrant("Screen Recording", ok) }
    }

    // MARK: steps

    @ViewBuilder private var content: some View {
        switch step {
        case .intro:
            Para("Proctor lets a model test a Mac app the way a person would check it: read what "
                 + "is actually on screen, operate the controls, and look at what the app drew.")
            Para("It works through macOS's accessibility system rather than by faking mouse and "
                 + "keyboard input, so it can drive a window that is behind another one, or on "
                 + "another Space, without stealing your focus or interrupting what you are doing.")
            Callout(icon: "lock.shield", tint: .accentColor,
                    title: "Two permissions, asked once",
                    message: "macOS gives these to Proctor itself, not to the tool driving it. That is "
                        + "why they survive when you upgrade or switch the model you use.")

        case .permissions:
            HeroPermissions(
                appIcon: NSApp.applicationIconImage,
                accessibilityGranted: granted("Accessibility"),
                screenRecordingGranted: granted("Screen Recording"),
                justGranted: justGranted,
                reduceMotion: reduceMotion,
                onAllowAccessibility: { model.requestAccessibilityPrompt() },
                onAllowScreenRecording: { model.requestScreenRecordingPrompt() },
                onOpenSettings: { Actions.openPane("Privacy_Accessibility") })

        case .connect:
            Para("Last step. Add Proctor to whichever tool you drive it from. The command below "
                 + "holds no permissions of its own; it just forwards to Proctor, which does.")
            ConnectSnippet()
            if model.ready {
                Callout(icon: "checkmark.seal.fill", tint: .green,
                        title: "You're all set",
                        message: "Both permissions are granted. Proctor stays running in the "
                            + "background and lives in the menu bar — no Dock icon. Open Proctor "
                            + "Status any time to re-check, see attached apps, or copy this again.")
            } else {
                Callout(icon: "lock.shield", tint: .accentColor,
                        title: "Proctor lives in the menu bar",
                        message: "It stays running in the background — no Dock icon, because it is "
                            + "something a model drives. You can grant the remaining permission any "
                            + "time from Proctor Status.")
            }
        }
    }

    // MARK: transitions

    private func advance() {
        started = true
        if step == .connect { complete(); return }
        goingBack = false
        withAnimation(motion) { step = Step(rawValue: step.rawValue + 1) ?? .connect }
    }

    private func back() {
        goingBack = true
        withAnimation(motion) { step = Step(rawValue: step.rawValue - 1) ?? .intro }
    }

    private func complete() { completed = true; finish() }

    /// A grant landed. Play it back on its row, and once both are in, move on.
    private func onGrant(_ name: String, _ ok: Bool) {
        guard ok else { return }
        if step == .permissions { justGranted = name }
        guard started, step == .permissions,
              granted("Accessibility"), granted("Screen Recording") else { return }
        // Let the success animation finish before sliding the step away.
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.6)) {
            guard step == .permissions else { return }
            goingBack = false
            withAnimation(motion) { step = .connect }
        }
    }

    private func granted(_ name: String) -> Bool {
        model.report?.grants.first { $0.name == name }?.granted ?? false
    }
}

// MARK: - hero permission sheet

private struct HeroPermissions: View {
    let appIcon: NSImage
    let accessibilityGranted: Bool
    let screenRecordingGranted: Bool
    let justGranted: String?
    let reduceMotion: Bool
    let onAllowAccessibility: () -> Void
    let onAllowScreenRecording: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: appIcon)
                .resizable().frame(width: 72, height: 72)
                .padding(.top, 2).padding(.bottom, 16)
            Text("Enable Proctor").font(.system(size: 22, weight: .bold))
                .padding(.bottom, 7)
            Text("Proctor needs two macOS permissions to read and drive your apps. They go to "
                 + "Proctor itself, asked once, and are used only when a model you connect asks "
                 + "it to run a test.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .padding(.bottom, 20)

            VStack(spacing: 10) {
                HeroPermRow(
                    name: "Accessibility", glyph: "accessibility",
                    desc: "Lets Proctor read the control tree and drive it",
                    granted: accessibilityGranted,
                    justGranted: justGranted == "Accessibility",
                    reduceMotion: reduceMotion, onAllow: onAllowAccessibility)
                HeroPermRow(
                    name: "Screen Recording", glyph: "display",
                    desc: "Lets Proctor see what your app drew",
                    granted: screenRecordingGranted,
                    justGranted: justGranted == "Screen Recording",
                    reduceMotion: reduceMotion, onAllow: onAllowScreenRecording)
            }

            if !(accessibilityGranted && screenRecordingGranted) {
                Button("Already allowed? Open System Settings", action: onOpenSettings)
                    .buttonStyle(.borderless).controlSize(.small)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HeroPermRow: View {
    let name: String
    let glyph: String
    let desc: String
    let granted: Bool
    let justGranted: Bool
    let reduceMotion: Bool
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .semibold))
                Text(desc).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if granted {
                HStack(spacing: 5) {
                    GrantSuccessCheck(animate: justGranted, reduceMotion: reduceMotion)
                    Text("Allowed").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }
            } else {
                Button("Allow", action: onAllow)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .accessibilityLabel("Allow \(name)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .stroke(granted ? Color.green.opacity(0.35) : Color(nsColor: .separatorColor),
                    lineWidth: 1))
    }
}

/// The mock's grant-success moment: a check that pops in (scale .2 → 1.15 → 1)
/// with a ring radiating out behind it. Plays once, on the flip to granted.
private struct GrantSuccessCheck: View {
    let animate: Bool
    let reduceMotion: Bool
    @State private var scale: CGFloat = 0.2
    @State private var ringScale: CGFloat = 0.55
    @State private var ringOpacity: Double = 0.55

    private var playing: Bool { animate && !reduceMotion }

    var body: some View {
        ZStack {
            if playing {
                Circle().stroke(Color.green, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
            }
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .scaleEffect(playing ? scale : 1)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            guard playing else { return }
            withAnimation(Motion.slow) { scale = 1 }
            withAnimation(.easeOut(duration: 0.5)) { ringScale = 2.4; ringOpacity = 0 }
        }
    }
}

private struct ProgressDots: View {
    let current: Int
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.accentColor
                          : Color(nsColor: .quaternaryLabelColor))
                    .frame(height: 3)
                    .keyframeAnimator(initialValue: 1.0, trigger: current) { view, scaleY in
                        view.scaleEffect(x: 1,
                                         y: (reduceMotion || i != current) ? 1 : scaleY,
                                         anchor: .center)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(2.2, duration: 0.18)
                            CubicKeyframe(1.0, duration: 0.24)
                        }
                    }
                    .animation(reduceMotion ? nil : Motion.med, value: current)
            }
        }
    }
}

// MARK: - shared pieces

private struct Para: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ConnectSnippet: View {
    private var path: String { Bundle.main.bundlePath + "/Contents/MacOS/proctor-shim" }
    private var snippet: String {
        "{\n  \"mcpServers\": {\n    \"proctor\": { \"command\": \"\(path)\" }\n  }\n}"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snippet).font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .quaternarySystemFill),
                            in: RoundedRectangle(cornerRadius: 6))
            Button("Copy config") { Actions.copy(snippet) }.controlSize(.small)
        }
    }
}

private struct Callout: View {
    let icon: String, tint: Color, title: String, message: String
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}
