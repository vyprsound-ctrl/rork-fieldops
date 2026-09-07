import SwiftUI

/// The dispatch board.
///
/// Deliberately not a control centre. It answers the handful of questions a
/// dispatcher actually asks — what's on today, what still needs a worker, what's
/// urgent, what's running late, where is everyone — and then gets out of the
/// way. Everything it shows is the same `Job` and `FieldWorkerAssignment` data
/// the rest of the app uses; there is no second assignment system here.
struct DispatchView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = DispatchViewModel()
    @State private var assigningJob: JobRow?
    @State private var reschedulingJob: JobRow?

    private var session: TenantSession? { env.session }
    private var terms: Terminology { env.terms }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle("Dispatch")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
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
        }
        .searchable(text: $viewModel.query.searchText, prompt: "Job, customer or address")
        .task(id: session?.userID) { await reload() }
        .task(id: viewModel.query) { await reload(showLoading: false) }
        .sheet(item: $assigningJob) { job in
            assignSheet(for: job)
        }
        .sheet(item: $reschedulingJob) { job in
            RescheduleSheet(
                jobNumber: job.number,
                jobTitle: job.title,
                currentStart: job.scheduledStart,
                currentEnd: nil
            ) { start, end in
                Task { await reschedule(job, start: start, end: end) }
            }
        }
        .sheet(item: $viewModel.pendingConflict) { pending in
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

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading dispatch")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let board):
            loaded(board)
        }
    }

    private func loaded(_ board: DispatchBoard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(board)
                dayStrip

                if !board.conflicts.isEmpty { conflictBanner(board) }

                if !board.unassigned.isEmpty {
                    jobSection(
                        "Needs \(board.unassigned.count == 1 ? "a \(terms.worker)" : terms.workerPlural)",
                        board.unassigned,
                        tone: .warning,
                        board: board
                    )
                }

                if !board.urgent.isEmpty {
                    jobSection("Urgent", board.urgent, tone: .danger, board: board)
                }

                if !board.runningLate.isEmpty {
                    jobSection("Running late", board.runningLate, tone: .danger, board: board)
                }

                if !board.workers.isEmpty { workerSection(board) }

                jobSection(
                    "\(board.dateTitle)'s schedule",
                    board.scheduled,
                    tone: .info,
                    board: board,
                    emptyMessage: "Nothing booked for this day."
                )

                if !board.unscheduled.isEmpty {
                    jobSection(
                        "Unscheduled backlog",
                        board.unscheduled,
                        tone: .neutral,
                        board: board,
                        footnote: "These have no slot yet. Give one a time to put it on the calendar."
                    )
                }

                SimulatedServicesBanner()
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
            .padding(.top, 4)
        }
        .refreshable { await reload(showLoading: false) }
    }

    // MARK: - Sections

    private func header(_ board: DispatchBoard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(board.headline)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(board.subline)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)

            HStack(spacing: 8) {
                countChip("\(board.travelling.count)", "travelling", tone: .warning)
                countChip("\(board.inProgress.count)", "on site", tone: .success)
                countChip("\(board.unassigned.count)", "unassigned", tone: board.unassigned.isEmpty ? .neutral : .warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func countChip(_ value: String, _ caption: String, tone: StatusTone) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint(tone))
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint(tone).opacity(0.1))
        .clipShape(.capsule)
    }

    private var dayStrip: some View {
        HStack(spacing: 8) {
            Button {
                shiftDay(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Theme.primary)
                    .cardSurface(radius: 10)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.query.date = Date()
            } label: {
                Text(Formatters.dayTitle(viewModel.query.date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .cardSurface(radius: 10)
            }
            .buttonStyle(.plain)

            Button {
                shiftDay(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Theme.primary)
                    .cardSurface(radius: 10)
            }
            .buttonStyle(.plain)
        }
    }

    private func conflictBanner(_ board: DispatchBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(board.conflicts) { conflict in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(conflict.jobNumber) overlaps \(conflict.clashingJobNumber)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(conflict.detail)
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.1))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func workerSection(_ board: DispatchBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(terms.WorkerPlural).sectionLabelStyle()
                if board.canReadLocations {
                    NavigationLink(value: AppRoute.more(.workerLocations)) {
                        Text("Locations")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                    }
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(board.workers.enumerated()), id: \.element.id) { index, worker in
                    workerRow(worker)
                    if index < board.workers.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func workerRow(_ worker: FieldWorkerWorkload) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(worker.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(worker.isAvailable ? Theme.green : Theme.primary)
                .frame(width: 34, height: 34)
                .background((worker.isAvailable ? Theme.green : Theme.primary).opacity(0.12))
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(worker.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if worker.hasConflict {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.amber)
                    }
                }

                Text(worker.jobCount == 0
                     ? "No stops · \(worker.scheduleLabel)"
                     : "\(worker.jobCount) stop\(worker.jobCount == 1 ? "" : "s") · \(worker.scheduleLabel)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)

                if let current = worker.currentJobNumber, let status = worker.currentStatusTitle {
                    Text("On \(current) · \(status)")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                }

                if let location = worker.location {
                    HStack(spacing: 5) {
                        Image(systemName: location.freshness == .recent ? "location.fill" : "location.slash")
                            .font(.caption2)
                        Text("\(location.freshness.title) · \(location.recordedAtLabel)")
                            .font(.caption2)
                    }
                    .foregroundStyle(location.freshness == .recent ? Theme.green : Theme.meta)
                }
            }

            Spacer(minLength: 4)

            Text(worker.isAvailable ? "Free" : "Busy")
                .font(.caption2.weight(.bold))
                .foregroundStyle(worker.isAvailable ? Theme.green : Theme.meta)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((worker.isAvailable ? Theme.green : Theme.meta).opacity(0.12))
                .clipShape(.capsule)
        }
        .padding(14)
    }

    private func jobSection(
        _ title: String,
        _ rows: [JobRow],
        tone: StatusTone,
        board: DispatchBoard,
        emptyMessage: String? = nil,
        footnote: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).sectionLabelStyle()
                if !rows.isEmpty {
                    Text("\(rows.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint(tone))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint(tone).opacity(0.12))
                        .clipShape(.capsule)
                }
            }

            if rows.isEmpty {
                Text(emptyMessage ?? "Nothing here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        NavigationLink(value: AppRoute.job(row.id)) {
                            JobRowView(row: row)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if board.canManageJobs {
                                Button {
                                    reschedulingJob = row
                                } label: {
                                    Label("Reschedule", systemImage: "calendar")
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

                        if index < rows.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .cardSurface()
            }

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func assignSheet(for job: JobRow) -> some View {
        let board = viewModel.state.value
        AssignWorkerSheet(
            workers: (board?.workers ?? []).map {
                FieldWorkerOption(id: $0.id, name: $0.name, initials: $0.initials)
            },
            currentWorkerID: nil,
            terms: terms
        ) { workerID in
            let name = board?.workers.first { $0.id == workerID }?.name ?? terms.Worker
            Task { await assign(job, workerUserID: workerID, workerName: name) }
        }
    }

    // MARK: - Actions

    private func tint(_ tone: StatusTone) -> Color {
        switch tone {
        case .neutral: return Theme.meta
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .success: return Theme.green
        case .danger: return Theme.red
        }
    }

    private func shiftDay(_ days: Int) {
        viewModel.query.date = Calendar.current.date(
            byAdding: .day,
            value: days,
            to: viewModel.query.date
        ) ?? viewModel.query.date
    }

    private func assign(_ job: JobRow, workerUserID: String?, workerName: String) async {
        guard let session else { return }
        await viewModel.assign(
            gateway: env.gateway,
            session: session,
            jobID: job.id,
            jobNumber: job.number,
            workerUserID: workerUserID,
            workerName: workerName
        )
    }

    private func reschedule(_ job: JobRow, start: Date?, end: Date?) async {
        guard let session else { return }
        do {
            _ = try await env.gateway.rescheduleJob(
                session: session,
                jobID: job.id,
                input: RescheduleInput(scheduledStart: start, scheduledEnd: end, acknowledgesConflict: false)
            )
            await reload(showLoading: false)
        } catch {
            let check = (try? await env.gateway.checkReschedule(
                session: session,
                jobID: job.id,
                input: RescheduleInput(scheduledStart: start, scheduledEnd: end)
            )) ?? .clear
            if check.hasConflicts {
                viewModel.actionError = "\(check.summary) Open the job to move it with that overlap."
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
    NavigationStack {
        DispatchView()
            .environment(AppEnvironment())
    }
}
