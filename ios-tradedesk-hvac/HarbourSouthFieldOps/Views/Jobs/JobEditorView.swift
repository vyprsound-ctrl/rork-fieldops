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
    /// Automotive only: the selected customer's vehicles and the one chosen.
    @State private var customerVehicles: [Vehicle] = []
    @State private var vehicleID: String = ""
    @State private var isAddingVehicle: Bool = false

    private var usesVehicles: Bool { session?.trade.usesVehicles == true }

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
                            title: "No customers yet",
                            message: "A job needs a customer and a service address. Add your first customer from the Customers tab, then book the work."
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
        .task(id: viewModel.customerID) { await loadVehicles() }
        .sheet(isPresented: $isAddingVehicle) {
            VehicleEditorSheet(context: VehicleEditorContext(vehicle: nil)) { draft in
                guard let session else { return "Sign in again to continue." }
                do {
                    let saved = try await env.gateway.saveVehicle(
                        session: session,
                        customerID: viewModel.customerID,
                        vehicleID: nil,
                        draft: draft
                    )
                    customerVehicles.append(saved)
                    vehicleID = saved.id
                    return nil
                } catch {
                    return DataError.wrap(error).errorDescription ?? "The vehicle couldn't be saved."
                }
            }
        }
    }

    private func loadVehicles() async {
        guard usesVehicles, let session, !viewModel.customerID.isEmpty else {
            customerVehicles = []
            vehicleID = ""
            return
        }
        customerVehicles = (try? await env.gateway.vehicles(session: session, customerID: viewModel.customerID)) ?? []
        if !customerVehicles.contains(where: { $0.id == vehicleID }) {
            vehicleID = customerVehicles.count == 1 ? customerVehicles[0].id : ""
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
                if viewModel.sites.count > 1 {
                    Picker("Service address", selection: $viewModel.addressID) {
                        ForEach(viewModel.sites) { site in
                            Text(site.line).tag(site.id)
                        }
                    }
                } else if let site = viewModel.selectedSite {
                    Text(site.line)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }

                if !viewModel.equipmentOptions.isEmpty {
                    Picker(terms.Asset, selection: equipmentBinding) {
                        Text("None").tag("")
                        ForEach(viewModel.equipmentOptions) { unit in
                            Text(unit.name).tag(unit.id)
                        }
                    }
                }
            }

            if usesVehicles, !viewModel.customerID.isEmpty {
                Section {
                    Picker("Vehicle", selection: $vehicleID) {
                        Text("None").tag("")
                        ForEach(customerVehicles) { vehicle in
                            Text([vehicle.title, vehicle.subtitle].compactMap { $0 }.joined(separator: " · ")).tag(vehicle.id)
                        }
                    }
                    if session?.can(.customersManage) == true {
                        Button {
                            isAddingVehicle = true
                        } label: {
                            Label("Add a vehicle", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    Text("Vehicle")
                } footer: {
                    Text("Optional. The job appears in this vehicle's history.")
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
                // The job exists either way; a vehicle that fails to link can
                // be added from the job screen.
                if usesVehicles, !vehicleID.isEmpty {
                    try? await env.gateway.setJobVehicle(session: session, jobID: jobID, vehicleID: vehicleID)
                }
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
