import Foundation

/// Colour intent for a status pill, resolved to a real colour in the view layer.
nonisolated enum StatusTone: String, Sendable {
    case neutral
    case info
    case warning
    case success
    case danger
}

nonisolated struct StatusBadge: Hashable, Sendable {
    let text: String
    let tone: StatusTone
}

// MARK: - Job projections

/// A job as it appears in a list. `value` is populated only when the caller's
/// role carries a financial read permission — otherwise the field is never
/// filled by the gateway, so there is nothing for the UI to hide.
nonisolated struct JobRow: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let timeLabel: String
    let dayLabel: String
    let scheduledStart: Date?
    let customerName: String
    let addressShort: String
    let badge: StatusBadge
    let kindTitle: String
    let kindSymbol: String
    let workerName: String?
    let workerInitials: String?
    let isUrgent: Bool
    let isUnassigned: Bool
    let value: String?
}

nonisolated struct EquipmentHistoryRow: Identifiable, Hashable, Sendable {
    let id: String
    let dateLabel: String
    let summary: String
}

/// A serviceable asset, ready to render. `categoryTitle` and `attributes` are
/// whatever the company recorded, so no trade's vocabulary is baked in.
nonisolated struct EquipmentProjection: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let subtitle: String
    let serialNumber: String
    let warrantyLabel: String?
    /// Trade-specific facts, already formatted ("Refrigerant · R-410A").
    let attributes: [String]
    let history: [EquipmentHistoryRow]
}

nonisolated struct AssignedWorkerProjection: Hashable, Sendable {
    let userID: String
    let name: String
    let initials: String
    let etaLabel: String?
    let phone: String?
}

/// Financial block for a job. The gateway only constructs this for roles that
/// hold the relevant permissions; it is `nil` for dispatchers and field workers.
nonisolated struct JobFinancialProjection: Hashable, Sendable {
    let quoteSummary: String?
    let invoiceSummary: String?
}

/// One recorded status change, ready to render.
nonisolated struct JobTimelineEntry: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let byLabel: String
    let timeLabel: String
    let locationLabel: String?
    let tone: StatusTone
    let symbolName: String
}

nonisolated struct JobNoteProjection: Identifiable, Hashable, Sendable {
    let id: String
    let body: String
    let authorName: String
    let authorInitials: String
    let timeLabel: String
    let visibilityTitle: String
    let isInternal: Bool
}

nonisolated struct JobPhotoProjection: Identifiable, Hashable, Sendable {
    let id: String
    let kindTitle: String
    let caption: String?
    let timeLabel: String
    let authorName: String
    /// Development builds hold a `sim://` reference — no file is uploaded.
    let storageReference: String
}

/// A status change the caller is actually allowed to make, decided by the data
/// layer from the workflow table plus the caller's permissions and assignment.
nonisolated struct JobTransitionOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let toStatus: JobStatus
    let isDestructive: Bool
    let capturesLocation: Bool
}

nonisolated struct JobDetailProjection: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let jobDescription: String
    let status: JobStatus
    let badge: StatusBadge
    let kindTitle: String
    let kindSymbol: String
    let priorityTitle: String
    let isUrgent: Bool

    let customerID: String
    let customerName: String
    let customerTypeTitle: String
    let contactName: String?
    let contactRole: String?
    let contactPhone: String?

    let addressLine: String
    let accessNotes: String?
    let latitude: Double
    let longitude: Double

    let scheduleLabel: String
    let durationLabel: String?
    let createdLabel: String
    let assignedWorker: AssignedWorkerProjection?
    let equipment: EquipmentProjection?
    let serviceAgreementLabel: String?

    /// Operational reference to the originating quote — carries no money, so a
    /// dispatcher can still see where the job came from.
    let quoteReference: String?
    let quoteID: String?
    /// Money. Nil unless the role holds a financial read permission.
    let financials: JobFinancialProjection?

    let timeline: [JobTimelineEntry]
    let notes: [JobNoteProjection]
    let photos: [JobPhotoProjection]

    let transitions: [JobTransitionOption]
    let canManage: Bool
    let canAssign: Bool
    let canAddNotes: Bool
    let canAddPhotos: Bool
}

// MARK: - Dashboard

nonisolated struct DashboardFinancialTile: Identifiable, Hashable, Sendable {
    let id: String
    let caption: String
    let amount: String
    let symbolName: String
}

nonisolated struct DashboardSnapshot: Hashable, Sendable {
    let headline: String
    let subline: String
    let todayJobs: [JobRow]
    /// Empty for roles without financial permissions.
    let financialTiles: [DashboardFinancialTile]

    // Everything below defaults, so a gateway that does not yet supply these
    // keeps compiling and simply shows nothing rather than showing zero.

    /// Today's progress, so the headline is progress rather than a bare count.
    var completedToday: Int = 0
    var remainingToday: Int = 0
    /// Distinct people with work booked today, and work with nobody on it.
    var workersOnToday: Int = 0
    var unassignedToday: Int = 0
    /// Message credit remaining. `nil` for a role that may not read the ledger,
    /// so the tile is absent rather than showing a misleading zero.
    var smsBalance: Int?
}

// MARK: - Calendar

nonisolated struct CalendarDay: Identifiable, Hashable, Sendable {
    let id: String
    let date: Date
    let title: String
    let jobs: [JobRow]
    /// Jobs on this day whose worker is double-booked. Surfaced here so the
    /// calendar can mark them without re-deriving the overlap in the view layer.
    var conflictingJobIDs: Set<String> = []
    var unassignedCount: Int = 0
    var urgentCount: Int = 0

    var isEmpty: Bool { jobs.isEmpty }
}

/// A day or a week of scheduled work, plus the reference data the calendar
/// needs to filter and reassign without a second round trip.
nonisolated struct CalendarBoard: Hashable, Sendable {
    let span: CalendarSpan
    let days: [CalendarDay]
    let workers: [FieldWorkerOption]
    let canAssign: Bool
    let canReschedule: Bool
    let rangeTitle: String
    let totalJobs: Int
    let unassignedCount: Int
    let conflictCount: Int
}

// MARK: - Dispatch

/// How busy one field worker is on the dispatched day, and where they are.
///
/// Trade-neutral by construction: the worker is described by workload, never by
/// trade. `roleTitle` is rendered in the company's own vocabulary.
nonisolated struct FieldWorkerWorkload: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let initials: String
    /// "Engineer", "Plumber", "Electrician" — the company's own word.
    let roleTitle: String
    let jobCount: Int
    let completedCount: Int
    let openCount: Int
    /// The stop they are on right now, if any.
    let currentJobID: String?
    let currentJobNumber: String?
    let currentStatus: JobStatus?
    let currentStatusTitle: String?
    /// Nothing live — free to take the next call-out.
    let isAvailable: Bool
    let hasConflict: Bool
    let scheduleLabel: String
    /// Latest known position, only when the caller may see it.
    let location: FieldWorkerLocationProjection?
}

/// The dispatch board: today's work, who is on what, and what still needs a
/// worker.
nonisolated struct DispatchBoard: Hashable, Sendable {
    let dateTitle: String
    let headline: String
    let subline: String

    /// Jobs with a slot on this day.
    let scheduled: [JobRow]
    /// Jobs with no slot at all — the backlog dispatch still has to place.
    let unscheduled: [JobRow]
    /// Scheduled today with nobody assigned.
    let unassigned: [JobRow]
    let urgent: [JobRow]
    /// Past their scheduled end and still not finished.
    let runningLate: [JobRow]
    let travelling: [JobRow]
    let inProgress: [JobRow]

    let workers: [FieldWorkerWorkload]
    let conflicts: [SchedulingConflict]

    let canAssign: Bool
    let canManageJobs: Bool
    /// Whether the caller may see worker positions at all.
    let canReadLocations: Bool

    var availableWorkers: [FieldWorkerWorkload] { workers.filter(\.isAvailable) }
}

// MARK: - Location

/// How fresh a position fix is.
///
/// The distinction is the whole point: a fix from four minutes ago is worth
/// acting on, one from yesterday is a historical record. The UI must never
/// present the second as the first.
nonisolated enum LocationFreshness: String, Hashable, Sendable {
    case recent
    case lastKnown

    var title: String { self == .recent ? "Recent" : "Last known" }
    var tone: StatusTone { self == .recent ? .success : .neutral }
}

/// One field worker's latest position, ready to render.
///
/// Assembled only for callers holding a location read permission, and only for
/// the rows that permission covers — a field worker receives their own fix and
/// nobody else's.
nonisolated struct FieldWorkerLocationProjection: Identifiable, Hashable, Sendable {
    let id: String
    let userID: String
    let workerName: String
    let initials: String
    let latitude: Double
    let longitude: Double
    let coordinateLabel: String
    let accuracyLabel: String
    let headingLabel: String?
    let speedLabel: String?
    let recordedAtLabel: String
    let recordedAt: Date
    let freshness: LocationFreshness
    /// The job being worked when the fix was taken.
    let jobID: String?
    let jobNumber: String?
    let jobStatusTitle: String?
    /// True while positions come from the simulated adapter.
    let isSimulated: Bool
}

/// The dispatcher's view of where everyone is.
nonisolated struct FieldWorkerLocationBoard: Hashable, Sendable {
    let locations: [FieldWorkerLocationProjection]
    /// Workers with no fix recorded at all.
    let withoutLocation: [String]
    let isSimulated: Bool
    /// The capture and retention policy, stated plainly for the UI.
    let policySummary: String
    let recentCount: Int
    let lastKnownCount: Int
}

// MARK: - Travel

/// Everything the travel screen shows once a worker is on their way.
///
/// The estimate is optional because a route provider may be unavailable; the
/// screen degrades to destination-only rather than inventing an arrival time.
nonisolated struct TravelSnapshot: Hashable, Sendable {
    let jobID: String
    let number: String
    let customerName: String
    let addressLine: String
    let accessNotes: String?
    let siteContactName: String?
    let siteContactPhone: String?
    let latitude: Double
    let longitude: Double
    let status: JobStatus
    let statusTitle: String
    let badge: StatusBadge
    let scheduleLabel: String
    let isUrgent: Bool
    let nextActionTitle: String?
    let nextStatus: JobStatus?
    /// The company's country, so distance is shown in the right units.
    let countryCode: String
}

// MARK: - Customers

nonisolated struct CustomerRow: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let initials: String
    let typeTitle: String
    let addressShort: String
    let contactCount: Int
    let openJobCount: Int
    /// Only present for roles holding `customerBillingDetailsRead`.
    let balanceLabel: String?
}

// MARK: - Field worker shell

/// A field worker's stop. Note the type has no monetary field at all — the
/// restriction is structural, not cosmetic.
nonisolated struct FieldWorkerStop: Identifiable, Hashable, Sendable {
    let jobID: String
    let number: String
    let timeLabel: String
    let customerName: String
    let addressLine: String
    let jobTitle: String
    let kindTitle: String
    let equipmentLine: String?
    let status: JobStatus
    let statusTitle: String
    let isUrgent: Bool
    let completedLabel: String?
    let latitude: Double
    let longitude: Double
    let accessNotes: String?
    let siteContactName: String?
    let siteContactPhone: String?
    let nextActionTitle: String?
    let nextStatus: JobStatus?

    var id: String { jobID }
}

nonisolated struct FieldWorkerDaySnapshot: Hashable, Sendable {
    let greeting: String
    let progressLine: String
    let stops: [FieldWorkerStop]

    var currentStopID: String? {
        stops.first(where: { $0.status.isOpen })?.jobID
    }
}

/// Full job view for a field worker. Like `FieldWorkerStop`, this type carries
/// no price, total, balance or payment field of any kind: money is not merely
/// hidden from field workers, it is never assembled into their payload.
nonisolated struct FieldWorkerJobDetail: Identifiable, Hashable, Sendable {
    let jobID: String
    let number: String
    let title: String
    let jobDescription: String
    let kindTitle: String
    let isUrgent: Bool
    let status: JobStatus
    let badge: StatusBadge
    let scheduleLabel: String

    let customerName: String
    let addressLine: String
    let latitude: Double
    let longitude: Double
    let accessNotes: String?
    let siteContactName: String?
    let siteContactPhone: String?

    let equipment: EquipmentProjection?
    let timeline: [JobTimelineEntry]
    let notes: [JobNoteProjection]
    let photos: [JobPhotoProjection]
    let transitions: [JobTransitionOption]

    var id: String { jobID }
}

// MARK: - Quotes

nonisolated struct QuoteRow: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let customerName: String
    let addressShort: String
    let badge: StatusBadge
    let status: QuoteStatus
    let dateLabel: String
    let validityLabel: String?
    let itemCountLabel: String
    /// Nil for roles without `quoteFinancialsRead` (dispatchers see quotes,
    /// never their money).
    let totalLabel: String?
    let convertedJobNumber: String?
}

/// Pricing for one quote line. Assembled only for roles holding
/// `quoteFinancialsRead`.
nonisolated struct QuoteLinePricing: Hashable, Sendable {
    let unitPrice: Decimal
    let taxRate: Decimal
    let lineTotal: Decimal
    let unitPriceLabel: String
    let taxRateLabel: String
    let lineTotalLabel: String
}

nonisolated struct QuoteLineItemProjection: Identifiable, Hashable, Sendable {
    let id: String
    let itemDescription: String
    let quantity: Decimal
    let quantityLabel: String
    let sortOrder: Int
    let pricing: QuoteLinePricing?
}

nonisolated struct QuoteTotalsProjection: Hashable, Sendable {
    let subtotal: Decimal
    let tax: Decimal
    let total: Decimal
    let subtotalLabel: String
    let taxLabel: String
    let totalLabel: String
}

nonisolated struct QuoteStatusAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let status: QuoteStatus
    let isDestructive: Bool
}

nonisolated struct QuoteDetailProjection: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let scopeOfWork: String
    let status: QuoteStatus
    let badge: StatusBadge

    let customerID: String
    let customerName: String
    let contactLabel: String?
    let addressLine: String

    let createdLabel: String
    let sentLabel: String?
    let viewedLabel: String?
    let acceptedLabel: String?
    let declinedLabel: String?
    let validUntilLabel: String?
    let isExpiringSoon: Bool

    let lineItems: [QuoteLineItemProjection]
    /// Nil for roles without `quoteFinancialsRead`.
    let totals: QuoteTotalsProjection?

    /// The company's configured currency, so no screen has to assume one.
    let currencyCode: String
    /// The company's current default tax rate, offered when a **new** line is
    /// added. Existing lines always keep their own stored rate, so this value
    /// never rewrites tax already agreed on this document. Nil for roles
    /// without `quoteFinancialsRead`.
    let defaultTaxRate: Decimal?

    let statusActions: [QuoteStatusAction]
    let canManage: Bool
    let canEditLineItems: Bool
    let canConvert: Bool
    let convertedJobID: String?
    let convertedJobNumber: String?
    /// The invoice already raised from this quote, if any. Present only for
    /// roles holding `invoicesRead`; carries no money.
    let invoicedReference: String?
    let invoiceID: String?
    /// This quote is accepted and has not been invoiced yet.
    let canRaiseInvoice: Bool
}

// MARK: - Invoices

/// An invoice as it appears in a list.
///
/// Every monetary field on this type is non-optional, because the gateway only
/// ever constructs an `InvoiceRow` for a caller holding `invoicesRead`. A role
/// without that permission receives `notPermitted` from the query itself and no
/// row is assembled at all — there is no "stripped" invoice row to leak.
nonisolated struct InvoiceRow: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let customerID: String
    let customerName: String
    let badge: StatusBadge
    let status: InvoiceStatus
    let issuedLabel: String
    let dueLabel: String
    let isOverdue: Bool
    let daysOverdue: Int?
    let totalLabel: String
    let balanceLabel: String
    let amountPaidLabel: String?
    let jobReference: String?
    let quoteReference: String?
}

/// Pricing for one invoice line. Assembled only for roles holding
/// `invoicesRead`, exactly like `QuoteLinePricing`.
nonisolated struct InvoiceLinePricing: Hashable, Sendable {
    let unitPrice: Decimal
    let taxRate: Decimal
    let lineTotal: Decimal
    let lineTax: Decimal
    let unitPriceLabel: String
    let taxRateLabel: String
    let lineTotalLabel: String
    let lineTaxLabel: String
}

nonisolated struct InvoiceLineItemProjection: Identifiable, Hashable, Sendable {
    let id: String
    let itemDescription: String
    let quantity: Decimal
    let quantityLabel: String
    let sortOrder: Int
    let pricing: InvoiceLinePricing?
    /// True when this line was snapshotted from a quote at conversion time.
    let isFromQuote: Bool
}

/// The money block. `subtotal + tax == total` and `total - amountPaid ==
/// balance` are guaranteed by the gateway, which derives all five from the line
/// items and the recorded payments.
nonisolated struct InvoiceTotalsProjection: Hashable, Sendable {
    let subtotal: Decimal
    let tax: Decimal
    let total: Decimal
    let amountPaid: Decimal
    let balance: Decimal
    let subtotalLabel: String
    let taxLabel: String
    let totalLabel: String
    let amountPaidLabel: String
    let balanceLabel: String
}

nonisolated struct PaymentProjection: Identifiable, Hashable, Sendable {
    let id: String
    let amountLabel: String
    let amount: Decimal
    let methodTitle: String
    let methodSymbol: String
    let statusTitle: String
    let statusTone: StatusTone
    let receivedLabel: String
    let recordedByName: String
    let reference: String?
    let note: String?
    /// Development payments are marked on the record itself, so the UI cannot
    /// accidentally present one as a real settlement.
    let isSimulated: Bool
    let invoiceNumber: String?
    let customerName: String?
}

nonisolated struct InvoiceStatusAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let status: InvoiceStatus
    let isDestructive: Bool
}

nonisolated struct InvoiceDetailProjection: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let scopeOfWork: String
    let status: InvoiceStatus
    let badge: StatusBadge

    let customerID: String
    let customerName: String
    let customerTypeTitle: String
    /// The contact this invoice is billed to, captured when it was raised.
    let billingContactName: String?
    let billingContactRole: String?
    let billingContactPhone: String?
    let billingContactEmail: String?
    let addressLine: String?

    let issuedLabel: String
    let dueLabel: String
    let paymentTermsLabel: String
    let isOverdue: Bool
    let daysOverdue: Int?
    let sentLabel: String?
    let viewedLabel: String?
    let paidLabel: String?
    let voidedLabel: String?

    /// Operational reference to the job — carries no money.
    let jobReference: String?
    let jobID: String?
    /// Operational reference to the originating quote — carries no money.
    let quoteReference: String?
    let quoteID: String?

    let lineItems: [InvoiceLineItemProjection]
    let totals: InvoiceTotalsProjection
    let payments: [PaymentProjection]

    /// The currency this invoice was **issued in**, snapshotted at issue. Not
    /// the company's current setting.
    let currencyCode: String
    /// The company's current default rate, offered for a **new** line only.
    /// Existing lines keep their own stored rate.
    let defaultTaxRate: Decimal?

    let statusActions: [InvoiceStatusAction]
    let canManage: Bool
    let canEditLineItems: Bool
    let canRecordPayment: Bool
    /// The most a payment may be for: the remaining balance. Overpayment is
    /// refused by the data layer, not merely by the keyboard.
    let maximumPayment: Decimal
    let maximumPaymentLabel: String
}

// MARK: - Customer-facing delivery

/// The company's own online payment destination, as the settings screen sees it.
///
/// Harbour South holds a URL and nothing else — no processor account, no
/// credentials, no integration. The money never passes through this product.
nonisolated struct PaymentLinkSettings: Hashable, Sendable {
    let url: String?
    /// "buy.stripe.com", "square.link" — what the customer will be sent to.
    let displayHost: String?
    let canManage: Bool

    var isConfigured: Bool { url != nil }
}

/// One recorded delivery attempt, read back from the notifications ledger.
///
/// This is the attempt's *real* outcome, not an optimistic echo of the button
/// that was pressed: an attempt made with no provider configured is recorded,
/// and shown, as failed.
nonisolated struct InvoiceDeliveryProjection: Identifiable, Hashable, Sendable {
    let id: String
    let channel: NotificationChannel
    let channelTitle: String
    let channelSymbol: String
    let recipient: String
    let status: NotificationStatus
    let statusTitle: String
    let statusTone: StatusTone
    let timeLabel: String
    let failureReason: String?
}

/// Everything the invoice screen needs to share an invoice with the customer.
nonisolated struct InvoiceSharing: Hashable, Sendable {
    /// The live customer-facing link, if one has been issued.
    let shareURL: String?
    /// False for drafts and voided invoices — neither is a document a customer
    /// should be looking at.
    let canShare: Bool
    let blockedReason: String?
    /// `invoicesManage`. Sending is refused by the server as well.
    let canSend: Bool
    let emailRecipient: String?
    let smsRecipient: String?
    let paymentLink: PaymentLinkSettings
    let deliveries: [InvoiceDeliveryProjection]
    /// True on the development stack, where no link is live and no message can
    /// leave the device.
    let isSimulated: Bool
}

/// What actually happened on one channel.
nonisolated struct InvoiceSendResult: Identifiable, Hashable, Sendable {
    let channel: NotificationChannel
    let recipient: String
    let delivered: Bool
    /// False when the provider has no credentials configured. Kept separate
    /// from `delivered` so "we didn't try" is never dressed up as "it failed
    /// in transit" — or worse, as "sent".
    let providerConfigured: Bool
    let detail: String

    var id: String { channel.rawValue }
}

nonisolated struct InvoiceSendOutcome: Hashable, Sendable {
    let results: [InvoiceSendResult]

    var deliveredCount: Int { results.filter(\.delivered).count }
    var didDeliverAnything: Bool { deliveredCount > 0 }
    var missingProviders: [NotificationChannel] {
        results.filter { !$0.providerConfigured }.map(\.channel)
    }
}

// MARK: - Accounts receivable

nonisolated struct ReceivablesMetric: Identifiable, Hashable, Sendable {
    let id: String
    let caption: String
    let amountLabel: String
    let amount: Decimal
    let countLabel: String
    let symbolName: String
    let tone: StatusTone
}

/// Operational accounts receivable: what is owed, what is late, what lands this
/// week and what has been collected.
///
/// Deliberately *not* accounting software — there is no ledger, no chart of
/// accounts and no bookkeeping here, just the money the business is waiting on.
nonisolated struct ReceivablesSnapshot: Hashable, Sendable {
    let metrics: [ReceivablesMetric]
    let invoices: [InvoiceRow]
    /// Worst offenders first, for the collections list.
    let overdueInvoices: [InvoiceRow]
    let recentPayments: [PaymentProjection]
    let currencyCode: String
    let customerOptions: [CustomerOption]
    let collectedCaption: String
}
