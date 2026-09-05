import SwiftUI

/// The operational calendar.
///
/// Day and week are the same data at two zoom levels — both read
/// `Job.scheduledStart`/`scheduledEnd`, and neither introduces a second notion
/// of a schedule. Conflicts are marked by the data layer, so what the dispatcher
/// sees here is what the gateway would refuse to write silently.
struct CalendarView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = ScheduleViewModel()
    @State private var path = NavigationPath()
    @State private var reschedulingJob: JobRow?
    @State private var assigningJob: JobRow?

    private var session: TenantSession? { env.session }
    private var terms: Terminology { env.terms }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: AppRoute.self) { route in
                RouteDestinationView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
            .sheet(item: $reschedulingJob) { job in
                RescheduleSheet(
                    jobNumber: job.number,
                    jobTitle: job.title,
                    currentStart: job.scheduledStart,
                    currentEnd: nil
                ) { start, end in
                    guard let session else { return }
                    Task {
                        await viewModel.reschedule(
                            gateway: env.gateway,
                            session: session,
                            jobID: job.id,
                            jobNumber: job.number,
                            start: start,
                            end: end
                        )
                    }
                }
            }
            .sheet(item: $assigningJob) { job in
                AssignWorkerSheet(
                    workers: viewModel.state.value?.workers ?? [],
                    currentWorkerID: nil,
                    terms: terms
                ) { workerID in
                    guard let session else { return }
                    Task { await assign(job, workerUserID: workerID, session: session) }
                }
            }
            .sheet(item: $viewModel.pendingReschedule) { pending in
                SchedulingConflictSheet(
                    title: "Move \(pending.jobNumber)",
                    check: pending.check,
                    confirmTitle: "Move anyway"
                ) {
                    guard let session else { return }
                    Task { await viewModel.confirmPendingReschedule(gateway: env.gateway, session: session) }
                }
            }
            .alert(
                "Couldn't do that",
                isPresented: Binding(
                    get: { viewModel.actionError != nil },
                    set: { if !$0 { viewModel.actionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.actionError = nil }
            } message: {
                Text(viewModel.actionError ?? "")
            }
        }
        .task(id: session?.userID) { await reload() }
        .task(id: viewModel.query) { await reload(showLoading: false) }
    }

    private var filterMenu: some View {
        Menu {
            Picker("View", selection: $viewModel.span) {
                ForEach(CalendarSpan.allCases) { span in
                    Text(span.title).tag(span)
                }
            }

            Divider()

            Button {
                viewModel.query.unassignedOnly.toggle()
            } label: {
                Label(
                    viewModel.query.unassignedOnly ? "Showing unassigned only" : "Show unassigned only",
                    systemImage: viewModel.query.unassignedOnly ? "checkmark.circle.fill" : "circle"
                )
            }

            if let board = viewModel.state.value, !board.workers.isEmpty {
                Menu(terms.WorkerPlural) {
                    Button("Everyone") { viewModel.query.fieldWorkerUserID = nil }
                    ForEach(board.workers) { worker in
                        Button(worker.name) { viewModel.query.fieldWorkerUserID = worker.id }
                    }
                }
            }

            if viewModel.query.hasRefinements {
                Divider()
                Button("Clear filters", role: .destructive) {
                    viewModel.query.clearRefinements()
                }
            }
        } label: {
            Image(systemName: viewModel.query.hasRefinements
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .tint(Theme.primary)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading calendar")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let board):
            loaded(board)
        }
    }

    private func loaded(_ board: CalendarBoard) -> some View {
        VStack(spacing: 10) {
            rangeBar(board)

            if board.span == .week {
                weekStrip(board)
            }

            if board.conflictCount > 0 || board.unassignedCount > 0 {
                summaryBar(board)
                    .padding(.horizontal, Theme.margin)
            }

            dayContent(board)
        }
    }

    private func rangeBar(_ board: CalendarBoard) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.shift(by: board.span == .week ? -7 : -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Theme.primary)
                    .cardSurface(radius: 10)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.today()
            } label: {
                VStack(spacing: 1) {
                    Text(board.rangeTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("\(board.totalJobs) job\(board.totalJobs == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .cardSurface(radius: 10)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.shift(by: board.span == .week ? 7 : 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Theme.primary)
                    .cardSurface(radius: 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.margin)
    }

    private func weekStrip(_ board: CalendarBoard) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(board.days) { day in
                    let isSelected = viewModel.selectedDayID == day.id
                    Button {
                        viewModel.selectedDayID = day.id
                    } label: {
                        VStack(spacing: 3) {
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Theme.meta)
                            Text(day.date.formatted(.dateTime.day()))
                                .font(.headline)
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? Color.white : Theme.ink)

                            HStack(spacing: 3) {
                                if !day.conflictingJobIDs.isEmpty {
                                    Circle()
                                        .fill(isSelected ? Color.white : Theme.amber)
                                        .frame(width: 5, height: 5)
                                }
                                if day.unassignedCount > 0 {
                                    Circle()
                                        .fill(isSelected ? Color.white.opacity(0.7) : Theme.red)
                                        .frame(width: 5, height: 5)
                                }
                                if !day.isEmpty, day.conflictingJobIDs.isEmpty, day.unassignedCount == 0 {
                                    Circle()
                                        .fill(isSelected ? Color.white : Theme.primary)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(height: 6)
                        }
                        .frame(width: 50, height: 70)
                        .background(isSelected ? Theme.primary : Theme.surface)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.clear : Theme.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.title), \(day.jobs.count) jobs, \(day.unassignedCount) unassigned")
                }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
    }

    private func summaryBar(_ board: CalendarBoard) -> some View {
        HStack(spacing: 8) {
            if board.unassignedCount > 0 {
                legendChip("\(board.unassignedCount) unassigned", tone: .danger)
            }
            if board.conflictCount > 0 {
                legendChip("\(board.conflictCount) overlapping", tone: .warning)
            }
            Spacer(minLength: 0)
        }
    }

    private func legendChip(_ text: String, tone: StatusTone) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint(tone))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint(tone).opacity(0.12))
            .clipShape(.capsule)
    }

    @ViewBuilder
    private func dayContent(_ board: CalendarBoard) -> some View {
        let selected = board.days.first { $0.id == viewModel.selectedDayID } ?? board.days.first

        if let selected {
            if selected.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbolName: "calendar.badge.clock",
                        title: "Nothing on \(selected.title.lowercased())",
                        message: viewModel.query.hasRefinements
                            ? "No jobs match the current filter on this day."
                            : "Scheduled work will show on this day once it's booked."
                    )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selected.title).sectionLabelStyle()

                        VStack(spacing: 0) {
                            ForEach(Array(selected.jobs.enumerated()), id: \.element.id) { index, row in
                                jobRow(row, day: selected, board: board)

                                if index < selected.jobs.count - 1 {
                                    Divider().padding(.leading, 14)
                                }
                            }
                        }
                        .cardSurface()
                    }
                    .padding(.horizontal, Theme.margin)
                    .padding(.bottom, 20)
                }
                .refreshable { await reload(showLoading: false) }
            }
        }
    }

    private func jobRow(_ row: JobRow, day: CalendarDay, board: CalendarBoard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: AppRoute.job(row.id)) {
                JobRowView(row: row)
            }
            .buttonStyle(.plain)

            if day.conflictingJobIDs.contains(row.id) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("Overlaps another job for this \(terms.worker)")
                        .font(.caption2.weight(.medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .swipeActions(edge: .trailing) {
            if board.canReschedule {
                Button {
                    reschedulingJob = row
                } label: {
                    Label("Move", systemImage: "calendar")
                }
                .tint(Theme.primary)
            }
            if board.canAssign {
                Button {
                    assigningJob = row
                } label: {
                    Label("Assign", systemImage: "person.badge.plus")
                }
                .tint(Theme.green)
            }
        }
    }

    private func tint(_ tone: StatusTone) -> Color {
        switch tone {
        case .neutral: return Theme.meta
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .success: return Theme.green
        case .danger: return Theme.red
        }
    }

    private func assign(_ job: JobRow, workerUserID: String?, session: TenantSession) async {
        do {
            _ = try await env.gateway.assignJob(
                session: session,
                jobID: job.id,
                input: AssignmentInput(workerUserID: workerUserID, acknowledgesConflict: false)
            )
            await reload(showLoading: false)
        } catch {
            let check = (try? await env.gateway.checkAssignment(
                session: session,
                jobID: job.id,
                workerUserID: workerUserID
            )) ?? .clear
            if check.hasConflicts {
                viewModel.actionError = "\(check.summary) Open the job to assign with that overlap."
            } else {
                viewModel.actionError = DataError.wrap(error).errorDescription
            }
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    CalendarView()
        .environment(AppEnvironment())
}
