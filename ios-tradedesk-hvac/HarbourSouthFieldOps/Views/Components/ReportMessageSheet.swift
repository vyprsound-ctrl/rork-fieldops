import SwiftUI

/// Report one message: pick a reason, optionally add detail, optionally block
/// the sender, send. The report goes to the company's Owner/Admin — or to
/// Harbour South when it concerns an Owner — and Harbour South is alerted by
/// email either way, so every report is seen within 24 hours.
struct ReportMessageSheet: View {
    let target: ReportTarget
    /// Called after a successful report. `true` when the sender was blocked too.
    var onReported: (Bool) -> Void = { _ in }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var details: String = ""
    @State private var alsoBlock: Bool = false
    @State private var isSending: Bool = false
    @State private var errorMessage: String?
    @State private var didSend: Bool = false
    @State private var didBlock: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                if didSend {
                    confirmation
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    form
                }
            }
            .navigationTitle(didSend ? "" : "Report message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !didSend {
                        Button("Cancel") { dismiss() }
                            .disabled(isSending)
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: didSend)
        }
        .interactiveDismissDisabled(isSending)
        .sensoryFeedback(.success, trigger: didSend)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                excerptCard

                VStack(alignment: .leading, spacing: 8) {
                    Text("What's wrong with it?").sectionLabelStyle()
                    VStack(spacing: 0) {
                        ForEach(Array(ReportReason.allCases.enumerated()), id: \.element.id) { index, option in
                            reasonRow(option)
                            if index < ReportReason.allCases.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .cardSurface()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Anything else? (optional)").sectionLabelStyle()
                    TextField("Add detail for the reviewer", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.subheadline)
                        .padding(12)
                        .background(Theme.surface)
                        .clipShape(.rect(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
                        .accessibilityIdentifier("report.details")
                }

                if target.canBlockSender {
                    Toggle(isOn: $alsoBlock) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Also block \(target.senderName)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Their chat messages will be hidden from you.")
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .tint(Theme.red)
                    .padding(14)
                    .cardSurface()
                    .accessibilityIdentifier("report.alsoBlock")
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Label("Send report", systemImage: "flag.fill")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(reason == nil ? AnyShapeStyle(Theme.red.opacity(0.35)) : AnyShapeStyle(Theme.red.gradient))
                    .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                }
                .buttonStyle(PressableTileStyle())
                .disabled(reason == nil || isSending)
                .accessibilityIdentifier("report.send")

                Text("Reports are private. The person you report is never told who reported them. Reports are reviewed within 24 hours, and messages that break the rules are removed.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var excerptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(target.senderName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.meta)
            Text(target.excerpt.isEmpty ? "Photo message" : target.excerpt)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.cardRadius, bottomLeadingRadius: Theme.cardRadius)
                .fill(Theme.red)
                .frame(width: 4)
        }
    }

    private func reasonRow(_ option: ReportReason) -> some View {
        Button {
            withAnimation(.snappy) { reason = option }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.symbolName)
                    .font(.footnote)
                    .foregroundStyle(reason == option ? Color.white : Theme.red)
                    .frame(width: 28, height: 28)
                    .background(reason == option ? Theme.red : Theme.red.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 7))
                Text(option.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: reason == option ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reason == option ? Theme.red : Theme.border)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: Theme.minTap)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: reason)
        .accessibilityAddTraits(reason == option ? .isSelected : [])
        .accessibilityIdentifier("report.reason.\(option.rawValue)")
    }

    private var confirmation: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Theme.green)
                .symbolEffect(.bounce, value: didSend)
            Text("Report sent")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(confirmationText)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.primary.gradient)
                    .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .buttonStyle(PressableTileStyle())
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 16)
            .accessibilityIdentifier("report.done")
        }
    }

    private var confirmationText: String {
        var text = "Thanks for telling us. It will be reviewed within 24 hours, and you can follow it in More → Safety & reports."
        if didBlock {
            text += " You've blocked \(target.senderName), so their chat messages are hidden from you."
        }
        return text
    }

    private func send() async {
        guard let reason, let session = env.activeSession else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let note = details.trimmingCharacters(in: .whitespacesAndNewlines)
            try await env.gateway.reportMessage(session: session, target: target, reason: reason, details: note.isEmpty ? nil : note)
            if alsoBlock, let userID = target.senderUserID {
                try await env.gateway.blockChatUser(session: session, userID: userID, reason: reason, details: nil)
                didBlock = true
            }
            didSend = true
            onReported(didBlock)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
