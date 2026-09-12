import Foundation

/// Date scope for the jobs list. Kept separate from `JobStatus` because a job
/// can be, say, "assigned" and either scheduled or not.
nonisolated enum JobDateScope: Hashable, Sendable, Identifiable {
    case today
    case tomorrow
    case next7Days
    case unscheduled
    case all
    case on(Date)

    var id: String {
        switch self {
        case .today: return "today"
        case .tomorrow: return "tomorrow"
        case .next7Days: return "next7"
        case .unscheduled: return "unscheduled"
        case .all: return "all"
        case .on(let date): return "on-\(Int(date.timeIntervalSince1970))"
        }
    }

    var title: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .next7Days: return "Next 7 days"
        case .unscheduled: return "Unscheduled"
        case .all: return "All dates"
        case .on(let date): return Formatters.shortDate(date)
        }
    }

    static let chips: [JobDateScope] = [.today, .tomorrow, .next7Days, .unscheduled, .all]

    func matches(_ job: Job, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .unscheduled:
            return job.scheduledStart == nil
        case .today:
            guard let start = job.scheduledStart else { return false }
            return calendar.isDateInToday(start)
        case .tomorrow:
            guard let start = job.scheduledStart else { return false }
            return calendar.isDateInTomorrow(start)
        case .next7Days:
            guard let start = job.scheduledStart else { return false }
            guard let horizon = calendar.date(byAdding: .day, value: 7, to: Date()) else { return false }
            return start >= calendar.startOfDay(for: Date()) && start <= horizon
        case .on(let day):
            guard let start = job.scheduledStart else { return false }
            return calendar.isDate(start, inSameDayAs: day)
        }
    }
}

/// Everything the jobs list can be narrowed by. Passed to the gateway, which
/// applies it *after* the tenant and role gates — never instead of them.
nonisolated struct JobQuery: Hashable, Sendable {
    var dateScope: JobDateScope = .today
    var statuses: Set<JobStatus> = []
    var fieldWorkerUserID: String?
    var priority: JobPriority?
    var customerID: String?
    /// Matches job number, customer name or address.
    var searchText: String = ""

    static let today = JobQuery()

    /// Number of narrowing filters beyond the date chip, for the filter badge.
    var refinementCount: Int {
        var count = 0
        if !statuses.isEmpty { count += 1 }
        if fieldWorkerUserID != nil { count += 1 }
        if priority != nil { count += 1 }
        if customerID != nil { count += 1 }
        return count
    }

    var hasRefinements: Bool { refinementCount > 0 }

    mutating func clearRefinements() {
        statuses = []
        fieldWorkerUserID = nil
        priority = nil
        customerID = nil
    }
}

// MARK: - Options for filter and form pickers

nonisolated struct FieldWorkerOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let initials: String
}

nonisolated struct EquipmentOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// One of a customer's service addresses, with whatever is installed there.
nonisolated struct CustomerSiteOption: Identifiable, Hashable, Sendable {
    let id: String
    let line: String
    let equipment: [EquipmentOption]
}

nonisolated struct CustomerOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// The main site — the oldest address on the account.
    let addressID: String
    let addressLine: String
    let equipment: [EquipmentOption]
    /// Every site this customer has. Defaults to empty so a gateway that only
    /// serves the main site keeps working unchanged.
    var sites: [CustomerSiteOption] = []

    /// The sites to offer in a picker, always including the main one.
    var selectableSites: [CustomerSiteOption] {
        sites.isEmpty
            ? [CustomerSiteOption(id: addressID, line: addressLine, equipment: equipment)]
            : sites
    }

    func site(_ addressID: String) -> CustomerSiteOption? {
        selectableSites.first { $0.id == addressID }
    }
}

/// Reference data for the filter sheet and the job form, permission-gated: a
/// role without `usersRead` receives no worker list at all.
nonisolated struct JobFormOptions: Hashable, Sendable {
    let workers: [FieldWorkerOption]
    let customers: [CustomerOption]
    let canAssign: Bool

    static let empty = JobFormOptions(workers: [], customers: [], canAssign: false)
}

/// Payload for creating a job. `companyID` is absent on purpose — the gateway
/// takes it from the session so a caller can never write into another tenant.
nonisolated struct NewJobInput: Hashable, Sendable {
    var customerID: String
    /// The site the work happens at. One of the customer's own addresses.
    var addressID: String
    var equipmentID: String?
    var title: String
    var jobDescription: String
    var kind: JobKind = .callOut
    var priority: JobPriority = .standard
    var scheduledStart: Date?
    var scheduledEnd: Date?
    var fieldWorkerUserID: String?
    var quoteID: String?
}

/// Options chosen when turning an accepted quote into a job.
nonisolated struct QuoteConversionInput: Hashable, Sendable {
    var kind: JobKind = .install
    var priority: JobPriority = .standard
    var scheduledStart: Date?
    var scheduledEnd: Date?
    var fieldWorkerUserID: String?
}

nonisolated struct QuoteLineItemDraft: Hashable, Sendable, MoneyLine {
    /// `nil` creates a new line; an existing id edits that line in place.
    var id: String?
    var itemDescription: String
    var quantity: Decimal
    var unitPrice: Decimal
    var taxRate: Decimal
}

nonisolated struct NewQuoteInput: Hashable, Sendable {
    var customerID: String
    var addressID: String
    var title: String
    var scopeOfWork: String
    var validUntil: Date?
}

/// ISSUE #11 — the job filters a report metric can drill into.
///
/// Reports counted "Scheduled 14 / Completed 9" and stopped there: a number
/// with no way to reach the work behind it. Rather than build a second job list
/// with its own querying (and its own chance of quietly disagreeing with the
/// real one), a metric now opens the existing Jobs screen with one of these
/// applied. Each case maps onto `JobQuery`, which is the only thing that reads
/// jobs anywhere in the app, so permissions and tenancy are unchanged.
nonisolated enum JobListFilter: String, CaseIterable, Sendable, Identifiable {
    /// Live work across every date — matches the "Open" metric.
    case openNow
    /// Booked but with no slot — matches "Unscheduled".
    case unscheduled
    /// Booked for a date, in the reported window.
    case scheduled
    /// Finished, whether or not it has been billed.
    case completed
    /// Completed work that has reached an invoice.
    case billed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openNow: return "Open jobs"
        case .unscheduled: return "Unscheduled jobs"
        case .scheduled: return "Scheduled jobs"
        case .completed: return "Completed jobs"
        case .billed: return "Invoiced jobs"
        }
    }

    /// The statuses this filter means. Kept here rather than in the view so the
    /// report and the list can never drift apart.
    var statuses: Set<JobStatus> {
        switch self {
        case .openNow, .unscheduled, .scheduled:
            return [.scheduled, .workerAssigned, .travelling, .arrived, .inProgress]
        case .completed:
            return [.completed, .invoiced, .paid]
        case .billed:
            return [.invoiced, .paid]
        }
    }

    /// `openNow` and `unscheduled` are live counts across all dates in the
    /// report, so the list they open must not be narrowed to today.
    var dateScope: JobDateScope {
        switch self {
        case .openNow, .completed, .scheduled, .billed: return .all
        case .unscheduled: return .unscheduled
        }
    }

    var query: JobQuery {
        var query = JobQuery()
        query.dateScope = dateScope
        query.statuses = statuses
        return query
    }
}

nonisolated enum QuoteListFilter: String, CaseIterable, Sendable, Identifiable {
    case open
    case accepted
    case draft
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Open"
        case .accepted: return "Accepted"
        case .draft: return "Drafts"
        case .all: return "All"
        }
    }

    /// ISSUE #9A — a newly created quote never appeared under "Open".
    ///
    /// ROOT CAUSE, verified against the live database: `create_quote` stores a
    /// new quote with status `draft` (Q-1001 = draft), but `.open` matched only
    /// `sent`/`viewed`. A quote the user had just written was live work that the
    /// Open tab refused to show, so it appeared only under "All".
    ///
    /// "Open" now means what an operator means by it: still in play, not yet
    /// resolved. `accepted`, `declined` and `expired` are resolutions and stay
    /// out. `.draft` keeps its own tab, so nothing is lost — an unsent quote is
    /// visible in Open (it is live) and in Drafts (it is unsent).
    func matches(_ quote: Quote) -> Bool {
        switch self {
        case .open:
            return quote.status == .draft || quote.status == .sent || quote.status == .viewed
        case .accepted: return quote.status == .accepted
        case .draft: return quote.status == .draft
        case .all: return true
        }
    }
}
