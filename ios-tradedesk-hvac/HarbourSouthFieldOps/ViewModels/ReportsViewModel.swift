import Foundation
import Observation

/// Operational job figures for one reporting period.
///
/// The two groups are deliberately different in kind, and the screen labels
/// them that way: `openNow` and `unscheduledNow` describe the business as it
/// stands right now, while the `inPeriod` figures describe work by its
/// scheduled date inside the chosen window. Mixing the two would produce a
/// number nobody could act on.
nonisolated struct JobsReport: Hashable, Sendable {
    let periodTitle: String
    let scheduledInPeriod: Int
    let completedInPeriod: Int
    let billedInPeriod: Int
    let openNow: Int
    let unscheduledNow: Int
}

/// Reports assembled entirely from reads the gateway already serves.
///
/// There is no reporting table, no aggregate endpoint and no second data path:
/// every figure here comes from `jobs` and `receivables`, so each one carries
/// the same company scoping and the same permission gates as the screens that
/// show the underlying records. A number can never appear in a report that the
/// signed-in user could not have reached through the app itself.
///
/// The two blocks load independently. Operational and financial reporting are
/// separate grants held by different roles, so one being refused must not blank
/// the other.
@Observable
final class ReportsViewModel {
    private(set) var operational: LoadState<JobsReport> = .idle
    private(set) var financial: LoadState<ReceivablesSnapshot> = .idle

    /// Shared by both blocks so the two halves of the screen always describe
    /// the same window.
    var period: InvoiceDateScope = .last30Days

    /// Statuses where the work is still live. Kept in one place so "open" means
    /// the same thing here as `JobStatus.isOpen` does everywhere else.
    private static let openStatuses: Set<JobStatus> = [
        .scheduled, .workerAssigned, .travelling, .arrived, .inProgress
    ]

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        let wantsOperational = session.can(.reportsOperational)
        let wantsFinancial = session.can(.reportsFinancial)

        if showLoading {
            if wantsOperational { operational = .loading }
            if wantsFinancial { financial = .loading }
        }

        if wantsOperational {
            do {
                operational = .loaded(try await loadJobs(gateway: gateway, session: session))
            } catch {
                operational = .failed(DataError.wrap(error))
            }
        }

        if wantsFinancial {
            do {
                // The receivables snapshot already computes outstanding,
                // overdue, due-this-week and collected over the same window,
                // with its own permission checks. Reusing it means the report
                // and the receivables screen can never disagree.
                financial = .loaded(
                    try await gateway.receivables(
                        session: session,
                        query: InvoiceQuery(filter: .all, dateScope: period)
                    )
                )
            } catch {
                financial = .failed(DataError.wrap(error))
            }
        }
    }

    /// Counts jobs per bucket.
    ///
    /// `JobRow` carries a rendered badge rather than a raw status, so each
    /// bucket is a separate filtered read instead of one read counted locally.
    /// That costs a few extra round trips on a screen the user opens
    /// deliberately, and it keeps every count coming from the same gateway
    /// filter the jobs list itself uses.
    private func loadJobs(gateway: DataGateway, session: TenantSession) async throws -> JobsReport {
        let everything = try await gateway.jobs(
            session: session,
            query: JobQuery(dateScope: .all)
        )
        let open = try await gateway.jobs(
            session: session,
            query: JobQuery(dateScope: .all, statuses: Self.openStatuses)
        )
        let completed = try await gateway.jobs(
            session: session,
            query: JobQuery(dateScope: .all, statuses: [.completed])
        )
        let billed = try await gateway.jobs(
            session: session,
            query: JobQuery(dateScope: .all, statuses: [.invoiced, .paid])
        )

        return JobsReport(
            periodTitle: period.title,
            scheduledInPeriod: everything.filter { isInPeriod($0.scheduledStart) }.count,
            completedInPeriod: completed.filter { isInPeriod($0.scheduledStart) }.count,
            billedInPeriod: billed.filter { isInPeriod($0.scheduledStart) }.count,
            openNow: open.count,
            unscheduledNow: everything.filter { $0.scheduledStart == nil }.count
        )
    }

    /// Backward-looking window, matching how `InvoiceDateScope` reads an invoice
    /// issue date.
    ///
    /// Capped at now on purpose: a job booked for next week has not happened, so
    /// counting it in "last 30 days" would overstate what the company did.
    /// Unscheduled work has no date to test and is reported separately rather
    /// than being silently dropped from every window.
    private func isInPeriod(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard period != .all else { return true }
        guard let date, date <= now else { return false }

        switch period {
        case .all:
            return true
        case .last30Days:
            guard let from = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return date >= from
        case .last90Days:
            guard let from = calendar.date(byAdding: .day, value: -90, to: now) else { return true }
            return date >= from
        case .thisYear:
            return calendar.component(.year, from: date) == calendar.component(.year, from: now)
        }
    }
}
