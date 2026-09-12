import SwiftUI

struct JobsView: View {
    /// ISSUE #11 — the filter this screen opens on when a report metric drills
    /// into it. Nil keeps the screen's own default (today), which is what the
    /// Jobs tab itself relies on.
    var initialFilter: JobListFilter?

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = JobsViewModel()
    @State private var path = NavigationPath()
    @State private var isFiltering: Bool = false
    @State private var isCreating: Bool = false
    @State private var hasAppliedInitialFilter: Bool = false

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                VStack(spacing: 10) {
                    dateBar
                    if viewModel.query.hasRefinements { activeFilters }
                    content
                }
            }
            .navigationTitle("Jobs")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, prompt: "Job number, customer or address")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isFiltering = true
                    } label: {
                        Image(systemName: viewModel.query.hasRefinements ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .tint(Theme.actionTint)
                    .accessibilityLabel("Filter jobs")
                }
                if session?.can(.jobsManage) == true {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isCreating = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .tint(Theme.actionTint)
                        .accessibilityLabel("New job")
                    }
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                RouteDestinationView(route: route)
            }
            .sheet(isPresented: $isFiltering) {
                JobFilterSheet(query: $viewModel.query, options: viewModel.options, terms: terms)
            }
            .sheet(isPresented: $isCreating) {
                JobEditorView { jobID in
                    Task {
                        await reload(showLoading: false)
                        path.append(AppRoute.job(jobID))
                    }
                }
            }
        }
        .task(id: session?.userID) {
            guard let session else { return }
            if let initialFilter, !hasAppliedInitialFilter {
                viewModel.query = initialFilter.query
                hasAppliedInitialFilter = true
            }
            await viewModel.loadOptions(gateway: env.gateway, session: session)
            await reload()
        }
        .task(id: viewModel.query) { await reload(showLoading: false) }
        .task(id: viewModel.searchText) { await reload(showLoading: false) }
    }

    private var dateBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(JobDateScope.chips) { scope in
                    let isSelected = viewModel.query.dateScope == scope
                    Button {
                        viewModel.query.dateScope = scope
                    } label: {
                        Text(scope.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : Theme.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(isSelected ? Theme.selectedFill : Theme.surface)
                            .clipShape(.capsule)
                            .overlay {
                                Capsule().stroke(isSelected ? Color.clear : Theme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }

                if case .on(let date) = viewModel.query.dateScope {
                    Text(Formatters.shortDate(date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.primary)
                        .clipShape(.capsule)
                }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
    }

    private var activeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.activeFilterLabels(terms), id: \.self) { label in
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.actionTintSoft)
                        .clipShape(.capsule)
                }

                Button {
                    viewModel.query.clearRefinements()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Clear")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surface)
                    .clipShape(.capsule)
                    .overlay { Capsule().stroke(Theme.border, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading jobs")
        case .failed(let error):
            ScrollView {
                ErrorStateView(error: error) { Task { await reload() } }
            }
        case .loaded(let rows):
            if rows.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbolName: "briefcase",
                        title: emptyTitle,
                        message: emptyMessage
                    )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summaryLine(rows))
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                NavigationLink(value: AppRoute.job(row.id)) {
                                    JobRowView(row: row, showsDay: showsDayColumn)
                                }
                                .buttonStyle(.plain)

                                if index < rows.count - 1 {
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

    private var showsDayColumn: Bool {
        switch viewModel.query.dateScope {
        case .today, .tomorrow, .on: return false
        default: return true
        }
    }

    private func summaryLine(_ rows: [JobRow]) -> String {
        let urgent = rows.filter(\.isUrgent).count
        let unassigned = rows.filter(\.isUnassigned).count
        var parts = ["\(rows.count) job\(rows.count == 1 ? "" : "s")"]
        if urgent > 0 { parts.append("\(urgent) urgent") }
        if unassigned > 0 { parts.append("\(unassigned) unassigned") }
        return parts.joined(separator: " · ")
    }

    private var emptyTitle: String {
        viewModel.searchText.isEmpty ? "No jobs here" : "No matches"
    }

    private var emptyMessage: String {
        if !viewModel.searchText.isEmpty { return "Try a different job number, customer or address." }
        if viewModel.query.hasRefinements { return "Nothing matches these filters. Clear them to see the full list." }
        switch viewModel.query.dateScope {
        case .today: return "Nothing is scheduled for today."
        case .tomorrow: return "Tomorrow is clear."
        case .next7Days: return "Nothing booked in the next week."
        case .unscheduled: return "Everything has a slot in the calendar."
        case .all: return "Jobs will appear here once they're created."
        case .on(let date): return "Nothing booked on \(Formatters.shortDate(date))."
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    JobsView()
        .environment(AppEnvironment())
}
