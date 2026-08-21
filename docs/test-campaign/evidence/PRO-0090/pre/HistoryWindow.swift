import SwiftUI
import AppKit
import ProctorCore

// The History window.
//
// On the look, since two palette decisions are already settled elsewhere and
// neither applies here. The run HUD is neutral graphite on neutral white with
// vermilion as its only colour, because a panel floating over somebody else's
// application must not borrow that application's palette; the warm porcelain
// from the onboarding mock was tried in that position and rejected for reading
// as brown mud. This window has neither problem. It is Proctor's own window,
// opened from Proctor's own status window and sitting beside it, so it is built
// in that window's language — system cards, the monospaced uppercase section
// titles, system tints — and adopting the HUD's graphite here would make Proctor
// look like two applications rather than one.
//
// The one visual idea that is new is the fence, and it is containment rather
// than decoration. See `Fence` below.
struct HistoryWindow: View {
    @State private var model = HistoryModel()
    @State private var confirmingClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HistoryHeader(model: model, confirmingClear: $confirmingClear)
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 620, minHeight: 460)
        .onAppear {
            excludeFromCapture()
            model.load()
        }
        .onDisappear { model.forget() }
        .confirmationDialog("Clear Proctor's history?", isPresented: $confirmingClear) {
            Button("Clear history", role: .destructive) { model.clear() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Everything recorded here is removed from this Mac and cannot be brought "
                 + "back. Proctor keeps a note that the history was cleared, how much went, "
                 + "and when — but not what was in it.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            Card { ProgressView().controlSize(.small) }
        case .empty:
            Card {
                Text("Nothing recorded yet.").font(.system(size: 13, weight: .medium))
                Text("Proctor writes to its history whenever a model drives this Mac. "
                     + "When that has happened, the runs appear here.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .unreadable(let why):
            Card {
                Label("The history cannot be opened on this Mac",
                      systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 13, weight: .medium))
                // The agent's own words. It knows why; this window does not, and
                // guessing would be worse than quoting.
                Text(verbatim: why)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Proctor's history is encrypted, and the key lives in this Mac's login "
                     + "keychain and nowhere else. There is no copy and no recovery key: that "
                     + "was chosen deliberately, so a stolen backup is unreadable.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .unreachable(let why):
            Card {
                Label("Proctor's background agent is not answering",
                      systemImage: "bolt.horizontal.circle")
                    .font(.system(size: 13, weight: .medium))
                Text(verbatim: why)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The agent holds the key, so nothing can be read until it is running.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        case .loaded:
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Runs")
                ForEach(model.runs) { run in
                    RunRow(run: run,
                           expanded: model.expanded.contains(run.id),
                           toggle: {
                               if model.expanded.contains(run.id) {
                                   model.expanded.remove(run.id)
                               } else {
                                   model.expanded.insert(run.id)
                               }
                           })
                }
            }
        }
    }

    /// Keep this window out of every screen capture, Proctor's own included.
    ///
    /// The run panel already does this. A window holding opened history is
    /// exactly the window a model driving this Mac should not be able to
    /// photograph, and `proctor_capture` is a tool that model can call.
    private func excludeFromCapture() {
        for window in NSApplication.shared.windows
        where window.identifier?.rawValue.contains("history") == true
                || window.title == "History" {
            window.sharingType = .none
        }
    }
}

// MARK: - The fence

/// The one view that may draw text Proctor did not write.
///
/// An application's own accessibility titles reach this window, and so does any
/// name the calling model supplied. PRO-0014 fences those in quotation marks,
/// which is the best a `String` return can do, and its own after-merge note said
/// so: a text run "no character can escape" is the better fence. On a page of
/// rows that stops being a nicety. Forty quoted names give a hostile one plenty
/// of room to look like the row above it; a run with its own background, border
/// and bounds does not, because nothing inside a string can draw a border.
///
/// Three things make it hold. The text was sanitised in the agent before it
/// crossed, through the same routine the HUD uses. It is drawn with
/// `Text(verbatim:)`, never the `LocalizedStringKey` initialiser, which would
/// render Markdown. And Proctor's own words are never inside the fence, so the
/// boundary between what Proctor says and what an application says is structural
/// rather than punctuation.
struct Fence: View {
    let value: HistoryModel.Foreign
    var maxWidth: CGFloat = 260

    var body: some View {
        Text(verbatim: value.text)
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(Color(nsColor: .quaternarySystemFill),
                        in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .help(value.supplied
                  ? "A name the model driving Proctor supplied"
                  : "A name Proctor read from the application")
    }
}

// MARK: - Header

private struct HistoryHeader: View {
    let model: HistoryModel
    @Binding var confirmingClear: Bool

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("History")
                Spacer()
                Button("Refresh") { model.load() }.controlSize(.small)
                Button("Clear…", role: .destructive) { confirmingClear = true }
                    .controlSize(.small)
                    .disabled(model.header?.entries ?? 0 == 0)
            }
            Text("What Proctor did on this Mac, one row per run. It is kept on this Mac only, "
                 + "encrypted, and it clears itself as it ages.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let header = model.header {
                Retention(header: header)
                // A broken, rolled-back or partly unreadable trail must not read
                // as an ordinary short one. These are the only places this window
                // says something is wrong, so they are on the face of it.
                if !header.verdictClean || !header.keyConfirmed {
                    Callout(icon: "exclamationmark.triangle.fill", tint: .orange,
                            title: header.keyConfirmed
                                ? "This history does not check out"
                                : "This history could not be checked",
                            message: header.faultDetail
                                ?? "The signing key could not be reached, so what is below is "
                                 + "internally consistent but unconfirmed: nothing proves it was "
                                 + "written by Proctor on this Mac.")
                }
                if header.dropped > 0 {
                    Callout(icon: "square.stack.3d.up.slash", tint: .orange,
                            title: "\(header.dropped) "
                                + "\(header.dropped == 1 ? "action was" : "actions were") not recorded",
                            message: "Proctor could not write \(header.dropped == 1 ? "it" : "them") "
                                + "to the history this run, so \(header.dropped == 1 ? "it is" : "they are") "
                                + "missing from the list below. A history with nothing wrong in it is "
                                + "not the same as a complete one.")
                }
                if model.unreadable > 0 {
                    Callout(icon: "questionmark.square.dashed", tint: .secondary,
                            title: "\(model.unreadable) "
                                + "\(model.unreadable == 1 ? "entry" : "entries") could not be opened",
                            message: "\(model.unreadable == 1 ? "It was" : "They were") sealed with a "
                                + "key this Mac no longer holds. Something happened; this window "
                                + "cannot say what.")
                }
                if let discarded = header.rotatedDiscarded {
                    Callout(icon: "clock.arrow.circlepath", tint: .secondary,
                            title: header.rotatedReason == "person"
                                ? "History was cleared"
                                : "History reached its limit and started again",
                            message: "\(discarded) earlier "
                                + "\(discarded == 1 ? "entry was" : "entries were") removed. Proctor "
                                + "keeps a note that it happened and how much went, and nothing else "
                                + "about them.")
                }
            }
        }
    }
}

/// How much is held and how much of the window is left. Shown rather than left
/// to be discovered, because history here is not a sliding window: it fills to
/// the cap and then starts again, and a person should meet that in a bar rather
/// than in an empty list one morning.
private struct Retention: View {
    let header: HistoryModel.Header

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("\(header.entries)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                Text(header.entries == 1 ? "entry held" : "entries held")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text("keeps \(header.capDays) days or \(header.capEntries) entries, then starts again")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            ProgressView(value: max(0, min(1, 1 - header.remaining)))
                .progressViewStyle(.linear)
                .tint(header.remaining < 0.15 ? .orange : .secondary)
        }
    }
}

// MARK: - Rows

private struct RunRow: View {
    let run: HistoryModel.Run
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    OutcomeMark(outcome: run.outcome)
                    // Proctor's own name for the tool. Never foreign.
                    Text(run.tool)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    if let bundleId = run.bundleId {
                        // A bundle id rather than a display name: the record holds
                        // a session handle where a name would be, and a bundle id
                        // is the durable identity the policy gate judges on. It
                        // still comes from an application, so it is still fenced.
                        Fence(value: .init(text: bundleId, supplied: false), maxWidth: 220)
                    }
                    Spacer()
                    Text(summary)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if let ms = run.spanMs {
                        Text(Self.duration(ms))
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    Text(run.startedAt, format: .relative(presentation: .numeric))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .frame(width: 92, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)

            if expanded {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    if let reason = run.reason {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 9)).foregroundStyle(.tertiary)
                                .frame(width: 10)
                            Fence(value: reason, maxWidth: 460)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                    }
                    if run.steps.isEmpty && run.reason == nil {
                        Text("No steps were recorded for this run.")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                            .padding(.vertical, 6).padding(.horizontal, 10)
                    }
                    ForEach(run.steps) { step in
                        StepRow(step: step)
                    }
                    if run.unreadable > 0 {
                        Text("\(run.unreadable) \(run.unreadable == 1 ? "entry" : "entries") "
                             + "in this run could not be opened.")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                            .padding(.vertical, 6).padding(.horizontal, 10)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    private var summary: String {
        let steps = run.steps.count
        let count = steps == 0 ? "no steps" : (steps == 1 ? "1 step" : "\(steps) steps")
        switch run.outcome {
        case .ok:          return count
        case .failed:      return "\(count), failed"
        case .refused:     return "\(count), refused"
        case .halted:      return "\(count), stopped by a person"
        case .recommended: return "named another lane"
        case .mixed:       return "\(count), some failed"
        // Never "failed". The whole reason this outcome exists is that Proctor
        // has no basis for saying the step did not happen.
        case .indeterminate: return "\(count), outcome unknown"
        }
    }

    static func duration(_ ms: Int) -> String {
        ms < 1000 ? "\(ms) ms" : String(format: "%.1f s", Double(ms) / 1000)
    }
}

/// One step. The shape is fixed and identical for every row — mark, Proctor's
/// verb, the fence, the plane, the time — so no application can reshape a row by
/// choosing what its controls are called.
private struct StepRow: View {
    let step: HistoryModel.Step

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                OutcomeMark(outcome: step.outcome, small: true)
                    .frame(width: 12)
                // Proctor's own past-tense wording, stored apart from the object
                // exactly so it can be drawn plainly here.
                Text(step.act ?? step.kind ?? "Acted")
                    .font(.system(size: 11, weight: .medium))
                if let object = step.object {
                    Fence(value: object)
                }
                Spacer()
                if let plane = step.plane {
                    PlaneBadge(plane: plane)
                }
                if let ms = step.ms {
                    Text(RunRow.duration(ms))
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 56, alignment: .trailing)
                }
            }
            if let reason = step.reason {
                HStack(spacing: 8) {
                    Spacer().frame(width: 20)
                    Fence(value: reason, maxWidth: 420)
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
    }
}

/// Which way the action travelled. Proctor's own vocabulary is spelled out; an
/// unrecognised value is drawn as it came rather than dropped, so a later
/// actuation lane naming a plane this build has never heard of shows up as a
/// label instead of as a blank.
private struct PlaneBadge: View {
    let plane: String

    private var label: String {
        switch plane {
        case "accessibility": return "accessibility"
        case "appleEvent":    return "Apple event"
        case "syntheticEvent": return "synthetic"
        default:              return plane
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(plane == "syntheticEvent"
                        ? Color.orange.opacity(0.14)
                        : Color(nsColor: .quaternarySystemFill),
                        in: Capsule())
            .foregroundStyle(plane == "syntheticEvent" ? Color.orange : Color.secondary)
    }
}

private struct OutcomeMark: View {
    let outcome: RunHistory.Outcome
    var small = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: small ? 9 : 11))
            .foregroundStyle(tint)
    }

    private var symbol: String {
        switch outcome {
        case .ok:          return "checkmark.circle.fill"
        case .failed:      return "xmark.circle.fill"
        case .refused:     return "hand.raised.fill"
        // A person's own stop is not a fault, and is not drawn as one. The run
        // panel already refuses to paint it red and this agrees with it.
        case .halted:      return "stop.circle.fill"
        case .recommended: return "arrow.turn.down.right"
        case .mixed:       return "exclamationmark.circle.fill"
        case .indeterminate: return "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch outcome {
        case .ok:          return .green
        case .failed:      return .orange
        case .refused:     return .orange
        case .halted:      return .secondary
        case .recommended: return .secondary
        case .mixed:       return .orange
        case .indeterminate: return .orange
        }
    }
}

// MARK: - Shared pieces

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

private struct Callout: View {
    let icon: String, tint: Color, title: String, message: String
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                // Verbatim: this can carry the verifier's own detail, which
                // quotes a trail entry's position and can reach text Proctor did
                // not write.
                Text(verbatim: message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}
