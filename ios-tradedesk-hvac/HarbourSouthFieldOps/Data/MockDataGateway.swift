import Foundation

/// DEVELOPMENT IMPLEMENTATION of `DataGateway`, backed by an in-memory store.
///
/// It exists to exercise the real enforcement rules before Supabase is wired:
/// * Tenant gate — every query starts by filtering on `session.companyID`,
///   which comes from the authenticated session and never from the caller.
/// * Row gate — jobs a field worker isn't assigned to are dropped, and a
///   request for one of them answers `notFound` rather than "forbidden", so the
///   row's existence never leaks.
/// * Field gate — money is simply never assembled for roles without financial
///   permissions, so restricted values never reach the device.
/// * Write gate — every status change is validated against `JobWorkflow` and
///   recorded in `JobStatusHistory`.
///
/// Labels are rendered in the company's own trade vocabulary via
/// `session.terms`; that affects wording only, never rows or fields.
///
/// The production implementation will express the same rules as Supabase Row
/// Level Security policies plus column grants.
actor MockDataGateway: DataGateway {
    private var store: MockDataStore
    private var decisions: [AccessDecision] = []
    private let latency: Duration

    init(store: MockDataStore = .seeded(), latency: Duration = .milliseconds(260)) {
        self.store = store
        self.latency = latency
    }

    /// DEVELOPMENT ONLY. Hands back a copy of the in-memory store so the
    /// acceptance suite can mutate a record *behind* the gateway and then prove
    /// an already-issued document is unaffected — for example, editing a quote
    /// after an invoice has been snapshotted from it.
    ///
    /// Deliberately absent from the `DataGateway` protocol: no screen, view
    /// model or production implementation can reach it, and it grants no
    /// privilege the app itself could ever use.
    func developmentSnapshot() -> MockDataStore { store }

    // MARK: - Gates

    private func record(_ query: String, _ session: TenantSession, allowed: Bool, _ detail: String) {
        decisions.insert(
            AccessDecision(
                id: UUID().uuidString,
                query: query,
                role: session.role,
                allowed: allowed,
                detail: detail,
                at: Date()
            ),
            at: 0
        )
        if decisions.count > 60 { decisions.removeLast(decisions.count - 60) }
    }

    private func require(_ permission: Permission, _ session: TenantSession, query: String) throws {
        guard session.can(permission) else {
            record(query, session, allowed: false, "Blocked at data layer — missing \(permission.rawValue)")
            throw DataError.notPermitted(permission)
        }
    }

    /// Tenant gate. Every collection read passes through here.
    private func scoped<T>(_ rows: [T], _ session: TenantSession, companyID: KeyPath<T, String>) -> [T] {
        rows.filter { $0[keyPath: companyID] == session.companyID }
    }

    private func assignedJobIDs(_ session: TenantSession) -> Set<String> {
        Set(
            store.assignments
                .filter { $0.companyID == session.companyID && $0.userID == session.userID }
                .map(\.jobID)
        )
    }

    /// Row gate for jobs: all company jobs, or only the caller's assignments.
    private func visibleJobs(_ session: TenantSession, query: String) throws -> [Job] {
        let tenantRows = scoped(store.jobs, session, companyID: \.companyID)
        if session.can(.jobsReadAll) {
            record(query, session, allowed: true, "\(tenantRows.count) rows in company scope")
            return tenantRows
        }
        if session.can(.jobsReadAssignedOnly) {
            let ids = assignedJobIDs(session)
            let rows = tenantRows.filter { ids.contains($0.id) }
            record(query, session, allowed: true, "\(rows.count) assigned rows of \(tenantRows.count) in company")
            return rows
        }
        record(query, session, allowed: false, "No job read permission")
        throw DataError.notPermitted(.jobsReadAll)
    }

    private func requireVisibleJob(_ jobID: String, _ session: TenantSession, query: String) throws -> Job {
        let visible = try visibleJobs(session, query: query)
        guard let job = visible.first(where: { $0.id == jobID }) else {
            record(query, session, allowed: false, "Row outside scope — returned notFound")
            throw DataError.notFound
        }
        return job
    }

    /// Row gate for quotes.
    private func visibleQuotes(_ session: TenantSession, query: String) throws -> [Quote] {
        try require(.quotesRead, session, query: query)
        let rows = scoped(store.quotes, session, companyID: \.companyID)
        record(query, session, allowed: true, "\(rows.count) rows, money \(session.can(.quoteFinancialsRead) ? "included" : "not assembled")")
        return rows
    }

    private func requireVisibleQuote(_ quoteID: String, _ session: TenantSession, query: String) throws -> Quote {
        let rows = try visibleQuotes(session, query: query)
        guard let quote = rows.first(where: { $0.id == quoteID }) else {
            record(query, session, allowed: false, "Row outside scope — returned notFound")
            throw DataError.notFound
        }
        return quote
    }

    private func canReadJobMoney(_ session: TenantSession) -> Bool {
        session.can(.quoteFinancialsRead) || session.can(.invoicesRead)
    }

    // MARK: - Lookups

    private func customer(_ id: String, _ session: TenantSession) -> Customer? {
        store.customers.first { $0.id == id && $0.companyID == session.companyID }
    }

    private func address(_ id: String, _ session: TenantSession) -> Address? {
        store.addresses.first { $0.id == id && $0.companyID == session.companyID }
    }

    private func primaryAssignment(_ jobID: String, _ session: TenantSession) -> FieldWorkerAssignment? {
        store.assignments.first { $0.jobID == jobID && $0.companyID == session.companyID && $0.isPrimary }
    }

    private func user(_ id: String, _ session: TenantSession) -> UserAccount? {
        store.users.first { $0.id == id && $0.companyID == session.companyID }
    }

    private func company(_ session: TenantSession) -> Company? {
        store.companies.first { $0.id == session.companyID }
    }

    private func primaryContact(_ customerID: String, _ session: TenantSession) -> CustomerContact? {
        store.contacts.first { $0.customerID == customerID && $0.companyID == session.companyID && $0.isPrimary }
    }

    private func lineItems(_ quoteID: String, _ session: TenantSession) -> [QuoteLineItem] {
        store.quoteLineItems
            .filter { $0.quoteID == quoteID && $0.companyID == session.companyID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func invoiceLines(_ invoiceID: String, _ session: TenantSession) -> [InvoiceLineItem] {
        store.invoiceLineItems
            .filter { $0.invoiceID == invoiceID && $0.companyID == session.companyID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func invoicePayments(_ invoiceID: String, _ session: TenantSession) -> [Payment] {
        store.payments
            .filter { $0.invoiceID == invoiceID && $0.companyID == session.companyID }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    /// The contact an invoice is billed to: the customer's designated billing
    /// contact, falling back to their primary contact.
    private func billingContact(_ customerID: String, _ session: TenantSession) -> CustomerContact? {
        let all = store.contacts.filter { $0.customerID == customerID && $0.companyID == session.companyID }
        return all.first(where: \.isBillingContact) ?? all.first(where: \.isPrimary) ?? all.first
    }

    /// The live (non-void) invoice already raised against a job or a quote.
    /// Used to refuse a second conversion from the same source.
    private func existingInvoice(jobID: String? = nil, quoteID: String? = nil, _ session: TenantSession) -> Invoice? {
        scoped(store.invoices, session, companyID: \.companyID).first { invoice in
            guard invoice.status != .void else { return false }
            if let jobID { return invoice.jobID == jobID }
            if let quoteID { return invoice.quoteID == quoteID }
            return false
        }
    }

    // MARK: - Company configuration

    /// The tenant's configured currency. Every money label in this gateway goes
    /// through here, so no screen and no projection can assume a currency.
    private func currencyCode(_ session: TenantSession) -> String {
        company(session)?.currencyCode ?? Company.fallbackCurrencyCode
    }

    private func money(_ value: Decimal, _ session: TenantSession) -> String {
        Formatters.currency(value, code: currencyCode(session))
    }

    private func moneyRounded(_ value: Decimal, _ session: TenantSession) -> String {
        Formatters.currencyRounded(value, code: currencyCode(session))
    }

    /// Money on an invoice is labelled in the currency that invoice was issued
    /// in — a snapshot taken when it was raised, not the company's current
    /// setting. Changing the company currency therefore re-labels nothing that
    /// has already been issued.
    private func invoiceMoney(_ value: Decimal, _ invoice: Invoice) -> String {
        Formatters.currency(value, code: invoice.currencyCode)
    }

    /// The company's default tax rate for a **new** line item. Existing lines
    /// keep the rate stored against them, so changing this never rewrites the
    /// tax on a document that has already been written.
    private func defaultTaxRate(_ session: TenantSession) -> Decimal {
        company(session)?.defaultTaxRate ?? 0
    }

    // MARK: - Presentation helpers

    private func badge(for status: JobStatus, _ session: TenantSession) -> StatusBadge {
        StatusBadge(text: status.title(session.terms), tone: status.tone)
    }

    /// Money label for a job row — only ever built for permitted roles.
    private func jobValueLabel(_ job: Job, _ session: TenantSession) -> String? {
        if session.can(.invoicesRead),
           let invoice = store.invoices.first(where: { $0.jobID == job.id && $0.companyID == session.companyID }) {
            // Labelled in the currency the invoice was *issued* in, not the
            // company's current setting.
            return invoiceMoney(invoice.total, invoice)
        }
        if session.can(.quoteFinancialsRead),
           let quoteID = job.quoteID,
           let quote = store.quotes.first(where: { $0.id == quoteID && $0.companyID == session.companyID }) {
            return money(quote.total, session)
        }
        return nil
    }

    private func jobRow(_ job: Job, _ session: TenantSession) -> JobRow {
        let cust = customer(job.customerID, session)
        let addr = address(job.addressID, session)
        let worker = primaryAssignment(job.id, session).flatMap { user($0.userID, session) }
        return JobRow(
            id: job.id,
            number: job.number,
            title: job.title,
            timeLabel: job.scheduledStart.map { Formatters.time($0) } ?? "No slot",
            dayLabel: job.scheduledStart.map { Formatters.dayTitle($0) } ?? "Unscheduled",
            scheduledStart: job.scheduledStart,
            customerName: cust?.name ?? "Customer",
            addressShort: addr?.shortLine ?? "",
            badge: badge(for: job.status, session),
            kindTitle: job.kind.title,
            kindSymbol: job.kind.symbolName,
            workerName: worker?.name,
            workerInitials: worker?.initials,
            isUrgent: job.priority == .urgent,
            isUnassigned: worker == nil,
            value: jobValueLabel(job, session),
            status: job.status
        )
    }

    private func equipmentProjection(_ equipmentID: String?, _ session: TenantSession) -> EquipmentProjection? {
        guard session.can(.equipmentRead),
              let equipmentID,
              let unit = store.equipment.first(where: { $0.id == equipmentID && $0.companyID == session.companyID })
        else { return nil }

        let history = store.equipmentHistory
            .filter { $0.equipmentID == unit.id && $0.companyID == session.companyID }
            .sorted { $0.occurredAt > $1.occurredAt }
            .map {
                EquipmentHistoryRow(
                    id: $0.id,
                    dateLabel: Formatters.monthYear($0.occurredAt),
                    summary: $0.summary
                )
            }

        let installedYear = unit.installedOn.formatted(.dateTime.year())
        var warranty: String?
        if let expires = unit.warrantyExpiresOn {
            warranty = expires > Date()
                ? "Warranty to \(Formatters.shortDate(expires))"
                : "Warranty expired \(Formatters.shortDate(expires))"
        }

        return EquipmentProjection(
            id: unit.id,
            displayName: unit.displayName,
            subtitle: "\(unit.category) · installed \(installedYear)",
            serialNumber: unit.serialNumber,
            warrantyLabel: warranty,
            attributes: unit.attributes.map { "\($0.name) · \($0.value)" },
            history: history
        )
    }

    /// Status history, rendered. Location is only included for callers allowed
    /// to see it — a field worker sees the pings they themselves produced.
    private func timeline(_ jobID: String, _ session: TenantSession) -> [JobTimelineEntry] {
        guard session.can(.jobStatusHistoryReadAll) || session.can(.jobStatusUpdateOwn) else { return [] }
        return store.jobStatusHistory
            .filter { $0.jobID == jobID && $0.companyID == session.companyID }
            .sorted { $0.changedAt < $1.changedAt }
            .map { entry in
                let author = user(entry.changedByUserID, session)?.name ?? "System"
                var locationLabel: String?
                if let lat = entry.latitude, let lon = entry.longitude {
                    let maySee = session.can(.fieldWorkerLocationReadAll)
                        || (session.can(.fieldWorkerLocationReadOwnOnly) && entry.changedByUserID == session.userID)
                    if maySee {
                        locationLabel = "Location captured · \(Formatters.coordinateLabel(latitude: lat, longitude: lon))"
                    }
                }
                let terms = session.terms
                let title = entry.fromStatus.map { "\($0.title(terms)) → \(entry.toStatus.title(terms))" } ?? entry.toStatus.title(terms)
                return JobTimelineEntry(
                    id: entry.id,
                    title: title,
                    byLabel: author,
                    timeLabel: Formatters.shortDayAndTime(entry.changedAt),
                    locationLabel: locationLabel,
                    tone: entry.toStatus.tone,
                    symbolName: entry.toStatus.symbolName
                )
            }
    }

    private func notes(_ jobID: String, _ session: TenantSession) -> [JobNoteProjection] {
        guard session.can(.jobNotesRead) else { return [] }
        return store.jobNotes
            .filter { $0.jobID == jobID && $0.companyID == session.companyID }
            .sorted { $0.createdAt > $1.createdAt }
            .map { note in
                let author = user(note.userID, session)
                return JobNoteProjection(
                    id: note.id,
                    body: note.body,
                    authorName: author?.name ?? "Team member",
                    authorInitials: author?.initials ?? "··",
                    timeLabel: Formatters.shortDayAndTime(note.createdAt),
                    visibilityTitle: note.visibility.title,
                    isInternal: note.visibility == .internalOnly
                )
            }
    }

    private func photos(_ jobID: String, _ session: TenantSession) -> [JobPhotoProjection] {
        guard session.can(.jobPhotosRead) else { return [] }
        return store.jobPhotos
            .filter { $0.jobID == jobID && $0.companyID == session.companyID }
            .sorted { $0.capturedAt > $1.capturedAt }
            .map { photo in
                JobPhotoProjection(
                    id: photo.id,
                    kindTitle: photo.kind.title,
                    caption: photo.caption,
                    timeLabel: Formatters.shortDayAndTime(photo.capturedAt),
                    authorName: user(photo.userID, session)?.name ?? "Team member",
                    storageReference: photo.storageReference
                )
            }
    }

    private func isAllowed(_ transition: JobTransition, _ session: TenantSession, assignedToCaller: Bool) -> Bool {
        switch transition.requirement {
        case .fieldWork:
            return session.can(.jobsManage) || (session.can(.jobStatusUpdateOwn) && assignedToCaller)
        case .office(let permission):
            return session.can(permission)
        }
    }

    /// Transitions this caller may actually perform on this job. Assignment
    /// changes are excluded — they run through `assignFieldWorker`.
    private func transitionOptions(_ job: Job, _ session: TenantSession) -> [JobTransitionOption] {
        let assigned = assignedJobIDs(session).contains(job.id)
        return JobWorkflow.transitions(from: job.status)
            .filter { $0.requirement != .office(.assignmentsManage) }
            .filter { isAllowed($0, session, assignedToCaller: assigned) }
            .map {
                JobTransitionOption(
                    id: $0.id,
                    title: $0.actionTitle(session.terms),
                    toStatus: $0.to,
                    isDestructive: $0.isDestructive,
                    capturesLocation: $0.capturesLocation
                )
            }
    }

    private func lastKnownLocation(_ session: TenantSession) -> FieldWorkerLocation? {
        store.workerLocations
            .filter { $0.userID == session.userID && $0.companyID == session.companyID }
            .max { $0.recordedAt < $1.recordedAt }
    }

    /// Applies a validated transition and writes the history row. Callers must
    /// have already passed the row and permission gates.
    ///
    /// When the transition is one the workflow marks as location-capturing and a
    /// fresh fix was supplied, the fix is stored as a `FieldWorkerLocation` row
    /// and stamped onto the history entry. Transitions the workflow does *not*
    /// mark capture nothing, even if a fix is offered — the workflow table is
    /// the authority on when a position is taken.
    private func applyStatus(
        jobIndex: Int,
        transition: JobTransition?,
        to status: JobStatus,
        session: TenantSession,
        locationFix: LocationFix? = nil
    ) {
        let previous = store.jobs[jobIndex].status
        let jobID = store.jobs[jobIndex].id
        store.jobs[jobIndex].status = status

        if status == .inProgress, store.jobs[jobIndex].actualStart == nil {
            store.jobs[jobIndex].actualStart = Date()
        }
        if status == .completed {
            store.jobs[jobIndex].actualEnd = Date()
        }

        let capturesLocation = transition?.capturesLocation ?? false
        var ping: FieldWorkerLocation?

        if capturesLocation,
           let event = LocationCaptureEvent.forTransition(to: status),
           let fix = locationFix {
            let recorded = FieldWorkerLocation(
                id: "loc_\(UUID().uuidString.prefix(8))",
                companyID: session.companyID,
                userID: session.userID,
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                accuracyMeters: fix.accuracyMeters,
                heading: fix.heading,
                speedMetersPerSecond: fix.speedMetersPerSecond,
                jobID: jobID,
                recordedAt: fix.capturedAt,
                captureEvent: event,
                isSimulated: fix.simulated
            )
            store.workerLocations.append(recorded)
            trimLocationHistory(session)
            ping = recorded
            record(
                "location.capture",
                session,
                allowed: true,
                "\(event.title) fix stored against \(store.jobs[jobIndex].number)\(fix.simulated ? " (SIMULATED)" : "")"
            )
        } else if capturesLocation {
            // No fresh fix available: fall back to the worker's last known
            // position for the history stamp rather than inventing one.
            ping = lastKnownLocation(session)
        }

        store.jobStatusHistory.append(
            JobStatusHistory(
                id: UUID().uuidString,
                companyID: session.companyID,
                jobID: store.jobs[jobIndex].id,
                fromStatus: previous,
                toStatus: status,
                changedByUserID: session.userID,
                changedAt: Date(),
                latitude: ping?.latitude,
                longitude: ping?.longitude
            )
        )

        raisePushForStatusChange(jobIndex: jobIndex, from: previous, to: status, session: session)
    }

    /// Notifications that follow from a status transition.
    ///
    /// Called from inside `applyStatus`, so every route that moves a job — the
    /// job screen, the field shell, dispatch, an assignment that advances the
    /// status — raises the event. There is no path that changes a status
    /// without coming through here.
    private func raisePushForStatusChange(
        jobIndex: Int,
        from previous: JobStatus,
        to status: JobStatus,
        session: TenantSession
    ) {
        guard previous != status else { return }
        let job = store.jobs[jobIndex]
        let label = pushJobLabel(job)

        // Cancellation is the single most important thing an engineer can be
        // told: it is the one that stops a wasted journey.
        if status == .cancelled {
            enqueuePush(
                session: session,
                to: store.assignments.first(where: { $0.jobID == job.id })?.userID,
                event: .jobCancelled,
                title: PushEvent.jobCancelled.title,
                body: "\(label) has been cancelled. Do not travel.",
                jobID: job.id,
                customerID: job.customerID
            )
            return
        }

        // Field progress travels the other way: the office hears that an
        // engineer has moved a job on. Recipients are chosen by permission, so
        // Accounts — who hold no operational permission — are not told.
        let fieldStatuses: Set<JobStatus> = [.travelling, .arrived, .inProgress, .completed]
        guard fieldStatuses.contains(status), session.role == .fieldWorker else { return }

        for recipient in officeRecipients(session, .assignmentsManage) {
            enqueuePush(
                session: session,
                to: recipient,
                event: .jobFieldUpdate,
                title: "\(session.displayName) updated a job",
                body: "\(label) — \(status.title).",
                jobID: job.id,
                customerID: job.customerID
            )
        }
    }

    /// Issues the next document number for the caller's company.
    ///
    /// The prefix and the counter both come from that company's
    /// `DocumentSequence` row — nothing here knows what "Q-" or "J-" is. The
    /// sequence is looked up by `session.companyID`, so another tenant's
    /// numbering can neither advance nor collide with this one, and the result
    /// is checked against this company's existing numbers so a number is never
    /// reused within the tenant.
    private func nextDocumentNumber(_ kind: DocumentKind, _ session: TenantSession, existing: [String]) -> String {
        let index = store.documentSequences.firstIndex {
            $0.companyID == session.companyID && $0.kind == kind
        }
        var sequence = index.map { store.documentSequences[$0] }
            ?? .makeDefault(companyID: session.companyID, kind: kind)

        let taken = Set(existing)
        var candidate = sequence.format(sequence.nextValue)
        while taken.contains(candidate) {
            sequence.nextValue += 1
            candidate = sequence.format(sequence.nextValue)
        }
        sequence.nextValue += 1

        if let index {
            store.documentSequences[index] = sequence
        } else {
            store.documentSequences.append(sequence)
        }
        return candidate
    }

    // MARK: - Overview surfaces

    func dashboard(session: TenantSession) async throws -> DashboardSnapshot {
        try await Task.sleep(for: latency)
        let jobs = try visibleJobs(session, query: "dashboard.jobs")

        let calendar = Calendar.current
        let todayJobs = jobs
            .filter { job in
                guard let start = job.scheduledStart else { return false }
                return calendar.isDateInToday(start)
            }
            .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }

        let openToday = todayJobs.filter { $0.status.isOpen }
        let headline = openToday.count == 1 ? "1 job today" : "\(openToday.count) jobs today"

        var subline = "Nothing else booked today"
        if let next = openToday.first {
            let name = customer(next.customerID, session)?.name ?? "Customer"
            let short = address(next.addressID, session)?.shortLine ?? ""
            let time = next.scheduledStart.map { Formatters.time($0) } ?? ""
            subline = "Next: \(time) · \(name) — \(short)"
        }

        var tiles: [DashboardFinancialTile] = []
        if session.can(.quoteFinancialsRead) {
            let openQuotes = scoped(store.quotes, session, companyID: \.companyID)
                .filter { $0.status == .sent || $0.status == .viewed }
            let value = openQuotes.reduce(Decimal(0)) { $0 + $1.total }
            tiles.append(
                DashboardFinancialTile(
                    id: "quotes",
                    caption: "Quotes out",
                    amount: moneyRounded(value, session),
                    symbolName: "doc.text"
                )
            )
        }
        if session.can(.invoicesRead) {
            let outstanding = scoped(store.invoices, session, companyID: \.companyID)
                .filter { $0.status != .paid && $0.status != .void }
                .reduce(Decimal(0)) { $0 + $1.balance }
            tiles.append(
                DashboardFinancialTile(
                    id: "unpaid",
                    caption: "Unpaid",
                    amount: moneyRounded(outstanding, session),
                    symbolName: "doc.plaintext"
                )
            )
        }

        record("dashboard", session, allowed: true, tiles.isEmpty ? "Financial tiles omitted for role" : "\(tiles.count) financial tiles")

        return DashboardSnapshot(
            headline: headline,
            subline: subline,
            todayJobs: todayJobs.map { jobRow($0, session) },
            financialTiles: tiles
        )
    }

    func calendarDays(session: TenantSession, dayCount: Int) async throws -> [CalendarDay] {
        try await Task.sleep(for: latency)
        guard session.can(.calendarReadAll) || session.can(.calendarReadOwnOnly) else {
            record("calendar", session, allowed: false, "No calendar permission")
            throw DataError.notPermitted(.calendarReadAll)
        }
        let jobs = try visibleJobs(session, query: "calendar.jobs")
        let calendar = Calendar.current

        return (0..<max(dayCount, 1)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { return nil }
            let dayJobs = jobs
                .filter { job in
                    guard let start = job.scheduledStart else { return false }
                    return calendar.isDate(start, inSameDayAs: day)
                }
                .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }
            return CalendarDay(
                id: "\(offset)",
                date: day,
                title: Formatters.dayTitle(day),
                jobs: dayJobs.map { jobRow($0, session) }
            )
        }
    }

    func customers(session: TenantSession, query: String) async throws -> [CustomerRow] {
        try await Task.sleep(for: latency)

        if session.can(.customersReadAssignedSiteOnly), !session.can(.customersReadAll) {
            // Field workers have no customer directory at all.
            record("customers.list", session, allowed: false, "Directory not available — assigned sites only")
            throw DataError.notPermitted(.customersReadAll)
        }
        try require(.customersReadAll, session, query: "customers.list")

        let tenantRows = scoped(store.customers, session, companyID: \.companyID)
        let jobs = scoped(store.jobs, session, companyID: \.companyID)
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        let rows = tenantRows
            .filter { trimmed.isEmpty || $0.name.localizedStandardContains(trimmed) }
            .sorted { $0.name < $1.name }
            .map { cust -> CustomerRow in
                let addr = store.addresses.first { $0.customerID == cust.id && $0.companyID == session.companyID }
                let contactCount = store.contacts.filter { $0.customerID == cust.id && $0.companyID == session.companyID }.count
                let openJobs = jobs.filter { $0.customerID == cust.id && $0.status.isOpen }.count

                var balanceLabel: String?
                if session.can(.customerBillingDetailsRead) {
                    let balance = scoped(store.invoices, session, companyID: \.companyID)
                        .filter { $0.customerID == cust.id && $0.status != .paid && $0.status != .void }
                        .reduce(Decimal(0)) { $0 + $1.balance }
                    balanceLabel = balance > 0 ? moneyRounded(balance, session) : nil
                }

                return CustomerRow(
                    id: cust.id,
                    name: cust.name,
                    initials: cust.initials,
                    typeTitle: cust.type.title,
                    addressShort: addr?.shortLine ?? "No address on file",
                    contactCount: contactCount,
                    openJobCount: openJobs,
                    balanceLabel: balanceLabel
                )
            }

        record("customers.list", session, allowed: true, "\(rows.count) rows, billing fields \(session.can(.customerBillingDetailsRead) ? "included" : "stripped")")
        return rows
    }

    func moreOverview(session: TenantSession) async throws -> MoreOverview {
        try await Task.sleep(for: latency)
        let company = store.companies.first { $0.id == session.companyID }

        let workerCount: Int? = session.can(.usersRead)
            ? scoped(store.users, session, companyID: \.companyID).filter { $0.role == .fieldWorker }.count
            : nil
        let quoteCount: Int? = session.can(.quotesRead)
            ? scoped(store.quotes, session, companyID: \.companyID).filter { $0.status == .sent || $0.status == .viewed || $0.status == .draft }.count
            : nil
        let invoiceCount: Int? = session.can(.invoicesRead)
            ? scoped(store.invoices, session, companyID: \.companyID).count
            : nil
        let outstanding: String? = session.can(.invoicesRead)
            ? moneyRounded(
                scoped(store.invoices, session, companyID: \.companyID)
                    .filter { $0.status != .paid && $0.status != .void }
                    .reduce(Decimal(0)) { $0 + $1.balance },
                session
            )
            : nil
        let paymentCount: Int? = session.can(.paymentsRead)
            ? scoped(store.payments, session, companyID: \.companyID).count
            : nil
        let smsBalance: Int? = session.can(.smsLedgerRead)
            ? scoped(store.smsLedger, session, companyID: \.companyID)
                .sorted { $0.createdAt > $1.createdAt }
                .first?.balanceAfter
            : nil

        var subscriptionSummary: String?
        if session.can(.saasBillingRead),
           let sub = store.subscriptions.first(where: { $0.companyID == session.companyID }) {
            subscriptionSummary = "\(sub.plan.title) · \(sub.status.title) · \(sub.seatCount) \(sub.seatCount == 1 ? "user" : "users")"
        }

        return MoreOverview(
            workerCount: workerCount,
            quoteCount: quoteCount,
            invoiceCount: invoiceCount,
            outstandingLabel: outstanding,
            paymentCount: paymentCount,
            smsBalance: smsBalance,
            subscriptionSummary: subscriptionSummary,
            companyName: company?.name ?? "Company",
            tradeTitle: (company?.trade ?? session.trade).title,
            roleTitle: session.roleTitle
        )
    }

    func recentAccessDecisions(session: TenantSession) async throws -> [AccessDecision] {
        decisions.filter { $0.role == session.role }
    }

    // MARK: - Jobs

    func jobs(session: TenantSession, query: JobQuery) async throws -> [JobRow] {
        try await Task.sleep(for: latency)
        let all = try visibleJobs(session, query: "jobs.list")

        let assignmentsByJob = Dictionary(
            scoped(store.assignments, session, companyID: \.companyID)
                .filter(\.isPrimary)
                .map { ($0.jobID, $0.userID) },
            uniquingKeysWith: { first, _ in first }
        )

        let trimmed = query.searchText.trimmingCharacters(in: .whitespaces)

        let filtered = all.filter { job in
            guard query.dateScope.matches(job) else { return false }
            if !query.statuses.isEmpty, !query.statuses.contains(job.status) { return false }
            if let priority = query.priority, job.priority != priority { return false }
            if let customerID = query.customerID, job.customerID != customerID { return false }
            if let workerID = query.fieldWorkerUserID, assignmentsByJob[job.id] != workerID { return false }
            if !trimmed.isEmpty {
                let name = customer(job.customerID, session)?.name ?? ""
                let line = address(job.addressID, session)?.singleLine ?? ""
                let matches = job.number.localizedStandardContains(trimmed)
                    || name.localizedStandardContains(trimmed)
                    || line.localizedStandardContains(trimmed)
                    || job.title.localizedStandardContains(trimmed)
                if !matches { return false }
            }
            return true
        }

        record(
            "jobs.list",
            session,
            allowed: true,
            "\(filtered.count) of \(all.count) after filters · money \(canReadJobMoney(session) ? "included" : "not assembled")"
        )

        return filtered
            .sorted { lhs, rhs in
                switch (lhs.scheduledStart, rhs.scheduledStart) {
                case let (l?, r?): return l < r
                case (nil, _?): return true
                case (_?, nil): return false
                default: return lhs.number > rhs.number
                }
            }
            .map { jobRow($0, session) }
    }

    func jobFormOptions(session: TenantSession) async throws -> JobFormOptions {
        try await Task.sleep(for: latency)
        guard session.can(.jobsReadAll) else {
            record("jobs.formOptions", session, allowed: false, "Reference data withheld — no company-wide job read")
            return .empty
        }

        let workers: [FieldWorkerOption] = session.can(.usersRead)
            ? scoped(store.users, session, companyID: \.companyID)
                .filter { $0.role == .fieldWorker && $0.status == .active }
                .sorted { $0.name < $1.name }
                .map { FieldWorkerOption(id: $0.id, name: $0.name, initials: $0.initials) }
            : []

        let customers: [CustomerOption] = scoped(store.customers, session, companyID: \.companyID)
            .sorted { $0.name < $1.name }
            .compactMap { cust in
                guard let addr = store.addresses.first(where: { $0.customerID == cust.id && $0.companyID == session.companyID }) else { return nil }
                let units = store.equipment
                    .filter { $0.addressID == addr.id && $0.companyID == session.companyID }
                    .map { EquipmentOption(id: $0.id, name: $0.displayName) }
                return CustomerOption(
                    id: cust.id,
                    name: cust.name,
                    addressID: addr.id,
                    addressLine: addr.singleLine,
                    equipment: units
                )
            }

        record("jobs.formOptions", session, allowed: true, "\(workers.count) \(session.terms.workerPlural), \(customers.count) customers")
        return JobFormOptions(workers: workers, customers: customers, canAssign: session.can(.assignmentsManage))
    }

    func jobDetail(session: TenantSession, jobID: String) async throws -> JobDetailProjection {
        try await Task.sleep(for: latency)
        let job = try requireVisibleJob(jobID, session, query: "jobs.detail")

        let cust = customer(job.customerID, session)
        let addr = address(job.addressID, session)
        let contact = primaryContact(job.customerID, session)

        var workerProjection: AssignedWorkerProjection?
        if let assignment = primaryAssignment(job.id, session), let worker = user(assignment.userID, session) {
            var eta: String?
            if job.status == .travelling, session.can(.fieldWorkerLocationReadAll) {
                let arrival = Date().addingTimeInterval(4 * 60)
                eta = "Arriving \(Formatters.time(arrival)) · 4 min away"
            }
            // Field workers never receive colleagues' contact details.
            let phone = session.can(.usersRead) ? worker.phone : nil
            workerProjection = AssignedWorkerProjection(
                userID: worker.id,
                name: worker.name,
                initials: worker.initials,
                etaLabel: eta,
                phone: phone
            )
        }

        // Operational reference to the quote — no money in this string.
        var quoteReference: String?
        if session.can(.quotesRead), let quoteID = job.quoteID,
           let quote = store.quotes.first(where: { $0.id == quoteID && $0.companyID == session.companyID }) {
            quoteReference = "\(quote.number) · \(quote.status.title)"
        }

        var financials: JobFinancialProjection?
        if canReadJobMoney(session) {
            var quoteSummary: String?
            if session.can(.quoteFinancialsRead),
               let quoteID = job.quoteID,
               let quote = store.quotes.first(where: { $0.id == quoteID && $0.companyID == session.companyID }) {
                quoteSummary = "\(quote.number) · \(quote.status.title) · \(money(quote.total, session))"
            }
            var invoiceSummary: String?
            if session.can(.invoicesRead) {
                if let invoice = store.invoices.first(where: { $0.jobID == job.id && $0.companyID == session.companyID }) {
                    let shown = invoice.effectiveStatus()
                    invoiceSummary = "\(invoice.number) · \(shown.title) · \(invoiceMoney(invoice.total, invoice))"
                    if invoice.balance > 0, invoice.amountPaid > 0 {
                        invoiceSummary? += " · \(invoiceMoney(invoice.balance, invoice)) outstanding"
                    }
                } else {
                    invoiceSummary = "Not invoiced yet"
                }
            }
            if quoteSummary != nil || invoiceSummary != nil {
                financials = JobFinancialProjection(quoteSummary: quoteSummary, invoiceSummary: invoiceSummary)
            }
        } else {
            record("jobs.detail.financials", session, allowed: false, "Money fields not assembled for role")
        }

        let scheduleLabel: String
        var durationLabel: String?
        if let start = job.scheduledStart, let end = job.scheduledEnd {
            scheduleLabel = "\(Formatters.dayTitle(start)) · \(Formatters.timeRange(start, end))"
            durationLabel = Formatters.durationLabel(from: start, to: end)
        } else if let start = job.scheduledStart {
            scheduleLabel = Formatters.dayAndTime(start)
        } else {
            scheduleLabel = "Not scheduled yet"
        }

        var agreementLabel: String?
        if let agreementID = job.serviceAgreementID,
           let agreement = store.serviceAgreements.first(where: { $0.id == agreementID && $0.companyID == session.companyID }) {
            agreementLabel = "\(agreement.frequency.title) agreement · next due \(Formatters.shortDate(agreement.nextDueDate))"
        }

        return JobDetailProjection(
            id: job.id,
            number: job.number,
            title: job.title,
            jobDescription: job.jobDescription,
            status: job.status,
            badge: badge(for: job.status, session),
            kindTitle: job.kind.title,
            kindSymbol: job.kind.symbolName,
            priorityTitle: job.priority.title,
            isUrgent: job.priority == .urgent,
            customerID: job.customerID,
            customerName: cust?.name ?? "Customer",
            customerTypeTitle: cust?.type.title ?? "",
            contactName: contact?.name,
            contactRole: contact?.contactRole,
            contactPhone: contact?.phone,
            addressLine: addr?.singleLine ?? "",
            accessNotes: addr?.accessNotes,
            latitude: addr?.latitude ?? 27.9506,
            longitude: addr?.longitude ?? -82.4572,
            scheduleLabel: scheduleLabel,
            durationLabel: durationLabel,
            createdLabel: "Raised \(Formatters.shortDate(job.createdAt))",
            assignedWorker: workerProjection,
            equipment: equipmentProjection(job.equipmentID, session),
            serviceAgreementLabel: agreementLabel,
            quoteReference: quoteReference,
            quoteID: session.can(.quotesRead) ? job.quoteID : nil,
            financials: financials,
            timeline: timeline(job.id, session),
            notes: notes(job.id, session),
            photos: photos(job.id, session),
            transitions: transitionOptions(job, session),
            canManage: session.can(.jobsManage),
            canAssign: session.can(.assignmentsManage) && job.status.isOpen,
            canAddNotes: session.can(.jobNotesCreate),
            canAddPhotos: session.can(.jobPhotosCreate)
        )
    }

    func createJob(session: TenantSession, input: NewJobInput) async throws -> String {
        try await Task.sleep(for: latency)
        try require(.jobsManage, session, query: "jobs.create")

        guard let addr = address(input.addressID, session),
              addr.customerID == input.customerID,
              customer(input.customerID, session) != nil else {
            record("jobs.create", session, allowed: false, "Customer or address outside company scope")
            throw DataError.notFound
        }

        let trimmedTitle = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw DataError.rejected("Give the job a short title.") }

        let number = nextDocumentNumber(
            .job,
            session,
            existing: scoped(store.jobs, session, companyID: \.companyID).map(\.number)
        )
        let jobID = "job_\(UUID().uuidString.prefix(8))"

        var status: JobStatus = .scheduled
        let workerID = input.fieldWorkerUserID
        if let workerID, session.can(.assignmentsManage),
           let worker = user(workerID, session), worker.role == .fieldWorker {
            status = .workerAssigned
        }

        let job = Job(
            id: jobID,
            companyID: session.companyID,
            customerID: input.customerID,
            addressID: input.addressID,
            equipmentID: input.equipmentID,
            quoteID: input.quoteID,
            number: number,
            title: trimmedTitle,
            jobDescription: input.jobDescription,
            kind: input.kind,
            priority: input.priority,
            status: status,
            scheduledStart: input.scheduledStart,
            scheduledEnd: input.scheduledEnd,
            actualStart: nil,
            actualEnd: nil,
            serviceAgreementID: nil,
            createdAt: Date()
        )
        store.jobs.append(job)

        store.jobStatusHistory.append(
            JobStatusHistory(
                id: UUID().uuidString,
                companyID: session.companyID,
                jobID: jobID,
                fromStatus: nil,
                toStatus: .scheduled,
                changedByUserID: session.userID,
                changedAt: Date(),
                latitude: nil,
                longitude: nil
            )
        )

        if status == .workerAssigned, let workerID {
            store.assignments.append(
                FieldWorkerAssignment(
                    id: UUID().uuidString,
                    companyID: session.companyID,
                    jobID: jobID,
                    userID: workerID,
                    assignedByUserID: session.userID,
                    assignedAt: Date(),
                    isPrimary: true,
                    acceptedAt: nil,
                    sortOrder: 0
                )
            )
            store.jobStatusHistory.append(
                JobStatusHistory(
                    id: UUID().uuidString,
                    companyID: session.companyID,
                    jobID: jobID,
                    fromStatus: .scheduled,
                    toStatus: .workerAssigned,
                    changedByUserID: session.userID,
                    changedAt: Date(),
                    latitude: nil,
                    longitude: nil
                )
            )
        }

        record("jobs.create", session, allowed: true, "\(number) created in \(session.companyID)")
        return jobID
    }

    func updateJobStatus(
        session: TenantSession,
        jobID: String,
        to status: JobStatus,
        locationFix: LocationFix?
    ) async throws {
        try await Task.sleep(for: latency)
        let job = try requireVisibleJob(jobID, session, query: "jobs.updateStatus")

        guard let transition = JobWorkflow.transition(from: job.status, to: status) else {
            record("jobs.updateStatus", session, allowed: false, "Rejected — \(job.status.title) → \(status.title) is not in the workflow")
            throw DataError.invalidTransition(from: job.status, to: status)
        }

        let assigned = assignedJobIDs(session).contains(jobID)
        guard isAllowed(transition, session, assignedToCaller: assigned) else {
            record("jobs.updateStatus", session, allowed: false, "Write blocked — \(transition.requirement.permissionForDisplay.rawValue) not held for this row")
            throw DataError.notPermitted(transition.requirement.permissionForDisplay)
        }

        guard let index = store.jobs.firstIndex(where: { $0.id == jobID }) else { throw DataError.notFound }
        applyStatus(jobIndex: index, transition: transition, to: status, session: session, locationFix: locationFix)

        record(
            "jobs.updateStatus",
            session,
            allowed: true,
            "\(job.status.title) → \(status.title), history row written\(transition.capturesLocation ? " with location" : "")"
        )
    }

    func assignFieldWorker(
        session: TenantSession,
        jobID: String,
        workerUserID: String?,
        acknowledgesConflict: Bool
    ) async throws {
        try await Task.sleep(for: latency)
        _ = try applyAssignment(
            session: session,
            jobID: jobID,
            workerUserID: workerUserID,
            acknowledgesConflict: acknowledgesConflict,
            query: "jobs.assign"
        )
    }

    /// The one place an assignment is checked and written.
    ///
    /// Both entry points — a job's own screen and the dispatch board — come
    /// through here, so the overlap rule cannot drift between them. The `query`
    /// only names the caller in the audit trail; the rule itself is identical.
    private func applyAssignment(
        session: TenantSession,
        jobID: String,
        workerUserID: String?,
        acknowledgesConflict: Bool,
        query: String
    ) throws -> SchedulingCheck {
        try require(.assignmentsManage, session, query: query)
        let job = try requireVisibleJob(jobID, session, query: query)
        guard let index = store.jobs.firstIndex(where: { $0.id == jobID }) else { throw DataError.notFound }

        // Who is on the job right now, read before anything is removed, so the
        // outgoing engineer can be told they are off it.
        let previousWorkerID = store.assignments
            .first { $0.jobID == jobID && $0.companyID == session.companyID }?.userID

        guard let workerUserID else {
            // Clearing an assignment can never create an overlap.
            store.assignments.removeAll { $0.jobID == jobID && $0.companyID == session.companyID }
            if job.status == .workerAssigned {
                applyStatus(jobIndex: index, transition: JobWorkflow.transition(from: .workerAssigned, to: .scheduled), to: .scheduled, session: session)
            }
            enqueuePush(
                session: session,
                to: previousWorkerID,
                event: .jobUnassigned,
                title: PushEvent.jobUnassigned.title,
                body: "\(pushJobLabel(job)) is no longer assigned to you.",
                jobID: jobID,
                customerID: job.customerID
            )
            record(query, session, allowed: true, "Assignment cleared on \(job.number)")
            return .clear
        }

        guard let worker = user(workerUserID, session), worker.role == .fieldWorker else {
            record(query, session, allowed: false, "\(session.terms.Worker) outside company scope")
            throw DataError.notFound
        }

        let check = SchedulingCheck(conflicts: conflictRows(job: job, workerUserID: workerUserID, session))

        // The whole rule: an overlap is allowed, but only deliberately. The
        // first attempt is refused and returns the clash so it can be shown; a
        // second attempt carrying the acknowledgement goes through. Refusing
        // before any mutation is what makes cancelling a no-op.
        if check.hasConflicts, !acknowledgesConflict {
            record(query, session, allowed: false, "Refused pending acknowledgement — \(check.summary)")
            throw DataError.rejected(check.summary)
        }

        // Reassignment drops the previous worker's claim on the job.
        store.assignments.removeAll { $0.jobID == jobID && $0.companyID == session.companyID }

        store.assignments.append(
            FieldWorkerAssignment(
                id: UUID().uuidString,
                companyID: session.companyID,
                jobID: jobID,
                userID: workerUserID,
                assignedByUserID: session.userID,
                assignedAt: Date(),
                isPrimary: true,
                acceptedAt: nil,
                sortOrder: 0
            )
        )

        if job.status == .scheduled {
            applyStatus(jobIndex: index, transition: JobWorkflow.transition(from: .scheduled, to: .workerAssigned), to: .workerAssigned, session: session)
        }

        // A reassignment is two events, both true: the outgoing engineer is
        // told they are off the job, the incoming one is told it is theirs.
        // Neither is inferred — the previous assignment was read above.
        if let previousWorkerID, previousWorkerID != workerUserID {
            enqueuePush(
                session: session,
                to: previousWorkerID,
                event: .jobUnassigned,
                title: PushEvent.jobUnassigned.title,
                body: "\(pushJobLabel(job)) is no longer assigned to you.",
                jobID: jobID,
                customerID: job.customerID
            )
        }

        if previousWorkerID != workerUserID {
            let isReassignment = previousWorkerID != nil
            let event: PushEvent = isReassignment ? .jobReassigned : .jobAssigned
            enqueuePush(
                session: session,
                to: workerUserID,
                event: event,
                title: event.title,
                body: "\(pushJobLabel(job)) — \(pushWhenLabel(job.scheduledStart))",
                jobID: jobID,
                customerID: job.customerID
            )
        }

        record(
            query,
            session,
            allowed: true,
            check.hasConflicts
                ? "\(job.number) assigned to \(worker.name) with an acknowledged overlap — \(check.summary)"
                : "\(job.number) assigned to \(worker.name)"
        )
        return check
    }

    func addJobNote(session: TenantSession, jobID: String, body: String, visibility: NoteVisibility) async throws {
        try await Task.sleep(for: latency)
        try require(.jobNotesCreate, session, query: "jobs.addNote")
        let job = try requireVisibleJob(jobID, session, query: "jobs.addNote")

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DataError.rejected("Write something before saving the note.") }

        store.jobNotes.append(
            JobNote(
                id: UUID().uuidString,
                companyID: session.companyID,
                jobID: jobID,
                userID: session.userID,
                body: trimmed,
                visibility: visibility,
                createdAt: Date()
            )
        )

        // Job and customer information the assigned engineer should act on.
        enqueuePush(
            session: session,
            to: store.assignments.first(where: { $0.jobID == jobID })?.userID,
            event: .jobNote,
            title: PushEvent.jobNote.title,
            body: "\(job.number) — \(session.displayName): \(trimmed.prefix(120))",
            jobID: jobID,
            customerID: job.customerID
        )

        record("jobs.addNote", session, allowed: true, "Note added to \(job.number)")
    }

    func addJobPhoto(session: TenantSession, jobID: String, kind: JobPhotoKind, caption: String?) async throws {
        try await Task.sleep(for: latency)
        try require(.jobPhotosCreate, session, query: "jobs.addPhoto")
        let job = try requireVisibleJob(jobID, session, query: "jobs.addPhoto")

        // DEVELOPMENT: no camera or upload is involved. The record is real, the
        // file reference is explicitly simulated.
        let reference = "sim://jobs/\(job.number)/\(kind.rawValue)-\(Int(Date().timeIntervalSince1970)).jpg"
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        store.jobPhotos.append(
            JobPhoto(
                id: UUID().uuidString,
                companyID: session.companyID,
                jobID: jobID,
                userID: session.userID,
                storageReference: reference,
                caption: (trimmedCaption?.isEmpty ?? true) ? nil : trimmedCaption,
                kind: kind,
                capturedAt: Date()
            )
        )
        record("jobs.addPhoto", session, allowed: true, "Simulated \(kind.title.lowercased()) photo attached to \(job.number)")
    }

    // MARK: - Field worker shell

    func fieldWorkerDay(session: TenantSession) async throws -> FieldWorkerDaySnapshot {
        try await Task.sleep(for: latency)
        let jobs = try visibleJobs(session, query: "fieldWorker.day")
        let calendar = Calendar.current

        let todays = jobs
            .filter { job in
                guard let start = job.scheduledStart else { return false }
                return calendar.isDateInToday(start)
            }
            .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }

        let stops = todays.map { job -> FieldWorkerStop in
            let addr = address(job.addressID, session)
            let cust = customer(job.customerID, session)
            let contact = primaryContact(job.customerID, session)
            var equipmentLine: String?
            if let projection = equipmentProjection(job.equipmentID, session) {
                equipmentLine = "\(projection.displayName) · \(projection.subtitle)"
            }
            let advance = JobWorkflow.fieldAdvance(from: job.status)
            return FieldWorkerStop(
                jobID: job.id,
                number: job.number,
                timeLabel: job.scheduledStart.map { Formatters.time($0) } ?? "",
                customerName: cust?.name ?? "Customer",
                addressLine: addr?.singleLine ?? "",
                jobTitle: job.title,
                kindTitle: job.kind.title,
                equipmentLine: equipmentLine,
                status: job.status,
                statusTitle: job.status.title(session.terms),
                isUrgent: job.priority == .urgent,
                completedLabel: job.actualEnd.map { "Completed \(Formatters.time($0))" },
                latitude: addr?.latitude ?? 27.9506,
                longitude: addr?.longitude ?? -82.4572,
                accessNotes: addr?.accessNotes,
                siteContactName: contact?.name,
                siteContactPhone: contact?.phone,
                nextActionTitle: advance?.actionTitle(session.terms),
                nextStatus: advance?.to
            )
        }

        let hour = calendar.component(.hour, from: Date())
        let partOfDay = hour < 12 ? "Morning" : (hour < 18 ? "Afternoon" : "Evening")
        let firstName = session.displayName.split(separator: " ").first.map(String.init) ?? session.displayName

        let currentIndex = stops.firstIndex(where: { $0.status.isOpen }).map { $0 + 1 }
        var progress = "All stops complete — nice work"
        if let currentIndex, !stops.isEmpty {
            let lastEnd = todays.compactMap(\.scheduledEnd).max() ?? Date()
            let minutesLeft = max(Int(lastEnd.timeIntervalSince(Date()) / 60), 0)
            progress = "Stop \(currentIndex) of \(stops.count) · \(Formatters.relativeDuration(minutes: minutesLeft)) left"
        } else if stops.isEmpty {
            progress = "No stops scheduled today"
        }

        return FieldWorkerDaySnapshot(
            greeting: "\(partOfDay), \(firstName)",
            progressLine: progress,
            stops: stops
        )
    }

    func fieldWorkerJobDetail(session: TenantSession, jobID: String) async throws -> FieldWorkerJobDetail {
        try await Task.sleep(for: latency)
        let job = try requireVisibleJob(jobID, session, query: "fieldWorker.jobDetail")

        let addr = address(job.addressID, session)
        let cust = customer(job.customerID, session)
        let contact = primaryContact(job.customerID, session)

        let scheduleLabel: String
        if let start = job.scheduledStart, let end = job.scheduledEnd {
            scheduleLabel = "\(Formatters.dayTitle(start)) · \(Formatters.timeRange(start, end))"
        } else if let start = job.scheduledStart {
            scheduleLabel = Formatters.dayAndTime(start)
        } else {
            scheduleLabel = "No slot booked"
        }

        record("fieldWorker.jobDetail", session, allowed: true, "Assigned row served with no monetary fields in the payload type")

        return FieldWorkerJobDetail(
            jobID: job.id,
            number: job.number,
            title: job.title,
            jobDescription: job.jobDescription,
            kindTitle: job.kind.title,
            isUrgent: job.priority == .urgent,
            status: job.status,
            badge: badge(for: job.status, session),
            scheduleLabel: scheduleLabel,
            customerName: cust?.name ?? "Customer",
            addressLine: addr?.singleLine ?? "",
            latitude: addr?.latitude ?? 27.9506,
            longitude: addr?.longitude ?? -82.4572,
            accessNotes: addr?.accessNotes,
            siteContactName: contact?.name,
            siteContactPhone: contact?.phone,
            equipment: equipmentProjection(job.equipmentID, session),
            timeline: timeline(job.id, session),
            notes: notes(job.id, session),
            photos: photos(job.id, session),
            transitions: transitionOptions(job, session)
        )
    }

    // MARK: - Quotes

    private func quoteBadge(_ quote: Quote) -> StatusBadge {
        StatusBadge(text: quote.status.title, tone: quote.status.tone)
    }

    func quotes(session: TenantSession, filter: QuoteListFilter, query: String) async throws -> [QuoteRow] {
        try await Task.sleep(for: latency)
        let rows = try visibleQuotes(session, query: "quotes.list")
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let mayReadMoney = session.can(.quoteFinancialsRead)

        return rows
            .filter { filter.matches($0) }
            .filter { quote in
                guard !trimmed.isEmpty else { return true }
                let name = customer(quote.customerID, session)?.name ?? ""
                return quote.number.localizedStandardContains(trimmed)
                    || quote.title.localizedStandardContains(trimmed)
                    || name.localizedStandardContains(trimmed)
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map { quote in
                let items = lineItems(quote.id, session)
                let convertedNumber = quote.convertedJobID
                    .flatMap { id in store.jobs.first { $0.id == id && $0.companyID == session.companyID } }?
                    .number
                return QuoteRow(
                    id: quote.id,
                    number: quote.number,
                    title: quote.title,
                    customerName: customer(quote.customerID, session)?.name ?? "Customer",
                    addressShort: address(quote.addressID, session)?.shortLine ?? "",
                    badge: quoteBadge(quote),
                    status: quote.status,
                    dateLabel: Formatters.shortDate(quote.createdAt),
                    validityLabel: quote.validUntil.map { Formatters.validityLabel($0) },
                    itemCountLabel: items.count == 1 ? "1 line item" : "\(items.count) line items",
                    totalLabel: mayReadMoney ? money(quote.total, session) : nil,
                    convertedJobNumber: convertedNumber
                )
            }
    }

    func quoteDetail(session: TenantSession, quoteID: String) async throws -> QuoteDetailProjection {
        try await Task.sleep(for: latency)
        let quote = try requireVisibleQuote(quoteID, session, query: "quotes.detail")
        let mayReadMoney = session.can(.quoteFinancialsRead)
        let items = lineItems(quote.id, session)

        if !mayReadMoney {
            record("quotes.detail.financials", session, allowed: false, "Line pricing and totals not assembled for role")
        }

        let lineProjections = items.map { item -> QuoteLineItemProjection in
            var pricing: QuoteLinePricing?
            if mayReadMoney {
                pricing = QuoteLinePricing(
                    unitPrice: item.unitPrice,
                    taxRate: item.taxRate,
                    lineTotal: item.lineTotal,
                    unitPriceLabel: money(item.unitPrice, session),
                    taxRateLabel: Money.percentLabel(item.taxRate),
                    lineTotalLabel: money(item.lineTotal, session)
                )
            }
            return QuoteLineItemProjection(
                id: item.id,
                itemDescription: item.itemDescription,
                quantity: item.quantity,
                quantityLabel: Money.quantityLabel(item.quantity),
                sortOrder: item.sortOrder,
                pricing: pricing
            )
        }

        var totals: QuoteTotalsProjection?
        if mayReadMoney {
            let computed = Money.totals(for: items)
            totals = QuoteTotalsProjection(
                subtotal: computed.subtotal,
                tax: computed.tax,
                total: computed.total,
                subtotalLabel: money(computed.subtotal, session),
                taxLabel: money(computed.tax, session),
                totalLabel: money(computed.total, session)
            )
        }

        let canManage = session.can(.quotesManage)
        let statusActions: [QuoteStatusAction] = canManage
            ? QuoteWorkflow.nextStatuses(from: quote.status).map {
                QuoteStatusAction(
                    id: $0.rawValue,
                    title: QuoteWorkflow.actionTitle(for: $0),
                    status: $0,
                    isDestructive: $0 == .declined || $0 == .expired
                )
            }
            : []

        let convertedJob = quote.convertedJobID.flatMap { id in
            store.jobs.first { $0.id == id && $0.companyID == session.companyID }
        }

        // Operational reference to any invoice already raised from this quote.
        // Gated on `invoicesRead` and deliberately money-free, so a dispatcher
        // still never learns a figure from it.
        let raisedInvoice = session.can(.invoicesRead)
            ? scoped(store.invoices, session, companyID: \.companyID).first(where: { $0.quoteID == quote.id && $0.status != .void })
            : nil

        let contact = primaryContact(quote.customerID, session)

        return QuoteDetailProjection(
            id: quote.id,
            number: quote.number,
            title: quote.title,
            scopeOfWork: quote.scopeOfWork,
            status: quote.status,
            badge: quoteBadge(quote),
            customerID: quote.customerID,
            customerName: customer(quote.customerID, session)?.name ?? "Customer",
            contactLabel: contact.map { "\($0.name) · \($0.phone)" },
            addressLine: address(quote.addressID, session)?.singleLine ?? "",
            createdLabel: Formatters.shortDate(quote.createdAt),
            sentLabel: quote.sentAt.map { Formatters.shortDate($0) },
            viewedLabel: quote.viewedAt.map { Formatters.shortDate($0) },
            acceptedLabel: quote.acceptedAt.map { Formatters.shortDate($0) },
            declinedLabel: quote.declinedAt.map { Formatters.shortDate($0) },
            validUntilLabel: quote.validUntil.map { Formatters.validityLabel($0) },
            isExpiringSoon: quote.validUntil.map { Formatters.daysUntil($0) <= 5 } ?? false,
            lineItems: lineProjections,
            totals: totals,
            currencyCode: currencyCode(session),
            defaultTaxRate: mayReadMoney ? defaultTaxRate(session) : nil,
            statusActions: statusActions,
            canManage: canManage,
            canEditLineItems: canManage && mayReadMoney && quote.status.isEditable,
            canConvert: quote.status == .accepted
                && quote.convertedJobID == nil
                && canManage
                && session.can(.jobsManage),
            convertedJobID: quote.convertedJobID,
            convertedJobNumber: convertedJob?.number,
            invoicedReference: raisedInvoice.map { "\($0.number) · \($0.effectiveStatus().title)" },
            invoiceID: raisedInvoice?.id,
            canRaiseInvoice: quote.status == .accepted
                && raisedInvoice == nil
                && session.can(.invoicesManage)
        )
    }

    func createQuote(session: TenantSession, input: NewQuoteInput) async throws -> String {
        try await Task.sleep(for: latency)
        try require(.quotesManage, session, query: "quotes.create")

        guard let addr = address(input.addressID, session),
              addr.customerID == input.customerID,
              customer(input.customerID, session) != nil else {
            record("quotes.create", session, allowed: false, "Customer or address outside company scope")
            throw DataError.notFound
        }

        let trimmedTitle = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw DataError.rejected("Give the quote a short title.") }

        let number = nextDocumentNumber(
            .quote,
            session,
            existing: scoped(store.quotes, session, companyID: \.companyID).map(\.number)
        )
        let quoteID = "qte_\(UUID().uuidString.prefix(8))"

        store.quotes.append(
            Quote(
                id: quoteID,
                companyID: session.companyID,
                customerID: input.customerID,
                addressID: input.addressID,
                number: number,
                title: trimmedTitle,
                scopeOfWork: input.scopeOfWork,
                status: .draft,
                subtotal: 0,
                tax: 0,
                total: 0,
                validUntil: input.validUntil,
                createdAt: Date(),
                sentAt: nil,
                viewedAt: nil,
                acceptedAt: nil,
                declinedAt: nil,
                convertedJobID: nil
            )
        )
        record("quotes.create", session, allowed: true, "\(number) created as draft")
        return quoteID
    }

    func updateQuoteStatus(session: TenantSession, quoteID: String, to status: QuoteStatus) async throws {
        try await Task.sleep(for: latency)
        try require(.quotesManage, session, query: "quotes.updateStatus")
        let quote = try requireVisibleQuote(quoteID, session, query: "quotes.updateStatus")

        guard QuoteWorkflow.nextStatuses(from: quote.status).contains(status) else {
            record("quotes.updateStatus", session, allowed: false, "Rejected — \(quote.status.title) → \(status.title) is not allowed")
            throw DataError.rejected("A \(quote.status.title.lowercased()) quote can't move to \(status.title.lowercased()).")
        }

        guard let index = store.quotes.firstIndex(where: { $0.id == quoteID }) else { throw DataError.notFound }
        let now = Date()
        store.quotes[index].status = status
        switch status {
        case .sent: store.quotes[index].sentAt = now
        case .viewed: store.quotes[index].viewedAt = now
        case .accepted: store.quotes[index].acceptedAt = now
        case .declined: store.quotes[index].declinedAt = now
        default: break
        }
        record("quotes.updateStatus", session, allowed: true, "\(quote.number): \(quote.status.title) → \(status.title)")
    }

    /// Recomputes and stores the quote header totals from its line items.
    private func recalculateQuote(_ quoteID: String, _ session: TenantSession) {
        guard let index = store.quotes.firstIndex(where: { $0.id == quoteID && $0.companyID == session.companyID }) else { return }
        let totals = Money.totals(for: lineItems(quoteID, session))
        store.quotes[index].subtotal = totals.subtotal
        store.quotes[index].tax = totals.tax
        store.quotes[index].total = totals.total
    }

    private func requireEditableQuote(_ quoteID: String, _ session: TenantSession, query: String) throws -> Quote {
        try require(.quotesManage, session, query: query)
        try require(.quoteFinancialsRead, session, query: query)
        let quote = try requireVisibleQuote(quoteID, session, query: query)
        guard quote.status.isEditable else {
            record(query, session, allowed: false, "Rejected — \(quote.number) is \(quote.status.title.lowercased()) and no longer editable")
            throw DataError.rejected("\(quote.number) has already been sent, so its line items are locked.")
        }
        return quote
    }

    func saveQuoteLineItem(session: TenantSession, quoteID: String, draft: QuoteLineItemDraft) async throws {
        try await Task.sleep(for: latency)
        let quote = try requireEditableQuote(quoteID, session, query: "quotes.saveLineItem")

        let description = draft.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { throw DataError.rejected("Describe the line item before saving.") }
        guard draft.quantity > 0 else { throw DataError.rejected("Quantity must be greater than zero.") }
        guard draft.unitPrice >= 0 else { throw DataError.rejected("Unit price can't be negative.") }

        let lineTotal = Money.lineTotal(quantity: draft.quantity, unitPrice: draft.unitPrice)

        if let id = draft.id,
           let index = store.quoteLineItems.firstIndex(where: { $0.id == id && $0.quoteID == quoteID && $0.companyID == session.companyID }) {
            store.quoteLineItems[index].itemDescription = description
            store.quoteLineItems[index].quantity = draft.quantity
            store.quoteLineItems[index].unitPrice = draft.unitPrice
            store.quoteLineItems[index].taxRate = draft.taxRate
            store.quoteLineItems[index].lineTotal = lineTotal
            record("quotes.saveLineItem", session, allowed: true, "\(quote.number): line updated, totals recalculated")
        } else {
            let nextOrder = (lineItems(quoteID, session).map(\.sortOrder).max() ?? -1) + 1
            store.quoteLineItems.append(
                QuoteLineItem(
                    id: UUID().uuidString,
                    companyID: session.companyID,
                    quoteID: quoteID,
                    itemDescription: description,
                    quantity: draft.quantity,
                    unitPrice: draft.unitPrice,
                    taxRate: draft.taxRate,
                    lineTotal: lineTotal,
                    sortOrder: nextOrder
                )
            )
            record("quotes.saveLineItem", session, allowed: true, "\(quote.number): line added, totals recalculated")
        }

        recalculateQuote(quoteID, session)
    }

    func deleteQuoteLineItem(session: TenantSession, quoteID: String, lineItemID: String) async throws {
        try await Task.sleep(for: latency)
        let quote = try requireEditableQuote(quoteID, session, query: "quotes.deleteLineItem")
        store.quoteLineItems.removeAll { $0.id == lineItemID && $0.quoteID == quoteID && $0.companyID == session.companyID }
        // Close the gap so sort orders stay contiguous.
        let remaining = lineItems(quoteID, session)
        for (index, item) in remaining.enumerated() {
            if let position = store.quoteLineItems.firstIndex(where: { $0.id == item.id }) {
                store.quoteLineItems[position].sortOrder = index
            }
        }
        recalculateQuote(quoteID, session)
        record("quotes.deleteLineItem", session, allowed: true, "\(quote.number): line removed, totals recalculated")
    }

    func reorderQuoteLineItems(session: TenantSession, quoteID: String, orderedIDs: [String]) async throws {
        try await Task.sleep(for: latency)
        let quote = try requireEditableQuote(quoteID, session, query: "quotes.reorderLineItems")
        for (index, id) in orderedIDs.enumerated() {
            guard let position = store.quoteLineItems.firstIndex(where: { $0.id == id && $0.quoteID == quoteID && $0.companyID == session.companyID }) else { continue }
            store.quoteLineItems[position].sortOrder = index
        }
        record("quotes.reorderLineItems", session, allowed: true, "\(quote.number): \(orderedIDs.count) lines reordered")
    }

    func convertQuoteToJob(session: TenantSession, quoteID: String, input: QuoteConversionInput) async throws -> String {
        try await Task.sleep(for: latency)
        try require(.quotesManage, session, query: "quotes.convert")
        try require(.jobsManage, session, query: "quotes.convert")
        let quote = try requireVisibleQuote(quoteID, session, query: "quotes.convert")

        guard quote.status == .accepted else {
            record("quotes.convert", session, allowed: false, "Rejected — only an accepted quote converts")
            throw DataError.rejected("Only an accepted quote can become a job.")
        }
        guard quote.convertedJobID == nil else {
            record("quotes.convert", session, allowed: false, "Rejected — \(quote.number) already produced a job")
            throw DataError.rejected("\(quote.number) has already been converted.")
        }

        // Preserve the customer, the address and the asset on that address.
        let equipmentID = store.equipment.first {
            $0.addressID == quote.addressID && $0.companyID == session.companyID
        }?.id

        let description = """
        \(quote.scopeOfWork)

        Agreed scope from quote \(quote.number).
        """

        let jobID = try await createJob(
            session: session,
            input: NewJobInput(
                customerID: quote.customerID,
                addressID: quote.addressID,
                equipmentID: equipmentID,
                title: quote.title,
                jobDescription: description,
                kind: input.kind,
                priority: input.priority,
                scheduledStart: input.scheduledStart,
                scheduledEnd: input.scheduledEnd,
                fieldWorkerUserID: input.fieldWorkerUserID,
                quoteID: quote.id
            )
        )

        // The quote itself is untouched apart from this back-reference: its
        // status, dates, line items and totals stay exactly as the customer
        // accepted them.
        if let index = store.quotes.firstIndex(where: { $0.id == quoteID }) {
            store.quotes[index].convertedJobID = jobID
        }

        let newNumber = store.jobs.first { $0.id == jobID }?.number ?? "job"
        record("quotes.convert", session, allowed: true, "\(quote.number) → \(newNumber); quote left intact with \(lineItems(quoteID, session).count) line items")
        return jobID
    }

    // MARK: - Invoice gates

    /// Row gate for invoices.
    ///
    /// Unlike quotes, there is no "see the document but not the money" tier: an
    /// invoice *is* money. A role without `invoicesRead` is refused here and no
    /// row is assembled at all, so dispatchers and field workers never receive
    /// an invoice payload that would need stripping.
    private func visibleInvoices(_ session: TenantSession, query: String) throws -> [Invoice] {
        try require(.invoicesRead, session, query: query)
        let rows = scoped(store.invoices, session, companyID: \.companyID)
        record(query, session, allowed: true, "\(rows.count) invoice rows in company scope")
        return rows
    }

    private func requireVisibleInvoice(_ invoiceID: String, _ session: TenantSession, query: String) throws -> Invoice {
        let rows = try visibleInvoices(session, query: query)
        guard let invoice = rows.first(where: { $0.id == invoiceID }) else {
            record(query, session, allowed: false, "Row outside scope — returned notFound")
            throw DataError.notFound
        }
        return invoice
    }

    private func requireEditableInvoice(_ invoiceID: String, _ session: TenantSession, query: String) throws -> Invoice {
        try require(.invoicesManage, session, query: query)
        let invoice = try requireVisibleInvoice(invoiceID, session, query: query)
        guard invoice.status.isEditable else {
            record(query, session, allowed: false, "Rejected — \(invoice.number) is \(invoice.status.title.lowercased()) and its lines are locked")
            throw DataError.rejected("\(invoice.number) has already been issued, so its line items are locked.")
        }
        return invoice
    }

    // MARK: - Invoice derivation

    /// Re-derives an invoice's money from its own line items and its own
    /// payments. This is the only place invoice totals are ever written.
    ///
    /// `subtotal + tax == total` and `total - amountPaid == balance` hold by
    /// construction, and the status follows the money rather than being typed
    /// in by hand.
    private func recalculateInvoice(_ invoiceID: String, _ session: TenantSession) {
        guard let index = store.invoices.firstIndex(where: { $0.id == invoiceID && $0.companyID == session.companyID }) else { return }

        let totals = Money.totals(for: invoiceLines(invoiceID, session))
        let paid = Money.rounded(
            invoicePayments(invoiceID, session)
                .filter { $0.status.reducesBalance }
                .reduce(Decimal(0)) { $0 + $1.amount }
        )

        store.invoices[index].subtotal = totals.subtotal
        store.invoices[index].tax = totals.tax
        store.invoices[index].total = totals.total
        store.invoices[index].amountPaid = paid
        store.invoices[index].balance = Money.rounded(totals.total - paid)

        let settled = InvoiceWorkflow.settledStatus(
            current: store.invoices[index].status,
            total: totals.total,
            amountPaid: paid
        )
        store.invoices[index].status = settled
        if settled == .paid {
            if store.invoices[index].paidAt == nil { store.invoices[index].paidAt = Date() }
        } else {
            store.invoices[index].paidAt = nil
        }
    }

    /// Advances a linked job through the approved workflow as a **recorded**
    /// transition, writing a history row like any other status change.
    ///
    /// Nothing else on the job is touched: its title, description, scope, dates,
    /// asset and quote reference are left exactly as they were, so the job
    /// remains the historical record of the work carried out.
    private func advanceLinkedJob(_ jobID: String?, to status: JobStatus, _ session: TenantSession) {
        guard let jobID,
              let index = store.jobs.firstIndex(where: { $0.id == jobID && $0.companyID == session.companyID }),
              let transition = JobWorkflow.transition(from: store.jobs[index].status, to: status),
              session.can(transition.requirement.permissionForDisplay)
        else { return }
        applyStatus(jobIndex: index, transition: transition, to: status, session: session)
    }

    /// Terms the picker recognises give a computed due date; anything else the
    /// company has agreed in its own words falls back to due on receipt, which
    /// the person raising the invoice can override.
    private func resolvedDueDate(for termsLabel: String, issued: Date, explicit: Date?) -> Date {
        if let explicit { return explicit }
        return PaymentTerms.matching(termsLabel)?.dueDate(from: issued) ?? issued
    }

    private func invoiceBadge(_ invoice: Invoice) -> StatusBadge {
        let shown = invoice.effectiveStatus()
        return StatusBadge(text: shown.title, tone: shown.tone)
    }

    private func invoiceRow(_ invoice: Invoice, _ session: TenantSession) -> InvoiceRow {
        let overdueDays = invoice.isOverdue() ? abs(Formatters.daysUntil(invoice.dueDate)) : nil
        let jobReference = invoice.jobID
            .flatMap { id in store.jobs.first { $0.id == id && $0.companyID == session.companyID } }?
            .number
        let quoteReference = invoice.quoteID
            .flatMap { id in store.quotes.first { $0.id == id && $0.companyID == session.companyID } }?
            .number

        return InvoiceRow(
            id: invoice.id,
            number: invoice.number,
            title: invoice.title,
            customerID: invoice.customerID,
            customerName: customer(invoice.customerID, session)?.name ?? "Customer",
            badge: invoiceBadge(invoice),
            status: invoice.effectiveStatus(),
            issuedLabel: "Issued \(Formatters.shortDate(invoice.issueDate))",
            dueLabel: invoice.status.isSettled
                ? "Due \(Formatters.shortDate(invoice.dueDate))"
                : Formatters.dueLabel(invoice.dueDate),
            isOverdue: invoice.isOverdue(),
            daysOverdue: overdueDays,
            totalLabel: invoiceMoney(invoice.total, invoice),
            balanceLabel: invoiceMoney(invoice.balance, invoice),
            amountPaidLabel: invoice.amountPaid > 0 ? invoiceMoney(invoice.amountPaid, invoice) : nil,
            jobReference: jobReference,
            quoteReference: quoteReference
        )
    }

    private func paymentProjection(
        _ payment: Payment,
        _ invoice: Invoice,
        _ session: TenantSession,
        includeContext: Bool = false
    ) -> PaymentProjection {
        PaymentProjection(
            id: payment.id,
            amountLabel: invoiceMoney(payment.amount, invoice),
            amount: payment.amount,
            methodTitle: payment.method.title,
            methodSymbol: payment.method.symbolName,
            statusTitle: payment.status.title,
            statusTone: payment.status.tone,
            receivedLabel: Formatters.shortDate(payment.receivedAt),
            recordedByName: user(payment.recordedByUserID, session)?.name ?? "Team member",
            reference: payment.reference,
            note: payment.note,
            isSimulated: payment.isSimulated,
            invoiceNumber: includeContext ? invoice.number : nil,
            customerName: includeContext ? customer(invoice.customerID, session)?.name : nil
        )
    }

    // MARK: - Invoices

    func invoices(session: TenantSession, query: InvoiceQuery) async throws -> [InvoiceRow] {
        try await Task.sleep(for: latency)
        let all = try visibleInvoices(session, query: "invoices.list")
        let trimmed = query.searchText.trimmingCharacters(in: .whitespaces)

        let filtered = all.filter { invoice in
            guard query.filter.matches(invoice) else { return false }
            guard query.dateScope.matches(invoice) else { return false }
            if let customerID = query.customerID, invoice.customerID != customerID { return false }
            if !trimmed.isEmpty {
                let name = customer(invoice.customerID, session)?.name ?? ""
                let matches = invoice.number.localizedStandardContains(trimmed)
                    || invoice.title.localizedStandardContains(trimmed)
                    || name.localizedStandardContains(trimmed)
                if !matches { return false }
            }
            return true
        }

        record("invoices.list", session, allowed: true, "\(filtered.count) of \(all.count) after the \(query.filter.title.lowercased()) filter")

        return filtered
            .sorted { lhs, rhs in
                // Most urgent money first: overdue, then by due date.
                if lhs.isOverdue() != rhs.isOverdue() { return lhs.isOverdue() }
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.number > rhs.number
            }
            .map { invoiceRow($0, session) }
    }

    func invoiceDetail(session: TenantSession, invoiceID: String) async throws -> InvoiceDetailProjection {
        try await Task.sleep(for: latency)
        let invoice = try requireVisibleInvoice(invoiceID, session, query: "invoices.detail")

        let lines = invoiceLines(invoice.id, session)
        let lineProjections = lines.map { item -> InvoiceLineItemProjection in
            let lineTax = Money.lineTax(lineTotal: item.lineTotal, taxRate: item.taxRate)
            return InvoiceLineItemProjection(
                id: item.id,
                itemDescription: item.itemDescription,
                quantity: item.quantity,
                quantityLabel: Money.quantityLabel(item.quantity),
                sortOrder: item.sortOrder,
                pricing: InvoiceLinePricing(
                    unitPrice: item.unitPrice,
                    taxRate: item.taxRate,
                    lineTotal: item.lineTotal,
                    lineTax: lineTax,
                    unitPriceLabel: invoiceMoney(item.unitPrice, invoice),
                    taxRateLabel: Money.percentLabel(item.taxRate),
                    lineTotalLabel: invoiceMoney(item.lineTotal, invoice),
                    lineTaxLabel: invoiceMoney(lineTax, invoice)
                ),
                isFromQuote: item.sourceQuoteLineItemID != nil
            )
        }

        // Derived from the stored lines every time, so the printed lines always
        // reconcile with the printed subtotal, tax and total.
        let computed = Money.totals(for: lines)
        let outstanding = Money.rounded(computed.total - invoice.amountPaid)
        let totals = InvoiceTotalsProjection(
            subtotal: computed.subtotal,
            tax: computed.tax,
            total: computed.total,
            amountPaid: invoice.amountPaid,
            balance: outstanding,
            subtotalLabel: invoiceMoney(computed.subtotal, invoice),
            taxLabel: invoiceMoney(computed.tax, invoice),
            totalLabel: invoiceMoney(computed.total, invoice),
            amountPaidLabel: invoiceMoney(invoice.amountPaid, invoice),
            balanceLabel: invoiceMoney(outstanding, invoice)
        )

        let paymentRows: [PaymentProjection] = session.can(.paymentsRead)
            ? invoicePayments(invoice.id, session).map { paymentProjection($0, invoice, session) }
            : []
        if !session.can(.paymentsRead) {
            record("invoices.detail.payments", session, allowed: false, "Payment rows not assembled — missing paymentsRead")
        }

        let canManage = session.can(.invoicesManage)
        let statusActions: [InvoiceStatusAction] = canManage
            ? InvoiceWorkflow.nextStatuses(from: invoice.status).map {
                InvoiceStatusAction(
                    id: $0.rawValue,
                    title: InvoiceWorkflow.actionTitle(for: $0),
                    status: $0,
                    isDestructive: $0 == .void
                )
            }
            : []

        let job = invoice.jobID.flatMap { id in store.jobs.first { $0.id == id && $0.companyID == session.companyID } }
        let quote = invoice.quoteID.flatMap { id in store.quotes.first { $0.id == id && $0.companyID == session.companyID } }
        let contact = invoice.billingContactID
            .flatMap { id in store.contacts.first { $0.id == id && $0.companyID == session.companyID } }
            ?? billingContact(invoice.customerID, session)
        let addr = invoice.addressID.flatMap { address($0, session) }
        let cust = customer(invoice.customerID, session)

        return InvoiceDetailProjection(
            id: invoice.id,
            number: invoice.number,
            title: invoice.title,
            scopeOfWork: invoice.scopeOfWork,
            status: invoice.effectiveStatus(),
            badge: invoiceBadge(invoice),
            customerID: invoice.customerID,
            customerName: cust?.name ?? "Customer",
            customerTypeTitle: cust?.type.title ?? "",
            billingContactName: contact?.name,
            billingContactRole: contact?.contactRole,
            billingContactPhone: contact?.phone,
            billingContactEmail: contact?.email,
            addressLine: addr?.singleLine,
            issuedLabel: Formatters.shortDate(invoice.issueDate),
            dueLabel: Formatters.shortDate(invoice.dueDate),
            paymentTermsLabel: invoice.paymentTermsLabel,
            isOverdue: invoice.isOverdue(),
            daysOverdue: invoice.isOverdue() ? abs(Formatters.daysUntil(invoice.dueDate)) : nil,
            sentLabel: invoice.sentAt.map { Formatters.shortDate($0) },
            viewedLabel: invoice.viewedAt.map { Formatters.shortDate($0) },
            paidLabel: invoice.paidAt.map { Formatters.shortDate($0) },
            voidedLabel: invoice.voidedAt.map { Formatters.shortDate($0) },
            jobReference: job.map { "\($0.number) · \($0.status.title(session.terms))" },
            jobID: session.can(.jobsReadAll) ? invoice.jobID : nil,
            quoteReference: quote.map { "\($0.number) · \($0.status.title)" },
            quoteID: session.can(.quotesRead) ? invoice.quoteID : nil,
            lineItems: lineProjections,
            totals: totals,
            payments: paymentRows,
            currencyCode: invoice.currencyCode,
            defaultTaxRate: canManage ? defaultTaxRate(session) : nil,
            statusActions: statusActions,
            canManage: canManage,
            canEditLineItems: canManage && invoice.status.isEditable,
            canRecordPayment: session.can(.paymentsManage) && invoice.status.isIssued && outstanding > 0,
            maximumPayment: outstanding,
            maximumPaymentLabel: invoiceMoney(outstanding, invoice)
        )
    }

    func invoiceSources(session: TenantSession) async throws -> InvoiceSourceOptions {
        try await Task.sleep(for: latency)
        guard session.can(.invoicesManage) else {
            record("invoices.sources", session, allowed: false, "Reference data withheld — missing invoicesManage")
            return .empty
        }

        let jobs = (try? visibleJobs(session, query: "invoices.sources")) ?? []
        let mayReadQuoteMoney = session.can(.quoteFinancialsRead)

        // Completed jobs that have not already produced a live invoice. Filtering
        // the source list is a convenience; the write path refuses duplicates
        // regardless of what the UI offered.
        let completed = jobs
            .filter { $0.status == .completed && existingInvoice(jobID: $0.id, session) == nil }
            .sorted { ($0.actualEnd ?? $0.createdAt) > ($1.actualEnd ?? $1.createdAt) }
            .map { job -> InvoiceSourceOption in
                let quote = job.quoteID.flatMap { id in store.quotes.first { $0.id == id && $0.companyID == session.companyID } }
                return InvoiceSourceOption(
                    id: job.id,
                    number: job.number,
                    title: job.title,
                    customerName: customer(job.customerID, session)?.name ?? "Customer",
                    dateLabel: job.actualEnd.map { "Completed \(Formatters.shortDate($0))" } ?? Formatters.shortDate(job.createdAt),
                    valueLabel: mayReadQuoteMoney ? quote.map { money($0.total, session) } : nil,
                    lineItemCount: quote.map { lineItems($0.id, session).count } ?? 0
                )
            }

        let quotes = scoped(store.quotes, session, companyID: \.companyID)
            .filter { $0.status == .accepted && existingInvoice(quoteID: $0.id, session) == nil }
            .sorted { ($0.acceptedAt ?? $0.createdAt) > ($1.acceptedAt ?? $1.createdAt) }
            .map { quote -> InvoiceSourceOption in
                InvoiceSourceOption(
                    id: quote.id,
                    number: quote.number,
                    title: quote.title,
                    customerName: customer(quote.customerID, session)?.name ?? "Customer",
                    dateLabel: quote.acceptedAt.map { "Accepted \(Formatters.shortDate($0))" } ?? Formatters.shortDate(quote.createdAt),
                    valueLabel: mayReadQuoteMoney ? money(quote.total, session) : nil,
                    lineItemCount: lineItems(quote.id, session).count
                )
            }

        record("invoices.sources", session, allowed: true, "\(completed.count) uninvoiced completed jobs, \(quotes.count) uninvoiced accepted quotes")
        return InvoiceSourceOptions(completedJobs: completed, acceptedQuotes: quotes, canCreate: true)
    }

    // MARK: - Raising invoices

    /// Shared creation path. Everything that makes the document reproducible —
    /// its currency, its terms, its dates — is snapshotted here and never
    /// re-read from the company afterwards.
    private func makeInvoice(
        session: TenantSession,
        customerID: String,
        addressID: String?,
        jobID: String?,
        quoteID: String?,
        title: String,
        scopeOfWork: String,
        paymentTermsLabel: String?,
        issueDate: Date,
        explicitDueDate: Date?
    ) throws -> Invoice {
        guard let cust = customer(customerID, session) else { throw DataError.notFound }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw DataError.rejected("Give the invoice a short title.") }

        // Terms are snapshotted from the customer, so changing their default
        // terms later cannot move the due date on an invoice already issued.
        let terms = paymentTermsLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? cust.billingTerms

        let number = nextDocumentNumber(
            .invoice,
            session,
            existing: scoped(store.invoices, session, companyID: \.companyID).map(\.number)
        )

        return Invoice(
            id: "inv_\(UUID().uuidString.prefix(8))",
            companyID: session.companyID,
            customerID: customerID,
            billingContactID: billingContact(customerID, session)?.id,
            addressID: addressID,
            jobID: jobID,
            quoteID: quoteID,
            number: number,
            title: trimmedTitle,
            scopeOfWork: scopeOfWork,
            status: .draft,
            // The currency the document is issued in, captured now.
            currencyCode: currencyCode(session),
            paymentTermsLabel: terms,
            issueDate: issueDate,
            dueDate: resolvedDueDate(for: terms, issued: issueDate, explicit: explicitDueDate),
            subtotal: 0,
            tax: 0,
            total: 0,
            amountPaid: 0,
            balance: 0,
            createdByUserID: session.userID,
            sentAt: nil,
            viewedAt: nil,
            paidAt: nil,
            voidedAt: nil
        )
    }

    /// Copies a quote's priced lines onto an invoice as an independent
    /// **snapshot**.
    ///
    /// Description, quantity, unit price and tax rate are copied by value at
    /// this moment. The invoice never reads the quote again, so a later edit to
    /// the quote cannot silently change money the customer has already been
    /// billed. The quote itself is not modified.
    private func snapshotQuoteLines(_ quoteID: String, into invoiceID: String, _ session: TenantSession) -> Int {
        let source = lineItems(quoteID, session)
        for (index, line) in source.enumerated() {
            store.invoiceLineItems.append(
                InvoiceLineItem(
                    id: "ili_\(UUID().uuidString.prefix(8))",
                    companyID: session.companyID,
                    invoiceID: invoiceID,
                    itemDescription: line.itemDescription,
                    quantity: line.quantity,
                    unitPrice: line.unitPrice,
                    // The rate agreed on the quote, not the company's current
                    // default — this is the number the customer accepted.
                    taxRate: line.taxRate,
                    lineTotal: Money.lineTotal(quantity: line.quantity, unitPrice: line.unitPrice),
                    sortOrder: index,
                    sourceQuoteLineItemID: line.id
                )
            )
        }
        return source.count
    }

    func createInvoice(session: TenantSession, input: NewInvoiceInput) async throws -> String {
        try await Task.sleep(for: latency)
        try require(.invoicesManage, session, query: "invoices.create")

        guard customer(input.customerID, session) != nil else {
            record("invoices.create", session, allowed: false, "Customer outside company scope")
            throw DataError.notFound
        }
        if let addressID = input.addressID {
            guard let addr = address(addressID, session), addr.customerID == input.customerID else {
                record("invoices.create", session, allowed: false, "Address outside company scope")
                throw DataError.notFound
            }
        }

        let invoice = try makeInvoice(
            session: session,
            customerID: input.customerID,
            addressID: input.addressID,
            jobID: nil,
            quoteID: nil,
            title: input.title,
            scopeOfWork: input.scopeOfWork,
            paymentTermsLabel: input.paymentTermsLabel,
            issueDate: input.issueDate,
            explicitDueDate: input.dueDate
        )
        store.invoices.append(invoice)
        record("invoices.create", session, allowed: true, "\(invoice.number) created as a draft in \(invoice.currencyCode)")
        return invoice.id
    }

    func createInvoiceFromJob(session: TenantSession, jobID: String, input: InvoiceConversionInput) async throws -> String {
        try await Task.sleep(for: latency)
        try require(.invoicesManage, session, query: "invoices.createFromJob")
        let job = try requireVisibleJob(jobID, session, query: "invoices.createFromJob")

        guard job.status == .completed || job.status == .invoiced else {
            record("invoices.createFromJob", session, allowed: false, "Rejected — \(job.number) is \(job.status.title.lowercased()), not completed")
            throw DataError.rejected("Only a completed job can be invoiced.")
        }
        // One live invoice per job. A voided invoice frees the job to be
        // re-billed; a live one blocks it.
        if let existing = existingInvoice(jobID: jobID, session) {
            record("invoices.createFromJob", session, allowed: false, "Rejected — \(job.number) is already billed as \(existing.number)")
            throw DataError.rejected("\(job.number) has already been invoiced as \(existing.number).")
        }

        // Where the job came from an accepted quote, that quote's reference and
        // its agreed pricing carry through to the invoice.
        let quote = job.quoteID.flatMap { id in
            store.quotes.first { $0.id == id && $0.companyID == session.companyID && $0.status == .accepted }
        }
        if let existing = quote.flatMap({ existingInvoice(quoteID: $0.id, session) }) {
            record("invoices.createFromJob", session, allowed: false, "Rejected — the quote behind \(job.number) is already billed as \(existing.number)")
            throw DataError.rejected("The quote behind \(job.number) has already been invoiced as \(existing.number).")
        }

        let scope = quote.map { $0.scopeOfWork.isEmpty ? job.jobDescription : $0.scopeOfWork } ?? job.jobDescription

        let invoice = try makeInvoice(
            session: session,
            customerID: job.customerID,
            addressID: job.addressID,
            jobID: job.id,
            quoteID: quote?.id,
            title: job.title,
            scopeOfWork: scope,
            paymentTermsLabel: input.paymentTermsLabel,
            issueDate: input.issueDate,
            explicitDueDate: input.dueDate
        )
        store.invoices.append(invoice)

        var copiedLines = 0
        if input.copyLineItems, let quote {
            copiedLines = snapshotQuoteLines(quote.id, into: invoice.id, session)
        }
        recalculateInvoice(invoice.id, session)

        if input.advanceJobStatus {
            advanceLinkedJob(job.id, to: .invoiced, session)
        }

        let stored = store.invoices.first { $0.id == invoice.id }
        record(
            "invoices.createFromJob",
            session,
            allowed: true,
            "\(job.number) → \(invoice.number) · \(copiedLines) lines snapshotted from \(quote?.number ?? "no quote") · total \(stored.map { invoiceMoney($0.total, $0) } ?? "nil") · the job record itself is unchanged"
        )
        return invoice.id
    }

    func createInvoiceFromQuote(session: TenantSession, quoteID: String, input: InvoiceConversionInput) async throws -> String {
        try await Task.sleep(for: latency)
        try require(.invoicesManage, session, query: "invoices.createFromQuote")
        let quote = try requireVisibleQuote(quoteID, session, query: "invoices.createFromQuote")

        guard quote.status == .accepted else {
            record("invoices.createFromQuote", session, allowed: false, "Rejected — only an accepted quote can be invoiced")
            throw DataError.rejected("Only an accepted quote can be invoiced.")
        }
        if let existing = existingInvoice(quoteID: quoteID, session) {
            record("invoices.createFromQuote", session, allowed: false, "Rejected — \(quote.number) is already billed as \(existing.number)")
            throw DataError.rejected("\(quote.number) has already been invoiced as \(existing.number).")
        }

        // The job raised from this quote, if any, so the invoice keeps the
        // operational reference too — and so the same work can't be billed once
        // via the quote and again via its job.
        let linkedJobID = quote.convertedJobID
        if let linkedJobID, let existing = existingInvoice(jobID: linkedJobID, session) {
            record("invoices.createFromQuote", session, allowed: false, "Rejected — the job raised from \(quote.number) is already billed as \(existing.number)")
            throw DataError.rejected("The job raised from \(quote.number) has already been invoiced as \(existing.number).")
        }

        let invoice = try makeInvoice(
            session: session,
            customerID: quote.customerID,
            addressID: quote.addressID,
            jobID: linkedJobID,
            quoteID: quote.id,
            title: quote.title,
            scopeOfWork: quote.scopeOfWork,
            paymentTermsLabel: input.paymentTermsLabel,
            issueDate: input.issueDate,
            explicitDueDate: input.dueDate
        )
        store.invoices.append(invoice)

        var copiedLines = 0
        if input.copyLineItems {
            copiedLines = snapshotQuoteLines(quote.id, into: invoice.id, session)
        }
        recalculateInvoice(invoice.id, session)

        if input.advanceJobStatus {
            advanceLinkedJob(linkedJobID, to: .invoiced, session)
        }

        let stored = store.invoices.first { $0.id == invoice.id }
        record(
            "invoices.createFromQuote",
            session,
            allowed: true,
            "\(quote.number) → \(invoice.number) · \(copiedLines) lines snapshotted · total \(stored.map { invoiceMoney($0.total, $0) } ?? "nil") · quote left \(quote.status.title.lowercased()) and untouched"
        )
        return invoice.id
    }

    // MARK: - Invoice line items and status

    func saveInvoiceLineItem(session: TenantSession, invoiceID: String, draft: InvoiceLineItemDraft) async throws {
        try await Task.sleep(for: latency)
        let invoice = try requireEditableInvoice(invoiceID, session, query: "invoices.saveLineItem")

        let description = draft.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { throw DataError.rejected("Describe the line item before saving.") }
        guard draft.quantity > 0 else { throw DataError.rejected("Quantity must be greater than zero.") }
        guard draft.unitPrice >= 0 else { throw DataError.rejected("Unit price can't be negative.") }

        let lineTotal = Money.lineTotal(quantity: draft.quantity, unitPrice: draft.unitPrice)

        if let id = draft.id,
           let index = store.invoiceLineItems.firstIndex(where: { $0.id == id && $0.invoiceID == invoiceID && $0.companyID == session.companyID }) {
            store.invoiceLineItems[index].itemDescription = description
            store.invoiceLineItems[index].quantity = draft.quantity
            store.invoiceLineItems[index].unitPrice = draft.unitPrice
            store.invoiceLineItems[index].taxRate = draft.taxRate
            store.invoiceLineItems[index].lineTotal = lineTotal
            record("invoices.saveLineItem", session, allowed: true, "\(invoice.number): line updated, totals recalculated")
        } else {
            let nextOrder = (invoiceLines(invoiceID, session).map(\.sortOrder).max() ?? -1) + 1
            store.invoiceLineItems.append(
                InvoiceLineItem(
                    id: "ili_\(UUID().uuidString.prefix(8))",
                    companyID: session.companyID,
                    invoiceID: invoiceID,
                    itemDescription: description,
                    quantity: draft.quantity,
                    unitPrice: draft.unitPrice,
                    taxRate: draft.taxRate,
                    lineTotal: lineTotal,
                    sortOrder: nextOrder
                )
            )
            record("invoices.saveLineItem", session, allowed: true, "\(invoice.number): line added, totals recalculated")
        }

        recalculateInvoice(invoiceID, session)
    }

    func deleteInvoiceLineItem(session: TenantSession, invoiceID: String, lineItemID: String) async throws {
        try await Task.sleep(for: latency)
        let invoice = try requireEditableInvoice(invoiceID, session, query: "invoices.deleteLineItem")
        store.invoiceLineItems.removeAll { $0.id == lineItemID && $0.invoiceID == invoiceID && $0.companyID == session.companyID }

        // Close the gap so sort orders stay contiguous.
        let remaining = invoiceLines(invoiceID, session)
        for (index, item) in remaining.enumerated() {
            if let position = store.invoiceLineItems.firstIndex(where: { $0.id == item.id }) {
                store.invoiceLineItems[position].sortOrder = index
            }
        }
        recalculateInvoice(invoiceID, session)
        record("invoices.deleteLineItem", session, allowed: true, "\(invoice.number): line removed, totals recalculated")
    }

    func updateInvoiceStatus(session: TenantSession, invoiceID: String, to status: InvoiceStatus) async throws {
        try await Task.sleep(for: latency)
        try require(.invoicesManage, session, query: "invoices.updateStatus")
        let invoice = try requireVisibleInvoice(invoiceID, session, query: "invoices.updateStatus")

        guard InvoiceWorkflow.nextStatuses(from: invoice.status).contains(status) else {
            record("invoices.updateStatus", session, allowed: false, "Rejected — \(invoice.status.title) → \(status.title) is not allowed")
            throw DataError.rejected("A \(invoice.status.title.lowercased()) invoice can't move to \(status.title.lowercased()).")
        }
        if status == .sent, invoiceLines(invoiceID, session).isEmpty {
            record("invoices.updateStatus", session, allowed: false, "Rejected — \(invoice.number) has no line items")
            throw DataError.rejected("Add at least one line item before sending \(invoice.number).")
        }

        guard let index = store.invoices.firstIndex(where: { $0.id == invoiceID }) else { throw DataError.notFound }
        let now = Date()
        store.invoices[index].status = status
        switch status {
        case .sent: store.invoices[index].sentAt = now
        case .viewed: store.invoices[index].viewedAt = now
        case .void: store.invoices[index].voidedAt = now
        default: break
        }
        record("invoices.updateStatus", session, allowed: true, "\(invoice.number): \(invoice.status.title) → \(status.title)")
    }

    // MARK: - Payments

    func recordPayment(session: TenantSession, invoiceID: String, draft: PaymentDraft) async throws {
        try await Task.sleep(for: latency)
        try require(.paymentsManage, session, query: "payments.record")
        let invoice = try requireVisibleInvoice(invoiceID, session, query: "payments.record")

        guard invoice.status != .void else {
            record("payments.record", session, allowed: false, "Rejected — \(invoice.number) is void")
            throw DataError.rejected("\(invoice.number) has been voided and can't take a payment.")
        }
        guard invoice.status.isIssued else {
            record("payments.record", session, allowed: false, "Rejected — \(invoice.number) is still a draft")
            throw DataError.rejected("Send \(invoice.number) before recording a payment against it.")
        }

        let amount = Money.rounded(draft.amount)
        guard amount > 0 else { throw DataError.rejected("Enter an amount greater than zero.") }

        // Overpayment is refused at the data layer. There is deliberately no
        // refund or credit-note mechanism in this phase, so declining the excess
        // is the only correct answer — inventing one would be a schema change
        // nobody has approved.
        let outstanding = Money.rounded(invoice.total - invoice.amountPaid)
        guard amount <= outstanding else {
            record(
                "payments.record",
                session,
                allowed: false,
                "Rejected — \(invoiceMoney(amount, invoice)) exceeds the \(invoiceMoney(outstanding, invoice)) outstanding on \(invoice.number)"
            )
            throw DataError.rejected("That's more than the \(invoiceMoney(outstanding, invoice)) outstanding on \(invoice.number). Record that amount or less.")
        }

        // DEVELOPMENT: nothing is charged and no processor is contacted. The
        // record is real; the settlement is explicitly simulated and marked as
        // such on the row itself, not merely in the UI.
        store.payments.append(
            Payment(
                id: "pay_\(UUID().uuidString.prefix(8))",
                companyID: session.companyID,
                invoiceID: invoiceID,
                amount: amount,
                method: draft.method,
                status: .succeeded,
                reference: draft.reference?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                note: draft.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                receivedAt: draft.receivedAt,
                recordedByUserID: session.userID,
                isSimulated: true
            )
        )

        recalculateInvoice(invoiceID, session)
        guard let updated = store.invoices.first(where: { $0.id == invoiceID }) else { return }

        // A fully settled invoice carries its job to paid, as a recorded
        // workflow transition.
        if updated.status == .paid {
            advanceLinkedJob(updated.jobID, to: .paid, session)
        }

        record(
            "payments.record",
            session,
            allowed: true,
            "\(invoiceMoney(amount, updated)) \(draft.method.title) against \(updated.number) (SIMULATED) · paid \(invoiceMoney(updated.amountPaid, updated)) of \(invoiceMoney(updated.total, updated)) · balance \(invoiceMoney(updated.balance, updated)) · now \(updated.effectiveStatus().title)"
        )
    }

    func payments(session: TenantSession, query: InvoiceQuery) async throws -> [PaymentProjection] {
        try await Task.sleep(for: latency)
        try require(.paymentsRead, session, query: "payments.list")

        let invoicesByID = Dictionary(
            scoped(store.invoices, session, companyID: \.companyID).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let trimmed = query.searchText.trimmingCharacters(in: .whitespaces)

        let rows = scoped(store.payments, session, companyID: \.companyID)
            .sorted { $0.receivedAt > $1.receivedAt }
            .compactMap { payment -> PaymentProjection? in
                // A payment is only reachable through an invoice inside the
                // tenant, so an orphaned row can never be served.
                guard let invoice = invoicesByID[payment.invoiceID] else { return nil }
                if let customerID = query.customerID, invoice.customerID != customerID { return nil }
                guard query.dateScope.matches(invoice) else { return nil }
                if !trimmed.isEmpty {
                    let name = customer(invoice.customerID, session)?.name ?? ""
                    let matches = invoice.number.localizedStandardContains(trimmed)
                        || name.localizedStandardContains(trimmed)
                        || (payment.reference?.localizedStandardContains(trimmed) ?? false)
                    if !matches { return nil }
                }
                return paymentProjection(payment, invoice, session, includeContext: true)
            }

        record("payments.list", session, allowed: true, "\(rows.count) payment rows in company scope")
        return rows
    }

    // MARK: - Accounts receivable

    func receivables(session: TenantSession, query: InvoiceQuery) async throws -> ReceivablesSnapshot {
        try await Task.sleep(for: latency)
        let all = try visibleInvoices(session, query: "receivables")
        let now = Date()

        // Headline figures are computed over the whole book, narrowed only by
        // the customer and date filters — not by the status chip — so they don't
        // move when the list below is re-filtered.
        let book = all.filter { invoice in
            guard query.dateScope.matches(invoice, now: now) else { return false }
            if let customerID = query.customerID, invoice.customerID != customerID { return false }
            return true
        }

        let outstandingRows = book.filter { $0.isReceivable(asOf: now) }
        let overdueRows = book.filter { $0.isOverdue(asOf: now) }
        // Overdue invoices are counted under overdue, never again here, so the
        // two figures never double-count the same money.
        let dueThisWeekRows = outstandingRows.filter {
            !$0.isOverdue(asOf: now) && InvoiceListFilter.isDueWithinAWeek($0, now: now)
        }

        func sum(_ rows: [Invoice]) -> Decimal {
            Money.rounded(rows.reduce(Decimal(0)) { $0 + $1.balance })
        }

        let invoiceIDs = Set(book.map(\.id))
        let collectedPayments = scoped(store.payments, session, companyID: \.companyID)
            .filter { invoiceIDs.contains($0.invoiceID) && $0.status.reducesBalance }
        let collected = Money.rounded(collectedPayments.reduce(Decimal(0)) { $0 + $1.amount })

        func countLabel(_ count: Int, _ noun: String) -> String {
            count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
        }

        let outstandingTotal = sum(outstandingRows)
        let overdueTotal = sum(overdueRows)
        let dueThisWeekTotal = sum(dueThisWeekRows)

        let metrics = [
            ReceivablesMetric(
                id: "outstanding",
                caption: "Outstanding",
                amountLabel: moneyRounded(outstandingTotal, session),
                amount: outstandingTotal,
                countLabel: countLabel(outstandingRows.count, "invoice"),
                symbolName: "tray.full.fill",
                tone: .info
            ),
            ReceivablesMetric(
                id: "overdue",
                caption: "Overdue",
                amountLabel: moneyRounded(overdueTotal, session),
                amount: overdueTotal,
                countLabel: countLabel(overdueRows.count, "invoice"),
                symbolName: "exclamationmark.triangle.fill",
                tone: overdueRows.isEmpty ? .neutral : .danger
            ),
            ReceivablesMetric(
                id: "dueThisWeek",
                caption: "Due this week",
                amountLabel: moneyRounded(dueThisWeekTotal, session),
                amount: dueThisWeekTotal,
                countLabel: countLabel(dueThisWeekRows.count, "invoice"),
                symbolName: "calendar.badge.clock",
                tone: dueThisWeekRows.isEmpty ? .neutral : .warning
            ),
            ReceivablesMetric(
                id: "collected",
                caption: "Collected",
                amountLabel: moneyRounded(collected, session),
                amount: collected,
                countLabel: countLabel(collectedPayments.count, "payment"),
                symbolName: "checkmark.circle.fill",
                tone: .success
            )
        ]

        let listed = book
            .filter { query.filter.matches($0, now: now) }
            .sorted { lhs, rhs in
                if lhs.isOverdue(asOf: now) != rhs.isOverdue(asOf: now) { return lhs.isOverdue(asOf: now) }
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.number > rhs.number
            }
            .map { invoiceRow($0, session) }

        let worstFirst = overdueRows
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(5)
            .map { invoiceRow($0, session) }

        var recent: [PaymentProjection] = []
        if session.can(.paymentsRead) {
            let invoicesByID = Dictionary(book.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            recent = scoped(store.payments, session, companyID: \.companyID)
                .filter { invoiceIDs.contains($0.invoiceID) }
                .sorted { $0.receivedAt > $1.receivedAt }
                .prefix(6)
                .compactMap { payment in
                    guard let invoice = invoicesByID[payment.invoiceID] else { return nil }
                    return paymentProjection(payment, invoice, session, includeContext: true)
                }
        } else {
            record("receivables.payments", session, allowed: false, "Payment rows not assembled — missing paymentsRead")
        }

        // Customer filter options. `addressLine` carries the classification so
        // the picker reads well; no address or asset data is needed here.
        let customerOptions = scoped(store.customers, session, companyID: \.companyID)
            .sorted { $0.name < $1.name }
            .map { cust in
                CustomerOption(id: cust.id, name: cust.name, addressID: "", addressLine: cust.type.title, equipment: [])
            }

        record(
            "receivables",
            session,
            allowed: true,
            "\(outstandingRows.count) outstanding, \(overdueRows.count) overdue, \(dueThisWeekRows.count) due this week, \(collectedPayments.count) payments collected"
        )

        return ReceivablesSnapshot(
            metrics: metrics,
            invoices: listed,
            overdueInvoices: Array(worstFirst),
            recentPayments: recent,
            currencyCode: currencyCode(session),
            customerOptions: customerOptions,
            collectedCaption: query.dateScope == .all ? "All time" : query.dateScope.title
        )
    }

    // MARK: - Dispatch helpers

    /// Dispatch is operational, not financial. `calendarReadAll` is the gate:
    /// owner, admin and dispatcher hold it; accounts does not, so the money role
    /// gets no dispatch control, and a field worker never reaches it either.
    private func requireDispatch(_ session: TenantSession, query: String) throws {
        try require(.calendarReadAll, session, query: query)
    }

    private func assignmentsByJob(_ session: TenantSession) -> [String: String] {
        Dictionary(
            scoped(store.assignments, session, companyID: \.companyID)
                .filter(\.isPrimary)
                .map { ($0.jobID, $0.userID) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The interval a job occupies. A job with no start occupies nothing and can
    /// never clash.
    private func slot(_ job: Job) -> (start: Date, end: Date)? {
        guard let start = job.scheduledStart else { return nil }
        // A start with no end is treated as one hour, so an open-ended booking
        // still takes part in overlap checks instead of colliding with
        // everything after it.
        let end = job.scheduledEnd ?? start.addingTimeInterval(3600)
        return (start, max(end, start))
    }

    private static func overlaps(_ a: (start: Date, end: Date), _ b: (start: Date, end: Date)) -> Bool {
        // Half-open: a job ending exactly as the next begins is not a clash.
        a.start < b.end && b.start < a.end
    }

    /// Every live job already booked for this worker that would overlap the
    /// candidate slot. Cancelled and finished work is ignored.
    private func overlappingJobs(
        workerUserID: String,
        candidate: (start: Date, end: Date),
        excludingJobID: String,
        _ session: TenantSession
    ) -> [Job] {
        let assignments = assignmentsByJob(session)
        return scoped(store.jobs, session, companyID: \.companyID)
            .filter { job in
                guard job.id != excludingJobID else { return false }
                guard assignments[job.id] == workerUserID else { return false }
                guard job.status.isOpen else { return false }
                guard let other = slot(job) else { return false }
                return Self.overlaps(candidate, other)
            }
            .sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }
    }

    private func conflictRows(
        job: Job,
        workerUserID: String,
        slotOverride: (start: Date, end: Date)? = nil,
        _ session: TenantSession
    ) -> [SchedulingConflict] {
        guard let candidate = slotOverride ?? slot(job) else { return [] }
        guard let worker = user(workerUserID, session) else { return [] }

        return overlappingJobs(
            workerUserID: workerUserID,
            candidate: candidate,
            excludingJobID: job.id,
            session
        ).map { clash in
            let range = slot(clash).map { Formatters.timeRange($0.start, $0.end) } ?? "no slot"
            return SchedulingConflict(
                id: "\(job.id)-\(clash.id)",
                kind: .workerDoubleBooked,
                jobID: job.id,
                jobNumber: job.number,
                clashingJobID: clash.id,
                clashingJobNumber: clash.number,
                clashingJobTitle: clash.title,
                workerUserID: workerUserID,
                workerName: worker.name,
                detail: "\(worker.name) is already on \(clash.number) (\(range))",
                overlapLabel: range
            )
        }
    }

    // MARK: - Dispatch board

    func dispatchBoard(session: TenantSession, query: DispatchQuery) async throws -> DispatchBoard {
        try await Task.sleep(for: latency)
        try requireDispatch(session, query: "dispatch.board")

        let all = try visibleJobs(session, query: "dispatch.board")
        let assignments = assignmentsByJob(session)
        let calendar = Calendar.current
        let now = Date()
        let trimmed = query.searchText.trimmingCharacters(in: .whitespaces)

        func matchesFilters(_ job: Job) -> Bool {
            if let workerID = query.fieldWorkerUserID, assignments[job.id] != workerID { return false }
            if query.unassignedOnly, assignments[job.id] != nil { return false }
            guard !trimmed.isEmpty else { return true }
            let name = customer(job.customerID, session)?.name ?? ""
            let line = address(job.addressID, session)?.singleLine ?? ""
            return job.number.localizedStandardContains(trimmed)
                || name.localizedStandardContains(trimmed)
                || line.localizedStandardContains(trimmed)
                || job.title.localizedStandardContains(trimmed)
        }

        let onDay = all
            .filter { job in
                guard let start = job.scheduledStart else { return false }
                return calendar.isDate(start, inSameDayAs: query.date) && matchesFilters(job)
            }
            .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }

        // The backlog: no slot at all and still live. Not tied to the chosen
        // day, because unscheduled work belongs to no day until it is placed.
        let unscheduled = all
            .filter { $0.isUnscheduled && $0.status.isOpen && matchesFilters($0) }
            .sorted { $0.createdAt > $1.createdAt }

        let unassigned = onDay.filter { assignments[$0.id] == nil && $0.status.isOpen }
        let urgent = onDay.filter { $0.priority == .urgent && $0.status.isOpen }
        let travelling = onDay.filter { $0.status == .travelling }
        let inProgress = onDay.filter { $0.status == .inProgress }

        // Running late: the slot has ended and the work is not finished.
        let runningLate = onDay.filter { job in
            guard job.status.isOpen, let bounds = slot(job) else { return false }
            return bounds.end < now
        }

        // Conflicts across the day, deduplicated so a clashing pair is reported
        // once rather than from both sides.
        var seenPairs = Set<String>()
        var conflicts: [SchedulingConflict] = []
        for job in onDay {
            guard let workerID = assignments[job.id] else { continue }
            for conflict in conflictRows(job: job, workerUserID: workerID, session) {
                let pair = [conflict.jobID, conflict.clashingJobID].sorted().joined(separator: "|")
                guard !seenPairs.contains(pair) else { continue }
                seenPairs.insert(pair)
                conflicts.append(conflict)
            }
        }
        let conflictedJobIDs = Set(conflicts.flatMap { [$0.jobID, $0.clashingJobID] })

        let mayReadLocations = session.can(.fieldWorkerLocationReadAll)
        let locationsByUser: [String: FieldWorkerLocationProjection] = mayReadLocations
            ? Dictionary(
                locationProjections(session).map { ($0.userID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            : [:]
        if !mayReadLocations {
            record("dispatch.board.locations", session, allowed: false, "Worker positions not assembled for role")
        }

        let workers: [FieldWorkerWorkload] = session.can(.usersRead)
            ? scoped(store.users, session, companyID: \.companyID)
                .filter { $0.role == .fieldWorker && $0.status == .active }
                .sorted { $0.name < $1.name }
                .map { worker in
                    let theirJobs = onDay.filter { assignments[$0.id] == worker.id }
                    let live = theirJobs.first { $0.status.isFieldActive }
                    let open = theirJobs.filter { $0.status.isOpen }
                    let done = theirJobs.filter { !$0.status.isOpen && $0.status != .cancelled }

                    let scheduleLabel: String
                    if theirJobs.isEmpty {
                        scheduleLabel = "Nothing booked"
                    } else if let first = theirJobs.first?.scheduledStart,
                              let last = theirJobs.compactMap(\.scheduledEnd).max() {
                        scheduleLabel = Formatters.timeRange(first, last)
                    } else {
                        scheduleLabel = "\(theirJobs.count) stops"
                    }

                    return FieldWorkerWorkload(
                        id: worker.id,
                        name: worker.name,
                        initials: worker.initials,
                        // The company's own word for this role — never
                        // "engineer" unless the company is an HVAC business.
                        roleTitle: Role.fieldWorker.title(session.terms),
                        jobCount: theirJobs.count,
                        completedCount: done.count,
                        openCount: open.count,
                        currentJobID: live?.id,
                        currentJobNumber: live?.number,
                        currentStatus: live?.status,
                        currentStatusTitle: live?.status.title(session.terms),
                        isAvailable: live == nil,
                        hasConflict: theirJobs.contains { conflictedJobIDs.contains($0.id) },
                        scheduleLabel: scheduleLabel,
                        location: locationsByUser[worker.id]
                    )
                }
            : []

        let openToday = onDay.filter { $0.status.isOpen }
        let headline = openToday.count == 1 ? "1 job open" : "\(openToday.count) jobs open"

        var subline = "Everything on this day is closed out"
        if !unassigned.isEmpty {
            subline = unassigned.count == 1
                ? "1 job still needs a \(session.terms.worker)"
                : "\(unassigned.count) jobs still need \(session.terms.workerPlural)"
        } else if !runningLate.isEmpty {
            subline = "\(runningLate.count) running past their slot"
        } else if !openToday.isEmpty {
            subline = "All assigned · \(travelling.count) travelling, \(inProgress.count) on site"
        }

        record(
            "dispatch.board",
            session,
            allowed: true,
            "\(onDay.count) scheduled, \(unscheduled.count) unscheduled, \(unassigned.count) unassigned, \(conflicts.count) conflicts, \(workers.count) \(session.terms.workerPlural)"
        )

        return DispatchBoard(
            dateTitle: Formatters.dayTitle(query.date),
            headline: headline,
            subline: subline,
            scheduled: onDay.map { jobRow($0, session) },
            unscheduled: unscheduled.map { jobRow($0, session) },
            unassigned: unassigned.map { jobRow($0, session) },
            urgent: urgent.map { jobRow($0, session) },
            runningLate: runningLate.map { jobRow($0, session) },
            travelling: travelling.map { jobRow($0, session) },
            inProgress: inProgress.map { jobRow($0, session) },
            workers: workers,
            conflicts: conflicts,
            canAssign: session.can(.assignmentsManage),
            canManageJobs: session.can(.jobsManage),
            canReadLocations: mayReadLocations
        )
    }

    // MARK: - Location

    /// Latest fix per worker, already row-gated.
    ///
    /// The gate is applied *here*, once: a caller holding
    /// `fieldWorkerLocationReadAll` receives the company's workers, a field
    /// worker holding only `fieldWorkerLocationReadOwnOnly` receives their own
    /// row and nothing else, and anyone else receives an empty list. Company
    /// scope is applied before either, so cross-tenant positions are never
    /// reachable at all.
    private func locationProjections(_ session: TenantSession, asOf now: Date = Date()) -> [FieldWorkerLocationProjection] {
        let tenantRows = scoped(store.workerLocations, session, companyID: \.companyID)

        let permitted: [FieldWorkerLocation]
        if session.can(.fieldWorkerLocationReadAll) {
            permitted = tenantRows
        } else if session.can(.fieldWorkerLocationReadOwnOnly) {
            permitted = tenantRows.filter { $0.userID == session.userID }
        } else {
            return []
        }

        // One row per worker: the most recent.
        let latest = Dictionary(grouping: permitted, by: \.userID)
            .compactMap { _, rows in rows.max { $0.recordedAt < $1.recordedAt } }

        return latest
            .sorted { $0.recordedAt > $1.recordedAt }
            .map { ping in
                let worker = user(ping.userID, session)
                let job = ping.jobID.flatMap { id in
                    store.jobs.first { $0.id == id && $0.companyID == session.companyID }
                }
                return FieldWorkerLocationProjection(
                    id: ping.id,
                    userID: ping.userID,
                    workerName: worker?.name ?? "Team member",
                    initials: worker?.initials ?? "··",
                    latitude: ping.latitude,
                    longitude: ping.longitude,
                    coordinateLabel: Formatters.coordinateLabel(latitude: ping.latitude, longitude: ping.longitude),
                    accuracyLabel: "±\(Int(ping.accuracyMeters.rounded())) m",
                    headingLabel: ping.heading.map { "\(Int($0.rounded()))° \(Formatters.compassPoint($0))" },
                    speedLabel: ping.speedMetersPerSecond.map { Formatters.speedLabel($0, countryCode: company(session)?.countryCode ?? "US") },
                    recordedAtLabel: Formatters.shortDayAndTime(ping.recordedAt),
                    recordedAt: ping.recordedAt,
                    freshness: ping.freshness(asOf: now),
                    jobID: job?.id,
                    jobNumber: job?.number,
                    jobStatusTitle: job?.status.title(session.terms),
                    isSimulated: ping.isSimulated
                )
            }
    }

    func fieldWorkerLocations(session: TenantSession) async throws -> FieldWorkerLocationBoard {
        try await Task.sleep(for: latency)

        guard session.can(.fieldWorkerLocationReadAll) || session.can(.fieldWorkerLocationReadOwnOnly) else {
            record("location.board", session, allowed: false, "No location read permission — nothing assembled")
            throw DataError.notPermitted(.fieldWorkerLocationReadAll)
        }

        let rows = locationProjections(session)
        let seenUserIDs = Set(rows.map(\.userID))

        // Only an office role has any business knowing who *hasn't* reported.
        let missing: [String] = session.can(.fieldWorkerLocationReadAll)
            ? scoped(store.users, session, companyID: \.companyID)
                .filter { $0.role == .fieldWorker && $0.status == .active && !seenUserIDs.contains($0.id) }
                .map(\.name)
                .sorted()
            : []

        let recent = rows.filter { $0.freshness == .recent }.count

        record(
            "location.board",
            session,
            allowed: true,
            session.can(.fieldWorkerLocationReadAll)
                ? "\(rows.count) worker positions in company scope, \(recent) recent"
                : "Own position only — \(rows.count) row"
        )

        return FieldWorkerLocationBoard(
            locations: rows,
            withoutLocation: missing,
            // An empty board is not a simulated one. Without the emptiness
            // check `allSatisfy` answers true for no rows at all, which would
            // put a "development fixtures" banner over a board with nothing on
            // it.
            isSimulated: !rows.isEmpty && rows.allSatisfy(\.isSimulated),
            policySummary: LocationRetentionPolicy.summary,
            recentCount: recent,
            lastKnownCount: rows.count - recent
        )
    }

    func recordLocationFix(
        session: TenantSession,
        jobID: String?,
        event: LocationCaptureEvent,
        fix: LocationFix
    ) async throws {
        // A worker may only ever write their *own* position, and only for a job
        // they are actually on.
        guard session.can(.fieldWorkerLocationReadOwnOnly) || session.can(.fieldWorkerLocationReadAll) else {
            record("location.record", session, allowed: false, "No location permission — fix discarded")
            throw DataError.notPermitted(.fieldWorkerLocationReadOwnOnly)
        }
        if let jobID {
            _ = try requireVisibleJob(jobID, session, query: "location.record")
        }

        store.workerLocations.append(
            FieldWorkerLocation(
                id: "loc_\(UUID().uuidString.prefix(8))",
                companyID: session.companyID,
                userID: session.userID,
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                accuracyMeters: fix.accuracyMeters,
                heading: fix.heading,
                speedMetersPerSecond: fix.speedMetersPerSecond,
                jobID: jobID,
                recordedAt: fix.capturedAt,
                captureEvent: event,
                isSimulated: fix.simulated
            )
        )
        trimLocationHistory(session)

        record(
            "location.record",
            session,
            allowed: true,
            "\(event.title) fix stored for \(session.displayName)\(jobID.map { _ in " on job" } ?? "")\(fix.simulated ? " (SIMULATED)" : "") · retention \(LocationRetentionPolicy.days)d / \(LocationRetentionPolicy.maximumPingsPerWorker) points"
        )
    }

    /// Enforces the retention policy as rows are written, so history is bounded
    /// by design rather than by whatever the table happens to accumulate.
    private func trimLocationHistory(_ session: TenantSession) {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -LocationRetentionPolicy.days,
            to: Date()
        ) ?? .distantPast

        store.workerLocations.removeAll { $0.companyID == session.companyID && $0.recordedAt < cutoff }

        let mine = store.workerLocations
            .filter { $0.companyID == session.companyID && $0.userID == session.userID }
            .sorted { $0.recordedAt > $1.recordedAt }

        guard mine.count > LocationRetentionPolicy.maximumPingsPerWorker else { return }
        let expired = Set(mine.dropFirst(LocationRetentionPolicy.maximumPingsPerWorker).map(\.id))
        store.workerLocations.removeAll { expired.contains($0.id) }
    }

    // MARK: - Scheduling checks and writes

    func checkAssignment(session: TenantSession, jobID: String, workerUserID: String?) async throws -> SchedulingCheck {
        try await Task.sleep(for: latency)
        try require(.assignmentsManage, session, query: "dispatch.checkAssignment")
        let job = try requireVisibleJob(jobID, session, query: "dispatch.checkAssignment")

        // Clearing an assignment can never create an overlap.
        guard let workerUserID else { return .clear }
        guard user(workerUserID, session)?.role == .fieldWorker else { throw DataError.notFound }

        let conflicts = conflictRows(job: job, workerUserID: workerUserID, session)
        record(
            "dispatch.checkAssignment",
            session,
            allowed: true,
            conflicts.isEmpty ? "\(job.number): no clash" : "\(job.number): \(conflicts.count) clash(es) — warning required before the write"
        )
        return SchedulingCheck(conflicts: conflicts)
    }

    func checkReschedule(session: TenantSession, jobID: String, input: RescheduleInput) async throws -> SchedulingCheck {
        try await Task.sleep(for: latency)
        try require(.jobsManage, session, query: "dispatch.checkReschedule")
        let job = try requireVisibleJob(jobID, session, query: "dispatch.checkReschedule")

        guard let workerUserID = primaryAssignment(jobID, session)?.userID else { return .clear }
        guard let start = input.scheduledStart else { return .clear }
        let end = input.scheduledEnd ?? start.addingTimeInterval(3600)

        let conflicts = conflictRows(
            job: job,
            workerUserID: workerUserID,
            slotOverride: (start, max(end, start)),
            session
        )
        record(
            "dispatch.checkReschedule",
            session,
            allowed: true,
            conflicts.isEmpty ? "\(job.number): slot is free" : "\(job.number): \(conflicts.count) clash(es) in the new slot"
        )
        return SchedulingCheck(conflicts: conflicts)
    }

    func assignJob(session: TenantSession, jobID: String, input: AssignmentInput) async throws -> SchedulingCheck {
        try await Task.sleep(for: latency)

        // Same rule, same code as the job screen — only the audit name differs.
        return try applyAssignment(
            session: session,
            jobID: jobID,
            workerUserID: input.workerUserID,
            acknowledgesConflict: input.acknowledgesConflict,
            query: "dispatch.assign"
        )
    }

    func rescheduleJob(session: TenantSession, jobID: String, input: RescheduleInput) async throws -> SchedulingCheck {
        try await Task.sleep(for: latency)
        try require(.jobsManage, session, query: "dispatch.reschedule")
        let job = try requireVisibleJob(jobID, session, query: "dispatch.reschedule")

        if let start = input.scheduledStart, let end = input.scheduledEnd, end < start {
            throw DataError.rejected("A job can't finish before it starts.")
        }

        var check = SchedulingCheck.clear
        if let workerUserID = primaryAssignment(jobID, session)?.userID, let start = input.scheduledStart {
            let end = input.scheduledEnd ?? start.addingTimeInterval(3600)
            check = SchedulingCheck(
                conflicts: conflictRows(job: job, workerUserID: workerUserID, slotOverride: (start, max(end, start)), session)
            )
            if check.hasConflicts, !input.acknowledgesConflict {
                record("dispatch.reschedule", session, allowed: false, "Refused pending acknowledgement — \(check.summary)")
                throw DataError.rejected(check.summary)
            }
        }

        guard let index = store.jobs.firstIndex(where: { $0.id == jobID }) else { throw DataError.notFound }
        let previous = store.jobs[index].scheduledStart
        let previousEnd = store.jobs[index].scheduledEnd
        store.jobs[index].scheduledStart = input.scheduledStart
        store.jobs[index].scheduledEnd = input.scheduledEnd

        // Only a real move raises the event: saving the same slot again is not
        // a change and must not wake anyone up.
        if previous != input.scheduledStart || previousEnd != input.scheduledEnd {
            enqueuePush(
                session: session,
                to: store.assignments.first(where: { $0.jobID == jobID })?.userID,
                event: .jobRescheduled,
                title: PushEvent.jobRescheduled.title,
                body: "\(pushJobLabel(job)) is now \(pushWhenLabel(input.scheduledStart)).",
                jobID: jobID,
                customerID: job.customerID
            )
        }

        let from = previous.map { Formatters.dayAndTime($0) } ?? "unscheduled"
        let to = input.scheduledStart.map { Formatters.dayAndTime($0) } ?? "unscheduled"
        record(
            "dispatch.reschedule",
            session,
            allowed: true,
            "\(job.number): \(from) → \(to)\(check.hasConflicts ? " with an acknowledged overlap" : "")"
        )
        return check
    }

    // MARK: - Calendar

    func calendarBoard(session: TenantSession, query: CalendarQuery) async throws -> CalendarBoard {
        try await Task.sleep(for: latency)
        guard session.can(.calendarReadAll) || session.can(.calendarReadOwnOnly) else {
            record("calendar.board", session, allowed: false, "No calendar permission")
            throw DataError.notPermitted(.calendarReadAll)
        }

        let all = try visibleJobs(session, query: "calendar.board")
        let assignments = assignmentsByJob(session)
        let calendar = Calendar.current

        // A week starts on the calendar's own first weekday, so the grid follows
        // the user's locale rather than an assumption baked into the code.
        let anchor: Date
        if query.span == .week {
            anchor = calendar.dateInterval(of: .weekOfYear, for: query.anchorDate)?.start ?? query.anchorDate
        } else {
            anchor = calendar.startOfDay(for: query.anchorDate)
        }

        func matchesFilters(_ job: Job) -> Bool {
            if let workerID = query.fieldWorkerUserID, assignments[job.id] != workerID { return false }
            if query.unassignedOnly, assignments[job.id] != nil { return false }
            return true
        }

        // Conflicts are computed once across the whole visible set, then marked
        // per day, so a clash is flagged on both jobs involved.
        var conflictedJobIDs = Set<String>()
        for job in all where job.status.isOpen {
            guard let workerID = assignments[job.id] else { continue }
            let rows = conflictRows(job: job, workerUserID: workerID, session)
            if !rows.isEmpty {
                conflictedJobIDs.insert(job.id)
                conflictedJobIDs.formUnion(rows.map(\.clashingJobID))
            }
        }

        let days: [CalendarDay] = (0..<query.span.dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: anchor) else { return nil }
            let dayJobs = all
                .filter { job in
                    guard let start = job.scheduledStart else { return false }
                    return calendar.isDate(start, inSameDayAs: day) && matchesFilters(job)
                }
                .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }

            return CalendarDay(
                id: "\(offset)",
                date: day,
                title: Formatters.dayTitle(day),
                jobs: dayJobs.map { jobRow($0, session) },
                conflictingJobIDs: Set(dayJobs.map(\.id)).intersection(conflictedJobIDs),
                unassignedCount: dayJobs.filter { assignments[$0.id] == nil && $0.status.isOpen }.count,
                urgentCount: dayJobs.filter { $0.priority == .urgent && $0.status.isOpen }.count
            )
        }

        let workers: [FieldWorkerOption] = session.can(.usersRead)
            ? scoped(store.users, session, companyID: \.companyID)
                .filter { $0.role == .fieldWorker && $0.status == .active }
                .sorted { $0.name < $1.name }
                .map { FieldWorkerOption(id: $0.id, name: $0.name, initials: $0.initials) }
            : []

        let rangeTitle: String
        if query.span == .day {
            rangeTitle = days.first?.title ?? Formatters.dayTitle(anchor)
        } else if let first = days.first?.date, let last = days.last?.date {
            rangeTitle = "\(Formatters.shortDate(first)) – \(Formatters.shortDate(last))"
        } else {
            rangeTitle = Formatters.shortDate(anchor)
        }

        let totalJobs = days.reduce(0) { $0 + $1.jobs.count }
        let conflictCount = days.reduce(into: Set<String>()) { $0.formUnion($1.conflictingJobIDs) }.count

        record(
            "calendar.board",
            session,
            allowed: true,
            "\(query.span.title) view: \(totalJobs) jobs over \(days.count) day(s), \(conflictCount) in conflict"
        )

        return CalendarBoard(
            span: query.span,
            days: days,
            workers: workers,
            canAssign: session.can(.assignmentsManage),
            canReschedule: session.can(.jobsManage),
            rangeTitle: rangeTitle,
            totalJobs: totalJobs,
            unassignedCount: days.reduce(0) { $0 + $1.unassignedCount },
            conflictCount: conflictCount
        )
    }

    // MARK: - Travel

    func travelSnapshot(session: TenantSession, jobID: String) async throws -> TravelSnapshot {
        try await Task.sleep(for: latency)
        // Row-gated like any other job read: a field worker reaches only their
        // own assignment, and anything else answers notFound.
        let job = try requireVisibleJob(jobID, session, query: "travel.snapshot")

        let addr = address(job.addressID, session)
        let cust = customer(job.customerID, session)
        let contact = primaryContact(job.customerID, session)
        let advance = JobWorkflow.fieldAdvance(from: job.status)

        let scheduleLabel: String
        if let start = job.scheduledStart, let end = job.scheduledEnd {
            scheduleLabel = "\(Formatters.dayTitle(start)) · \(Formatters.timeRange(start, end))"
        } else if let start = job.scheduledStart {
            scheduleLabel = Formatters.dayAndTime(start)
        } else {
            scheduleLabel = "No slot booked"
        }

        record(
            "travel.snapshot",
            session,
            allowed: true,
            "\(job.number) travel view served — the payload type carries no monetary field"
        )

        return TravelSnapshot(
            jobID: job.id,
            number: job.number,
            customerName: cust?.name ?? "Customer",
            addressLine: addr?.singleLine ?? "",
            accessNotes: addr?.accessNotes,
            siteContactName: contact?.name,
            siteContactPhone: contact?.phone,
            latitude: addr?.latitude ?? 27.9506,
            longitude: addr?.longitude ?? -82.4572,
            status: job.status,
            statusTitle: job.status.title(session.terms),
            badge: badge(for: job.status, session),
            scheduleLabel: scheduleLabel,
            isUrgent: job.priority == .urgent,
            nextActionTitle: advance?.actionTitle(session.terms),
            nextStatus: advance?.to,
            countryCode: company(session)?.countryCode ?? "US"
        )
    }

    // MARK: - Customer-facing delivery

    func companyPaymentLink(session: TenantSession) async throws -> PaymentLinkSettings {
        try await Task.sleep(for: latency)
        try require(.companyProfileRead, session, query: "company.paymentLink")

        let stored = company(session)?.onlinePaymentLinkURL
        record(
            "company.paymentLink",
            session,
            allowed: true,
            stored == nil ? "No payment link configured" : "Payment link configured — a URL only, no processor account"
        )

        return PaymentLinkSettings(
            url: stored,
            displayHost: OnlinePaymentLink.displayHost(stored),
            canManage: session.can(.companyProfileManage)
        )
    }

    func updateCompanyPaymentLink(session: TenantSession, url: String?) async throws {
        try await Task.sleep(for: latency)
        try require(.companyProfileManage, session, query: "company.paymentLink.update")

        let normalised = try OnlinePaymentLink.normalise(url ?? "")
        guard let index = store.companies.firstIndex(where: { $0.id == session.companyID }) else {
            throw DataError.notFound
        }
        store.companies[index].onlinePaymentLinkURL = normalised

        record(
            "company.paymentLink.update",
            session,
            allowed: true,
            normalised == nil
                ? "Payment link cleared — customers are shown no payment button"
                : "Payment link set to \(OnlinePaymentLink.displayHost(normalised) ?? "—") — stored as a URL, nothing connected"
        )
    }

    func invoiceSharing(session: TenantSession, invoiceID: String) async throws -> InvoiceSharing {
        try await Task.sleep(for: latency)
        let invoice = try requireVisibleInvoice(invoiceID, session, query: "invoices.sharing")
        let contact = billingContact(invoice.customerID, session)
        let blocked = Self.sharingBlockedReason(for: invoice)

        let token = store.invoiceShareTokens.first {
            $0.invoiceID == invoice.id && $0.companyID == session.companyID && $0.isActive
        }

        let deliveries = store.notifications
            .filter { $0.invoiceID == invoice.id && $0.companyID == session.companyID }
            .sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }
            .map(Self.deliveryProjection)

        let stored = company(session)?.onlinePaymentLinkURL

        return InvoiceSharing(
            shareURL: token.map { "https://simulated.invalid/i?t=\($0.token)" },
            canShare: blocked == nil,
            blockedReason: blocked,
            canSend: session.can(.invoicesManage),
            emailRecipient: contact?.email,
            smsRecipient: contact?.phone,
            paymentLink: PaymentLinkSettings(
                url: stored,
                displayHost: OnlinePaymentLink.displayHost(stored),
                canManage: session.can(.companyProfileManage)
            ),
            deliveries: deliveries,
            isSimulated: true
        )
    }

    func issueInvoiceShareLink(session: TenantSession, invoiceID: String, rotate: Bool) async throws -> String {
        try await Task.sleep(for: latency)
        try require(.invoicesManage, session, query: "invoices.share.issue")
        let invoice = try requireVisibleInvoice(invoiceID, session, query: "invoices.share.issue")

        if let blocked = Self.sharingBlockedReason(for: invoice) {
            throw DataError.rejected(blocked)
        }

        if rotate {
            revokeTokens(invoiceID: invoice.id, session: session)
        } else if let existing = store.invoiceShareTokens.first(where: {
            $0.invoiceID == invoice.id && $0.companyID == session.companyID && $0.isActive
        }) {
            return "https://simulated.invalid/i?t=\(existing.token)"
        }

        let token = Self.randomToken()
        store.invoiceShareTokens.append(
            InvoiceShareToken(
                id: "ist_\(UUID().uuidString.prefix(8))",
                companyID: session.companyID,
                invoiceID: invoice.id,
                token: token,
                createdByUserID: session.userID,
                createdAt: Date(),
                revokedAt: nil,
                lastViewedAt: nil,
                viewCount: 0
            )
        )

        record(
            "invoices.share.issue",
            session,
            allowed: true,
            rotate
                ? "Previous link revoked, new random token issued for \(invoice.number)"
                : "Random token issued for \(invoice.number) — the URL carries no identifier"
        )

        return "https://simulated.invalid/i?t=\(token)"
    }

    func revokeInvoiceShareLink(session: TenantSession, invoiceID: String) async throws {
        try await Task.sleep(for: latency)
        try require(.invoicesManage, session, query: "invoices.share.revoke")
        let invoice = try requireVisibleInvoice(invoiceID, session, query: "invoices.share.revoke")

        revokeTokens(invoiceID: invoice.id, session: session)
        record("invoices.share.revoke", session, allowed: true, "Every live link for \(invoice.number) stopped working")
    }

    func sendInvoice(
        session: TenantSession,
        invoiceID: String,
        channels: Set<NotificationChannel>
    ) async throws -> InvoiceSendOutcome {
        try await Task.sleep(for: latency)
        try require(.invoicesManage, session, query: "invoices.send")
        let invoice = try requireVisibleInvoice(invoiceID, session, query: "invoices.send")

        if let blocked = Self.sharingBlockedReason(for: invoice) {
            throw DataError.rejected(blocked)
        }

        let wanted = [NotificationChannel.email, .sms].filter { channels.contains($0) }
        guard !wanted.isEmpty else { throw DataError.rejected("Choose email, SMS or both.") }

        let contact = billingContact(invoice.customerID, session)
        var results: [InvoiceSendResult] = []

        for channel in wanted {
            let recipient = channel == .email ? contact?.email : contact?.phone
            guard let recipient, !recipient.isEmpty else {
                throw DataError.rejected(
                    channel == .email
                        ? "There's no email address for this invoice's billing contact."
                        : "There's no mobile number for this invoice's billing contact."
                )
            }

            // DEVELOPMENT: nothing leaves the device, so the attempt is recorded
            // as failed. It is never recorded as sent.
            let reason = "Development build — no message was delivered."
            store.notifications.append(
                AppNotification(
                    id: "ntf_\(UUID().uuidString.prefix(8))",
                    companyID: session.companyID,
                    channel: channel,
                    template: "invoice.share",
                    recipient: recipient,
                    jobID: nil,
                    customerID: invoice.customerID,
                    invoiceID: invoice.id,
                    status: .failed,
                    providerReference: nil,
                    sentAt: Date(),
                    deliveredAt: nil,
                    failureReason: reason
                )
            )

            results.append(
                InvoiceSendResult(
                    channel: channel,
                    recipient: recipient,
                    delivered: false,
                    providerConfigured: false,
                    detail: reason
                )
            )
        }

        record(
            "invoices.send",
            session,
            allowed: true,
            "\(results.count) attempt(s) recorded against \(invoice.number) — all failed, nothing was delivered"
        )

        return InvoiceSendOutcome(results: results)
    }

    private func revokeTokens(invoiceID: String, session: TenantSession) {
        for index in store.invoiceShareTokens.indices
        where store.invoiceShareTokens[index].invoiceID == invoiceID
            && store.invoiceShareTokens[index].companyID == session.companyID
            && store.invoiceShareTokens[index].isActive {
            store.invoiceShareTokens[index].revokedAt = Date()
        }
    }

    private static func randomToken() -> String {
        let halves = [UUID().uuidString, UUID().uuidString]
            .map { $0.replacingOccurrences(of: "-", with: "").lowercased() }
        return halves.joined()
    }

    /// A draft is not a document the customer should see, and a voided one is
    /// not a document at all.
    private static func sharingBlockedReason(for invoice: Invoice) -> String? {
        switch invoice.status {
        case .draft:
            return "Move \(invoice.number) out of draft before sharing it with the customer."
        case .void:
            return "\(invoice.number) has been voided and can't be shared."
        default:
            return nil
        }
    }

    // MARK: - Push notifications

    func registerPushDevice(session: TenantSession, registration: PushDeviceRegistration) async throws -> String {
        try await Task.sleep(for: latency)

        // Tenancy is never taken from the caller's payload, exactly as the
        // database does it: company and user come from the session.
        guard let index = store.pushDevices.firstIndex(where: { $0.token == registration.token }) else {
            let device = PushDeviceRecord(
                id: "pdv_\(UUID().uuidString.prefix(8))",
                companyID: session.companyID,
                userID: session.userID,
                token: registration.token,
                environment: registration.environment,
                appVersion: registration.appVersion,
                deviceModel: registration.deviceModel,
                lastRegisteredAt: Date(),
                revokedAt: nil,
                revokedReason: nil
            )
            store.pushDevices.append(device)
            record("push.register", session, allowed: true, "Device \(device.masked) registered to \(session.displayName)")
            return device.id
        }

        // A handset passed to another engineer takes the token with it. The row
        // moves to whoever is signed in now, so the previous holder stops
        // receiving alerts on a device they no longer have.
        let moved = store.pushDevices[index].userID != session.userID
        let existingID = store.pushDevices[index].id
        store.pushDevices[index] = PushDeviceRecord(
            id: existingID,
            companyID: session.companyID,
            userID: session.userID,
            token: registration.token,
            environment: registration.environment,
            appVersion: registration.appVersion,
            deviceModel: registration.deviceModel,
            lastRegisteredAt: Date(),
            revokedAt: nil,
            revokedReason: nil
        )
        record(
            "push.register",
            session,
            allowed: true,
            moved
                ? "Device re-registered to \(session.displayName) \u{2014} the previous holder no longer receives its alerts"
                : "Device registration refreshed for \(session.displayName)"
        )
        return existingID
    }

    func unregisterPushDevice(session: TenantSession, token: String) async throws -> Bool {
        try await Task.sleep(for: latency)

        guard let index = store.pushDevices.firstIndex(where: {
            $0.token == token && $0.userID == session.userID && $0.revokedAt == nil
        }) else {
            record("push.unregister", session, allowed: true, "No live registration for this device")
            return false
        }

        store.pushDevices[index].revokedAt = Date()
        store.pushDevices[index].revokedReason = "Signed out on this device"
        record("push.unregister", session, allowed: true, "Device registration removed on sign-out")
        return true
    }

    func pushInbox(session: TenantSession, limit: Int) async throws -> [PushNotificationRecord] {
        try await Task.sleep(for: latency)

        // Tenant gate then addressee gate: a person only ever reads what was
        // addressed to them, and never across companies.
        let rows = store.notifications
            .filter {
                $0.companyID == session.companyID
                    && $0.channel == .push
                    && $0.targetUserID == session.userID
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(max(1, min(limit, 100)))

        record("push.inbox", session, allowed: true, "\(rows.count) notification(s) addressed to \(session.displayName)")
        return rows.map(Self.pushRecord)
    }

    private static func pushRecord(_ notification: AppNotification) -> PushNotificationRecord {
        PushNotificationRecord(
            id: notification.id,
            event: notification.template,
            title: notification.title ?? PushEvent(rawValue: notification.template)?.title ?? Brand.name,
            body: notification.body ?? "",
            status: notification.status,
            jobID: notification.jobID,
            deepLink: notification.deepLink,
            failureReason: notification.failureReason,
            createdAt: notification.createdAt,
            sentAt: notification.sentAt
        )
    }

    /// The one place a push notification is written, mirroring the database
    /// trigger exactly.
    ///
    /// Every rule that matters lives here rather than at the call sites, so the
    /// same event raised from dispatch and from a job screen cannot diverge:
    ///
    /// * nobody is told about their own action;
    /// * the addressee must be an active member of the same company;
    /// * an engineer is only ever told about a job they are actually on;
    /// * one row per live device, and an honest failed row when there is none.
    @discardableResult
    private func enqueuePush(
        session: TenantSession,
        to userID: String?,
        event: PushEvent,
        title: String,
        body: String,
        jobID: String?,
        customerID: String?
    ) -> Int {
        guard let userID, userID != session.userID else { return 0 }

        guard let target = store.users.first(where: {
            $0.id == userID && $0.companyID == session.companyID && $0.status == .active
        }) else { return 0 }

        // Assignment gate. `jobUnassigned` is the deliberate exception: it is
        // the event that says the assignment has just been taken away.
        if let jobID, event != .jobUnassigned,
           PermissionMatrix.can(target.role, .jobsReadAssignedOnly),
           !store.assignments.contains(where: { $0.jobID == jobID && $0.userID == userID }) {
            return 0
        }

        let link = jobID.map { "tradedesk://job/\($0)" } ?? "tradedesk://jobs"
        let devices = store.pushDevices.filter {
            $0.userID == userID && $0.companyID == session.companyID && $0.isLive
        }

        guard !devices.isEmpty else {
            // No device: the event still happened, so it is recorded — as a
            // failure naming the reason, never as delivered.
            store.notifications.append(
                AppNotification(
                    id: "ntf_\(UUID().uuidString.prefix(8))",
                    companyID: session.companyID,
                    channel: .push,
                    template: event.rawValue,
                    recipient: "no registered device",
                    jobID: jobID,
                    customerID: customerID,
                    invoiceID: nil,
                    status: .failed,
                    providerReference: nil,
                    sentAt: nil,
                    deliveredAt: nil,
                    failureReason: "No device registered for push notifications.",
                    targetUserID: userID,
                    pushDeviceID: nil,
                    title: title,
                    body: body,
                    deepLink: link
                )
            )
            return 0
        }

        for device in devices {
            store.notifications.append(
                AppNotification(
                    id: "ntf_\(UUID().uuidString.prefix(8))",
                    companyID: session.companyID,
                    channel: .push,
                    template: event.rawValue,
                    recipient: "ios \(device.token.suffix(6))",
                    jobID: jobID,
                    customerID: customerID,
                    invoiceID: nil,
                    // Queued, not sent. Only a real APNs acceptance makes it sent.
                    status: .queued,
                    providerReference: nil,
                    sentAt: nil,
                    deliveredAt: nil,
                    failureReason: nil,
                    targetUserID: userID,
                    pushDeviceID: device.id,
                    title: title,
                    body: body,
                    deepLink: link
                )
            )
        }
        return devices.count
    }

    /// Office staff entitled to hear about operational change, chosen by
    /// permission rather than by a hardcoded list of roles.
    private func officeRecipients(_ session: TenantSession, _ permission: Permission) -> [String] {
        store.users
            .filter {
                $0.companyID == session.companyID
                    && $0.status == .active
                    && PermissionMatrix.can($0.role, permission)
            }
            .map(\.id)
    }

    private func pushJobLabel(_ job: Job) -> String {
        "\(job.number) · \(job.title)"
    }

    private func pushWhenLabel(_ start: Date?) -> String {
        start.map { Formatters.dayAndTime($0) } ?? "not yet scheduled"
    }

    private static func deliveryProjection(_ notification: AppNotification) -> InvoiceDeliveryProjection {
        InvoiceDeliveryProjection(
            id: notification.id,
            channel: notification.channel,
            channelTitle: notification.channel.title,
            channelSymbol: notification.channel == .email ? "envelope.fill" : "message.fill",
            recipient: notification.recipient,
            status: notification.status,
            statusTitle: notification.status.title,
            statusTone: Self.tone(for: notification.status),
            timeLabel: notification.sentAt.map { Formatters.shortDayAndTime($0) } ?? "Not sent",
            failureReason: notification.failureReason
        )
    }

    private static func tone(for status: NotificationStatus) -> StatusTone {
        switch status {
        case .queued: return .warning
        case .sent: return .info
        case .delivered: return .success
        case .failed: return .danger
        }
    }

    // MARK: - Office messaging

    /// Mirrors the `office_threads_select` policy:
    /// `company_id = current_company_id() AND (engineer_user_id = auth.uid() OR is_office_user())`.
    ///
    /// The development stack used to refuse messaging outright, which meant no
    /// automated test could reach the conversation screen — and a broken "Open"
    /// button on a job-linked message survived two shipped builds as a result.
    private func isOfficeUser(_ session: TenantSession) -> Bool {
        session.can(.assignmentsManage) || session.can(.usersManage)
    }

    private func readableThreads(_ session: TenantSession) -> [DevOfficeThread] {
        scoped(store.officeThreads, session, companyID: \.companyID)
            .filter { isOfficeUser(session) || $0.engineerUserID == session.userID }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    private func lastReadAt(_ thread: DevOfficeThread, _ session: TenantSession) -> Date? {
        isOfficeUser(session) ? thread.lastReadByOfficeAt : thread.lastReadByEngineerAt
    }

    func officeInbox(session: TenantSession) async throws -> OfficeInbox {
        try await Task.sleep(for: latency)

        let threads = readableThreads(session)
        let rows: [OfficeThreadRow] = threads.map { thread in
            let messages = store.officeMessages
                .filter { $0.threadID == thread.id }
                .sorted { $0.createdAt < $1.createdAt }
            let last = messages.last

            // Unread means somebody else has written since this person last
            // looked. Your own message never marks your own thread unread.
            let isUnread: Bool = {
                guard let last, last.senderUserID != session.userID else { return false }
                guard let seenAt = lastReadAt(thread, session) else { return true }
                return last.createdAt > seenAt
            }()

            let counterparty: String = isOfficeUser(session)
                ? (user(thread.engineerUserID, session)?.name ?? "Field worker")
                : "Office"

            return OfficeThreadRow(
                id: thread.id,
                subject: thread.subject,
                preview: last?.body ?? "",
                timeLabel: Formatters.shortDayAndTime(thread.lastMessageAt),
                lastMessageAt: thread.lastMessageAt,
                counterpartyName: counterparty,
                jobID: thread.jobID,
                jobNumber: thread.jobID.flatMap { id in
                    store.jobs.first { $0.id == id && $0.companyID == session.companyID }?.number
                },
                customerName: thread.customerID.flatMap { customer($0, session)?.name },
                isUnread: isUnread
            )
        }

        record(
            "engineer.officeInbox",
            session,
            allowed: true,
            isOfficeUser(session)
                ? "Office role reads every thread in the company"
                : "Field worker reads only their own threads"
        )

        return OfficeInbox(
            threads: rows,
            unreadCount: rows.filter(\.isUnread).count,
            isAvailable: true,
            unavailableReason: nil
        )
    }

    func officeConversation(session: TenantSession, threadID: String) async throws -> OfficeConversation {
        try await Task.sleep(for: latency)

        // A thread the caller may not read answers `notFound` rather than
        // "forbidden", so its existence never leaks.
        guard let thread = readableThreads(session).first(where: { $0.id == threadID }) else {
            record("engineer.officeConversation", session, allowed: false, "Thread not readable by this caller")
            throw DataError.notFound
        }

        let references: [String: String] = Dictionary(
            uniqueKeysWithValues: scoped(store.jobPhotos, session, companyID: \.companyID)
                .map { ($0.id, $0.storageReference) }
        )

        let messages = store.officeMessages
            .filter { $0.threadID == thread.id && $0.companyID == session.companyID }
            .sorted { $0.createdAt < $1.createdAt }
            .map { message -> OfficeMessageRow in
                let isMine = message.senderUserID == session.userID
                let senderName = user(message.senderUserID, session)?.name ?? "Office"
                return OfficeMessageRow(
                    id: message.id,
                    body: message.body,
                    senderName: isMine ? "You" : senderName,
                    senderInitials: Self.initials(senderName),
                    timeLabel: Formatters.shortDayAndTime(message.createdAt),
                    isMine: isMine,
                    photoReferences: message.jobPhotoIDs.compactMap { references[$0] }
                )
            }

        record("engineer.officeConversation", session, allowed: true, "Thread read with \(messages.count) message(s)")

        return OfficeConversation(
            id: thread.id,
            subject: thread.subject,
            jobID: thread.jobID,
            jobNumber: thread.jobID.flatMap { id in
                store.jobs.first { $0.id == id && $0.companyID == session.companyID }?.number
            },
            customerName: thread.customerID.flatMap { customer($0, session)?.name },
            messages: messages,
            canReply: true
        )
    }

    @discardableResult
    func sendOfficeMessage(session: TenantSession, draft: OfficeMessageDraft) async throws -> String {
        try await Task.sleep(for: latency)

        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        // A message must say something — in words, in pictures, or both. A
        // photograph of a failed part IS the message.
        guard !body.isEmpty || !draft.photoIDs.isEmpty else {
            throw DataError.rejected("Write a message or attach a photo.")
        }

        let threadID: String
        var threadJobID: String?
        if let existing = draft.threadID {
            guard let thread = readableThreads(session).first(where: { $0.id == existing }) else {
                throw DataError.notFound
            }
            threadID = thread.id
            threadJobID = thread.jobID
        } else {
            // A new thread always belongs to a field worker: either the sender,
            // or — when the office starts it — the worker on the job.
            let job = draft.jobID.flatMap { id in
                store.jobs.first { $0.id == id && $0.companyID == session.companyID }
            }
            let engineerID: String = isOfficeUser(session)
                ? (draft.jobID.flatMap { primaryAssignment($0, session)?.userID } ?? session.userID)
                : session.userID

            let new = DevOfficeThread(
                id: "thr_\(UUID().uuidString.prefix(8))",
                companyID: session.companyID,
                engineerUserID: engineerID,
                subject: draft.subject.trimmingCharacters(in: .whitespaces).nilIfEmpty
                    ?? job?.title
                    ?? "Message",
                jobID: draft.jobID,
                customerID: job?.customerID,
                lastMessageAt: Date(),
                lastReadByEngineerAt: nil,
                lastReadByOfficeAt: nil
            )
            store.officeThreads.append(new)
            threadID = new.id
            threadJobID = new.jobID
        }

        // Attachments are validated as a set, mirroring `send_office_message`.
        // Silently dropping one would tell the sender their photo went when it
        // did not; silently keeping an unrelated one would be a leak. Either
        // every id checks out or the whole message is refused.
        if !draft.photoIDs.isEmpty {
            let valid = draft.photoIDs.allSatisfy { id in
                guard let photo = store.jobPhotos.first(where: { $0.id == id }) else { return false }
                return photo.companyID == session.companyID
                    && photo.userID == session.userID
                    && photo.jobID == threadJobID
                    && (photo.threadID == nil || photo.threadID == threadID)
            }
            guard valid else {
                record("engineer.sendOfficeMessage", session, allowed: false, "Refused — an attachment did not belong to this conversation")
                throw DataError.rejected("One of those photos could not be attached to this conversation.")
            }

            // Stamp the conversation onto images uploaded before it existed,
            // which is the normal case when a message opens a new thread.
            for index in store.jobPhotos.indices where draft.photoIDs.contains(store.jobPhotos[index].id) {
                if store.jobPhotos[index].threadID == nil {
                    store.jobPhotos[index].threadID = threadID
                }
            }
        }

        store.officeMessages.append(
            DevOfficeMessage(
                id: "omsg_\(UUID().uuidString.prefix(8))",
                companyID: session.companyID,
                threadID: threadID,
                senderUserID: session.userID,
                body: body,
                jobPhotoIDs: draft.photoIDs,
                createdAt: Date()
            )
        )

        if let index = store.officeThreads.firstIndex(where: { $0.id == threadID }) {
            store.officeThreads[index].lastMessageAt = Date()
            // The sender has, by definition, read their own message.
            if isOfficeUser(session) {
                store.officeThreads[index].lastReadByOfficeAt = Date()
            } else {
                store.officeThreads[index].lastReadByEngineerAt = Date()
            }
        }

        record("engineer.sendOfficeMessage", session, allowed: true, "Message posted to thread \(threadID)")
        return threadID
    }

    func markOfficeThreadRead(session: TenantSession, threadID: String) async throws {
        guard let index = store.officeThreads.firstIndex(where: {
            $0.id == threadID && $0.companyID == session.companyID
        }) else { return }

        if isOfficeUser(session) {
            store.officeThreads[index].lastReadByOfficeAt = Date()
        } else if store.officeThreads[index].engineerUserID == session.userID {
            store.officeThreads[index].lastReadByEngineerAt = Date()
        }
    }

    // MARK: - Subscription

    /// The seeded company's plans and roster counts, so the Subscription
    /// screen renders its real layout on the development stack.
    func subscriptionOverview(session: TenantSession) async throws -> SubscriptionOverview {
        try await Task.sleep(for: latency)
        guard session.can(.saasBillingRead) else {
            record("subscription.overview", session, allowed: false, "Blocked — missing saasBillingRead")
            throw DataError.notPermitted(.saasBillingRead)
        }

        let people = scoped(store.users, session, companyID: \.companyID)
        record("subscription.overview", session, allowed: true, "Development plans — the standard price list")

        return SubscriptionOverview(
            plans: PlanCatalog.standard,
            pricesAreLive: false,
            canManage: session.can(.saasBillingManage),
            activeUsers: people.filter { $0.status == .active }.count,
            invitedUsers: people.filter { $0.status == .invited }.count,
            suspendedUsers: people.filter { $0.status == .suspended }.count
        )
    }

    /// Stripe's view of the company's own account.
    ///
    /// Reported as `ready` for Gulf Coast so the screens that depend on a
    /// connected account render their real layout. Nothing here can move money.
    func connectAccountStatus(session: TenantSession) async throws -> ConnectAccountStatus {
        try await Task.sleep(for: latency)
        guard session.can(.paymentsRead) || session.can(.saasBillingRead) else {
            record("payments.connect.status", session, allowed: false, "Blocked — missing paymentsRead")
            throw DataError.notPermitted(.paymentsRead)
        }

        let link = company(session)?.onlinePaymentLinkURL
        let connected = Self.developmentStripeConnected(session.companyID)
        record("payments.connect.status", session, allowed: true, "Development Stripe position — no live account behind it")

        return ConnectAccountStatus(
            readiness: connected ? .ready : .notConnected,
            accountID: connected ? "acct_development" : nil,
            chargesEnabled: connected,
            payoutsEnabled: connected,
            detailsSubmitted: connected,
            requirementsDue: [],
            disabledReason: nil,
            canManage: session.can(.paymentsManage) || session.can(.saasBillingManage),
            fallbackLink: PaymentLinkSettings(
                url: link,
                displayHost: link.flatMap { URL(string: $0)?.host },
                canManage: session.can(.paymentsManage)
            )
        )
    }

    // MARK: - Commercial position

    /// Which seeded company has a connected Stripe account. Northline has not
    /// connected, so the "Set up Stripe" path is the one it sees.
    private static func developmentStripeConnected(_ companyID: String) -> Bool {
        companyID == "cmp_gulfcoast"
    }

    /// The seeded company's commercial position.
    ///
    /// Gulf Coast holds an active Team plan (annual) with Stripe connected;
    /// Northline has no plan and has not connected Stripe, so both the
    /// subscribed and the choose-a-plan paths are exercised. Every company is
    /// on the same commercial model — nothing here is a programme benefit.
    func commercialState(session: TenantSession) async throws -> CommercialState {
        try await Task.sleep(for: latency)
        guard session.can(.saasBillingRead) else {
            record("commercial.state", session, allowed: false, "Blocked — missing saasBillingRead")
            throw DataError.notPermitted(.saasBillingRead)
        }

        let people = scoped(store.users, session, companyID: \.companyID)
        let active = people.filter { $0.status == .active }.count
        let invited = people.filter { $0.status == .invited }.count
        let connected = Self.developmentStripeConnected(session.companyID)
        let subscribed = session.companyID == "cmp_gulfcoast"
        let team = PlanCatalog.standard.first { $0.id == .team }

        record("commercial.state", session, allowed: true, "Development commercial position — seeded, not a live Apple or Stripe account")

        return CommercialState(
            paymentModel: connected ? .harbourSouthPayments : .undecided,
            entitlementState: subscribed ? .active : .none,
            planID: subscribed ? .team : nil,
            planName: subscribed ? team?.displayName : nil,
            billingPeriod: subscribed ? .annual : nil,
            planPriceCents: subscribed ? (team?.annualCents ?? 0) : 0,
            userLimit: subscribed ? team?.userLimit : 1,
            includedUsers: subscribed ? (team?.includedUsers ?? 5) : 1,
            activeUsers: active,
            openInvitations: invited,
            canAddUser: true,
            seatLimitsEnforced: false,
            periodEndsAt: subscribed ? Date(timeIntervalSinceNow: 60 * 60 * 24 * 200) : nil,
            willAutoRenew: subscribed ? true : nil,
            renewsToPlanID: subscribed ? .team : nil,
            renewsToPeriod: subscribed ? .annual : nil,
            billingStore: subscribed ? .apple : .none,
            stripeConnected: connected,
            chargesEnabled: connected,
            payoutsEnabled: connected,
            detailsSubmitted: connected,
            requirementsDue: [],
            disabledReason: nil,
            stripeAccountID: connected ? "acct_development" : nil,
            platformFeeBps: 30,
            externalPaymentURL: company(session)?.onlinePaymentLinkURL,
            businessEmail: nil,
            canManageBilling: session.can(.saasBillingManage)
        )
    }

    // MARK: - Job media

    /// Stores a captured image against a job.
    ///
    /// The development stack has no object storage, so the bytes are held with
    /// the record as a `data:` reference — the same path the production gateway
    /// falls back to when a project has no media bucket. The image therefore
    /// renders for real rather than showing a placeholder, which is what makes
    /// photo evidence testable here at all.
    func attachJobMedia(
        session: TenantSession,
        jobID: String,
        upload: JobMediaUpload
    ) async throws -> JobMediaResult {
        try await Task.sleep(for: latency)
        try require(.jobPhotosCreate, session, query: "jobs.attachMedia")

        guard let job = store.jobs.first(where: { $0.id == jobID && $0.companyID == session.companyID }) else {
            throw DataError.notFound
        }
        // A field worker may only add evidence to their own work.
        if session.can(.jobsReadAssignedOnly), !session.can(.jobsReadAll),
           !assignedJobIDs(session).contains(job.id) {
            record("jobs.attachMedia", session, allowed: false, "Job is not assigned to this field worker")
            throw DataError.notFound
        }
        guard !upload.data.isEmpty else {
            return JobMediaResult(id: upload.id, kindTitle: upload.kind.title, stored: false, detail: "Empty image.")
        }

        let caption = upload.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        store.jobPhotos.append(
            JobPhoto(
                id: upload.id.uuidString,
                companyID: session.companyID,
                jobID: job.id,
                userID: session.userID,
                storageReference: JobMediaReference.inline(upload.data, mimeType: upload.mimeType),
                caption: caption.isEmpty ? nil : caption,
                kind: upload.kind,
                capturedAt: Date()
            )
        )

        record("jobs.attachMedia", session, allowed: true, "\(upload.kind.title) image stored with the job record")
        return JobMediaResult(
            id: upload.id,
            kindTitle: upload.kind.title,
            stored: true,
            detail: "Stored with the job record (\(upload.sizeLabel))"
        )
    }

    /// Stores an image sent in a conversation.
    ///
    /// This mirrors the production rule exactly, because the rule is the
    /// feature: a job conversation produces ONE row carrying both the job and
    /// the thread, so the picture is the message attachment and the job's
    /// evidence at the same time. A general conversation produces a row with no
    /// job at all, which is precisely what migration 0011 makes possible.
    func attachMessageMedia(
        session: TenantSession,
        threadID: String,
        jobID: String?,
        upload: JobMediaUpload
    ) async throws -> JobMediaResult {
        try await Task.sleep(for: latency)
        try require(.jobPhotosCreate, session, query: "messages.attachMedia")

        // The conversation has to be one this caller may actually post in.
        guard let thread = readableThreads(session).first(where: { $0.id == threadID }) else {
            record("messages.attachMedia", session, allowed: false, "Thread not readable by this caller")
            throw DataError.notFound
        }

        // The job is taken from the thread, never from the caller. A forged job
        // id cannot file an image against somebody else's work.
        let resolvedJobID = thread.jobID
        if let resolvedJobID, session.can(.jobsReadAssignedOnly), !session.can(.jobsReadAll),
           !assignedJobIDs(session).contains(resolvedJobID) {
            record("messages.attachMedia", session, allowed: false, "Job is not assigned to this field worker")
            throw DataError.notFound
        }

        guard !upload.data.isEmpty else {
            return JobMediaResult(id: upload.id, kindTitle: upload.kind.title, stored: false, detail: "Empty image.")
        }

        let caption = upload.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        store.jobPhotos.append(
            JobPhoto(
                id: upload.id.uuidString,
                companyID: session.companyID,
                jobID: resolvedJobID,
                userID: session.userID,
                storageReference: JobMediaReference.inline(upload.data, mimeType: upload.mimeType),
                caption: caption.isEmpty ? nil : caption,
                kind: upload.kind,
                capturedAt: Date(),
                threadID: thread.id
            )
        )

        record(
            "messages.attachMedia",
            session,
            allowed: true,
            resolvedJobID == nil
                ? "\(upload.kind.title) image attached to a general conversation"
                : "\(upload.kind.title) image attached to the conversation and filed as job evidence"
        )
        return JobMediaResult(
            id: upload.id,
            kindTitle: upload.kind.title,
            stored: true,
            detail: "Sent (\(upload.sizeLabel))"
        )
    }
}

nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
