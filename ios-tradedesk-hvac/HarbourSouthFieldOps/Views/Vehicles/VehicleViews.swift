import SwiftUI

// Vehicle records for Automotive companies.
//
// Every view here renders nothing unless the signed-in company's business type
// is Automotive, so no other company ever sees a vehicle field or the word.
// Vehicle data itself is never deleted — a business-type change only hides it.

// MARK: - Customer section

/// The customer's vehicles, on the customer screen.
struct CustomerVehiclesSection: View {
    let customerID: String
    let canManage: Bool

    @Environment(AppEnvironment.self) private var env
    @State private var vehicles: [Vehicle] = []
    @State private var editing: VehicleEditorContext?
    @State private var loadError: String?

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        if session?.trade.usesVehicles == true {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Vehicles").sectionLabelStyle()
                    if canManage {
                        Button("Add") { editing = VehicleEditorContext(vehicle: nil) }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                    }
                }

                VStack(spacing: 0) {
                    if vehicles.isEmpty {
                        Text(loadError ?? "No vehicles on file yet.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.meta)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
                    } else {
                        ForEach(Array(vehicles.enumerated()), id: \.element.id) { index, vehicle in
                            if index > 0 { Divider().padding(.leading, 60) }
                            NavigationLink {
                                VehicleDetailView(vehicle: vehicle, canManage: canManage) { updated in
                                    if let i = vehicles.firstIndex(where: { $0.id == updated.id }) {
                                        vehicles[i] = updated
                                    }
                                }
                            } label: {
                                VehicleRow(vehicle: vehicle, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .cardSurface()
            }
            .task(id: customerID) { await load() }
            .sheet(item: $editing) { context in
                VehicleEditorSheet(context: context) { draft in
                    await save(draft: draft, vehicleID: context.vehicle?.id)
                }
            }
        }
    }

    private func load() async {
        guard let session else { return }
        do {
            vehicles = try await env.gateway.vehicles(session: session, customerID: customerID)
            loadError = nil
        } catch {
            loadError = DataError.wrap(error).errorDescription
        }
    }

    private func save(draft: VehicleDraft, vehicleID: String?) async -> String? {
        guard let session else { return "Sign in again to continue." }
        do {
            _ = try await env.gateway.saveVehicle(
                session: session,
                customerID: customerID,
                vehicleID: vehicleID,
                draft: draft
            )
            await load()
            return nil
        } catch {
            return DataError.wrap(error).errorDescription ?? "The vehicle couldn't be saved."
        }
    }
}

// MARK: - Row

struct VehicleRow: View {
    let vehicle: Vehicle
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 34, height: 34)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                if let subtitle = vehicle.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.meta)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }
}

// MARK: - Detail

/// One vehicle and every job it has been on.
struct VehicleDetailView: View {
    @State var vehicle: Vehicle
    let canManage: Bool
    var onUpdate: (Vehicle) -> Void = { _ in }

    @Environment(AppEnvironment.self) private var env
    @State private var jobs: LoadState<[VehicleJobEntry]> = .idle
    @State private var editing: VehicleEditorContext?

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    factRow("Registration", vehicle.registration)
                    Divider().padding(.leading, 14)
                    factRow("VIN", vehicle.vin)
                    Divider().padding(.leading, 14)
                    factRow("Make", vehicle.make)
                    Divider().padding(.leading, 14)
                    factRow("Model", vehicle.model)
                }
                .cardSurface()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Job history").sectionLabelStyle()
                    VStack(spacing: 0) {
                        switch jobs {
                        case .idle, .loading:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        case .failed(let error):
                            Text(error.errorDescription ?? "Couldn't load this vehicle's jobs.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.red)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .loaded(let entries):
                            if entries.isEmpty {
                                Text("No jobs for this vehicle yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.meta)
                                    .padding(.horizontal, 14)
                                    .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
                            } else {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { Divider().padding(.leading, 14) }
                                    NavigationLink(value: AppRoute.job(entry.id)) {
                                        jobRow(entry)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .cardSurface()
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 12)
        }
        .background(Theme.canvas)
        .navigationTitle(vehicle.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = VehicleEditorContext(vehicle: vehicle) }
                }
            }
        }
        .task(id: vehicle.id) { await load() }
        .refreshable { await load() }
        .sheet(item: $editing) { context in
            VehicleEditorSheet(context: context) { draft in
                guard let session else { return "Sign in again to continue." }
                do {
                    let saved = try await env.gateway.saveVehicle(
                        session: session,
                        customerID: vehicle.customerID,
                        vehicleID: vehicle.id,
                        draft: draft
                    )
                    vehicle = saved
                    onUpdate(saved)
                    return nil
                } catch {
                    return DataError.wrap(error).errorDescription ?? "The vehicle couldn't be saved."
                }
            }
        }
    }

    private func factRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text(value.tidied.isEmpty ? "Not recorded" : value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(value.tidied.isEmpty ? Theme.meta : Theme.ink)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    private func jobRow(_ entry: VehicleJobEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text([entry.reference, entry.dateLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 4)
            Text(entry.status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }

    private func load() async {
        guard let session else { return }
        if jobs.value == nil { jobs = .loading }
        do {
            jobs = .loaded(try await env.gateway.vehicleJobs(session: session, vehicleID: vehicle.id))
        } catch {
            jobs = .failed(DataError.wrap(error))
        }
    }
}

// MARK: - Editor

struct VehicleEditorContext: Identifiable {
    let id = UUID()
    let vehicle: Vehicle?
}

struct VehicleEditorSheet: View {
    let context: VehicleEditorContext
    let onSave: (VehicleDraft) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: VehicleDraft
    @State private var isSaving: Bool = false
    @State private var error: String?

    init(context: VehicleEditorContext, onSave: @escaping (VehicleDraft) async -> String?) {
        self.context = context
        self.onSave = onSave
        _draft = State(initialValue: context.vehicle.map(VehicleDraft.init) ?? VehicleDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Registration", text: $draft.registration)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("VIN", text: $draft.vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("All fields are optional. Fill in what you have.")
                }
                Section {
                    TextField("Make", text: $draft.make)
                    TextField("Model", text: $draft.model)
                }
                if let error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(Theme.red)
                    }
                }
            }
            .navigationTitle(context.vehicle == nil ? "Add vehicle" : "Edit vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            isSaving = true
                            Task {
                                let problem = await onSave(draft)
                                isSaving = false
                                if let problem { error = problem } else { dismiss() }
                            }
                        }
                        .disabled(draft.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - On a job

/// The vehicle a job is for, on the job screens. Hidden when the company isn't
/// Automotive or the job has no vehicle.
struct JobVehicleCard: View {
    let jobID: String
    /// Office screens may change the vehicle; the engineer's screen may not.
    var customerID: String? = nil
    var canChange: Bool = false

    @Environment(AppEnvironment.self) private var env
    @State private var vehicle: Vehicle?
    @State private var isLoaded: Bool = false
    @State private var isPicking: Bool = false
    @State private var error: String?

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        if session?.trade.usesVehicles == true {
            Group {
                if vehicle != nil || (canChange && isLoaded) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Vehicle").sectionLabelStyle()
                            if canChange, customerID != nil {
                                Button(vehicle == nil ? "Add" : "Change") { isPicking = true }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.primary)
                            }
                        }
                        VStack(spacing: 0) {
                            if let vehicle {
                                NavigationLink {
                                    VehicleDetailView(vehicle: vehicle, canManage: session?.can(.customersManage) == true)
                                } label: {
                                    VehicleRow(vehicle: vehicle, showsChevron: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("No vehicle linked to this job.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.meta)
                                    .padding(.horizontal, 14)
                                    .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
                            }
                        }
                        .cardSurface()
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(Theme.red)
                        }
                    }
                }
            }
            .task(id: jobID) { await load() }
            .sheet(isPresented: $isPicking) {
                if let customerID {
                    VehiclePickerSheet(customerID: customerID, selectedID: vehicle?.id) { picked in
                        await link(picked)
                    }
                }
            }
        }
    }

    private func load() async {
        guard let session else { return }
        vehicle = try? await env.gateway.jobVehicle(session: session, jobID: jobID)
        isLoaded = true
    }

    private func link(_ picked: Vehicle?) async {
        guard let session else { return }
        do {
            try await env.gateway.setJobVehicle(session: session, jobID: jobID, vehicleID: picked?.id)
            vehicle = picked
            error = nil
        } catch {
            self.error = DataError.wrap(error).errorDescription
        }
    }
}

// MARK: - Picker

/// Choose one of the customer's vehicles, or add a new one in place.
struct VehiclePickerSheet: View {
    let customerID: String
    let selectedID: String?
    let onPick: (Vehicle?) async -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var vehicles: [Vehicle] = []
    @State private var isLoading: Bool = true
    @State private var adding: VehicleEditorContext?

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Section {
                        Button {
                            Task { await onPick(nil); dismiss() }
                        } label: {
                            HStack {
                                Text("No vehicle").foregroundStyle(Theme.ink)
                                Spacer()
                                if selectedID == nil { Image(systemName: "checkmark").foregroundStyle(Theme.primary) }
                            }
                        }
                        ForEach(vehicles) { vehicle in
                            Button {
                                Task { await onPick(vehicle); dismiss() }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(vehicle.title).foregroundStyle(Theme.ink)
                                        if let subtitle = vehicle.subtitle {
                                            Text(subtitle).font(.caption).foregroundStyle(Theme.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selectedID == vehicle.id {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.primary)
                                    }
                                }
                            }
                        }
                    }
                    if session?.can(.customersManage) == true {
                        Section {
                            Button {
                                adding = VehicleEditorContext(vehicle: nil)
                            } label: {
                                Label("Add a new vehicle", systemImage: "plus.circle.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
            .sheet(item: $adding) { context in
                VehicleEditorSheet(context: context) { draft in
                    guard let session else { return "Sign in again to continue." }
                    do {
                        let saved = try await env.gateway.saveVehicle(
                            session: session,
                            customerID: customerID,
                            vehicleID: nil,
                            draft: draft
                        )
                        await onPick(saved)
                        dismiss()
                        return nil
                    } catch {
                        return DataError.wrap(error).errorDescription ?? "The vehicle couldn't be saved."
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        guard let session else { return }
        vehicles = (try? await env.gateway.vehicles(session: session, customerID: customerID)) ?? []
        isLoading = false
    }
}
