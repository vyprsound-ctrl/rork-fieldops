import SwiftUI

/// The engineer's own forward schedule.
///
/// Read-only on purpose, and it says so rather than leaving the engineer poking
/// at rows that will never move. Scheduling belongs to dispatch: there is no
/// drag, no reschedule, no reassign and no delete anywhere on this screen, and
/// no gateway call behind it that could perform one.
struct EngineerScheduleView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = EngineerScheduleViewModel()
    @State private var path = NavigationPath()

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: FieldJobRoute.self) { route in
                FieldWorkerJobView(jobID: route.jobID)
            }
        }
        .task(id: session?.userID) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading your schedule")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let schedule):
            loaded(schedule)
        }
    }

    private func loaded(_ schedule: EngineerSchedule) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.headline)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(schedule.subline)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                .accessibilityElement(children: .combine)

                ForEach(schedule.days) { day in
                    dayCard(day)
                }

                readOnlyNotice
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        }
        .refreshable { await reload(showLoading: false) }
    }

    private func dayCard(_ day: EngineerScheduleDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.title)
                    .sectionLabelStyle()
                Spacer(minLength: 0)
                Text(day.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            }

            VStack(spacing: 0) {
                if day.stops.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.footnote)
                            .foregroundStyle(Theme.meta)
                        Text("Nothing booked.")
                            .font(.footnote)
                            .foregroundStyle(Theme.meta)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                } else {
                    ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                        NavigationLink(value: FieldJobRoute(jobID: stop.jobID)) {
                            stopRow(stop)
                        }
                        .buttonStyle(.plain)

                        if index < day.stops.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .cardSurface()
        }
    }

    private func stopRow(_ stop: EngineerScheduleStop) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.timeLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                if let duration = stop.durationLabel {
                    Text(duration)
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                }
            }
            .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(stop.customerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if stop.isUrgent {
                        Text("Urgent")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.red.opacity(0.12))
                            .clipShape(.capsule)
                    }
                }

                Text(stop.addressLine)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    StatusPill(badge: stop.badge)
                    Text(stop.kindTitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.meta)
                .padding(.top, 2)
        }
        .padding(14)
        .contentShape(.rect)
    }

    /// Stated plainly rather than implied by the absence of buttons, so nobody
    /// goes looking for a way to move their own jobs.
    private var readOnlyNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            Text("This is your assigned work. Times and assignments are set by the office — message them from the Office tab if something needs changing.")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.border, lineWidth: 1)
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    EngineerScheduleView()
        .environment(AppEnvironment())
}
