import SwiftUI

/// The field worker's job screen. Everything they need on site and nothing they
/// don't: the payload type carries no price, total or balance at all.
struct FieldWorkerJobView: View {
    let jobID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = FieldWorkerJobViewModel()
    @State private var isAddingNote: Bool = false
    @State private var isAddingPhoto: Bool = false
    @State private var navigationHandoff: NavigationHandoff?
    @State private var travelEstimate: RouteEstimate?

    private var session: TenantSession? { env.session }
    private var terms: Terminology { env.terms }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle(viewModel.state.value?.number ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: jobID) { await reload() }
        .sheet(isPresented: $isAddingNote) {
            AddNoteSheet(showsVisibilityPicker: false) { body, _ in
                guard let session else { return }
                Task { await viewModel.addNote(gateway: env.gateway, session: session, jobID: jobID, body: body) }
            }
        }
        .sheet(isPresented: $isAddingPhoto) {
            AddPhotoSheet { kind, caption in
                guard let session else { return }
                Task { await viewModel.addPhoto(gateway: env.gateway, session: session, jobID: jobID, kind: kind, caption: caption) }
            }
        }
        .sheet(item: $navigationHandoff) { handoff in
            NavigationHandoffSheet(handoff: handoff, estimate: travelEstimate)
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

    private func loaded(_ job: FieldWorkerJobDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        StatusPill(badge: job.badge)
                        if job.isUrgent {
                            Text("Urgent")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.red.opacity(0.12))
                                .clipShape(.rect(cornerRadius: 6))
                        }
                        Text(job.kindTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                    }

                    Text(job.customerName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.ink)

                    Text(job.title)
                        .font(.headline)
                        .foregroundStyle(Theme.secondary)

                    Text(job.scheduleLabel)
                        .font(.subheadline)
                        .foregroundStyle(Theme.meta)
                }
                .padding(.top, 4)

                if let error = viewModel.actionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.red.opacity(0.08))
                        .clipShape(.rect(cornerRadius: Theme.cardRadius))
                }

                // Only appears when a step genuinely could not record a
                // position. Nothing is invented in its place.
                if let refused = viewModel.lastCaptureOutcome?.refusedState {
                    LocationPermissionNotice(state: refused, worker: env.terms.worker)
                }

                siteCard(job)
                descriptionCard(job)
                if let equipment = job.equipment { equipmentCard(equipment) }
                JobNotesSection(notes: job.notes, canAdd: true) { isAddingNote = true }
                JobPhotosSection(photos: job.photos, canAdd: true) { isAddingPhoto = true }
                JobTimelineSection(entries: job.timeline)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
        }
        .safeAreaInset(edge: .bottom) {
            if !job.transitions.isEmpty { actionBar(job) }
        }
        .refreshable { await reload(showLoading: false) }
    }

    private func siteCard(_ job: FieldWorkerJobDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                icon("mappin.and.ellipse")
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.addressLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let access = job.accessNotes {
                        Text(access)
                            .font(.footnote)
                            .foregroundStyle(Theme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if let name = job.siteContactName {
                Divider()
                HStack(spacing: 12) {
                    icon("person.crop.circle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Text("Site contact")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                    if let phone = job.siteContactPhone, let url = URL(string: "tel://\(phone.filter(\.isNumber))") {
                        Link(destination: url) {
                            Text("Call")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Theme.primaryTint)
                                .clipShape(.capsule)
                        }
                    }
                }
            }

            Button {
                navigate(job)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                    Text("Navigate")
                }
                .font(.headline)
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .buttonStyle(PressableTileStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func descriptionCard(_ job: FieldWorkerJobDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's the job")
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

    private func equipmentCard(_ equipment: EquipmentProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(terms.Asset) & history")
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

                if equipment.history.isEmpty {
                    Text("No service history recorded yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                } else {
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

    private func actionBar(_ job: FieldWorkerJobDetail) -> some View {
        VStack(spacing: 8) {
            ForEach(job.transitions) { transition in
                Button {
                    guard let session else { return }
                    Task {
                        await viewModel.advance(
                            gateway: env.gateway,
                            location: env.location,
                            session: session,
                            jobID: jobID,
                            to: transition.toStatus,
                            destination: Coordinate(latitude: job.latitude, longitude: job.longitude)
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isWorking { ProgressView().tint(.white) }
                        Text(transition.title)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(transition.toStatus == .completed ? Theme.green : Theme.primary)
                    .foregroundStyle(.white)
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

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.footnote)
            .foregroundStyle(Theme.primary)
            .frame(width: 32, height: 32)
            .background(Theme.primaryTint)
            .clipShape(.circle)
    }

    /// Prepares the destination through the `MapService` adapter. The app hands
    /// off to the device's maps application; it does not navigate.
    private func navigate(_ job: FieldWorkerJobDetail) {
        let destination = Coordinate(latitude: job.latitude, longitude: job.longitude)
        Task {
            if let origin = await env.location.currentLocation() {
                travelEstimate = await env.routes.estimate(from: origin, to: destination)
            }
            navigationHandoff = env.maps.prepareNavigation(
                to: destination,
                label: job.customerName,
                addressLine: job.addressLine
            )
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, jobID: jobID, showLoading: showLoading)
    }
}

#Preview {
    NavigationStack {
        FieldWorkerJobView(jobID: "job_1042")
            .environment(AppEnvironment())
    }
}
