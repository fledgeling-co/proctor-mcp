import SwiftUI
import AppKit

/// First-run walkthrough.
///
/// The static checklist is fine once you know what Proctor is; it is the wrong
/// thing to meet first. This walks the two grants one at a time, asks macOS for
/// the real consent dialog rather than only linking to Settings, and advances
/// on its own when the grant lands so nobody has to work out whether it worked.
struct Walkthrough: View {
    let model: AgentModel
    let finish: () -> Void

    @State private var step: Step = .intro
    /// Auto-advance is a convenience for someone already working through the
    /// grants. Letting it fire before that skips the one step that says what
    /// Proctor is, which is the first thing anyone opening this needs.
    @State private var started = false
    @AppStorage("walkthroughCompleted") private var completed = false

    enum Step: Int, CaseIterable {
        case intro, accessibility, screenRecording, connect, done
        var title: String {
            switch self {
            case .intro:           return "What Proctor does"
            case .accessibility:   return "Let Proctor read and drive your app"
            case .screenRecording: return "Let Proctor see what your app drew"
            case .connect:         return "Point a model at it"
            case .done:            return "Ready"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressDots(current: step)
                .padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(step.title).font(.system(size: 22, weight: .semibold))
                    content
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                if step != .intro {
                    Button("Back") { withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .intro } }
                }
                Spacer()
                Button("Skip setup") { completed = true; finish() }
                    .buttonStyle(.borderless)
                Button(primaryLabel) { advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(primaryDisabled)
            }
            .padding(.horizontal, 30).padding(.vertical, 16)
        }
        .frame(width: 620, height: 540)
        .onChange(of: model.report?.ready) { _, isReady in
            // Advance on the real state change rather than making the user
            // decide whether their click in System Settings took effect.
            if started, isReady == true, step == .accessibility || step == .screenRecording {
                withAnimation { step = .connect }
            }
        }
        .onChange(of: granted("Accessibility")) { _, ok in
            if started, ok, step == .accessibility { withAnimation { step = .screenRecording } }
        }
        .onChange(of: granted("Screen Recording")) { _, ok in
            if started, ok, step == .screenRecording { withAnimation { step = .connect } }
        }
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

        case .accessibility:
            Para("This is the one that lets Proctor read your app's controls and press them. "
                 + "Without it, every element looks missing rather than blocked.")
            GrantStep(
                name: "Accessibility",
                granted: granted("Accessibility"),
                primary: "Ask macOS now",
                onPrimary: { model.requestAccessibilityPrompt() },
                secondary: "Open System Settings",
                onSecondary: { Actions.openPane("Privacy_Accessibility") },
                note: "macOS only offers its dialog once per app. If nothing appears, the answer "
                    + "is already recorded and you will need to change it in System Settings — "
                    + "Proctor is under Privacy & Security ▸ Accessibility.")

        case .screenRecording:
            Para("This one lets Proctor capture the window's pixels, so a model can check what "
                 + "your app actually rendered rather than only what it claims.")
            GrantStep(
                name: "Screen Recording",
                granted: granted("Screen Recording"),
                primary: "Ask macOS now",
                onPrimary: { model.requestScreenRecordingPrompt() },
                secondary: "Open System Settings",
                onSecondary: { Actions.openPane("Privacy_ScreenCapture") },
                note: "Apple never lets this one be granted silently or by a profile on any "
                    + "version of macOS — a person has to click it. macOS offers its dialog once "
                    + "per app; if nothing appears, add Proctor by hand under Privacy & Security "
                    + "▸ Screen & System Audio Recording.")
            Button("Reveal Proctor in Finder") { Actions.revealSelf() }
                .controlSize(.small)
            Text("Proctor is installed in your own Applications folder, so the file picker's "
                 + "default location will not list it. Reveal it and drag it in.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

        case .connect:
            Para("Add Proctor to whichever tool you drive it from. The command below holds no "
                 + "permissions of its own; it just forwards to Proctor, which does.")
            ConnectSnippet()

        case .done:
            Para("Proctor is ready. It stays running in the background and lives in the menu bar; "
                 + "reopen this window from there whenever you want to check on it.")
        }
    }

    private var primaryLabel: String {
        switch step {
        case .connect: return "Finish"
        case .done:    return "Close"
        default:       return "Continue"
        }
    }

    private var primaryDisabled: Bool { false }

    private func advance() {
        started = true
        if step == .connect || step == .done { completed = true; finish(); return }
        withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .done }
    }

    private func granted(_ name: String) -> Bool {
        model.report?.grants.first { $0.name == name }?.granted ?? false
    }
}

// MARK: - pieces

private struct Para: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GrantStep: View {
    let name: String
    let granted: Bool
    let primary: String
    let onPrimary: () -> Void
    let secondary: String?
    let onSecondary: (() -> Void)?
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(granted ? .green : .orange)
                Text(granted ? "\(name) is granted" : "\(name) is not granted yet")
                    .font(.system(size: 13, weight: .medium))
            }
            if !granted {
                HStack {
                    Button(primary, action: onPrimary)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("\(primary) — \(name)")
                    if let secondary, let onSecondary {
                        Button(secondary, action: onSecondary)
                            .accessibilityLabel("\(secondary) — \(name)")
                    }
                }
                Text(note).font(.system(size: 11)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((granted ? Color.green : Color.orange).opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 8))
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

private struct ProgressDots: View {
    let current: Walkthrough.Step
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Walkthrough.Step.allCases.dropLast(), id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= current.rawValue ? Color.accentColor : Color(nsColor: .quaternaryLabelColor))
                    .frame(height: 3)
            }
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
