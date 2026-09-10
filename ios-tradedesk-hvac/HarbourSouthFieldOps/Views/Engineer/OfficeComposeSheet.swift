import SwiftUI

/// Starting a new message to the office.
///
/// The topic chips are the point of this screen. On a cold morning with gloves
/// on, "I need a part" should be two taps and one sentence — not a blank box
/// and a subject line to invent. The chip fills in the subject the office sees;
/// the engineer still writes what is actually wrong.
///
/// Recipients are never chosen here. The database resolves who the office is
/// from the company's own permission grants, so no individual is named by this
/// app and a message can never leave the company.
struct OfficeComposeSheet: View {
    /// Set when composing from inside a job, so the office gets the context.
    let jobID: String?
    let jobNumber: String?
    let onSent: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = OfficeComposerViewModel()
    @FocusState private var isBodyFocused: Bool

    private var session: TenantSession? { env.activeSession }

    private static let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let jobNumber {
                        jobContext(jobNumber)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's this about?")
                            .sectionLabelStyle()

                        LazyVGrid(columns: Self.columns, spacing: 8) {
                            ForEach(OfficeMessageTopic.allCases) { topic in
                                topicChip(topic)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your message")
                            .sectionLabelStyle()

                        TextEditor(text: $viewModel.body)
                            .font(.body)
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .cardSurface()
                            .focused($isBodyFocused)
                            .overlay(alignment: .topLeading) {
                                if viewModel.body.isEmpty {
                                    Text(viewModel.topic.prompt)
                                        .font(.body)
                                        .foregroundStyle(Theme.meta)
                                        .padding(.horizontal, 15)
                                        .padding(.vertical, 18)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    if let error = viewModel.actionError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.red.opacity(0.08))
                            .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    }

                    Text("The office gets an alert straight away. Replies come back here and you'll be notified.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.margin)
            }
            .background(Theme.canvas)
            .navigationTitle("Message the office")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        send()
                    } label: {
                        if viewModel.isSending {
                            ProgressView()
                        } else {
                            Text("Send").fontWeight(.semibold)
                        }
                    }
                    .disabled(!viewModel.canSend)
                }
            }
            .onAppear { isBodyFocused = true }
        }
    }

    private func jobContext(_ number: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.adjustable")
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 32, height: 32)
                .background(Theme.primaryTint)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 1) {
                Text("About job \(number)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("The office will see this job with your message.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func topicChip(_ topic: OfficeMessageTopic) -> some View {
        let isSelected = viewModel.topic == topic
        return Button {
            viewModel.topic = topic
        } label: {
            HStack(spacing: 7) {
                Image(systemName: topic.symbolName)
                    .font(.caption)
                Text(topic.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .white : Theme.ink)
            .padding(.horizontal, 11)
            .frame(minHeight: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.primary : Theme.surface)
            .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.buttonRadius)
                    .stroke(isSelected ? Theme.primary : Theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityLabel(topic.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func send() {
        guard let session else { return }
        isBodyFocused = false
        Task {
            let threadID = await viewModel.send(
                gateway: env.gateway,
                session: session,
                jobID: jobID,
                jobNumber: jobNumber
            )
            // Only dismissed once the server has it. A failed send stays on
            // screen with the text intact and the reason shown.
            guard let threadID else { return }
            onSent(threadID)
            dismiss()
        }
    }
}

#Preview {
    OfficeComposeSheet(jobID: nil, jobNumber: nil) { _ in }
        .environment(AppEnvironment())
}
