import SwiftUI

/// Create a job. The form only offers customers and workers the data layer
/// returned for this session, and the write itself is checked again against
/// `jobsManage` before anything is stored.
struct JobEditorView: View {
    var quotePrefill: QuotePrefill?
    let onCreated: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = JobEditorViewModel()

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    /// Values carried across when a job is raised from a quote.
    struct QuotePrefill: Hashable {
        let customerID: String
        let title: String
        let scopeOfWork: String
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingOptions {
                    LoadingStateView(message: "Loading customers")
                } else if viewModel.options.customers.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            symbolName: "person.2.slash",
                            title: "No customers available",
                            message: "Your role can't create jobs without customer records."
                        )
                    }
                } else {
                    form
                }
            }
            .background(Theme.canvas)
            .navigationTitle("New job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(!viewModel.canSave || viewModel.isSaving)
                }
            }
        }
        .task {
            guard let session else { return }
            await viewModel.loadOptions(gateway: env.gateway, session: session)
            if let prefill = quotePrefill {
                viewModel.customerID = prefill.customerID
                viewModel.title = prefill.title
                viewModel.jobDescription = prefill.scopeOfWork
                viewModel.kind = .install
            }
        }
    }

    private var form: some View {
        Form {
            Section("Customer") {
                Picker("Customer", selection: $viewModel.customerID) {
                    ForEach(viewModel.options.customers) { customer in
                        Text(customer.name).tag(customer.id)
                    }
                }
                if let customer = viewModel.selectedCustomer {
                    Text(customer.addressLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)

                    if !customer.equipment.isEmpty {
                        Picker(terms.Asset, selection: equipmentBinding) {
                            Text("None").tag("")
                            ForEach(customer.equipment) { unit in
                                Text(unit.name).tag(unit.id)
                            }
                        }
                    }
                }
            }

            Section("Job") {
                TextField("Title", text: $viewModel.title)
                Picker("Type", selection: $viewModel.kind) {
                    ForEach(JobKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Picker("Priority", selection: $viewModel.priority) {
                    ForEach(JobPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                    TextEditor(text: $viewModel.jobDescription)
                        .frame(minHeight: 90)
                        .font(.subheadline)
                }
            }

            Section("Schedule") {
                Toggle("Book a slot now", isOn: $viewModel.isScheduled)
                    .tint(Theme.primary)
                if viewModel.isScheduled {
                    DatePicker("Starts", selection: $viewModel.scheduledStart)
                    Picker("Duration", selection: $viewModel.durationMinutes) {
                        Text("30 min").tag(30)
                        Text("1 hr").tag(60)
                        Text("1.5 hrs").tag(90)
                        Text("2 hrs").tag(120)
                        Text("Half day").tag(240)
                        Text("Full day").tag(480)
                    }
                } else {
                    Text("The job is created without a slot and shows under Unscheduled.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                }
            }

            if viewModel.options.canAssign, !viewModel.options.workers.isEmpty {
                Section(terms.Worker) {
                    Picker("Assign to", selection: workerBinding) {
                        Text("Assign later").tag("")
                        ForEach(viewModel.options.workers) { worker in
                            Text(worker.name).tag(worker.id)
                        }
                    }
                    Text("Assigning here moves the job straight to \(JobStatus.workerAssigned.title(terms)) and records the change.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                }
            }
        }
    }

    private var equipmentBinding: Binding<String> {
        Binding(
            get: { viewModel.equipmentID ?? "" },
            set: { viewModel.equipmentID = $0.isEmpty ? nil : $0 }
        )
    }

    private var workerBinding: Binding<String> {
        Binding(
            get: { viewModel.workerUserID ?? "" },
            set: { viewModel.workerUserID = $0.isEmpty ? nil : $0 }
        )
    }

    private func save() {
        guard let session else { return }
        Task {
            await viewModel.save(gateway: env.gateway, session: session)
            if let jobID = viewModel.createdJobID {
                onCreated(jobID)
                dismiss()
            }
        }
    }
}

#Preview {
    JobEditorView { _ in }
        .environment(AppEnvironment())
}
