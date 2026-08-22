import SwiftUI
import AppKit
import ProctorCore

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
    @State private var justGranted: WalkthroughFlow.Grant?
    /// Auto-advance is a convenience for someone already working the grants.
    /// Letting it fire before that skips the step that says what Proctor is.
    @State private var started = false
    @AppStorage(WalkthroughFlow.completionDefaultsKey) private var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// PRO-0067. The view keeps an `Int`-backed enum because the slide
    /// direction is computed from the ordering, and maps to
    /// `WalkthroughFlow.Step` for every decision and every string. One source
    /// for the flow, one for the animation, and no second answer to "which step
    /// is this".
    enum Step: Int, CaseIterable {
        case intro, permissions, connect

        var flow: WalkthroughFlow.Step {
            switch self {
            case .intro: return .intro
            case .permissions: return .permissions
            case .connect: return .connect
            }
        }
        /// PRO-0090. The table moved to `WalkthroughFlow.stepTitle(for:)`,
        /// beside `primaryAction`, `heading` and `lede`. `permissions` still
        /// returns empty there — the hero carries its own title.
        var title: String { WalkthroughFlow.stepTitle(for: flow) }
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
            // PRO-0086, closing DEF-160. The reason rides directly above the
            // buttons rather than up in the hero sheet: somebody stuck on a dead
            // control is looking at the control, and the sheet already carries
            // the restart note and the Settings link.
            VStack(alignment: .trailing, spacing: 6) {
                if let reason = disabledReason {
                    Text(reason)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(WalkthroughFlow.ID.reason)
                }
                HStack {
                    if step != .intro {
                        Button(WalkthroughFlow.Copy.back) { back() }
                            .accessibilityIdentifier(WalkthroughFlow.ID.back)
                    }
                    Spacer()
                    // Never disabled and never conditional on a grant. Skipping
                    // is completing (`WalkthroughFlow.completes`), so this is the
                    // way out for somebody macOS will not grant to, and the
                    // refusal above must not close it.
                    if step != .connect {
                        Button(WalkthroughFlow.Copy.skip) { complete() }
                            .accessibilityIdentifier(WalkthroughFlow.ID.skip)
                            .buttonStyle(.borderless)
                    }
                    // PRO-0081, closing PRO-0067's A3. Disabled and visible rather
                    // than absent: a control that disappears makes the layout jump
                    // and teaches the user the step does not exist. The rule is
                    // `WalkthroughFlow.primaryEnabled`, decided in Core where it is
                    // tested at every combination, because a decision made in a view
                    // body is one this repo cannot prove.
                    Button(WalkthroughFlow.primaryAction(for: step.flow)) { advance() }
                        .accessibilityIdentifier(WalkthroughFlow.ID.primary)
                        .buttonStyle(.borderedProminent)
                        .disabled(!WalkthroughFlow.primaryEnabled(
                            on: step.flow,
                            accessibility: granted(.accessibility),
                            screenRecording: granted(.screenRecording)))
                        // The same sentence a sighted person reads above, so
                        // VoiceOver landing on the button hears why it refuses
                        // without having to find the caption first.
                        .hint(disabledReason)
                }
            }
            .padding(.horizontal, 30).padding(.vertical, 16)
        }
        .frame(width: 620, height: 540)
        .onChange(of: granted(.accessibility)) { _, ok in onGrant(.accessibility, ok) }
        .onChange(of: granted(.screenRecording)) { _, ok in onGrant(.screenRecording, ok) }
    }

    // MARK: steps

    @ViewBuilder private var content: some View {
        switch step {
        case .intro:
            Para(WalkthroughFlow.Copy.introParagraph1)
            Para(WalkthroughFlow.Copy.introParagraph2)
            Callout(icon: WalkthroughFlow.Copy.introCalloutIcon, tint: .accentColor,
                    title: WalkthroughFlow.Copy.introCalloutTitle,
                    message: WalkthroughFlow.Copy.introCalloutMessage)

        case .permissions:
            HeroPermissions(
                appIcon: NSApp.applicationIconImage,
                accessibilityGranted: granted(.accessibility),
                screenRecordingGranted: granted(.screenRecording),
                justGranted: justGranted,
                reduceMotion: reduceMotion,
                onAllowAccessibility: { model.requestAccessibilityPrompt() },
                onAllowScreenRecording: { model.requestScreenRecordingPrompt() },
                onOpenSettings: {
                    // The pane anchor was a literal here and is a Core mapping
                    // that `MainWindow` already reads the same way. PRO-0081
                    // moved it there because an anchor macOS does not recognise
                    // opens the top of Settings and looks like the button did
                    // nothing.
                    if let pane = Actions.pane(for: WalkthroughFlow.Grant.accessibility.title) {
                        Actions.openPane(pane)
                    }
                })

        case .connect:
            Para(WalkthroughFlow.Copy.connectParagraph)
            ConnectSnippet()
            if model.ready {
                Callout(icon: WalkthroughFlow.Copy.connectReadyIcon, tint: .green,
                        title: WalkthroughFlow.Copy.connectReadyTitle,
                        message: WalkthroughFlow.Copy.connectReadyMessage)
            } else {
                Callout(icon: WalkthroughFlow.Copy.introCalloutIcon, tint: .accentColor,
                        title: WalkthroughFlow.Copy.connectPendingTitle,
                        message: WalkthroughFlow.Copy.connectPendingMessage)
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
    private func onGrant(_ grant: WalkthroughFlow.Grant, _ ok: Bool) {
        guard ok else { return }
        if step == .permissions { justGranted = grant }
        guard started, step == .permissions,
              granted(.accessibility), granted(.screenRecording) else { return }
        // Let the success animation finish before sliding the step away.
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.6)) {
            guard step == .permissions else { return }
            goingBack = false
            withAnimation(motion) { step = .connect }
        }
    }

    /// Why the primary refuses on this step, or nil when it does not.
    /// `WalkthroughFlow.primaryDisabledReason`, which is non-nil exactly where
    /// `primaryEnabled` is false — one rule, read twice, rather than a caption
    /// with its own idea of when to appear.
    private var disabledReason: String? {
        WalkthroughFlow.primaryDisabledReason(
            on: step.flow,
            accessibility: granted(.accessibility),
            screenRecording: granted(.screenRecording))
    }

    private func granted(_ grant: WalkthroughFlow.Grant) -> Bool {
        model.report?.grants.first { $0.name == grant.title }?.granted ?? false
    }
}

// MARK: - hero permission sheet

private struct HeroPermissions: View {
    let appIcon: NSImage
    let accessibilityGranted: Bool
    let screenRecordingGranted: Bool
    let justGranted: WalkthroughFlow.Grant?
    let reduceMotion: Bool
    let onAllowAccessibility: () -> Void
    let onAllowScreenRecording: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: appIcon)
                .resizable().frame(width: 72, height: 72)
                .padding(.top, 2).padding(.bottom, 16)
            Text(WalkthroughFlow.Copy.heroTitle).font(.system(size: 22, weight: .bold))
                .padding(.bottom, 7)
            Text(WalkthroughFlow.Copy.heroLede)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .padding(.bottom, 20)

            // PRO-0090, closing DEF-056. Which row is prominent is
            // `WalkthroughFlow.prominentGrant`, decided in Core where it is
            // tested at all four combinations, because the design of record's
            // rule — "Only one Grant is prominent at a time: the one to press
            // next" — is a claim about the pair and this repo cannot ask a view
            // about a pair.
            let prominent = WalkthroughFlow.prominentGrant(
                accessibility: accessibilityGranted,
                screenRecording: screenRecordingGranted)

            VStack(spacing: 10) {
                HeroPermRow(
                    grant: .accessibility,
                    granted: accessibilityGranted,
                    justGranted: justGranted == .accessibility,
                    prominent: prominent == .accessibility,
                    reduceMotion: reduceMotion, onAllow: onAllowAccessibility)
                HeroPermRow(
                    grant: .screenRecording,
                    granted: screenRecordingGranted,
                    justGranted: justGranted == .screenRecording,
                    prominent: prominent == .screenRecording,
                    reduceMotion: reduceMotion, onAllow: onAllowScreenRecording)
            }

            // PRO-0086, closing DEF-161. The design of record draws this
            // paragraph under the two rows in the pane where the grant is
            // missing and omits it where it is held; the build has rendered it
            // nowhere since PRO-0067 wrote the constant. Visibility is
            // `WalkthroughFlow.statesRestartNote` for the same reason the
            // other two footer rules live in Core.
            if WalkthroughFlow.statesRestartNote(screenRecording: screenRecordingGranted) {
                Text(WalkthroughFlow.Copy.restartNote)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                    .padding(.top, 14)
                    .accessibilityIdentifier(WalkthroughFlow.ID.restartNote)
            }

            if !(accessibilityGranted && screenRecordingGranted) {
                Button(WalkthroughFlow.Copy.openSettings, action: onOpenSettings)
                    .buttonStyle(.borderless).controlSize(.small)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HeroPermRow: View {
    let grant: WalkthroughFlow.Grant
    let granted: Bool
    let justGranted: Bool
    /// Whether this is the Grant to press next. Decided by
    /// `WalkthroughFlow.prominentGrant` and passed in, never worked out here:
    /// the rule is about both rows and a row can only see itself.
    let prominent: Bool
    let reduceMotion: Bool
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: grant.glyph)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(grant.title).font(.system(size: 13, weight: .semibold))
                Text(grant.rowDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if granted {
                HStack(spacing: 5) {
                    GrantSuccessCheck(animate: justGranted, reduceMotion: reduceMotion)
                    Text(WalkthroughFlow.Copy.allowed).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }
            } else {
                allowButton
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

    /// One button, two treatments. `.borderedProminent` is the filled Grant the
    /// design draws on the row to press next; `.bordered` is the plain one it
    /// draws on the other. Written as two branches rather than a conditional
    /// modifier because `buttonStyle` returns a different opaque type per style
    /// and SwiftUI has no way to pick one at the call site.
    @ViewBuilder private var allowButton: some View {
        if prominent {
            Button(WalkthroughFlow.Copy.allow, action: onAllow)
                .buttonStyle(.borderedProminent).controlSize(.small)
                .accessibilityIdentifier(WalkthroughFlow.ID.grantButton(grant))
                .accessibilityLabel(grant.allowLabel)
        } else {
            Button(WalkthroughFlow.Copy.allow, action: onAllow)
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityIdentifier(WalkthroughFlow.ID.grantButton(grant))
                .accessibilityLabel(grant.allowLabel)
        }
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
            Image(systemName: WalkthroughFlow.Copy.grantedCheckSymbol)
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
    /// PRO-0090. Both halves were literals here and both already had one Core
    /// definition: `Wire.shimPath` (PRO-0081, after two views assembled the same
    /// path by hand) and `StatusSurface.Copy.connectSnippet`, which the status
    /// window's Connect card copies. The two snippets were character-identical,
    /// so this is the same text a person pastes into an MCP host reaching one
    /// definition instead of two.
    private var path: String { Wire.shimPath(inBundle: Bundle.main.bundlePath) }
    private var snippet: String { StatusSurface.Copy.connectSnippet(shimPath: path) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snippet).font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .quaternarySystemFill),
                            in: RoundedRectangle(cornerRadius: 6))
            Button(WalkthroughFlow.Copy.copyConfig) { Actions.copy(snippet) }
                .accessibilityIdentifier(WalkthroughFlow.ID.copySnippet)
                .controlSize(.small)
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

// MARK: - PRO-0086

/// An accessibility hint that is not applied at all when there is nothing to
/// say.
///
/// Written as a modifier taking `String?` rather than
/// `.accessibilityHint(reason ?? "")` because `Walkthrough.swift` may hold no
/// string literal of its own — DEF-039 counts quote characters outside comments
/// and an empty fallback is two of them.
private extension View {
    @ViewBuilder func hint(_ text: String?) -> some View {
        if let text { accessibilityHint(text) } else { self }
    }
}
