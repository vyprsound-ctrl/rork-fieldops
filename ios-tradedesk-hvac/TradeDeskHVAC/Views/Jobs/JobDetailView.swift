import SwiftUI
import MapKit

struct JobDetailView: View {
    let jobID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = JobDetailViewModel()
    @State private var isAddingNote: Bool = false
    @State private var isAddingPhoto: Bool = false
    @State private var isAssigning: Bool = false
    @State private var pendingTransition: JobTransitionOption?
    @State private var navigationHandoff: NavigationHandoff?

    /// Whichever session is signed in. A production session reads this screen
    /// through the Supabase gateway, which is what lets a tapped notification
    /// land on the real job rather than on a development fixture.
    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle(viewModel.state.value?.number ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: jobID) {
            guard let session else { return }
            await viewModel.loadOptions(gateway: env.gateway, session: session)
            await reload()
        }
        .sheet(isPresented: $isAddingNote) {
            AddNoteSheet { body, visibility in
                guard let session else { return }
                Task {
                    await viewModel.addNote(gateway: env.gateway, session: session, jobID: jobID, body: body, visibility: visibility)
                }
            }
        }
        .sheet(isPresented: $isAddingPhoto) {
            AddPhotoSheet { kind, caption in
                guard let session else { return }
                Task {
                    await viewModel.addPhoto(gateway: env.gateway, session: session, jobID: jobID, kind: kind, caption: caption)
                }
            }
        }
        .sheet(isPresented: $isAssigning) {
            AssignWorkerSheet(
                workers: viewModel.options.workers,
                currentWorkerID: viewModel.state.value?.assignedWorker?.userID,
                terms: terms
            ) { workerID in
                guard let session else { return }
                Task {
                    await viewModel.assign(gateway: env.gateway, session: session, jobID: jobID, workerUserID: workerID)
                }
            }
        }
        .sheet(item: $navigationHandoff) { handoff in
            NavigationHandoffSheet(handoff: handoff)
        }
        .sheet(item: $viewModel.pendingConflict) { pending in
            // The same sheet, wording and acknowledgement the dispatch board
            // uses. Nothing has been written at this point: dismissing it
            // leaves the assignment exactly as it was.
            SchedulingConflictSheet(
                title: "Assign \(terms.worker)",
                context: pending.contextLine,
                check: pending.check,
                confirmTitle: "Assign anyway"
            ) {
                guard let session else { return }
                Task { await viewModel.confirmPendingAssignment(gateway: env.gateway, session: session) }
            }
        }
        .alert(
            "Confirm",
            isPresented: Binding(get: { pendingTransition != nil }, set: { if !$0 { pendingTransition = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingTransition = nil }
            Button(pendingTransition?.title ?? "Continue", role: pendingTransition?.isDestructive == true ? .destructive : nil) {
                if let transition = pendingTransition { apply(transition) }
                pendingTransition = nil
            }
        } message: {
            Text(pendingTransition.map { "This records a status change to \($0.toStatus.title(terms)) against your name." } ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading job")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let job):
            loaded(job)
        }
    }

    private func loaded(_ job: JobDetailProjection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(job)
                statusStrip(job)
                if let error = viewModel.actionError { errorBanner(error) }
                customerSection(job)
                map(job)
                descriptionSection(job)
                scheduleSection(job)
                if let equipment = job.equipment { equipmentSection(equipment) }
                billingSection(job)
                JobTimelineSection(entries: job.timeline)
                JobNotesSection(notes: job.notes, canAdd: job.canAddNotes) { isAddingNote = true }
                JobPhotosSection(photos: job.photos, canAdd: job.canAddPhotos) { isAddingPhoto = true }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
        }
        .safeAreaInset(edge: .bottom) {
            if !job.transitions.isEmpty { actionBar(job) }
        }
        .refreshable { await reload(showLoading: false) }
    }

    // MARK: - Sections

    private func header(_ job: JobDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(job.number)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.primaryTint)
                    .clipShape(.rect(cornerRadius: 6))

                Label(job.kindTitle, systemImage: job.kindSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)

                if job.isUrgent {
                    Text("Urgent")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.red.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 6))
                }
            }

            Text(job.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                StatusPill(badge: job.badge)
                Text(job.createdLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            }
        }
        .padding(.top, 4)
    }

    /// Compact pipeline stepper — where this job sits in the nine-state flow.
    private func statusStrip(_ job: JobDetailProjection) -> some View {
        let current = job.status.pipelineIndex
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(JobStatus.pipeline.enumerated()), id: \.element) { index, _ in
                    let isDone = current.map { index <= $0 } ?? false
                    Capsule()
                        .fill(isDone ? tint(job) : Theme.border)
                        .frame(height: 5)
                        .accessibilityHidden(true)
                    if index < JobStatus.pipeline.count - 1 { Spacer(minLength: 0) }
                }
            }
            Text(job.status == .cancelled ? "Cancelled — outside the normal flow" : "Step \((current ?? 0) + 1) of \(JobStatus.pipeline.count) · \(job.status.title(terms))")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    private func tint(_ job: JobDetailProjection) -> Color {
        job.status == .cancelled ? Theme.meta : Theme.primary
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.footnote)
                .foregroundStyle(Theme.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.red.opacity(0.08))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func customerSection(_ job: JobDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Customer & site")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                NavigationLink(value: AppRoute.customer(job.customerID)) {
                    infoRow(symbol: "person.crop.circle", title: job.customerName, detail: job.customerTypeTitle, showsChevron: true)
                }
                .buttonStyle(.plain)

                if let contact = job.contactName {
                    Divider().padding(.leading, 54)
                    HStack(spacing: 12) {
                        icon("phone")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                            Text([job.contactRole, job.contactPhone].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 4)
                        if let phone = job.contactPhone, let url = URL(string: "tel://\(phone.filter(\.isNumber))") {
                            Link(destination: url) {
                                Text("Call")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.primaryTint)
                                    .clipShape(.capsule)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: Theme.minTap)
                }

                Divider().padding(.leading, 54)
                HStack(spacing: 12) {
                    icon("mappin.and.ellipse")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.addressLine)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let access = job.accessNotes {
                            Text(access)
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    Button {
                        navigate(job)
                    } label: {
                        Text("Navigate")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.primaryTint)
                            .clipShape(.capsule)
                    }
                    .buttonStyle(PressableTileStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .cardSurface()
        }
    }

    private func map(_ job: JobDetailProjection) -> some View {
        Map(initialPosition: .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: job.latitude, longitude: job.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )) {
            Marker(job.customerName, coordinate: CLLocationCoordinate2D(latitude: job.latitude, longitude: job.longitude))
                .tint(Theme.primary)
        }
        .frame(height: 160)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .allowsHitTesting(false)
        .overlay(alignment: .topTrailing) {
            SimulatedBadge(text: "Static preview")
                .padding(10)
        }
    }

    private func descriptionSection(_ job: JobDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job description")
                .sectionLabelStyle()
            Text(job.jobDescription.isEmpty ? "No description recorded." : job.jobDescription)
                .font(.subheadline)
                .foregroundStyle(job.jobDescription.isEmpty ? Theme.meta : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
        }
    }

    private func scheduleSection(_ job: JobDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule & \(terms.worker)")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                infoRow(
                    symbol: "calendar",
                    title: job.scheduleLabel,
                    detail: [job.durationLabel, job.serviceAgreementLabel].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
                )

                Divider().padding(.leading, 54)

                if let worker = job.assignedWorker {
                    HStack(spacing: 12) {
                        Text(worker.initials)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 30, height: 30)
                            .background(Theme.primaryTint)
                            .clipShape(.circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(worker.name)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                            if let eta = worker.etaLabel {
                                HStack(spacing: 6) {
                                    Text(eta)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondary)
                                    SimulatedBadge(text: "Simulated ETA")
                                }
                            } else {
                                Text("Assigned \(terms.worker)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        Spacer(minLength: 4)
                        if job.canAssign {
                            Button("Change") { isAssigning = true }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.primary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: Theme.minTap)
                } else {
                    HStack(spacing: 12) {
                        icon("person.badge.plus", tint: Theme.amber)
                        Text("No \(terms.worker) assigned")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 4)
                        if job.canAssign {
                            Button("Assign") { isAssigning = true }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.primary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: Theme.minTap)
                }
            }
            .cardSurface()
        }
    }

    private func equipmentSection(_ equipment: EquipmentProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(terms.Asset) on site")
                .sectionLabelStyle()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 44, height: 44)
                        .background(Theme.primaryTint)
                        .clipShape(.rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(equipment.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("\(equipment.subtitle) · \(equipment.serialNumber)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let warranty = equipment.warrantyLabel {
                            Text(warranty)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.green)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if !equipment.attributes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(equipment.attributes, id: \.self) { attribute in
                            Text(attribute)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.canvas)
                                .clipShape(.capsule)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if !equipment.history.isEmpty {
                    Divider()
                    ForEach(equipment.history) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "wrench.adjustable")
                                .font(.caption)
                                .foregroundStyle(Theme.primary)
                                .frame(width: 26, height: 26)
                                .background(Theme.primaryTint)
                                .clipShape(.circle)
                            Text("\(entry.dateLabel) — \(entry.summary)")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    @ViewBuilder
    private func billingSection(_ job: JobDetailProjection) -> some View {
        if job.financials != nil || job.quoteReference != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(job.financials == nil ? "Origin" : "Billing")
                    .sectionLabelStyle()

                VStack(spacing: 0) {
                    if let financials = job.financials {
                        if let quote = financials.quoteSummary {
                            if let quoteID = job.quoteID {
                                NavigationLink(value: AppRoute.quote(quoteID)) {
                                    infoRow(symbol: "doc.text", title: quote, showsChevron: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                infoRow(symbol: "doc.text", title: quote)
                            }
                        }
                        if let invoice = financials.invoiceSummary {
                            if financials.quoteSummary != nil { Divider().padding(.leading, 54) }
                            infoRow(symbol: "doc.plaintext", title: invoice)
                        }
                    } else if let reference = job.quoteReference {
                        // Dispatcher view: the job's origin without its value.
                        if let quoteID = job.quoteID {
                            NavigationLink(value: AppRoute.quote(quoteID)) {
                                infoRow(symbol: "doc.text", title: "From quote \(reference)", showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            infoRow(symbol: "doc.text", title: "From quote \(reference)")
                        }
                    }
                }
                .cardSurface()

                if job.financials == nil {
                    Text("Quote and invoice values aren't part of this role's data, so they're never sent to this device.")
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                }
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
                Text("Pricing isn't part of this role's data. Quote and invoice values are never sent to this device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func actionBar(_ job: JobDetailProjection) -> some View {
        VStack(spacing: 8) {
            ForEach(job.transitions) { transition in
                Button {
                    if transition.isDestructive {
                        pendingTransition = transition
                    } else {
                        apply(transition)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isWorking { ProgressView().tint(transition.isDestructive ? Theme.red : .white) }
                        Text(transition.title)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                    .background(transition.isDestructive ? Theme.red.opacity(0.1) : Theme.primary)
                    .foregroundStyle(transition.isDestructive ? Theme.red : .white)
                    .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                }
                .buttonStyle(PressableTileStyle())
                .disabled(viewModel.isWorking)
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    // MARK: - Helpers

    private func icon(_ symbol: String, tint: Color = Theme.primary) -> some View {
        Image(systemName: symbol)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12))
            .clipShape(.circle)
    }

    private func infoRow(symbol: String, title: String, detail: String? = nil, showsChevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            icon(symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 4)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.meta)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }

    private func apply(_ transition: JobTransitionOption) {
        guard let session else { return }
        Task {
            await viewModel.updateStatus(gateway: env.gateway, session: session, jobID: jobID, to: transition.toStatus)
        }
    }

    /// Prepares the hand-off through the `MapService` adapter and confirms it
    /// before leaving the app. Nothing here routes or navigates.
    private func navigate(_ job: JobDetailProjection) {
        navigationHandoff = env.maps.prepareNavigation(
            to: Coordinate(latitude: job.latitude, longitude: job.longitude),
            label: job.customerName,
            addressLine: job.addressLine
        )
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, jobID: jobID, showLoading: showLoading)
    }
}

/// Assignment picker. Whether the change is accepted is decided by the data
/// layer's `assignmentsManage` check, not by this sheet being reachable.
struct AssignWorkerSheet: View {
    let workers: [FieldWorkerOption]
    let currentWorkerID: String?
    let terms: Terminology
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(workers) { worker in
                        Button {
                            onSelect(worker.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(worker.initials)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 34, height: 34)
                                    .background(Theme.primaryTint)
                                    .clipShape(.circle)
                                Text(worker.name)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if worker.id == currentWorkerID {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if currentWorkerID != nil {
                    Section {
                        Button("Remove assignment", role: .destructive) {
                            onSelect(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Assign \(terms.worker)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        JobDetailView(jobID: "job_1042")
            .environment(AppEnvironment())
    }
}
