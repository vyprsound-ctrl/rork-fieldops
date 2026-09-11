import Foundation
import Supabase

/// One site address, in whatever shape the caller's role was allowed to read it.
private nonisolated struct SiteAddress: Hashable, Sendable {
    let line1: String
    let city: String
    let state: String
    let postalCode: String
    let latitude: Double?
    let longitude: Double?
    let accessNotes: String?

    var singleLine: String { "\(line1), \(city) \(state) \(postalCode)" }
    var shortLine: String { line1 }
}

private nonisolated struct SiteCustomer: Hashable, Sendable {
    let name: String
    let type: CustomerType
}

private nonisolated struct SitePrimaryContact: Hashable, Sendable {
    let name: String
    let contactRole: String?
    let phone: String?
}

/// Everything a job projection needs beyond the job row itself, already narrowed
/// to what the database was willing to return for this caller.
///
/// Nothing here is a security decision: the rows are whatever RLS produced. The
/// dictionaries exist so a screen's worth of projections can be assembled from a
/// handful of requests instead of one per row.
private nonisolated struct JobReference: Sendable {
    var customers: [String: SiteCustomer] = [:]
    var addresses: [String: SiteAddress] = [:]
    /// Primary site contact, keyed by customer id.
    var contacts: [String: SitePrimaryContact] = [:]
    /// Job id → primary field worker's user id.
    var primaryWorkerByJob: [String: String] = [:]
    var users: [String: AppUserRecord] = [:]
    /// Job id → money label, only ever populated for permitted roles.
    var valueLabels: [String: String] = [:]
}

/// PRODUCTION IMPLEMENTATION of `DataGateway`, backed by Supabase.
///
/// The enforcement model is deliberately different from the development gateway:
/// nothing here decides which rows a caller may see. Every request is issued
/// with the caller's own JWT, and Row Level Security in PostgreSQL is the
/// boundary — the tenant gate (`company_id = current_company_id()`), the row gate
/// (`has_perm('jobsReadAll')` or `is_assigned_to_job(id)`) and the field gate
/// (money columns live on tables and views a role without financial permissions
/// simply cannot select) all live in the database.
///
/// The permission checks in this file are therefore *not* the security boundary.
/// They exist so the app fails the same way it does in development — a clear
/// `notPermitted` instead of a silently empty screen — and so a payload that
/// carries money is never even requested for a role that shouldn't have it.
///
/// Writes follow the same model. A single-table write is an ordinary insert or
/// update, governed by the policy on that table. Anything spanning rows or
/// carrying a workflow rule is one call to a database function that performs the
/// whole change in a single transaction, so a half-finished write — a job
/// without its history row, a payment without a re-derived balance — is not
/// expressible. Those functions run as the caller, so RLS applies inside them
/// too. See `SupabaseDataGateway+Writes.swift`.
actor SupabaseDataGateway: DataGateway {
    let client: SupabaseClient
    private var decisions: [AccessDecision] = []
    private var companyCache: [String: CompanyRecord] = [:]

    /// Used when an address has no recorded position, matching the development
    /// gateway so a map never opens on null island.
    private static let fallbackLatitude: Double = 27.9506
    private static let fallbackLongitude: Double = -82.4572

    init(client: SupabaseClient) {
        self.client = client
    }

    /// `nil` when the build has no Supabase coordinates.
    static func make() -> SupabaseDataGateway? {
        guard let client = SupabaseClientProvider.shared else { return nil }
        return SupabaseDataGateway(client: client)
    }

    // MARK: - Access record

    func record(_ query: String, _ session: TenantSession, allowed: Bool, _ detail: String) {
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

    /// Refuses before the request is even issued. RLS would refuse too — this
    /// only makes the refusal legible instead of an empty list.
    func require(_ permission: Permission, _ session: TenantSession, query: String) throws {
        guard session.can(permission) else {
            record(query, session, allowed: false, "Blocked before the request — missing \(permission.rawValue)")
            throw DataError.notPermitted(permission)
        }
    }

    // MARK: - Transport

    func fetch<T: Decodable & Sendable>(_ type: T.Type, _ builder: PostgrestBuilder) async throws -> [T] {
        do {
            let response: PostgrestResponse<Void> = try await builder.execute()
            return try SupabaseCoding.decoder.decode([T].self, from: response.data)
        } catch let error as DecodingError {
            print("[data] could not decode \(T.self): \(Self.describe(error))")
            throw DataError.unexpected(
                "This screen couldn't read \(T.self) from the server. Nothing was changed."
            )
        } catch {
            throw Self.translate(error)
        }
    }

    /// Names the offending field instead of printing an opaque dump, so a
    /// contract drift between this build and the database is diagnosable from
    /// a single log line rather than a debugger session.
    nonisolated static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let parts = context.codingPath.map(\.stringValue)
            return parts.isEmpty ? "(root)" : parts.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "missing field '\(key.stringValue)' at \(path(context)) — the select list is narrower than the type"
        case .typeMismatch(let type, let context):
            return "field at \(path(context)) is not \(type)"
        case .valueNotFound(let type, let context):
            return "field at \(path(context)) was null but \(type) is not optional"
        case .dataCorrupted(let context):
            return "unreadable value at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }

    /// Calls a database function with the caller's own JWT.
    func perform(_ name: String, _ params: [String: AnyJSON]) async throws {
        _ = try await performReturningData(name, params)
    }

    /// Calls a database function that returns the id of the row it created.
    func performReturningID(_ name: String, _ params: [String: AnyJSON]) async throws -> String {
        let data = try await performReturningData(name, params)
        guard let id = try? SupabaseCoding.decoder.decode(String.self, from: data), !id.isEmpty else {
            throw DataError.unexpected("The change was saved but the server didn't identify the new record.")
        }
        return id
    }

    private func performReturningData(_ name: String, _ params: [String: AnyJSON]) async throws -> Data {
        do {
            let response: PostgrestResponse<Void> = try await client.rpc(name, params: params).execute()
            return response.data
        } catch {
            throw Self.translateWrite(error)
        }
    }

    /// Executes a direct insert or update, mapping a policy refusal onto a
    /// `DataError` rather than a raw database message.
    func performWrite(_ builder: PostgrestBuilder) async throws {
        do {
            let _: PostgrestResponse<Void> = try await builder.execute()
        } catch {
            throw Self.translateWrite(error)
        }
    }

    /// Maps the database's own refusal onto `DataError`, so a rule expressed in
    /// SQL reaches the person using the app as the same sentence the
    /// development gateway would have shown them.
    ///
    /// The codes are raised deliberately by the write functions; `42501` is
    /// PostgreSQL's own "insufficient privilege", which is what a row failing an
    /// RLS policy produces.
    private static func translateWrite(_ error: Error) -> DataError {
        guard let postgrest = error as? PostgrestError else { return translate(error) }

        switch postgrest.code {
        case "TD401":
            return .notPermitted(Permission(rawValue: postgrest.message) ?? .jobsManage)
        case "TD404":
            return .notFound
        case "TD409":
            let parts = postgrest.message.split(separator: "|").map(String.init)
            if parts.count == 2,
               let from = JobStatus(rawValue: parts[0]),
               let to = JobStatus(rawValue: parts[1]) {
                return .invalidTransition(from: from, to: to)
            }
            return .rejected("That isn't a step this job can take.")
        case "TD422":
            return .rejected(postgrest.message)
        case "42501":
            return .notPermitted(.jobsManage)
        case "23505":
            return .rejected("That record already exists.")
        case "23502", "23503", "23514", "22P02", "42703":
            // A payload the database could not accept: a missing required
            // column, a reference to a row that isn't there, a failed check, a
            // malformed value, or a column this build thinks exists and the
            // schema does not.
            //
            // These used to fall through to the transport branch and surface as
            // "Couldn't reach the server", which sent people into a retry loop
            // over a request that could never succeed. The detail is logged for
            // diagnosis; the sentence shown says what actually happened.
            print("[data] write rejected by the schema: \(postgrest.code ?? "-") \(postgrest.message) \(postgrest.detail ?? "")")
            return .rejected("The server wouldn't accept this record. Check the details and try again — if it keeps happening, this needs looking at.")
        default:
            print("[data] write refused: \(postgrest.code ?? "-") \(postgrest.message)")
            return translate(error)
        }
    }

    /// Maps a transport or API failure onto the sentence that actually
    /// describes it.
    ///
    /// The previous version funnelled everything it did not recognise into
    /// "Couldn't reach the server. Try again in a moment." That sentence is a
    /// lie for any deterministic failure — a missing function, a refused
    /// permission, a malformed payload — and it invites an endless Try Again
    /// loop over a request that can never succeed. Only a genuine transport
    /// fault is described as a connection problem now; everything else says
    /// what happened and whether retrying is worth anything.
    static func translate(_ error: Error) -> DataError {
        if let dataError = error as? DataError { return dataError }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .timedOut, .dataNotAllowed:
                return .offline
            default:
                print("[data] transport failure: \(urlError.code.rawValue) \(urlError.localizedDescription)")
                return .unexpected("The connection failed before the server answered.")
            }
        }

        if let decoding = error as? DecodingError {
            print("[data] could not decode response: \(describe(decoding))")
            return .unexpected("The server's answer didn't match what this version expects.")
        }

        if let postgrest = error as? PostgrestError {
            return translatePostgrest(postgrest)
        }

        let text = error.localizedDescription.lowercased()
        if text.contains("jwt") || text.contains("token is expired") {
            return .unexpected("Your session has expired. Sign in again.")
        }

        print("[data] request failed: \(error)")
        return .unexpected("Something went wrong talking to the server.")
    }

    /// A refusal the API itself expressed, named honestly.
    ///
    /// `PGRST202` is the one that caused the Create Job "Couldn't reach the
    /// server" loop: PostgREST answers 404 when no function matches the
    /// argument names it was sent, which is a build/database mismatch and is
    /// never fixed by pressing the button again.
    private static func translatePostgrest(_ error: PostgrestError) -> DataError {
        let code = error.code ?? "-"
        print("[data] api refused: \(code) \(error.message) \(error.detail ?? "")")

        switch code {
        case "PGRST202":
            return .unexpected(
                "This version of the app is asking the server for something it doesn't recognise. Updating the app should fix it."
            )
        case "PGRST301", "PGRST303":
            return .unexpected("Your session has expired. Sign in again.")
        case "42501":
            return .notPermitted(.jobsManage)
        case "42702", "42703", "42883":
            return .unexpected(
                "The server couldn't complete that request. This needs looking at rather than retrying."
            )
        default:
            if error.message.lowercased().contains("jwt") {
                return .unexpected("Your session has expired. Sign in again.")
            }
            return .unexpected("The server refused that request.")
        }
    }

    // MARK: - Company configuration

    func companyRecord(_ session: TenantSession) async throws -> CompanyRecord? {
        if let cached = companyCache[session.companyID] { return cached }
        let rows = try await fetch(
            CompanyRecord.self,
            client.from("companies")
                .select(CompanyRecord.columns)
                .eq("id", value: session.companyID)
                .limit(1)
        )
        if let row = rows.first { companyCache[session.companyID] = row }
        return rows.first
    }

    /// Drops the cached company row so the next read sees a change this app
    /// just made — the payment link, for instance.
    func invalidateCompanyCache(_ companyID: String) {
        companyCache[companyID] = nil
    }

    func currencyCode(_ session: TenantSession) async throws -> String {
        let code = try await companyRecord(session)?.currencyCode
        return code ?? Company.fallbackCurrencyCode
    }

    private func countryCode(_ session: TenantSession) async throws -> String {
        let code = try await companyRecord(session)?.countryCode
        return code ?? "US"
    }

    private nonisolated static func initials(of name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    // MARK: - Row loads

    /// Jobs, as RLS chose to return them.
    ///
    /// A field worker's policy answers with their assignments only; an office
    /// role's answers with the whole company. The permission check here mirrors
    /// that so a role with no job read permission gets a clear refusal.
    func jobRecords(_ session: TenantSession, query: String) async throws -> [Job] {
        guard session.can(.jobsReadAll) || session.can(.jobsReadAssignedOnly) else {
            record(query, session, allowed: false, "No job read permission")
            throw DataError.notPermitted(.jobsReadAll)
        }
        let rows = try await fetch(JobRecord.self, client.from("jobs").select(JobRecord.columns))
        record(
            query,
            session,
            allowed: true,
            session.can(.jobsReadAll)
                ? "\(rows.count) rows returned by RLS in company scope"
                : "\(rows.count) assigned rows returned by RLS"
        )
        return rows.map { $0.model(companyID: session.companyID) }
    }

    /// One job, or `notFound`.
    ///
    /// A row the caller may not see is indistinguishable from a row that does
    /// not exist, because RLS simply returns nothing — the record's existence
    /// never leaks.
    func requireJob(_ jobID: String, _ session: TenantSession, query: String) async throws -> Job {
        guard session.can(.jobsReadAll) || session.can(.jobsReadAssignedOnly) else {
            record(query, session, allowed: false, "No job read permission")
            throw DataError.notPermitted(.jobsReadAll)
        }
        guard UUID(uuidString: jobID) != nil else { throw DataError.notFound }
        let rows = try await fetch(
            JobRecord.self,
            client.from("jobs").select(JobRecord.columns).eq("id", value: jobID).limit(1)
        )
        guard let job = rows.first else {
            record(query, session, allowed: false, "Row outside scope — answered notFound")
            throw DataError.notFound
        }
        return job.model(companyID: session.companyID)
    }

    func users(ids: [String]) async throws -> [String: AppUserRecord] {
        guard !ids.isEmpty else { return [:] }
        let rows = try await fetch(
            AppUserRecord.self,
            client.from("app_users").select(AppUserRecord.columns).in("id", values: ids)
        )
        return Dictionary(rows.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Active field workers in the company. Empty without `usersRead`, which is
    /// also what the policy on `app_users` returns for such a role.
    private func fieldWorkers(_ session: TenantSession) async throws -> [AppUserRecord] {
        guard session.can(.usersRead) else { return [] }
        let rows = try await fetch(
            AppUserRecord.self,
            client.from("app_users")
                .select(AppUserRecord.columns)
                .eq("role", value: Role.fieldWorker.rawValue)
                .eq("status", value: UserStatus.active.rawValue)
        )
        return rows.sorted { $0.name < $1.name }
    }

    private func assignments(jobIDs: [String]) async throws -> [String: String] {
        guard !jobIDs.isEmpty else { return [:] }
        let rows = try await fetch(
            AssignmentRecord.self,
            client.from("field_worker_assignments")
                .select(AssignmentRecord.columns)
                .in("job_id", values: jobIDs)
        )
        var byJob: [String: String] = [:]
        for row in rows where row.isPrimary {
            byJob[row.jobID.uuidString] = row.userID.uuidString
        }
        return byJob
    }

    /// Reference data for a set of jobs.
    ///
    /// Which customer surface is used depends on the caller's role, because the
    /// two are genuinely different data: an office role reads the customer
    /// directory, while a field worker reads `assigned_site_customers`, a view
    /// that exposes the site of a job they are assigned to and carries no
    /// billing terms or customer notes at all.
    private func jobReference(
        for jobs: [Job],
        _ session: TenantSession,
        includeMoney: Bool = true
    ) async throws -> JobReference {
        var reference = JobReference()
        guard !jobs.isEmpty else { return reference }

        let customerIDs = Array(Set(jobs.map(\.customerID)))
        let addressIDs = Array(Set(jobs.map(\.addressID)))
        let jobIDs = jobs.map(\.id)

        if session.can(.customersReadAll) {
            let customers = try await fetch(
                CustomerRecord.self,
                client.from("customers").select(CustomerRecord.columns).in("id", values: customerIDs)
            )
            for row in customers {
                reference.customers[row.id.uuidString] = SiteCustomer(name: row.name, type: row.type)
            }

            let addresses = try await fetch(
                AddressRecord.self,
                client.from("addresses").select(AddressRecord.columns).in("id", values: addressIDs)
            )
            for row in addresses {
                reference.addresses[row.id.uuidString] = SiteAddress(
                    line1: row.line1,
                    city: row.city,
                    state: row.state,
                    postalCode: row.postalCode,
                    latitude: row.latitude,
                    longitude: row.longitude,
                    accessNotes: row.accessNotes
                )
            }
        } else if session.can(.customersReadAssignedSiteOnly) {
            let sites = try await fetch(
                AssignedSiteRecord.self,
                client.from("assigned_site_customers")
                    .select(AssignedSiteRecord.columns)
                    .in("id", values: customerIDs)
            )
            for row in sites {
                reference.customers[row.id.uuidString] = SiteCustomer(name: row.name, type: row.type)
                reference.addresses[row.addressID.uuidString] = SiteAddress(
                    line1: row.line1,
                    city: row.city,
                    state: row.state,
                    postalCode: row.postalCode,
                    latitude: row.latitude,
                    longitude: row.longitude,
                    accessNotes: row.accessNotes
                )
            }
            record(
                "jobs.site",
                session,
                allowed: true,
                "Assigned-site view used — \(sites.count) site(s), no directory and no billing fields"
            )
        }

        // The primary site contact, from the operational contact view. It has no
        // email and no billing flag, so a phone number for the doorstep is all
        // any role can obtain through it.
        let contacts = try await fetch(
            SiteContactRecord.self,
            client.from("site_contacts_operational")
                .select(SiteContactRecord.columns)
                .in("customer_id", values: customerIDs)
        )
        for row in contacts where reference.contacts[row.customerID.uuidString] == nil {
            reference.contacts[row.customerID.uuidString] = SitePrimaryContact(
                name: row.name,
                contactRole: row.contactRole,
                phone: row.phone
            )
        }

        reference.primaryWorkerByJob = try await assignments(jobIDs: jobIDs)
        reference.users = try await users(ids: Array(Set(reference.primaryWorkerByJob.values)))

        if includeMoney, session.can(.quoteFinancialsRead) {
            let quoteIDs = Array(Set(jobs.compactMap(\.quoteID)))
            if !quoteIDs.isEmpty {
                let quotes = try await fetch(
                    QuoteFinancialRecord.self,
                    client.from("quotes").select(QuoteFinancialRecord.columns).in("id", values: quoteIDs)
                )
                let code = try await currencyCode(session)
                let byID = Dictionary(quotes.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
                for job in jobs {
                    guard let quoteID = job.quoteID, let quote = byID[quoteID] else { continue }
                    reference.valueLabels[job.id] = Formatters.currency(
                        SupabaseCoding.decimal(quote.total),
                        code: code
                    )
                }
            }
        }

        if includeMoney, session.can(.invoicesRead) {
            record(
                "jobs.value.invoice",
                session,
                allowed: false,
                "Invoice money is not read in this phase — quote value only"
            )
        }

        return reference
    }

    // MARK: - Presentation

    private func badge(for status: JobStatus, _ session: TenantSession) -> StatusBadge {
        StatusBadge(text: status.title(session.terms), tone: status.tone)
    }

    private func jobRow(_ job: Job, _ session: TenantSession, _ reference: JobReference) -> JobRow {
        let workerID = reference.primaryWorkerByJob[job.id]
        let worker = workerID.flatMap { reference.users[$0] }
        return JobRow(
            id: job.id,
            number: job.number,
            title: job.title,
            timeLabel: job.scheduledStart.map { Formatters.time($0) } ?? "No slot",
            dayLabel: job.scheduledStart.map { Formatters.dayTitle($0) } ?? "Unscheduled",
            scheduledStart: job.scheduledStart,
            customerName: reference.customers[job.customerID]?.name ?? "Customer",
            addressShort: reference.addresses[job.addressID]?.shortLine ?? "",
            badge: badge(for: job.status, session),
            kindTitle: job.kind.title,
            kindSymbol: job.kind.symbolName,
            workerName: worker?.name,
            workerInitials: worker.map { Self.initials(of: $0.name) },
            isUrgent: job.priority == .urgent,
            isUnassigned: workerID == nil,
            value: reference.valueLabels[job.id],
            status: job.status
        )
    }

    private func equipmentProjections(ids: [String], _ session: TenantSession) async throws -> [String: EquipmentProjection] {
        guard session.can(.equipmentRead), !ids.isEmpty else { return [:] }

        let units = try await fetch(
            EquipmentRecord.self,
            client.from("equipment").select(EquipmentRecord.columns).in("id", values: ids)
        )
        guard !units.isEmpty else { return [:] }

        let history = try await fetch(
            EquipmentHistoryRecord.self,
            client.from("equipment_history")
                .select(EquipmentHistoryRecord.columns)
                .in("equipment_id", values: units.map { $0.id.uuidString })
        )
        let historyByEquipment = Dictionary(grouping: history, by: { $0.equipmentID.uuidString })

        var projections: [String: EquipmentProjection] = [:]
        for unit in units {
            let key = unit.id.uuidString
            let rows = (historyByEquipment[key] ?? [])
                .sorted { $0.occurredAt > $1.occurredAt }
                .map {
                    EquipmentHistoryRow(
                        id: $0.id.uuidString,
                        dateLabel: Formatters.monthYear($0.occurredAt),
                        summary: $0.summary
                    )
                }

            var warranty: String?
            if let expires = unit.warrantyExpiresOn {
                warranty = expires > Date()
                    ? "Warranty to \(Formatters.shortDate(expires))"
                    : "Warranty expired \(Formatters.shortDate(expires))"
            }

            let subtitle = unit.installedOn
                .map { "\(unit.category) · installed \($0.formatted(.dateTime.year()))" }
                ?? unit.category

            projections[key] = EquipmentProjection(
                id: key,
                displayName: unit.displayName,
                subtitle: subtitle,
                serialNumber: unit.serialNumber,
                warrantyLabel: warranty,
                attributes: unit.attributes.map { "\($0.name) · \($0.value)" },
                history: rows
            )
        }
        return projections
    }

    private func equipmentProjection(_ equipmentID: String?, _ session: TenantSession) async throws -> EquipmentProjection? {
        guard let equipmentID else { return nil }
        return try await equipmentProjections(ids: [equipmentID], session)[equipmentID]
    }

    private func timeline(_ jobID: String, _ session: TenantSession) async throws -> [JobTimelineEntry] {
        guard session.can(.jobStatusHistoryReadAll) || session.can(.jobStatusUpdateOwn) else { return [] }

        let rows = try await fetch(
            StatusHistoryRecord.self,
            client.from("job_status_history")
                .select(StatusHistoryRecord.columns)
                .eq("job_id", value: jobID)
        )
        let authors = try await users(ids: Array(Set(rows.compactMap { $0.changedByUserID?.uuidString })))
        let terms = session.terms

        return rows
            .sorted { $0.changedAt < $1.changedAt }
            .map { entry in
                let changedBy = entry.changedByUserID?.uuidString
                let author = changedBy.flatMap { authors[$0]?.name } ?? "System"

                var locationLabel: String?
                if let latitude = entry.latitude, let longitude = entry.longitude {
                    let maySee = session.can(.fieldWorkerLocationReadAll)
                        || (session.can(.fieldWorkerLocationReadOwnOnly) && changedBy == session.userID)
                    if maySee {
                        locationLabel = "Location captured · \(Formatters.coordinateLabel(latitude: latitude, longitude: longitude))"
                    }
                }

                let title = entry.fromStatus.map { "\($0.title(terms)) → \(entry.toStatus.title(terms))" }
                    ?? entry.toStatus.title(terms)

                return JobTimelineEntry(
                    id: entry.id.uuidString,
                    title: title,
                    byLabel: author,
                    timeLabel: Formatters.shortDayAndTime(entry.changedAt),
                    locationLabel: locationLabel,
                    tone: entry.toStatus.tone,
                    symbolName: entry.toStatus.symbolName
                )
            }
    }

    private func notes(_ jobID: String, _ session: TenantSession) async throws -> [JobNoteProjection] {
        guard session.can(.jobNotesRead) else { return [] }

        let rows = try await fetch(
            JobNoteRecord.self,
            client.from("job_notes").select(JobNoteRecord.columns).eq("job_id", value: jobID)
        )
        let authors = try await users(ids: Array(Set(rows.compactMap { $0.userID?.uuidString })))

        return rows
            .sorted { $0.createdAt > $1.createdAt }
            .map { note in
                let author = note.userID.flatMap { authors[$0.uuidString] }
                return JobNoteProjection(
                    id: note.id.uuidString,
                    body: note.body,
                    authorName: author?.name ?? "Team member",
                    authorInitials: author.map { Self.initials(of: $0.name) } ?? "··",
                    timeLabel: Formatters.shortDayAndTime(note.createdAt),
                    visibilityTitle: note.visibility.title,
                    isInternal: note.visibility == .internalOnly
                )
            }
    }

    private func photos(_ jobID: String, _ session: TenantSession) async throws -> [JobPhotoProjection] {
        guard session.can(.jobPhotosRead) else { return [] }

        let rows = try await fetch(
            JobPhotoRecord.self,
            client.from("job_photos").select(JobPhotoRecord.columns).eq("job_id", value: jobID)
        )
        let authors = try await users(ids: Array(Set(rows.compactMap { $0.userID?.uuidString })))

        return rows
            .sorted { $0.capturedAt > $1.capturedAt }
            .map { photo in
                JobPhotoProjection(
                    id: photo.id.uuidString,
                    kindTitle: photo.kind.title,
                    caption: photo.caption,
                    timeLabel: Formatters.shortDayAndTime(photo.capturedAt),
                    authorName: photo.userID.flatMap { authors[$0.uuidString]?.name } ?? "Team member",
                    storageReference: photo.storageReference
                )
            }
    }

    private func transitionOptions(_ job: Job, assignedToCaller: Bool, _ session: TenantSession) -> [JobTransitionOption] {
        JobWorkflow.transitions(from: job.status)
            .filter { $0.requirement != .office(.assignmentsManage) }
            .filter { transition in
                switch transition.requirement {
                case .fieldWork:
                    return session.can(.jobsManage) || (session.can(.jobStatusUpdateOwn) && assignedToCaller)
                case .office(let permission):
                    return session.can(permission)
                }
            }
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

    // MARK: - Scheduling helpers

    private func slot(_ job: Job) -> (start: Date, end: Date)? {
        guard let start = job.scheduledStart else { return nil }
        let end = job.scheduledEnd ?? start.addingTimeInterval(3600)
        return (start, max(end, start))
    }

    private static func overlaps(_ a: (start: Date, end: Date), _ b: (start: Date, end: Date)) -> Bool {
        a.start < b.end && b.start < a.end
    }

    private func conflictRows(
        job: Job,
        workerUserID: String,
        slotOverride: (start: Date, end: Date)? = nil,
        jobs: [Job],
        assignments: [String: String],
        workerName: String
    ) -> [SchedulingConflict] {
        guard let candidate = slotOverride ?? slot(job) else { return [] }

        return jobs
            .filter { other in
                guard other.id != job.id else { return false }
                guard assignments[other.id] == workerUserID else { return false }
                guard other.status.isOpen else { return false }
                guard let otherSlot = slot(other) else { return false }
                return Self.overlaps(candidate, otherSlot)
            }
            .sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }
            .map { clash in
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
                    workerName: workerName,
                    detail: "\(workerName) is already on \(clash.number) (\(range))",
                    overlapLabel: range
                )
            }
    }

    // MARK: - Overview surfaces

    func dashboard(session: TenantSession) async throws -> DashboardSnapshot {
        let jobs = try await jobRecords(session, query: "dashboard.jobs")
        let calendar = Calendar.current

        let todayJobs = jobs
            .filter { job in
                guard let start = job.scheduledStart else { return false }
                return calendar.isDateInToday(start)
            }
            .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }

        let reference = try await jobReference(for: todayJobs, session)
        let openToday = todayJobs.filter { $0.status.isOpen }
        let headline = openToday.count == 1 ? "1 job today" : "\(openToday.count) jobs today"

        var subline = "Nothing else booked today"
        if let next = openToday.first {
            let name = reference.customers[next.customerID]?.name ?? "Customer"
            let short = reference.addresses[next.addressID]?.shortLine ?? ""
            let time = next.scheduledStart.map { Formatters.time($0) } ?? ""
            subline = "Next: \(time) · \(name) — \(short)"
        }

        var tiles: [DashboardFinancialTile] = []
        if session.can(.quoteFinancialsRead) {
            let quotes = try await fetch(
                QuoteFinancialRecord.self,
                client.from("quotes")
                    .select(QuoteFinancialRecord.columns)
                    .in("status", values: [QuoteStatus.sent.rawValue, QuoteStatus.viewed.rawValue])
            )
            let value = quotes.reduce(Decimal(0)) { $0 + SupabaseCoding.decimal($1.total) }
            let code = try await currencyCode(session)
            tiles.append(
                DashboardFinancialTile(
                    id: "quotes",
                    caption: "Quotes out",
                    amount: Formatters.currencyRounded(value, code: code),
                    symbolName: "doc.text"
                )
            )
        }
        // Outstanding and overdue money. Overdue is derived from the due date
        // and the balance rather than stored, so an invoice becomes overdue by
        // the clock alone and a paid invoice can never read as overdue.
        if session.can(.invoicesRead) {
            let invoices = try await fetch(
                InvoiceRecord.self,
                client.from("invoices").select(InvoiceRecord.columns)
            ).map { $0.model(companyID: session.companyID) }

            let now = Date()
            let code = try await currencyCode(session)

            let outstanding = invoices.filter { $0.isReceivable(asOf: now) }
            let overdue = invoices.filter { $0.isOverdue(asOf: now) }

            tiles.append(
                DashboardFinancialTile(
                    id: "outstanding",
                    caption: "Outstanding",
                    amount: Formatters.currencyRounded(
                        Money.rounded(outstanding.reduce(Decimal(0)) { $0 + $1.balance }),
                        code: code
                    ),
                    symbolName: "doc.plaintext"
                )
            )

            if !overdue.isEmpty {
                tiles.append(
                    DashboardFinancialTile(
                        id: "overdue",
                        caption: overdue.count == 1 ? "Overdue (1)" : "Overdue (\(overdue.count))",
                        amount: Formatters.currencyRounded(
                            Money.rounded(overdue.reduce(Decimal(0)) { $0 + $1.balance }),
                            code: code
                        ),
                        symbolName: "exclamationmark.triangle"
                    )
                )
            }

            // Settled in the last 30 days — the number that tells an owner
            // whether collection is actually working.
            let since = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            let collected = invoices.filter { ($0.paidAt ?? .distantPast) >= since }
            if !collected.isEmpty {
                tiles.append(
                    DashboardFinancialTile(
                        id: "collected",
                        caption: "Paid (30 days)",
                        amount: Formatters.currencyRounded(
                            Money.rounded(collected.reduce(Decimal(0)) { $0 + $1.total }),
                            code: code
                        ),
                        symbolName: "checkmark.circle"
                    )
                )
            }

            record("dashboard.invoiceTiles", session, allowed: true, "Invoice money read in company scope by RLS")
        }

        // Message credit. Absent rather than zero for a role that may not read
        // the ledger, so nobody is shown a balance that isn't theirs to see.
        var smsBalance: Int?
        if session.can(.smsLedgerRead) {
            smsBalance = await {
                do {
                    let data = try await client.rpc("sms_credit_balance").execute().data
                    return try? SupabaseCoding.decoder.decode(Int.self, from: data)
                } catch {
                    return nil
                }
            }()
        }

        // Work that is finished as far as the field is concerned. Invoiced and
        // paid count too: the visit happened, it is just further down the
        // money pipeline. Cancelled is neither done nor remaining.
        let completedToday = todayJobs.filter {
            $0.status == .completed || $0.status == .invoiced || $0.status == .paid
        }.count
        let assignedWorkers = Set(todayJobs.compactMap { reference.primaryWorkerByJob[$0.id] })
        let unassigned = todayJobs.filter { reference.primaryWorkerByJob[$0.id] == nil && $0.status.isOpen }.count

        record(
            "dashboard",
            session,
            allowed: true,
            tiles.isEmpty ? "Financial tiles omitted for role" : "\(tiles.count) financial tile(s)"
        )

        return DashboardSnapshot(
            headline: headline,
            subline: subline,
            todayJobs: todayJobs.map { jobRow($0, session, reference) },
            financialTiles: tiles,
            completedToday: completedToday,
            remainingToday: openToday.count,
            workersOnToday: assignedWorkers.count,
            unassignedToday: unassigned,
            smsBalance: smsBalance
        )
    }

    func calendarDays(session: TenantSession, dayCount: Int) async throws -> [CalendarDay] {
        guard session.can(.calendarReadAll) || session.can(.calendarReadOwnOnly) else {
            record("calendar", session, allowed: false, "No calendar permission")
            throw DataError.notPermitted(.calendarReadAll)
        }

        let jobs = try await jobRecords(session, query: "calendar.jobs")
        let reference = try await jobReference(for: jobs, session)
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
                jobs: dayJobs.map { jobRow($0, session, reference) }
            )
        }
    }

    func customers(session: TenantSession, query: String) async throws -> [CustomerRow] {
        if session.can(.customersReadAssignedSiteOnly), !session.can(.customersReadAll) {
            // Field workers have no customer directory at all — the policy on
            // `customers` returns nothing for them, and this says so plainly.
            record("customers.list", session, allowed: false, "Directory not available — assigned sites only")
            throw DataError.notPermitted(.customersReadAll)
        }
        try require(.customersReadAll, session, query: "customers.list")

        let customers = try await fetch(
            CustomerRecord.self,
            client.from("customers").select(CustomerRecord.columns)
        )
        let addresses = try await fetch(
            AddressRecord.self,
            client.from("addresses").select(AddressRecord.columns)
        )

        var addressByCustomer: [String: AddressRecord] = [:]
        for row in addresses where addressByCustomer[row.customerID.uuidString] == nil {
            addressByCustomer[row.customerID.uuidString] = row
        }

        // The full contact list is billing data; without that permission the
        // count comes from the operational view, which holds primary contacts
        // only.
        let contacts: [SiteContactRecord]
        if session.can(.customerBillingDetailsRead) {
            contacts = try await fetch(
                SiteContactRecord.self,
                client.from("customer_contacts").select(SiteContactRecord.columns)
            )
        } else {
            contacts = try await fetch(
                SiteContactRecord.self,
                client.from("site_contacts_operational").select(SiteContactRecord.columns)
            )
        }
        let contactCounts = contacts.reduce(into: [String: Int]()) { counts, row in
            counts[row.customerID.uuidString, default: 0] += 1
        }

        var openJobCounts: [String: Int] = [:]
        if session.can(.jobsReadAll) {
            let jobs = try await fetch(
                JobCountRecord.self,
                client.from("jobs").select(JobCountRecord.columns)
            )
            for row in jobs where row.status.isOpen {
                openJobCounts[row.customerID.uuidString, default: 0] += 1
            }
        }

        if session.can(.customerBillingDetailsRead) {
            record(
                "customers.balance",
                session,
                allowed: false,
                "Outstanding balances are not read in this phase — invoices stay on the mock path"
            )
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let rows = customers
            .filter { trimmed.isEmpty || $0.name.localizedStandardContains(trimmed) }
            .sorted { $0.name < $1.name }
            .map { customer -> CustomerRow in
                let key = customer.id.uuidString
                return CustomerRow(
                    id: key,
                    name: customer.name,
                    initials: Self.initials(of: customer.name),
                    typeTitle: customer.type.title,
                    addressShort: addressByCustomer[key]?.line1 ?? "No address on file",
                    contactCount: contactCounts[key] ?? 0,
                    openJobCount: openJobCounts[key] ?? 0,
                    balanceLabel: nil
                )
            }

        record("customers.list", session, allowed: true, "\(rows.count) rows returned by RLS in company scope")
        return rows
    }

    func moreOverview(session: TenantSession) async throws -> MoreOverview {
        let company = try await companyRecord(session)

        var workerCount: Int?
        if session.can(.usersRead) {
            workerCount = try await fieldWorkers(session).count
        }

        var quoteCount: Int?
        if session.can(.quotesRead) {
            let quotes = try await fetch(
                QuoteOperationalRecord.self,
                client.from("quotes_operational")
                    .select(QuoteOperationalRecord.columns)
                    .in("status", values: [
                        QuoteStatus.draft.rawValue,
                        QuoteStatus.sent.rawValue,
                        QuoteStatus.viewed.rawValue
                    ])
            )
            quoteCount = quotes.count
        }

        if session.can(.invoicesRead) || session.can(.paymentsRead)
            || session.can(.smsLedgerRead) || session.can(.saasBillingRead) {
            record(
                "more.overview",
                session,
                allowed: false,
                "Invoice, payment, SMS and subscription figures are not read in this phase"
            )
        }

        return MoreOverview(
            workerCount: workerCount,
            quoteCount: quoteCount,
            invoiceCount: nil,
            outstandingLabel: nil,
            paymentCount: nil,
            smsBalance: nil,
            subscriptionSummary: nil,
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
        let all = try await jobRecords(session, query: "jobs.list")
        let reference = try await jobReference(for: all, session)
        let trimmed = query.searchText.trimmingCharacters(in: .whitespaces)

        let filtered = all.filter { job in
            guard query.dateScope.matches(job) else { return false }
            if !query.statuses.isEmpty, !query.statuses.contains(job.status) { return false }
            if let priority = query.priority, job.priority != priority { return false }
            if let customerID = query.customerID, job.customerID != customerID { return false }
            if let workerID = query.fieldWorkerUserID, reference.primaryWorkerByJob[job.id] != workerID { return false }
            if !trimmed.isEmpty {
                let name = reference.customers[job.customerID]?.name ?? ""
                let line = reference.addresses[job.addressID]?.singleLine ?? ""
                let matches = job.number.localizedStandardContains(trimmed)
                    || name.localizedStandardContains(trimmed)
                    || line.localizedStandardContains(trimmed)
                    || job.title.localizedStandardContains(trimmed)
                if !matches { return false }
            }
            return true
        }

        record("jobs.list", session, allowed: true, "\(filtered.count) of \(all.count) after filters")

        return filtered
            .sorted { lhs, rhs in
                switch (lhs.scheduledStart, rhs.scheduledStart) {
                case let (l?, r?): return l < r
                case (nil, _?): return true
                case (_?, nil): return false
                default: return lhs.number > rhs.number
                }
            }
            .map { jobRow($0, session, reference) }
    }

    func jobFormOptions(session: TenantSession) async throws -> JobFormOptions {
        guard session.can(.jobsReadAll) else {
            record("jobs.formOptions", session, allowed: false, "Reference data withheld — no company-wide job read")
            return .empty
        }

        let workers = try await fieldWorkers(session).map {
            FieldWorkerOption(id: $0.id.uuidString, name: $0.name, initials: Self.initials(of: $0.name))
        }

        var customerOptions: [CustomerOption] = []
        if session.can(.customersReadAll) {
            let customers = try await fetch(
                CustomerRecord.self,
                client.from("customers").select(CustomerRecord.columns)
            )
            let addresses = try await fetch(
                AddressRecord.self,
                client.from("addresses").select(AddressRecord.columns)
            )
            // Every site, not just the first: a commercial customer with four
            // buildings needs the job pointed at the right one.
            var addressesByCustomer: [String: [AddressRecord]] = [:]
            for row in addresses {
                addressesByCustomer[row.customerID.uuidString, default: []].append(row)
            }

            var equipmentByAddress: [String: [EquipmentOption]] = [:]
            if session.can(.equipmentRead) {
                let units = try await fetch(
                    EquipmentRecord.self,
                    client.from("equipment").select(EquipmentRecord.columns)
                )
                for unit in units {
                    guard let addressID = unit.addressID?.uuidString else { continue }
                    equipmentByAddress[addressID, default: []].append(
                        EquipmentOption(id: unit.id.uuidString, name: unit.displayName)
                    )
                }
            }

            customerOptions = customers
                .sorted { $0.name < $1.name }
                .compactMap { customer in
                    let rows = addressesByCustomer[customer.id.uuidString] ?? []
                    guard let main = rows.first else { return nil }
                    let mainKey = main.id.uuidString
                    let sites = rows.map { row in
                        let key = row.id.uuidString
                        return CustomerSiteOption(
                            id: key,
                            line: "\(row.line1), \(row.city) \(row.state) \(row.postalCode)",
                            equipment: equipmentByAddress[key] ?? []
                        )
                    }
                    return CustomerOption(
                        id: customer.id.uuidString,
                        name: customer.name,
                        addressID: mainKey,
                        addressLine: "\(main.line1), \(main.city) \(main.state) \(main.postalCode)",
                        equipment: equipmentByAddress[mainKey] ?? [],
                        sites: sites
                    )
                }
        }

        record("jobs.formOptions", session, allowed: true, "\(workers.count) \(session.terms.workerPlural), \(customerOptions.count) customers")
        return JobFormOptions(workers: workers, customers: customerOptions, canAssign: session.can(.assignmentsManage))
    }

    func jobDetail(session: TenantSession, jobID: String) async throws -> JobDetailProjection {
        let job = try await requireJob(jobID, session, query: "jobs.detail")
        let reference = try await jobReference(for: [job], session)

        let customer = reference.customers[job.customerID]
        let address = reference.addresses[job.addressID]
        let contact = reference.contacts[job.customerID]

        var workerProjection: AssignedWorkerProjection?
        if let workerID = reference.primaryWorkerByJob[job.id], let worker = reference.users[workerID] {
            var eta: String?
            if job.status == .travelling, session.can(.fieldWorkerLocationReadAll) {
                let arrival = Date().addingTimeInterval(4 * 60)
                eta = "Arriving \(Formatters.time(arrival)) · 4 min away"
            }
            workerProjection = AssignedWorkerProjection(
                userID: workerID,
                name: worker.name,
                initials: Self.initials(of: worker.name),
                etaLabel: eta,
                // Field workers never receive colleagues' contact details, and
                // the policy on `app_users` doesn't return them either.
                phone: session.can(.usersRead) ? worker.phone : nil
            )
        }

        var quoteReference: String?
        var quoteSummary: String?
        if let quoteID = job.quoteID, session.can(.quotesRead) {
            let operational = try await fetch(
                QuoteOperationalRecord.self,
                client.from("quotes_operational")
                    .select(QuoteOperationalRecord.columns)
                    .eq("id", value: quoteID)
                    .limit(1)
            )
            if let quote = operational.first {
                quoteReference = "\(quote.number) · \(quote.status.title)"
            }
            if session.can(.quoteFinancialsRead), let label = reference.valueLabels[job.id],
               let quote = operational.first {
                quoteSummary = "\(quote.number) · \(quote.status.title) · \(label)"
            }
        }

        var financials: JobFinancialProjection?
        if quoteSummary != nil {
            financials = JobFinancialProjection(quoteSummary: quoteSummary, invoiceSummary: nil)
        } else if !(session.can(.quoteFinancialsRead) || session.can(.invoicesRead)) {
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
        if let agreementID = job.serviceAgreementID, session.can(.customersReadAll) {
            let agreements = try await fetch(
                ServiceAgreementRecord.self,
                client.from("service_agreements")
                    .select(ServiceAgreementRecord.columns)
                    .eq("id", value: agreementID)
                    .limit(1)
            )
            if let agreement = agreements.first {
                let due = agreement.nextDueDate.map { Formatters.shortDate($0) } ?? "unscheduled"
                agreementLabel = "\(agreement.frequency.title) agreement · next due \(due)"
            }
        }

        let assignedToCaller = reference.primaryWorkerByJob[job.id] == session.userID

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
            customerName: customer?.name ?? "Customer",
            customerTypeTitle: customer?.type.title ?? "",
            contactName: contact?.name,
            contactRole: contact?.contactRole,
            contactPhone: contact?.phone,
            addressLine: address?.singleLine ?? "",
            accessNotes: address?.accessNotes,
            latitude: address?.latitude ?? Self.fallbackLatitude,
            longitude: address?.longitude ?? Self.fallbackLongitude,
            scheduleLabel: scheduleLabel,
            durationLabel: durationLabel,
            createdLabel: "Raised \(Formatters.shortDate(job.createdAt))",
            assignedWorker: workerProjection,
            equipment: try await equipmentProjection(job.equipmentID, session),
            serviceAgreementLabel: agreementLabel,
            quoteReference: quoteReference,
            quoteID: session.can(.quotesRead) ? job.quoteID : nil,
            financials: financials,
            timeline: try await timeline(job.id, session),
            notes: try await notes(job.id, session),
            photos: try await photos(job.id, session),
            transitions: transitionOptions(job, assignedToCaller: assignedToCaller, session),
            canManage: session.can(.jobsManage),
            canAssign: session.can(.assignmentsManage) && job.status.isOpen,
            canAddNotes: session.can(.jobNotesCreate),
            canAddPhotos: session.can(.jobPhotosCreate)
        )
    }

    // MARK: - Field worker shell

    func fieldWorkerDay(session: TenantSession) async throws -> FieldWorkerDaySnapshot {
        let jobs = try await jobRecords(session, query: "fieldWorker.day")
        let calendar = Calendar.current

        let todays = jobs
            .filter { job in
                guard let start = job.scheduledStart else { return false }
                return calendar.isDateInToday(start)
            }
            .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }

        let reference = try await jobReference(for: todays, session, includeMoney: false)
        let equipment = try await equipmentProjections(ids: todays.compactMap(\.equipmentID), session)

        let stops = todays.map { job -> FieldWorkerStop in
            let address = reference.addresses[job.addressID]
            let contact = reference.contacts[job.customerID]
            var equipmentLine: String?
            if let equipmentID = job.equipmentID, let projection = equipment[equipmentID] {
                equipmentLine = "\(projection.displayName) · \(projection.subtitle)"
            }
            let advance = JobWorkflow.fieldAdvance(from: job.status)
            return FieldWorkerStop(
                jobID: job.id,
                number: job.number,
                timeLabel: job.scheduledStart.map { Formatters.time($0) } ?? "",
                customerName: reference.customers[job.customerID]?.name ?? "Customer",
                addressLine: address?.singleLine ?? "",
                jobTitle: job.title,
                kindTitle: job.kind.title,
                equipmentLine: equipmentLine,
                status: job.status,
                statusTitle: job.status.title(session.terms),
                isUrgent: job.priority == .urgent,
                completedLabel: job.actualEnd.map { "Completed \(Formatters.time($0))" },
                latitude: address?.latitude ?? Self.fallbackLatitude,
                longitude: address?.longitude ?? Self.fallbackLongitude,
                accessNotes: address?.accessNotes,
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
        let job = try await requireJob(jobID, session, query: "fieldWorker.jobDetail")
        let reference = try await jobReference(for: [job], session, includeMoney: false)

        let address = reference.addresses[job.addressID]
        let contact = reference.contacts[job.customerID]

        let scheduleLabel: String
        if let start = job.scheduledStart, let end = job.scheduledEnd {
            scheduleLabel = "\(Formatters.dayTitle(start)) · \(Formatters.timeRange(start, end))"
        } else if let start = job.scheduledStart {
            scheduleLabel = Formatters.dayAndTime(start)
        } else {
            scheduleLabel = "No slot booked"
        }

        record(
            "fieldWorker.jobDetail",
            session,
            allowed: true,
            "Assigned row served with no monetary fields in the payload type"
        )

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
            customerName: reference.customers[job.customerID]?.name ?? "Customer",
            addressLine: address?.singleLine ?? "",
            latitude: address?.latitude ?? Self.fallbackLatitude,
            longitude: address?.longitude ?? Self.fallbackLongitude,
            accessNotes: address?.accessNotes,
            siteContactName: contact?.name,
            siteContactPhone: contact?.phone,
            equipment: try await equipmentProjection(job.equipmentID, session),
            timeline: try await timeline(job.id, session),
            notes: try await notes(job.id, session),
            photos: try await photos(job.id, session),
            transitions: transitionOptions(
                job,
                assignedToCaller: reference.primaryWorkerByJob[job.id] == session.userID,
                session
            )
        )
    }

    // MARK: - Dispatch

    func dispatchBoard(session: TenantSession, query: DispatchQuery) async throws -> DispatchBoard {
        try require(.calendarReadAll, session, query: "dispatch.board")

        let all = try await jobRecords(session, query: "dispatch.board")
        let reference = try await jobReference(for: all, session)
        let assignments = reference.primaryWorkerByJob
        let calendar = Calendar.current
        let now = Date()
        let trimmed = query.searchText.trimmingCharacters(in: .whitespaces)

        func matchesFilters(_ job: Job) -> Bool {
            if let workerID = query.fieldWorkerUserID, assignments[job.id] != workerID { return false }
            if query.unassignedOnly, assignments[job.id] != nil { return false }
            guard !trimmed.isEmpty else { return true }
            let name = reference.customers[job.customerID]?.name ?? ""
            let line = reference.addresses[job.addressID]?.singleLine ?? ""
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

        let unscheduled = all
            .filter { $0.isUnscheduled && $0.status.isOpen && matchesFilters($0) }
            .sorted { $0.createdAt > $1.createdAt }

        let unassigned = onDay.filter { assignments[$0.id] == nil && $0.status.isOpen }
        let urgent = onDay.filter { $0.priority == .urgent && $0.status.isOpen }
        let travelling = onDay.filter { $0.status == .travelling }
        let inProgress = onDay.filter { $0.status == .inProgress }
        let runningLate = onDay.filter { job in
            guard job.status.isOpen, let bounds = slot(job) else { return false }
            return bounds.end < now
        }

        let workerRecords = try await fieldWorkers(session)
        let workerNames = Dictionary(
            workerRecords.map { ($0.id.uuidString, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        var seenPairs = Set<String>()
        var conflicts: [SchedulingConflict] = []
        for job in onDay {
            guard let workerID = assignments[job.id] else { continue }
            let name = workerNames[workerID] ?? reference.users[workerID]?.name ?? "Team member"
            for conflict in conflictRows(
                job: job,
                workerUserID: workerID,
                jobs: all,
                assignments: assignments,
                workerName: name
            ) {
                let pair = [conflict.jobID, conflict.clashingJobID].sorted().joined(separator: "|")
                guard !seenPairs.contains(pair) else { continue }
                seenPairs.insert(pair)
                conflicts.append(conflict)
            }
        }
        let conflictedJobIDs = Set(conflicts.flatMap { [$0.jobID, $0.clashingJobID] })

        let mayReadLocations = session.can(.fieldWorkerLocationReadAll)
        var locationsByUser: [String: FieldWorkerLocationProjection] = [:]
        if mayReadLocations {
            locationsByUser = Dictionary(
                try await locationProjections(session).map { ($0.userID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            record("dispatch.board.locations", session, allowed: false, "Worker positions not assembled for role")
        }

        let workers: [FieldWorkerWorkload] = workerRecords.map { worker in
            let key = worker.id.uuidString
            let theirJobs = onDay.filter { assignments[$0.id] == key }
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
                id: key,
                name: worker.name,
                initials: Self.initials(of: worker.name),
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
                location: locationsByUser[key]
            )
        }

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
            scheduled: onDay.map { jobRow($0, session, reference) },
            unscheduled: unscheduled.map { jobRow($0, session, reference) },
            unassigned: unassigned.map { jobRow($0, session, reference) },
            urgent: urgent.map { jobRow($0, session, reference) },
            runningLate: runningLate.map { jobRow($0, session, reference) },
            travelling: travelling.map { jobRow($0, session, reference) },
            inProgress: inProgress.map { jobRow($0, session, reference) },
            workers: workers,
            conflicts: conflicts,
            canAssign: session.can(.assignmentsManage),
            canManageJobs: session.can(.jobsManage),
            canReadLocations: mayReadLocations
        )
    }

    func calendarBoard(session: TenantSession, query: CalendarQuery) async throws -> CalendarBoard {
        guard session.can(.calendarReadAll) || session.can(.calendarReadOwnOnly) else {
            record("calendar.board", session, allowed: false, "No calendar permission")
            throw DataError.notPermitted(.calendarReadAll)
        }

        let all = try await jobRecords(session, query: "calendar.board")
        let reference = try await jobReference(for: all, session)
        let assignments = reference.primaryWorkerByJob
        let calendar = Calendar.current

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

        let workerRecords = try await fieldWorkers(session)
        let workerNames = Dictionary(
            workerRecords.map { ($0.id.uuidString, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        var conflictedJobIDs = Set<String>()
        for job in all where job.status.isOpen {
            guard let workerID = assignments[job.id] else { continue }
            let rows = conflictRows(
                job: job,
                workerUserID: workerID,
                jobs: all,
                assignments: assignments,
                workerName: workerNames[workerID] ?? reference.users[workerID]?.name ?? "Team member"
            )
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
                jobs: dayJobs.map { jobRow($0, session, reference) },
                conflictingJobIDs: Set(dayJobs.map(\.id)).intersection(conflictedJobIDs),
                unassignedCount: dayJobs.filter { assignments[$0.id] == nil && $0.status.isOpen }.count,
                urgentCount: dayJobs.filter { $0.priority == .urgent && $0.status.isOpen }.count
            )
        }

        let workers = workerRecords.map {
            FieldWorkerOption(id: $0.id.uuidString, name: $0.name, initials: Self.initials(of: $0.name))
        }

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

    func checkAssignment(session: TenantSession, jobID: String, workerUserID: String?) async throws -> SchedulingCheck {
        try require(.assignmentsManage, session, query: "dispatch.checkAssignment")
        let job = try await requireJob(jobID, session, query: "dispatch.checkAssignment")

        // Clearing an assignment can never create an overlap.
        guard let workerUserID else { return .clear }
        let candidates = try await users(ids: [workerUserID])
        guard let worker = candidates[workerUserID], worker.role == .fieldWorker else {
            throw DataError.notFound
        }

        let all = try await jobRecords(session, query: "dispatch.checkAssignment.jobs")
        let assignments = try await assignments(jobIDs: all.map(\.id))
        let conflicts = conflictRows(
            job: job,
            workerUserID: workerUserID,
            jobs: all,
            assignments: assignments,
            workerName: worker.name
        )

        record(
            "dispatch.checkAssignment",
            session,
            allowed: true,
            conflicts.isEmpty ? "\(job.number): no clash" : "\(job.number): \(conflicts.count) clash(es)"
        )
        return SchedulingCheck(conflicts: conflicts)
    }

    func checkReschedule(session: TenantSession, jobID: String, input: RescheduleInput) async throws -> SchedulingCheck {
        try require(.jobsManage, session, query: "dispatch.checkReschedule")
        let job = try await requireJob(jobID, session, query: "dispatch.checkReschedule")

        let all = try await jobRecords(session, query: "dispatch.checkReschedule.jobs")
        let assignments = try await assignments(jobIDs: all.map(\.id))

        guard let workerUserID = assignments[job.id] else { return .clear }
        guard let start = input.scheduledStart else { return .clear }
        let end = input.scheduledEnd ?? start.addingTimeInterval(3600)

        let worker = try await users(ids: [workerUserID])[workerUserID]
        let conflicts = conflictRows(
            job: job,
            workerUserID: workerUserID,
            slotOverride: (start, max(end, start)),
            jobs: all,
            assignments: assignments,
            workerName: worker?.name ?? "Team member"
        )

        record(
            "dispatch.checkReschedule",
            session,
            allowed: true,
            conflicts.isEmpty ? "\(job.number): slot is free" : "\(job.number): \(conflicts.count) clash(es) in the new slot"
        )
        return SchedulingCheck(conflicts: conflicts)
    }

    // MARK: - Location

    private func locationProjections(_ session: TenantSession, asOf now: Date = Date()) async throws -> [FieldWorkerLocationProjection] {
        guard session.can(.fieldWorkerLocationReadAll) || session.can(.fieldWorkerLocationReadOwnOnly) else {
            return []
        }

        // The policy on `field_worker_locations` has already narrowed this to the
        // company, and for a field worker to their own rows.
        let rows = try await fetch(
            WorkerLocationRecord.self,
            client.from("field_worker_locations")
                .select(WorkerLocationRecord.columns)
                .order("recorded_at", ascending: false)
                .limit(400)
        )

        let latest = Dictionary(grouping: rows, by: { $0.userID.uuidString })
            .compactMap { _, group in group.max { $0.recordedAt < $1.recordedAt } }

        let workerNames = try await users(ids: Array(Set(latest.map { $0.userID.uuidString })))

        var jobsByID: [String: Job] = [:]
        let jobIDs = Array(Set(latest.compactMap { $0.jobID?.uuidString }))
        if !jobIDs.isEmpty, session.can(.jobsReadAll) || session.can(.jobsReadAssignedOnly) {
            let jobRows = try await fetch(
                JobRecord.self,
                client.from("jobs").select(JobRecord.columns).in("id", values: jobIDs)
            )
            jobsByID = Dictionary(
                jobRows.map { ($0.id.uuidString, $0.model(companyID: session.companyID)) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        let country = try await countryCode(session)

        return latest
            .sorted { $0.recordedAt > $1.recordedAt }
            .map { ping in
                let key = ping.userID.uuidString
                let worker = workerNames[key]
                let job = ping.jobID.flatMap { jobsByID[$0.uuidString] }
                let minutes = now.timeIntervalSince(ping.recordedAt) / 60
                let freshness: LocationFreshness = minutes <= Double(LocationRetentionPolicy.recentThresholdMinutes)
                    ? .recent
                    : .lastKnown

                return FieldWorkerLocationProjection(
                    id: ping.id.uuidString,
                    userID: key,
                    workerName: worker?.name ?? "Team member",
                    initials: worker.map { Self.initials(of: $0.name) } ?? "··",
                    latitude: ping.latitude,
                    longitude: ping.longitude,
                    coordinateLabel: Formatters.coordinateLabel(latitude: ping.latitude, longitude: ping.longitude),
                    accuracyLabel: ping.accuracyMeters.map { "±\(Int($0.rounded())) m" } ?? "Accuracy unknown",
                    headingLabel: ping.heading.map { "\(Int($0.rounded()))° \(Formatters.compassPoint($0))" },
                    speedLabel: ping.speedMetersPerSecond.map { Formatters.speedLabel($0, countryCode: country) },
                    recordedAtLabel: Formatters.shortDayAndTime(ping.recordedAt),
                    recordedAt: ping.recordedAt,
                    freshness: freshness,
                    jobID: job?.id,
                    jobNumber: job?.number,
                    jobStatusTitle: job?.status.title(session.terms),
                    isSimulated: ping.isSimulated
                )
            }
    }

    func fieldWorkerLocations(session: TenantSession) async throws -> FieldWorkerLocationBoard {
        guard session.can(.fieldWorkerLocationReadAll) || session.can(.fieldWorkerLocationReadOwnOnly) else {
            record("location.board", session, allowed: false, "No location read permission — nothing assembled")
            throw DataError.notPermitted(.fieldWorkerLocationReadAll)
        }

        let rows = try await locationProjections(session)
        let seenUserIDs = Set(rows.map(\.userID))

        // Only an office role has any business knowing who hasn't reported.
        var missing: [String] = []
        if session.can(.fieldWorkerLocationReadAll) {
            missing = try await fieldWorkers(session)
                .filter { !seenUserIDs.contains($0.id.uuidString) }
                .map(\.name)
                .sorted()
        }

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
            // put a "development fixtures" banner over a production company
            // that simply has not recorded a position yet.
            isSimulated: !rows.isEmpty && rows.allSatisfy(\.isSimulated),
            policySummary: LocationRetentionPolicy.summary,
            recentCount: recent,
            lastKnownCount: rows.count - recent
        )
    }

    func travelSnapshot(session: TenantSession, jobID: String) async throws -> TravelSnapshot {
        let job = try await requireJob(jobID, session, query: "travel.snapshot")
        let reference = try await jobReference(for: [job], session, includeMoney: false)

        let address = reference.addresses[job.addressID]
        let contact = reference.contacts[job.customerID]
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
            customerName: reference.customers[job.customerID]?.name ?? "Customer",
            addressLine: address?.singleLine ?? "",
            accessNotes: address?.accessNotes,
            siteContactName: contact?.name,
            siteContactPhone: contact?.phone,
            latitude: address?.latitude ?? Self.fallbackLatitude,
            longitude: address?.longitude ?? Self.fallbackLongitude,
            status: job.status,
            statusTitle: job.status.title(session.terms),
            badge: badge(for: job.status, session),
            scheduleLabel: scheduleLabel,
            isUrgent: job.priority == .urgent,
            nextActionTitle: advance?.actionTitle(session.terms),
            nextStatus: advance?.to,
            countryCode: try await countryCode(session)
        )
    }

}
