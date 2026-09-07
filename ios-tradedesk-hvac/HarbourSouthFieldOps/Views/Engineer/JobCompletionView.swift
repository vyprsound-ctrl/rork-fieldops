import SwiftUI

/// What an engineer fills in when the work is done.
///
/// Ordered the way the job actually finishes: say what you did, list what you
/// used, attach the evidence, get it signed. Only the first is required — a
/// completion form that refuses to submit until six boxes are full is a
/// completion form that gets filled with full stops.
struct JobCompletionView: View {
    let jobID: String
    let jobNumber: String
    let customerName: String
    let destination: Coordinate?
    let onCompleted: (JobCompletionOutcome) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = JobCompletionViewModel()

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    workPerformed
                    partsAndLabour
                    photos
                    signature
                    followUp
                    if let error = viewModel.errorMessage { errorBanner(error) }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 28)
            }
            .background(Theme.canvas)
            .navigationTitle("Complete job")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSubmitting)
                }
            }
            .safeAreaInset(edge: .bottom) { submitBar }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(customerName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text("\(jobNumber) · finishing up")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    private var workPerformed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Work performed")
                .sectionLabelStyle()

            TextEditor(text: $viewModel.draft.workPerformed)
                .font(.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(10)
                .cardSurface()
                .overlay(alignment: .topLeading) {
                    if viewModel.draft.workPerformed.isEmpty {
                        Text("What did you do on site?")
                            .font(.body)
                            .foregroundStyle(Theme.meta)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            Text("The customer sees this. It's also added to the unit's service history.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
        }
    }

    private var partsAndLabour: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Parts & labour")
                    .sectionLabelStyle()
                Button("Add part") { viewModel.addPartLine() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
            }

            VStack(spacing: 0) {
                if viewModel.draft.parts.isEmpty {
                    Text("Nothing used on this visit.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    ForEach(Array(viewModel.draft.parts.enumerated()), id: \.element.id) { index, part in
                        if index > 0 { Divider().padding(.leading, 14) }
                        partRow(index: index, id: part.id)
                    }
                }

                Divider().padding(.leading, 14)

                HStack {
                    Text("Time on site")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Picker("Time on site", selection: $viewModel.draft.labourHours) {
                        Text("Not recorded").tag(0.0)
                        Text("30 min").tag(0.5)
                        Text("1 hr").tag(1.0)
                        Text("1.5 hrs").tag(1.5)
                        Text("2 hrs").tag(2.0)
                        Text("3 hrs").tag(3.0)
                        Text("4 hrs").tag(4.0)
                        Text("Full day").tag(8.0)
                    }
                    .labelsHidden()
                    .tint(Theme.primary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTap)
            }
            .cardSurface()
        }
    }

    private func partRow(index: Int, id: UUID) -> some View {
        HStack(spacing: 10) {
            Stepper(
                value: Binding(
                    get: { viewModel.draft.parts.indices.contains(index) ? viewModel.draft.parts[index].quantity : 1 },
                    set: { if viewModel.draft.parts.indices.contains(index) { viewModel.draft.parts[index].quantity = $0 } }
                ),
                in: 1...99
            ) {
                Text("\(viewModel.draft.parts.indices.contains(index) ? viewModel.draft.parts[index].quantity : 1)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26, alignment: .leading)
            }
            .labelsHidden()
            .fixedSize()

            TextField(
                "Part or material",
                text: Binding(
                    get: { viewModel.draft.parts.indices.contains(index) ? viewModel.draft.parts[index].name : "" },
                    set: { if viewModel.draft.parts.indices.contains(index) { viewModel.draft.parts[index].name = $0 } }
                )
            )
            .font(.subheadline)
            .textFieldStyle(.plain)

            Button {
                viewModel.removePart(id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.body)
                    .foregroundStyle(Theme.red)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove part")
        }
        .padding(.leading, 14)
        .frame(minHeight: 52)
    }

    private var photos: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos")
                .sectionLabelStyle()
            JobPhotoCollector(uploads: $viewModel.draft.photos)
        }
    }

    private var signature: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Customer signature")
                .sectionLabelStyle()

            SignaturePad(image: $viewModel.draft.signatureImage)

            TextField("Name of the person signing", text: $viewModel.draft.signatureName)
                .textFieldStyle(.plain)
                .textContentType(.name)
                .padding(14)
                .frame(minHeight: Theme.minTap)
                .cardSurface()

            Text("Leave both blank if nobody was on site to sign.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
        }
    }

    private var followUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Office notes")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                TextEditor(text: $viewModel.draft.internalNotes)
                    .font(.subheadline)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .overlay(alignment: .topLeading) {
                        if viewModel.draft.internalNotes.isEmpty {
                            Text("Anything the office should know (not shown to the customer)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.meta)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                Divider().padding(.leading, 14)

                Toggle("Follow-up visit needed", isOn: $viewModel.draft.followUpRequired)
                    .tint(Theme.primary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)

                if viewModel.draft.followUpRequired {
                    Divider().padding(.leading, 14)
                    TextField("What's outstanding?", text: $viewModel.draft.followUpNotes)
                        .font(.subheadline)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(minHeight: Theme.minTap)
                }
            }
            .cardSurface()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Theme.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.red.opacity(0.08))
            .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private var submitBar: some View {
        VStack(spacing: 6) {
            if let problem = viewModel.draft.validationMessage {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting { ProgressView().tint(.white) }
                    Text(viewModel.isSubmitting ? "Saving the record" : "Complete job")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(viewModel.canSubmit ? Theme.green : Theme.meta.opacity(0.4))
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .buttonStyle(PressableTileStyle())
            .disabled(!viewModel.canSubmit)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func submit() {
        guard let session else { return }
        Task {
            let didComplete = await viewModel.submit(
                gateway: env.gateway,
                location: env.location,
                session: session,
                jobID: jobID,
                destination: destination
            )
            if didComplete, let outcome = viewModel.outcome {
                onCompleted(outcome)
                dismiss()
            }
        }
    }
}

#Preview {
    JobCompletionView(
        jobID: "job_1041",
        jobNumber: "JOB-1041",
        customerName: "Ramirez Residence",
        destination: nil
    ) { _ in }
    .environment(AppEnvironment())
}
