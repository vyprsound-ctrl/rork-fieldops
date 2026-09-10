import SwiftUI

/// The engineer's own completed work.
///
/// Field history, deliberately not a report. There is no total, no value, no
/// hours-billed column and no financial figure of any kind — the record type
/// behind this screen has none. It exists so an engineer can find what they
/// did at a site three months ago, not so anyone can be measured by it.
struct EngineerWorkHistoryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = EngineerWorkHistoryViewModel()

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle("My work")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: session?.userID) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading your work")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let records):
            loaded(records)
        }
    }

    @ViewBuilder
    private func loaded(_ records: [EngineerWorkRecord]) -> some View {
        if records.isEmpty {
            ScrollView {
                EmptyStateView(
                    symbolName: "checkmark.seal",
                    title: "Nothing completed yet",
                    message: "Jobs you finish show up here with your notes, photos and the customer's signature."
                )
                .cardSurface()
                .padding(Theme.margin)
            }
            .refreshable { await reload(showLoading: false) }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(grouped(records), id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .sectionLabelStyle()

                            VStack(spacing: 0) {
                                ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                                    NavigationLink(value: FieldJobRoute(jobID: record.id)) {
                                        row(record)
                                    }
                                    .buttonStyle(.plain)

                                    if index < group.records.count - 1 {
                                        Divider().padding(.leading, 14)
                                    }
                                }
                            }
                            .cardSurface()
                        }
                    }

                    Text("Your completed visits. Open one to see the full record — what you did, the photos, and the signature.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .refreshable { await reload(showLoading: false) }
        }
    }

    private func row(_ record: EngineerWorkRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.green)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.customerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Text(record.title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(record.addressLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.meta)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(record.completedLabel, systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)

                    if record.photoCount > 0 {
                        Label("\(record.photoCount)", systemImage: "photo")
                            .font(.caption2)
                            .foregroundStyle(Theme.meta)
                    }
                    if record.noteCount > 0 {
                        Label("\(record.noteCount)", systemImage: "note.text")
                            .font(.caption2)
                            .foregroundStyle(Theme.meta)
                    }
                    if record.hasSignature {
                        Label("Signed", systemImage: "signature")
                            .font(.caption2)
                            .foregroundStyle(Theme.green)
                    }
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
        .accessibilityElement(children: .combine)
    }

    /// Grouped by month, because "what did I do at that place in June" is how
    /// an engineer actually looks for their own work.
    private func grouped(_ records: [EngineerWorkRecord]) -> [WorkGroup] {
        var order: [String] = []
        var buckets: [String: [EngineerWorkRecord]] = [:]

        for record in records {
            let key = Formatters.monthYear(record.completedAt)
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(record)
        }

        return order.map { WorkGroup(title: $0, records: buckets[$0] ?? []) }
    }

    private struct WorkGroup {
        let title: String
        let records: [EngineerWorkRecord]
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    NavigationStack {
        EngineerWorkHistoryView()
            .environment(AppEnvironment())
    }
}
