import SwiftUI

/// The field worker shell: no tabs, no money, no customer directory. Just
/// today's stops in order with glove-sized controls.
///
/// Identical for every trade — only the vocabulary changes.
struct FieldWorkerDayView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = FieldWorkerDayViewModel()
    @State private var path = NavigationPath()
    @State private var isReportingDelay: Bool = false
    @State private var navigationHandoff: NavigationHandoff?
    @State private var travelEstimate: RouteEstimate?
    @State private var messagingJob: MessagingContext?

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationDestination(for: FieldJobRoute.self) { route in
                FieldWorkerJobView(jobID: route.jobID)
            }
            .navigationDestination(for: FieldTravelRoute.self) { route in
                TravelModeView(jobID: route.jobID)
            }
            .navigationTitle("My day")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isReportingDelay) {
                AddNoteSheet(showsVisibilityPicker: false) { body, _ in
                    guard let session, let jobID = viewModel.state.value?.currentStopID else { return }
                    Task {
                        await viewModel.notifyDispatch(
                            gateway: env.gateway,
                            session: session,
                            jobID: jobID,
                            body: body
                        )
                    }
                }
            }
            .sheet(item: $navigationHandoff) { handoff in
                NavigationHandoffSheet(handoff: handoff, estimate: travelEstimate)
            }
            .sheet(item: $messagingJob) { context in
                OfficeComposeSheet(jobID: context.jobID, jobNumber: context.number) { _ in }
            }
        }
        .task(id: session?.userID) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading your day")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let snapshot):
            loaded(snapshot)
        }
    }

    private func loaded(_ snapshot: FieldWorkerDaySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.greeting)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(snapshot.progressLine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.top, 4)
                .accessibilityElement(children: .combine)

                if snapshot.stops.isEmpty {
                    EmptyStateView(
                        symbolName: "checkmark.circle",
                        title: "No stops today",
                        message: "When dispatch assigns you work, it shows up here."
                    )
                    .cardSurface()
                } else {
                    ForEach(snapshot.stops) { stop in
                        if stop.jobID == snapshot.currentStopID {
                            currentStopCard(stop)
                        } else if stop.status.isOpen {
                            NavigationLink(value: FieldJobRoute(jobID: stop.jobID)) {
                                upcomingRow(stop)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(value: FieldJobRoute(jobID: stop.jobID)) {
                                completedRow(stop)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let error = viewModel.actionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                }

                // Only appears when a step genuinely could not record a
                // position. Nothing is invented in its place.
                if let refused = viewModel.lastCaptureOutcome?.refusedState {
                    LocationPermissionNotice(state: refused, worker: env.terms.worker)
                }

                if let confirmation = viewModel.lastConfirmation {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                        Text(confirmation)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Theme.green.opacity(0.1))
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                }

                // Two different things, kept apart on purpose. A note goes on
                // the job record where the office reads it later; a message
                // raises an alert on somebody's phone now. Collapsing them
                // would mean an engineer who urgently needs a part writes a
                // note nobody is told about.
                if let stop = snapshot.stops.first(where: { $0.jobID == snapshot.currentStopID }) {
                    actionRow(
                        symbol: "bubble.left.and.bubble.right.fill",
                        title: "Message the office",
                        detail: "Part needed, running late, need a decision"
                    ) {
                        messagingJob = MessagingContext(jobID: stop.jobID, number: stop.number)
                    }

                    actionRow(
                        symbol: "note.text",
                        title: "Add a note to this job",
                        detail: "Saved on the record — no alert sent"
                    ) {
                        isReportingDelay = true
                    }
                }

                if env.isDevelopmentSession { SimulatedServicesBanner() }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        }
        .refreshable { await reload(showLoading: false) }
    }

    private func currentStopCard(_ stop: FieldWorkerStop) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(stop.status.isFieldActive ? Theme.green : Theme.amber)
                    .frame(width: 12, height: 12)
                Text("\(stop.timeLabel) · \(stop.customerName)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if stop.isUrgent {
                    Text("Urgent")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.red.opacity(0.12))
                        .clipShape(.capsule)
                }
            }

            Text(stop.addressLine)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)

            VStack(alignment: .leading, spacing: 8) {
                iconLine(symbol: "wrench.adjustable", text: "\(stop.jobTitle) · \(stop.kindTitle)")
                if let equipment = stop.equipmentLine {
                    iconLine(symbol: "shippingbox", text: equipment)
                }
                if let notes = stop.accessNotes {
                    iconLine(symbol: "key", text: notes)
                }
                if let contact = stop.siteContactName, let phone = stop.siteContactPhone {
                    iconLine(symbol: "phone", text: "\(contact) · \(phone)")
                }
                iconLine(symbol: stop.status.symbolName, text: stop.statusTitle)
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    openNavigation(stop)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                        Text("Navigate")
                    }
                    .font(.headline)
                    // #1 — Navigate is an action, so it carries the action
                    // colour. Completion stays green: a semantic status is
                    // never overwritten by the brand.
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                    .background(Theme.surface)
                    .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.buttonRadius)
                            .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
                    }
                }
                .buttonStyle(PressableTileStyle())

                if let next = stop.nextStatus, let title = stop.nextActionTitle {
                    Button {
                        guard let session else { return }
                        Task {
                            await viewModel.advance(
                                gateway: env.gateway,
                                location: env.location,
                                session: session,
                                jobID: stop.jobID,
                                to: next,
                                destination: Coordinate(latitude: stop.latitude, longitude: stop.longitude)
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isUpdating { ProgressView().tint(.white) }
                            Text(title)
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        .background(next == .completed ? Theme.green : Theme.accent)
                        .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(viewModel.isUpdating)
                }
            }

            // Once they're on the road, travel mode is the useful screen.
            if stop.status == .travelling {
                NavigationLink(value: FieldTravelRoute(jobID: stop.jobID)) {
                    HStack(spacing: 6) {
                        Image(systemName: "car.fill")
                            .font(.caption)
                        Text("Travel mode")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            NavigationLink(value: FieldJobRoute(jobID: stop.jobID)) {
                HStack(spacing: 6) {
                    Text("Open job \(stop.number)")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func actionRow(
        symbol: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 32, height: 32)
                    .background(Theme.primaryTint)
                    .clipShape(.circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.meta)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(minHeight: Theme.minTap)
            .cardSurface()
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func iconLine(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .frame(width: 28, height: 28)
                .background(Theme.canvas)
                .clipShape(.circle)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func upcomingRow(_ stop: FieldWorkerStop) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(stop.timeLabel) · \(stop.customerName)")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text(stop.jobTitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .cardSurface()
    }

    private func completedRow(_ stop: FieldWorkerStop) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(stop.timeLabel) · \(stop.customerName)")
                    .font(.subheadline)
                    .strikethrough()
                    .foregroundStyle(Theme.meta)
                if let completed = stop.completedLabel {
                    Text(completed)
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .cardSurface()
    }

    /// Prepares the destination through the `MapService` adapter and confirms
    /// the hand-off. No routing happens inside this app.
    private func openNavigation(_ stop: FieldWorkerStop) {
        let destination = Coordinate(latitude: stop.latitude, longitude: stop.longitude)
        Task {
            if let origin = await env.location.currentLocation() {
                travelEstimate = await env.routes.estimate(from: origin, to: destination)
            }
            navigationHandoff = env.maps.prepareNavigation(
                to: destination,
                label: stop.customerName,
                addressLine: stop.addressLine
            )
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

/// Route value for the field stack. Deliberately separate from `AppRoute` so a
/// field worker's navigation can never resolve to an office screen.
nonisolated struct FieldJobRoute: Hashable, Sendable {
    let jobID: String
}

/// Travel mode, kept separate from the job route so the field stack stays
/// explicit about which screen it is pushing.
nonisolated struct FieldTravelRoute: Hashable, Sendable {
    let jobID: String
}

/// The job a message is being composed about, so the office sees the context.
nonisolated struct MessagingContext: Identifiable, Hashable, Sendable {
    let jobID: String
    let number: String

    var id: String { jobID }
}

#Preview {
    FieldWorkerDayView()
        .environment(AppEnvironment())
}
