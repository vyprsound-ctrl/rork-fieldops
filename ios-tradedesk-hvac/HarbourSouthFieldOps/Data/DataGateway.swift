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

    // MARK: Customers, sites and assets
    //
    // These are protocol *requirements* with default implementations in
    // `CrmWorkflow.swift`, not extension-only members. The difference matters:
    // the app holds a `DataGateway` existential, and only a requirement
    // dispatches dynamically to the Supabase implementation. An extension-only
    // member would silently call the default on every caller.

    /// The full customer record: contacts, sites, assets, jobs and documents,
    /// each narrowed to what the caller's role may read.
    func customerProfile(session: TenantSession, customerID: String) async throws -> CustomerProfile

    /// Creates a customer with their first service address and main contact.
    /// Requires `customersManage`. Returns the new customer's id.
    func createCustomer(session: TenantSession, draft: CustomerDraft) async throws -> String

    func updateCustomer(session: TenantSession, customerID: String, draft: CustomerDraft) async throws

    /// Removes a customer that has no job, quote or invoice history. A customer
    /// with history is never removed.
    func deleteCustomer(session: TenantSession, customerID: String) async throws

    /// Adds or edits one service address. Returns its id.
    func saveCustomerAddress(session: TenantSession, customerID: String, draft: AddressDraft) async throws -> String

    /// Adds or edits one contact. Promoting a contact to main demotes the
    /// previous one in the same call.
    func saveCustomerContact(session: TenantSession, customerID: String, draft: ContactDraft) async throws -> String

    /// Registers or edits a serviceable asset at one of the customer's sites.
    /// Requires `equipmentManage`.
    func saveEquipment(session: TenantSession, customerID: String, draft: EquipmentDraft) async throws -> String

    // MARK: Team

    /// Everybody in the company, plus outstanding invitations. Requires
    /// `usersRead`; invitations additionally require `usersManage`.
    func teamRoster(session: TenantSession) async throws -> TeamRoster

    /// Issues an invitation and returns its one-time join code. The company and
    /// the role are stamped onto the invitation inside the database.
    func inviteTeamMember(session: TenantSession, draft: TeamInviteDraft) async throws -> TeamInvite

    func revokeInvitation(session: TenantSession, invitationID: String) async throws
    func updateTeamMemberStatus(session: TenantSession, userID: String, status: UserStatus) async throws
    func updateTeamMemberRole(session: TenantSession, userID: String, role: Role) async throws
    func updateTeamMemberDetails(session: TenantSession, userID: String, name: String, phone: String) async throws

    // MARK: Job completion and media

    /// Records the completion — work performed, parts, labour, signature,
    /// photos, asset history — and only then moves the job to completed.
    func completeJob(
        session: TenantSession,
        jobID: String,
        draft: JobCompletionDraft,
        locationFix: LocationFix?
    ) async throws -> JobCompletionOutcome

    /// Stores one image against a job and writes its photo record.
    func attachJobMedia(session: TenantSession, jobID: String, upload: JobMediaUpload) async throws -> JobMediaResult

    /// Stores one image sent in a conversation.
    ///
    /// A job-linked conversation passes its `jobID`, and the single row that
    /// results is simultaneously the message attachment and that job's
    /// permanent visual evidence — one upload, one object, both surfaces. A
    /// general conversation passes `nil` and the image is anchored to the
    /// thread alone, belonging to no job.
    func attachMessageMedia(
        session: TenantSession,
        threadID: String,
        jobID: String?,
        upload: JobMediaUpload
    ) async throws -> JobMediaResult

    /// A URL for an uploaded image, or `nil` when the image is held with the
    /// record itself or was never captured.
    func jobMediaURL(session: TenantSession, reference: String) async throws -> URL?

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

    // MARK: Engineer workspace
    //
    // Requirements with defaults in `EngineerWorkflow.swift`, for exactly the
    // reason given above the CRM block: the app holds a `DataGateway`
    // existential, so only a requirement dispatches to the Supabase
    // implementation. The defaults are built from other requirements on this
    // protocol, so every gateway answers something truthful without a second
    // hand-written implementation of the same rules.
    //
    // None of these types carries a monetary field. An engineer's payload is
    // money-free by construction, not by hiding.

    /// The engineer's own forward schedule. Read-only: there is deliberately no
    /// reschedule or reassign counterpart anywhere on this protocol for a field
    /// role.
    func engineerSchedule(session: TenantSession, dayCount: Int) async throws -> EngineerSchedule

    /// Sites this engineer has legitimate work at — never the company's whole
    /// customer directory.
    func engineerSites(session: TenantSession, query: String) async throws -> [EngineerSiteRow]

    /// One site: contacts, access, equipment, and the work done there.
    func engineerSiteDetail(session: TenantSession, addressID: String) async throws -> EngineerSiteDetail

    /// The engineer's own completed work. Field history, not a report.
    func engineerWorkHistory(session: TenantSession, limit: Int) async throws -> [EngineerWorkRecord]

    /// Profile, duty state and the counts behind them.
    func engineerProfile(session: TenantSession) async throws -> EngineerProfile

    /// Sets the caller's own availability. The database scopes this to
    /// `auth.uid()`, so it cannot set anybody else's.
    func updateDutyState(session: TenantSession, state: DutyState) async throws

    // MARK: Engineer ↔ office messaging

    func officeInbox(session: TenantSession) async throws -> OfficeInbox
    func officeConversation(session: TenantSession, threadID: String) async throws -> OfficeConversation

    /// Sends one message. Returns the conversation it landed in. Recipients are
    /// resolved from the company's own permission grants inside the database —
    /// this app names no individual.
    @discardableResult
    func sendOfficeMessage(session: TenantSession, draft: OfficeMessageDraft) async throws -> String

    func markOfficeThreadRead(session: TenantSession, threadID: String) async throws

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
    /// money — Harbour South is never a party to the customer's payment.
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

    // MARK: Phase 2 — the commercial layer
    //
    // Requirements, not extension-only members, for the same reason as the CRM
    // surface above: the app holds a `DataGateway` existential, and only a
    // requirement dispatches dynamically to the Supabase implementation.
    // Defaults live in `CommerceWorkflow.swift`.

    /// The company's SaaS subscription, with the price itemised from the live
    /// head count rather than a stored total.
    func subscriptionOverview(session: TenantSession) async throws -> SubscriptionOverview

    /// The company's own Stripe account — where *their* customers' money lands.
    /// Nothing here concerns the Harbour South subscription.
    func connectAccountStatus(session: TenantSession) async throws -> ConnectAccountStatus

    /// A one-time Stripe onboarding link. Requires `companyProfileManage`.
    ///
    /// `businessType` prefills the very first account creation and nothing else.
    /// It cannot move money, change a fee or reach another company, and Stripe
    /// independently verifies whatever is claimed.
    func beginConnectOnboarding(
        session: TenantSession,
        businessType: ConnectBusinessType
    ) async throws -> URL

    /// A login link to the merchant's own Stripe dashboard.
    func connectDashboardLink(session: TenantSession) async throws -> URL

    // MARK: The commercial model
    //
    // Apple subscription entitlement, plan, user seats, Stripe readiness and
    // the applicable platform fee. Every one of those is decided by
    // `company_commercial_state()` in the database; this call carries the
    // answers and the app renders them. There is deliberately no member here
    // that lets a client assert an entitlement, a plan, a fee or a trial.

    /// The company's whole commercial position, in one server-authoritative
    /// read. Requires a SaaS billing grant, which only the owner holds.
    func commercialState(session: TenantSession) async throws -> CommercialState

    /// Records that the company keeps its own payment provider, or clears the
    /// choice. Cannot be used to claim Harbour South Payments — that follows
    /// from Stripe reporting the account can take charges, and is set
    /// server-side.
    func selectPaymentModel(session: TenantSession, model: PaymentModel) async throws

    /// Hands Apple's SIGNED purchase data to the server, which verifies it
    /// against Apple's root certificate and records the entitlement. The app
    /// never records a subscription itself. Owner only.
    func linkStorePurchases(session: TenantSession, purchases: [SignedStorePurchase]) async throws -> StoreLinkResult

    /// Whether the caller's company has an active subscription, and its
    /// state. Readable by every company member; carries nothing else.
    func workspaceAccess(session: TenantSession) async throws -> WorkspaceAccess

    /// Whether the company may move to `planID`: refused while it has more
    /// active users than that plan allows. Owner only. Answers only — it never
    /// suspends or deletes anybody.
    func planChangeCheck(session: TenantSession, planID: PlanID) async throws -> PlanChangeCheck

    // MARK: Business email identity

    /// The business's own customer-facing email address, as used on the
    /// invoices its customers receive.
    func businessEmailSettings(session: TenantSession) async throws -> BusinessEmailSettings

    /// Sets or clears that address. `nil` clears it.
    func updateBusinessEmail(session: TenantSession, email: String?) async throws

    /// Balance, price list, ledger and recent messages.
    func smsCreditOverview(session: TenantSession) async throws -> SmsCreditOverview

    /// Sends one customer message. The credit is consumed atomically server-side
    /// *before* the provider is called, and returned if the provider refuses.
    func sendCustomerSms(session: TenantSession, draft: SmsSendDraft) async throws -> SmsSendOutcome

    /// Starts a credit purchase and returns the checkout URL. Credits are only
    /// granted once Stripe confirms the money arrived — never here.
    func purchaseSmsCredits(session: TenantSession, bundleID: String?, credits: Int?) async throws -> URL

    // Recurring service
    func recurringServices(session: TenantSession) async throws -> RecurringServiceBoard
    func saveRecurringService(session: TenantSession, draft: RecurringServiceDraft) async throws -> String
    func deleteRecurringService(session: TenantSession, id: String) async throws

    // Payment terms
    func paymentTermsSettings(session: TenantSession) async throws -> PaymentTermsSettings
    func updatePaymentTerms(session: TenantSession, option: PaymentTermOption, customDays: Int) async throws

    // Company profile

    /// The company's own details. Readable by anyone with `companyProfileRead`,
    /// which every office role has — an engineer does not.
    func companyProfile(session: TenantSession) async throws -> CompanyProfileSettings

    /// Writes the editable subset. Trade, country and currency are not part of
    /// the write: changing them would retro-relabel documents that already
    /// exist, so they are displayed and left alone.
    func updateCompanyProfile(session: TenantSession, profile: CompanyProfileSettings) async throws

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
