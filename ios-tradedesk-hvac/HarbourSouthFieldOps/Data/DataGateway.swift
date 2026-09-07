import Foundation

/// Counts and summaries for the More section, each one gated.
nonisolated struct MoreOverview: Hashable, Sendable {
    let workerCount: Int?
    let quoteCount: Int?
    let invoiceCount: Int?
    let outstandingLabel: String?
    let paymentCount: Int?
    let smsBalance: Int?
    let subscriptionSummary: String?
    let companyName: String
    let tradeTitle: String
    let roleTitle: String
}

/// A single recorded access decision, used by the in-app data-access inspector
/// to make enforcement visible rather than assumed.
nonisolated struct AccessDecision: Identifiable, Hashable, Sendable {
    let id: String
    let query: String
    let role: Role
    let allowed: Bool
    let detail: String
    let at: Date
}

/// The only way the app is allowed to reach data.
///
/// Implementations must apply the tenant gate (company scope) and the role
/// gate (row + field projection) before returning anything. The production
/// implementation will be backed by Supabase with the same rules expressed as
/// Row Level Security policies.
///
/// Nothing in this protocol is trade-specific: the same surface serves HVAC,
/// plumbing, electrical, roofing and every other field-service trade.
protocol DataGateway: Sendable {
    // Overview surfaces
    func dashboard(session: TenantSession) async throws -> DashboardSnapshot
    func calendarDays(session: TenantSession, dayCount: Int) async throws -> [CalendarDay]
    func customers(session: TenantSession, query: String) async throws -> [CustomerRow]
    func moreOverview(session: TenantSession) async throws -> MoreOverview
    func recentAccessDecisions(session: TenantSession) async throws -> [AccessDecision]

    /// The company's field workers, for the roster screen.
    ///
    /// Requires `usersRead`. A default implementation derives the list from the
    /// assignable-worker options, so an implementation that cannot read user
    /// records still answers something truthful; gateways that can read them
    /// override it to include invited and suspended people too.
    func fieldWorkerRoster(session: TenantSession) async throws -> FieldWorkerRoster

    // Jobs
    func jobs(session: TenantSession, query: JobQuery) async throws -> [JobRow]
    func jobFormOptions(session: TenantSession) async throws -> JobFormOptions
    func jobDetail(session: TenantSession, jobID: String) async throws -> JobDetailProjection
    func createJob(session: TenantSession, input: NewJobInput) async throws -> String
    /// Applies a workflow transition, optionally stamping it with a position
    /// captured by the `LocationService` adapter at that moment.
    ///
    /// The fix is passed *in* rather than fetched here: the data layer stays
    /// free of service dependencies, and the capture policy lives in one place
    /// (`LocationCaptureEvent`) instead of being implied by the gateway.
    func updateJobStatus(session: TenantSession, jobID: String, to status: JobStatus, locationFix: LocationFix?) async throws
    /// Assigns, reassigns or clears a job's field worker from the job's own
    /// screen. Subject to the same overlap rule as dispatch: an assignment that
    /// would double-book is refused unless the caller has seen the clash and
    /// acknowledged it.
    func assignFieldWorker(
        session: TenantSession,
        jobID: String,
        workerUserID: String?,
        acknowledgesConflict: Bool
    ) async throws
    func addJobNote(session: TenantSession, jobID: String, body: String, visibility: NoteVisibility) async throws
    func addJobPhoto(session: TenantSession, jobID: String, kind: JobPhotoKind, caption: String?) async throws

    // Field worker shell
    func fieldWorkerDay(session: TenantSession) async throws -> FieldWorkerDaySnapshot
    func fieldWorkerJobDetail(session: TenantSession, jobID: String) async throws -> FieldWorkerJobDetail

    // Quotes
    func quotes(session: TenantSession, filter: QuoteListFilter, query: String) async throws -> [QuoteRow]
    func quoteDetail(session: TenantSession, quoteID: String) async throws -> QuoteDetailProjection
    func createQuote(session: TenantSession, input: NewQuoteInput) async throws -> String
    func updateQuoteStatus(session: TenantSession, quoteID: String, to status: QuoteStatus) async throws
    func saveQuoteLineItem(session: TenantSession, quoteID: String, draft: QuoteLineItemDraft) async throws
    func deleteQuoteLineItem(session: TenantSession, quoteID: String, lineItemID: String) async throws
    func reorderQuoteLineItems(session: TenantSession, quoteID: String, orderedIDs: [String]) async throws

    /// Converts an accepted quote into a new job. The quote is left historically
    /// intact; only its `convertedJobID` back-reference is set.
    func convertQuoteToJob(session: TenantSession, quoteID: String, input: QuoteConversionInput) async throws -> String

    // Invoices
    func invoices(session: TenantSession, query: InvoiceQuery) async throws -> [InvoiceRow]
    func invoiceDetail(session: TenantSession, invoiceID: String) async throws -> InvoiceDetailProjection
    /// Completed jobs and accepted quotes that have not yet been invoiced.
    func invoiceSources(session: TenantSession) async throws -> InvoiceSourceOptions
    func createInvoice(session: TenantSession, input: NewInvoiceInput) async throws -> String

    /// Raises an invoice for a completed job, inheriting the customer, billing
    /// contact, site, agreed scope and — where the job came from an accepted
    /// quote — that quote's priced lines and its reference. The job's own record
    /// is not rewritten; only its workflow status advances, and only as a
    /// recorded transition.
    func createInvoiceFromJob(session: TenantSession, jobID: String, input: InvoiceConversionInput) async throws -> String

    /// Raises an invoice from an accepted quote, taking a **snapshot** of the
    /// quote's line items as they stand at this moment. The quote is left
    /// exactly as the customer accepted it, and later edits to it never reach
    /// the invoice.
    func createInvoiceFromQuote(session: TenantSession, quoteID: String, input: InvoiceConversionInput) async throws -> String

    func saveInvoiceLineItem(session: TenantSession, invoiceID: String, draft: InvoiceLineItemDraft) async throws
    func deleteInvoiceLineItem(session: TenantSession, invoiceID: String, lineItemID: String) async throws
    func updateInvoiceStatus(session: TenantSession, invoiceID: String, to status: InvoiceStatus) async throws

    // Payments and receivables
    /// Records a payment against an invoice and re-derives the balance and
    /// status. Refuses to take more than the outstanding balance.
    func recordPayment(session: TenantSession, invoiceID: String, draft: PaymentDraft) async throws
    func payments(session: TenantSession, query: InvoiceQuery) async throws -> [PaymentProjection]
    func receivables(session: TenantSession, query: InvoiceQuery) async throws -> ReceivablesSnapshot

    // MARK: Customer-facing invoice delivery

    /// The company's own online payment destination, plus whether this caller
    /// may change it.
    func companyPaymentLink(session: TenantSession) async throws -> PaymentLinkSettings

    /// Sets or clears the company's payment link. `nil` clears it. Requires
    /// `companyProfileManage`; the value is validated before it is written and
    /// again by the database.
    ///
    /// This stores a URL. It connects nothing, authorises nothing and moves no
    /// money — TradeDesk is never a party to the customer's payment.
    func updateCompanyPaymentLink(session: TenantSession, url: String?) async throws

    /// Everything needed to share one invoice with its customer: the live link,
    /// who it would go to, and every delivery already attempted.
    func invoiceSharing(session: TenantSession, invoiceID: String) async throws -> InvoiceSharing

    /// Issues the customer-facing link, or returns the existing one. With
    /// `rotate` the previous link is revoked first, so a link sent to the wrong
    /// address can be killed and replaced.
    func issueInvoiceShareLink(session: TenantSession, invoiceID: String, rotate: Bool) async throws -> String

    /// Kills every live link for this invoice.
    func revokeInvoiceShareLink(session: TenantSession, invoiceID: String) async throws

    /// Sends the invoice to its customer. The work happens server-side — no
    /// provider credential ever reaches this app — and each attempt's real
    /// outcome is recorded in the notifications ledger.
    func sendInvoice(
        session: TenantSession,
        invoiceID: String,
        channels: Set<NotificationChannel>
    ) async throws -> InvoiceSendOutcome

    // MARK: Push notifications

    /// Registers this device against the signed-in user.
    ///
    /// The registration carries no company or user: both are resolved from the
    /// authenticated session inside the database, so a device cannot be
    /// registered into another tenant. Returns the stored device's id.
    func registerPushDevice(session: TenantSession, registration: PushDeviceRegistration) async throws -> String

    /// Removes this device's registration. Called on sign-out so a shared
    /// handset stops receiving the previous user's job alerts. Returns whether
    /// a live registration was actually removed.
    func unregisterPushDevice(session: TenantSession, token: String) async throws -> Bool

    /// Push notifications addressed to the signed-in user, newest first, read
    /// from the same notifications ledger that records SMS and email.
    func pushInbox(session: TenantSession, limit: Int) async throws -> [PushNotificationRecord]

    // MARK: Dispatch and scheduling

    /// The dispatch board for one day: scheduled work, the unscheduled backlog,
    /// what is unassigned, urgent, late or live, and each worker's load.
    func dispatchBoard(session: TenantSession, query: DispatchQuery) async throws -> DispatchBoard

    /// A day or week of scheduled work, with conflicts already marked.
    func calendarBoard(session: TenantSession, query: CalendarQuery) async throws -> CalendarBoard

    /// Dry run: would assigning this worker to this job create an overlap?
    /// Read-only, so the UI can warn *before* anything is written.
    func checkAssignment(session: TenantSession, jobID: String, workerUserID: String?) async throws -> SchedulingCheck

    /// Dry run for a proposed new time slot.
    func checkReschedule(session: TenantSession, jobID: String, input: RescheduleInput) async throws -> SchedulingCheck

    /// Assigns, reassigns or clears a job's field worker. Refuses an overlapping
    /// assignment unless the caller has acknowledged the conflict, so a worker
    /// can never be silently double-booked.
    func assignJob(session: TenantSession, jobID: String, input: AssignmentInput) async throws -> SchedulingCheck

    /// Moves a job to a new slot under the same conflict rule.
    func rescheduleJob(session: TenantSession, jobID: String, input: RescheduleInput) async throws -> SchedulingCheck

    // MARK: Location

    /// Latest known position per field worker, scoped by role: office roles see
    /// the company's workers, a field worker sees only themselves.
    func fieldWorkerLocations(session: TenantSession) async throws -> FieldWorkerLocationBoard

    /// Records a position captured at a workflow event. Called by the app layer
    /// with a fix from the `LocationService` adapter; the gateway stamps the
    /// company and user from the session, never from the caller.
    func recordLocationFix(
        session: TenantSession,
        jobID: String?,
        event: LocationCaptureEvent,
        fix: LocationFix
    ) async throws

    /// The travel screen for a job the caller is assigned to.
    func travelSnapshot(session: TenantSession, jobID: String) async throws -> TravelSnapshot
}

extension DataGateway {
    func pushInbox(session: TenantSession) async throws -> [PushNotificationRecord] {
        try await pushInbox(session: session, limit: 30)
    }

    /// Transition with no position attached — the common case for office
    /// transitions, which deliberately capture nothing.
    func updateJobStatus(session: TenantSession, jobID: String, to status: JobStatus) async throws {
        try await updateJobStatus(session: session, jobID: jobID, to: status, locationFix: nil)
    }

    /// First attempt: no acknowledgement offered, so an overlap is refused and
    /// comes back as a clash the caller must confirm.
    func assignFieldWorker(session: TenantSession, jobID: String, workerUserID: String?) async throws {
        try await assignFieldWorker(
            session: session,
            jobID: jobID,
            workerUserID: workerUserID,
            acknowledgesConflict: false
        )
    }
}
