import Foundation
import Supabase

// MARK: - Rows

/// The caller's own membership row, read for the parts the session does not
/// carry. Selecting by `auth.uid()` is a precision filter; the policy on
/// `app_users` is what actually decides which rows exist.
private nonisolated struct DutyStateRecord: Decodable, Sendable {
    let id: UUID
    let name: String
    let phone: String?
    let dutyState: DutyState
    let dutyStateChangedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, phone
        case dutyState = "duty_state"
        case dutyStateChangedAt = "duty_state_changed_at"
    }

    static let columns = "id,name,phone,duty_state,duty_state_changed_at"
}

private nonisolated struct OfficeThreadRecord: Decodable, Sendable {
    let id: UUID
    let engineerUserID: UUID
    let jobID: UUID?
    let customerID: UUID?
    let subject: String
    let createdAt: Date
    let lastMessageAt: Date
    let lastMessagePreview: String
    let lastSenderUserID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, subject
        case engineerUserID = "engineer_user_id"
        case jobID = "job_id"
        case customerID = "customer_id"
        case createdAt = "created_at"
        case lastMessageAt = "last_message_at"
        case lastMessagePreview = "last_message_preview"
        case lastSenderUserID = "last_sender_user_id"
    }

    static let columns = """
    id,engineer_user_id,job_id,customer_id,subject,created_at,\
    last_message_at,last_message_preview,last_sender_user_id
    """
}

private nonisolated struct OfficeMessageRecord: Decodable, Sendable {
    let id: UUID
    let threadID: UUID
    let senderUserID: UUID
    let body: String
    let jobPhotoIDs: [UUID]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case threadID = "thread_id"
        case senderUserID = "sender_user_id"
        case jobPhotoIDs = "job_photo_ids"
        case createdAt = "created_at"
    }

    static let columns = "id,thread_id,sender_user_id,body,job_photo_ids,created_at"
}

private nonisolated struct ThreadReadRecord: Decodable, Sendable {
    let threadID: UUID
    let lastReadAt: Date

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case lastReadAt = "last_read_at"
    }

    static let columns = "thread_id,last_read_at"
}

/// Just enough of a note or photo to count them per job.
private nonisolated struct JobRecordCountRow: Decodable, Sendable {
    let jobID: UUID

    enum CodingKeys: String, CodingKey { case jobID = "job_id" }

    static let columns = "job_id"
}

private nonisolated struct JobPhotoCountRow: Decodable, Sendable {
    let jobID: UUID
    let kind: JobPhotoKind

    enum CodingKeys: String, CodingKey {
        case kind
        case jobID = "job_id"
    }

    static let columns = "job_id,kind"
}

/// PRODUCTION ENGINEER WORKSPACE.
///
/// Every read below is an ordinary select issued with the engineer's own JWT.
/// Nothing here decides what an engineer may see — the policies do:
///
///   * `jobs_select` returns assigned rows only for a role holding
///     `jobsReadAssignedOnly`, so schedule, sites, equipment and work history
///     are all narrowed at the database before this file sees a row.
///   * `assigned_site_customers` is the field-worker site view. It has no
///     `billing_terms` and no customer `notes` column, so no amount of asking
///     can produce a payment term through it.
///   * `office_threads` / `office_messages` return a row only to the engineer
///     named on the thread or to an office user in the same company. There is
///     no cross-company path, and no client write policy at all.
///
/// The permission checks in this file exist so a refusal is a clear sentence
/// rather than a silently empty screen, exactly as in the rest of the gateway.
/// They are not the boundary.
///
/// No payload assembled here has a price, total, balance or payment field.
extension SupabaseDataGateway {

    // MARK: - Schedule

    func engineerSchedule(session: TenantSession, dayCount: Int) async throws -> EngineerSchedule {
        guard session.can(.calendarReadOwnOnly) || session.can(.calendarReadAll) else {
            record("engineer.schedule", session, allowed: false, "No calendar permission")
            throw DataError.notPermitted(.calendarReadOwnOnly)
        }

        let jobs = try await jobRecords(session, query: "engineer.schedule")
        let context = try await siteContext(for: jobs, session)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let upcoming = jobs.filter { job in
            guard let start = job.scheduledStart else { return false }
            return start >= today && job.status.isOpen
        }

        let days: [EngineerScheduleDay] = (0..<max(dayCount, 1)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let stops = upcoming
                .filter { job in
                    guard let start = job.scheduledStart else { return false }
                    return calendar.isDate(start, inSameDayAs: day)
                }
                .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }
                .map { job -> EngineerScheduleStop in
                    var duration: String?
                    if let start = job.scheduledStart, let end = job.scheduledEnd {
                        duration = Formatters.durationLabel(from: start, to: end)
                    }
                    return EngineerScheduleStop(
                        jobID: job.id,
                        number: job.number,
                        timeLabel: job.scheduledStart.map { Formatters.time($0) } ?? "No slot",
                        durationLabel: duration,
                        customerName: context.customerNames[job.customerID] ?? "Customer",
                        addressLine: context.addressLines[job.addressID] ?? "",
                        jobTitle: job.title,
                        kindTitle: job.kind.title,
                        status: job.status,
                        badge: StatusBadge(text: job.status.title(session.terms), tone: job.status.tone),
                        isUrgent: job.priority == .urgent
                    )
                }

            guard offset < 2 || !stops.isEmpty else { return nil }

            return EngineerScheduleDay(
                id: "day-\(offset)",
                date: day,
                title: Formatters.dayTitle(day),
                subtitle: stops.isEmpty
                    ? "Nothing booked"
                    : (stops.count == 1 ? "1 stop" : "\(stops.count) stops"),
                stops: stops
            )
        }

        let total = days.reduce(0) { $0 + $1.stops.count }
        let todayCount = days.first?.stops.count ?? 0

        record(
            "engineer.schedule",
            session,
            allowed: true,
            "\(total) assigned stop(s) returned by RLS — read-only, no reschedule path exists for this role"
        )

        return EngineerSchedule(
            days: days,
            headline: total == 0
                ? "Nothing assigned yet"
                : (total == 1 ? "1 assigned stop" : "\(total) assigned stops"),
            subline: todayCount == 0
                ? "Dispatch assigns your work — you can't move it yourself."
                : "\(todayCount) today · \(total) over the next \(max(dayCount, 1)) days"
        )
    }

    // MARK: - Sites

    func engineerSites(session: TenantSession, query: String) async throws -> [EngineerSiteRow] {
        guard session.can(.customersReadAssignedSiteOnly) || session.can(.customersReadAll) else {
            record("engineer.sites", session, allowed: false, "No site read permission")
            throw DataError.notPermitted(.customersReadAssignedSiteOnly)
        }

        let jobs = try await jobRecords(session, query: "engineer.sites")
        let context = try await siteContext(for: jobs, session)
        let equipmentCounts = try await equipmentCountsByAddress(
            addressIDs: Array(Set(jobs.map(\.addressID))),
            session
        )

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let grouped = Dictionary(grouping: jobs, by: \.addressID)

        let rows = grouped
            .compactMap { addressID, group -> EngineerSiteRow? in
                guard let first = group.first else { return nil }
                let name = context.customerNames[first.customerID] ?? "Customer"
                let line = context.addressLines[addressID] ?? ""
                let closed = group
                    .filter { !$0.status.isOpen }
                    .compactMap { $0.actualEnd ?? $0.scheduledStart }
                    .max()

                return EngineerSiteRow(
                    id: addressID,
                    customerID: first.customerID,
                    customerName: name,
                    initials: Self.engineerInitials(name),
                    addressLine: line,
                    equipmentCount: equipmentCounts[addressID] ?? 0,
                    visitCount: group.count,
                    lastVisitLabel: closed.map { Formatters.shortDate($0) },
                    hasOpenWork: group.contains { $0.status.isOpen }
                )
            }
            .filter { site in
                trimmed.isEmpty
                    || site.customerName.localizedStandardContains(trimmed)
                    || site.addressLine.localizedStandardContains(trimmed)
            }
            .sorted { lhs, rhs in
                if lhs.hasOpenWork != rhs.hasOpenWork { return lhs.hasOpenWork }
                return lhs.customerName < rhs.customerName
            }

        record(
            "engineer.sites",
            session,
            allowed: true,
            session.can(.customersReadAll)
                ? "\(rows.count) site(s) in company scope"
                : "\(rows.count) assigned site(s) — no directory, no billing fields in the payload"
        )
        return rows
    }

    func engineerSiteDetail(session: TenantSession, addressID: String) async throws -> EngineerSiteDetail {
        guard session.can(.customersReadAssignedSiteOnly) || session.can(.customersReadAll) else {
            throw DataError.notPermitted(.customersReadAssignedSiteOnly)
        }
        guard UUID(uuidString: addressID) != nil else { throw DataError.notFound }

        let jobs = try await jobRecords(session, query: "engineer.siteDetail")
        let atSite = jobs.filter { $0.addressID == addressID }
        guard let anchor = atSite.first else {
            // Indistinguishable from a site that does not exist, which is the
            // point: an engineer learns nothing about places they don't work.
            record("engineer.siteDetail", session, allowed: false, "No assigned work at that site — answered notFound")
            throw DataError.notFound
        }

        let context = try await siteContext(for: atSite, session)
        let equipment = try await equipmentAtAddress(addressID, session)

        var contacts: [EngineerSiteContact] = []
        let contactRows = try await fetch(
            SiteContactRecord.self,
            client.from("site_contacts_operational")
                .select(SiteContactRecord.columns)
                .eq("customer_id", value: anchor.customerID)
        )
        contacts = contactRows.map {
            EngineerSiteContact(
                id: $0.id.uuidString,
                name: $0.name,
                roleTitle: $0.contactRole?.nilIfBlank,
                phone: $0.phone?.nilIfBlank
            )
        }

        let visits = atSite
            .sorted { ($0.scheduledStart ?? .distantPast) > ($1.scheduledStart ?? .distantPast) }
            .map { job in
                EngineerVisitRow(
                    id: job.id,
                    number: job.number,
                    title: job.title,
                    dateLabel: (job.actualEnd ?? job.scheduledStart).map { Formatters.shortDate($0) } ?? "No date",
                    kindTitle: job.kind.title,
                    badge: StatusBadge(text: job.status.title(session.terms), tone: job.status.tone),
                    isMine: true
                )
            }

        record(
            "engineer.siteDetail",
            session,
            allowed: true,
            "Site served with \(equipment.count) asset(s) and \(visits.count) visit(s); no billing or pricing field is in this payload"
        )

        return EngineerSiteDetail(
            id: addressID,
            customerID: anchor.customerID,
            customerName: context.customerNames[anchor.customerID] ?? "Customer",
            typeTitle: context.customerTypes[anchor.customerID]?.title ?? "Site",
            addressLine: context.addressLines[addressID] ?? "",
            latitude: context.coordinates[addressID]?.latitude ?? Self.engineerFallbackLatitude,
            longitude: context.coordinates[addressID]?.longitude ?? Self.engineerFallbackLongitude,
            accessNotes: context.accessNotes[addressID],
            siteNotes: nil,
            contacts: contacts,
            equipment: equipment,
            openVisits: visits.filter { $0.badge.tone != .success && !$0.badge.text.contains("Cancel") },
            pastVisits: visits.filter { $0.badge.tone == .success || $0.badge.text.contains("Cancel") },
            canUpdateEquipment: session.can(.equipmentManage)
        )
    }

    // MARK: - Work history

    func engineerWorkHistory(session: TenantSession, limit: Int) async throws -> [EngineerWorkRecord] {
        guard session.can(.jobsReadAssignedOnly) || session.can(.jobsReadAll) else {
            throw DataError.notPermitted(.jobsReadAssignedOnly)
        }

        let jobs = try await jobRecords(session, query: "engineer.workHistory")
        let finished = jobs
            .filter { !$0.status.isOpen && $0.status != .cancelled }
            .sorted { ($0.actualEnd ?? $0.scheduledStart ?? .distantPast) > ($1.actualEnd ?? $1.scheduledStart ?? .distantPast) }
            .prefix(max(limit, 1))
            .map { $0 }

        guard !finished.isEmpty else { return [] }

        let context = try await siteContext(for: finished, session)
        let ids = finished.map(\.id)

        // Counts, not contents. The record itself opens from the job screen.
        var noteCounts: [String: Int] = [:]
        if session.can(.jobNotesRead) {
            let rows = try await fetch(
                JobRecordCountRow.self,
                client.from("job_notes").select(JobRecordCountRow.columns).in("job_id", values: ids)
            )
            for row in rows { noteCounts[row.jobID.uuidString, default: 0] += 1 }
        }

        var photoCounts: [String: Int] = [:]
        var signed: Set<String> = []
        if session.can(.jobPhotosRead) {
            let rows = try await fetch(
                JobPhotoCountRow.self,
                client.from("job_photos").select(JobPhotoCountRow.columns).in("job_id", values: ids)
            )
            for row in rows {
                let key = row.jobID.uuidString
                if row.kind == .proof {
                    signed.insert(key)
                } else {
                    photoCounts[key, default: 0] += 1
                }
            }
        }

        record("engineer.workHistory", session, allowed: true, "\(finished.count) completed visit(s) — field history only, no financial figure")

        return finished.map { job in
            let when = job.actualEnd ?? job.scheduledStart ?? job.createdAt
            return EngineerWorkRecord(
                id: job.id,
                number: job.number,
                title: job.title,
                customerName: context.customerNames[job.customerID] ?? "Customer",
                addressLine: context.addressLines[job.addressID] ?? "",
                kindTitle: job.kind.title,
                completedAt: when,
                completedLabel: Formatters.shortDayAndTime(when),
                noteCount: noteCounts[job.id] ?? 0,
                photoCount: photoCounts[job.id] ?? 0,
                hasSignature: signed.contains(job.id)
            )
        }
    }

    // MARK: - Profile and availability

    func engineerProfile(session: TenantSession) async throws -> EngineerProfile {
        let company = try? await companyRecord(session)

        let memberships = try await fetch(
            DutyStateRecord.self,
            client.from("app_users")
                .select(DutyStateRecord.columns)
                .eq("id", value: session.userID)
                .limit(1)
        )
        let membership = memberships.first

        let jobs = try await jobRecords(session, query: "engineer.profile")
        let calendar = Calendar.current
        let todays = jobs.filter { job in
            guard let start = job.scheduledStart else { return false }
            return calendar.isDateInToday(start)
        }
        let live = jobs.first { $0.status.isFieldActive }
        let duty = membership?.dutyState ?? .available

        return EngineerProfile(
            userID: session.userID,
            name: membership?.name.nilIfBlank ?? session.displayName,
            initials: Self.engineerInitials(membership?.name.nilIfBlank ?? session.displayName),
            email: session.email,
            phone: membership?.phone?.nilIfBlank,
            roleTitle: session.roleTitle,
            companyName: company?.name ?? "",
            tradeTitle: (company?.trade ?? session.trade).title,
            dutyState: duty,
            availability: EngineerAvailability.resolve(duty: duty, activeJobStatus: live?.status),
            dutyChangedLabel: membership?.dutyStateChangedAt.map { Formatters.shortDayAndTime($0) },
            activeJobNumber: live?.number,
            jobsToday: todays.count,
            completedToday: todays.filter { !$0.status.isOpen }.count,
            upcomingCount: jobs.filter { $0.status.isOpen }.count,
            completedAllTime: jobs.filter { !$0.status.isOpen && $0.status != .cancelled }.count
        )
    }

    /// Sets the caller's own availability.
    ///
    /// The RPC takes no user id: it writes against `auth.uid()` inside the
    /// database and touches only the two duty columns. There is no parameter
    /// this app could set to change somebody else's status, or to change any
    /// other column on the row.
    func updateDutyState(session: TenantSession, state: DutyState) async throws {
        try await perform("set_my_duty_state", ["p_state": .string(state.rawValue)])
        record(
            "engineer.dutyState",
            session,
            allowed: true,
            "Own availability set to \(state.title) — the function is scoped to auth.uid() and cannot reach another user's row"
        )
    }

    // MARK: - Office messaging

    func officeInbox(session: TenantSession) async throws -> OfficeInbox {
        let threads = try await fetch(
            OfficeThreadRecord.self,
            client.from("office_threads")
                .select(OfficeThreadRecord.columns)
                .order("last_message_at", ascending: false)
                .limit(60)
        )
        guard !threads.isEmpty else {
            return OfficeInbox(threads: [], unreadCount: 0, isAvailable: true, unavailableReason: nil)
        }

        let reads = try await fetch(
            ThreadReadRecord.self,
            client.from("office_thread_reads").select(ThreadReadRecord.columns)
        )
        let readAt = Dictionary(
            reads.map { ($0.threadID.uuidString, $0.lastReadAt) },
            uniquingKeysWith: { first, _ in first }
        )

        let counterpartyIDs = Set(threads.compactMap { $0.lastSenderUserID?.uuidString })
        let people = try await users(ids: Array(counterpartyIDs))

        let jobIDs = Array(Set(threads.compactMap { $0.jobID?.uuidString }))
        var jobNumbers: [String: String] = [:]
        if !jobIDs.isEmpty {
            let rows = try await fetch(
                JobRecord.self,
                client.from("jobs").select(JobRecord.columns).in("id", values: jobIDs)
            )
            for row in rows { jobNumbers[row.id.uuidString] = row.number }
        }

        var unread = 0
        let rows = threads.map { thread -> OfficeThreadRow in
            let key = thread.id.uuidString
            let lastRead = readAt[key]
            let mine = thread.lastSenderUserID?.uuidString == session.userID
            let isUnread = !mine && (lastRead == nil || lastRead! < thread.lastMessageAt)
            if isUnread { unread += 1 }

            return OfficeThreadRow(
                id: key,
                subject: thread.subject.nilIfBlank ?? "Message to the office",
                preview: thread.lastMessagePreview,
                timeLabel: Formatters.shortDayAndTime(thread.lastMessageAt),
                lastMessageAt: thread.lastMessageAt,
                counterpartyName: mine
                    ? "You"
                    : (thread.lastSenderUserID.flatMap { people[$0.uuidString]?.name } ?? "Office"),
                jobID: thread.jobID?.uuidString,
                jobNumber: thread.jobID.flatMap { jobNumbers[$0.uuidString] },
                customerName: nil,
                isUnread: isUnread
            )
        }

        record(
            "engineer.officeInbox",
            session,
            allowed: true,
            "\(rows.count) conversation(s); the policy returns only threads naming this user, or all threads to an office role"
        )

        return OfficeInbox(threads: rows, unreadCount: unread, isAvailable: true, unavailableReason: nil)
    }

    func officeConversation(session: TenantSession, threadID: String) async throws -> OfficeConversation {
        guard UUID(uuidString: threadID) != nil else { throw DataError.notFound }

        let threads = try await fetch(
            OfficeThreadRecord.self,
            client.from("office_threads")
                .select(OfficeThreadRecord.columns)
                .eq("id", value: threadID)
                .limit(1)
        )
        guard let thread = threads.first else { throw DataError.notFound }

        let messages = try await fetch(
            OfficeMessageRecord.self,
            client.from("office_messages")
                .select(OfficeMessageRecord.columns)
                .eq("thread_id", value: threadID)
                .order("created_at", ascending: true)
                .limit(300)
        )

        let people = try await users(ids: Array(Set(messages.map { $0.senderUserID.uuidString })))

        // Attachments are job photos. They are resolved through the same table
        // and the same policy as every other photo on that job — this feature
        // adds no second media path.
        let photoIDs = messages.flatMap { $0.jobPhotoIDs ?? [] }.map { $0.uuidString }
        var references: [String: String] = [:]
        if !photoIDs.isEmpty, session.can(.jobPhotosRead) {
            let rows = try await fetch(
                JobPhotoRecord.self,
                client.from("job_photos").select(JobPhotoRecord.columns).in("id", values: Array(Set(photoIDs)))
            )
            for row in rows { references[row.id.uuidString] = row.storageReference }
        }

        var jobNumber: String?
        if let jobID = thread.jobID?.uuidString {
            jobNumber = try? await requireJob(jobID, session, query: "engineer.officeThread").number
        }

        return OfficeConversation(
            id: thread.id.uuidString,
            subject: thread.subject.nilIfBlank ?? "Message to the office",
            jobID: thread.jobID?.uuidString,
            jobNumber: jobNumber,
            customerName: nil,
            messages: messages.map { message in
                let sender = people[message.senderUserID.uuidString]
                let isMine = message.senderUserID.uuidString == session.userID
                return OfficeMessageRow(
                    id: message.id.uuidString,
                    body: message.body,
                    senderName: isMine ? "You" : (sender?.name ?? "Office"),
                    senderInitials: Self.engineerInitials(sender?.name ?? "Office"),
                    timeLabel: Formatters.shortDayAndTime(message.createdAt),
                    isMine: isMine,
                    photoReferences: (message.jobPhotoIDs ?? []).compactMap { references[$0.uuidString] }
                )
            },
            canReply: true
        )
    }

    @discardableResult
    func sendOfficeMessage(session: TenantSession, draft: OfficeMessageDraft) async throws -> String {
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw DataError.rejected("Write a message first.") }

        // Neither the company nor the sender is sent. `send_office_message`
        // takes both from the authenticated session, and resolves recipients
        // from the company's own permission grants — so this app cannot post as
        // somebody else, into another company, or to a person it chose.
        var params: [String: AnyJSON] = [
            "p_thread": SupabaseCoding.json(id: draft.threadID),
            "p_job": SupabaseCoding.json(id: draft.jobID),
            "p_engineer": .null,
            "p_subject": .string(String(draft.subject.trimmingCharacters(in: .whitespaces).prefix(120))),
            "p_body": .string(body)
        ]
        if !draft.photoIDs.isEmpty {
            params["p_photo_ids"] = .array(draft.photoIDs.map { .string($0) })
        }

        let threadID = try await performReturningID("send_office_message", params)

        record(
            "engineer.sendOfficeMessage",
            session,
            allowed: true,
            "Message sent to the office; recipients resolved server-side from role grants, never named by this app"
        )
        return threadID
    }

    func markOfficeThreadRead(session: TenantSession, threadID: String) async throws {
        guard UUID(uuidString: threadID) != nil else { return }
        try await perform("mark_office_thread_read", ["p_thread": .string(threadID)])
    }

    // MARK: - Shared site context

    /// Names, address lines, coordinates and access notes for a set of jobs.
    ///
    /// Which surface is read depends on the role, because the two are genuinely
    /// different data: an office role reads the customer directory, a field
    /// worker reads `assigned_site_customers`, which carries no billing terms
    /// and no customer notes at all.
    private func siteContext(for jobs: [Job], _ session: TenantSession) async throws -> EngineerSiteContext {
        var context = EngineerSiteContext()
        guard !jobs.isEmpty else { return context }

        let customerIDs = Array(Set(jobs.map(\.customerID)))
        let addressIDs = Array(Set(jobs.map(\.addressID)))

        if session.can(.customersReadAll) {
            let customers = try await fetch(
                CustomerRecord.self,
                client.from("customers").select(CustomerRecord.columns).in("id", values: customerIDs)
            )
            for row in customers {
                context.customerNames[row.id.uuidString] = row.name
                context.customerTypes[row.id.uuidString] = row.type
            }

            let addresses = try await fetch(
                AddressRecord.self,
                client.from("addresses").select(AddressRecord.columns).in("id", values: addressIDs)
            )
            for row in addresses {
                let key = row.id.uuidString
                context.addressLines[key] = "\(row.line1), \(row.city) \(row.state) \(row.postalCode)"
                context.accessNotes[key] = row.accessNotes?.nilIfBlank
                if let latitude = row.latitude, let longitude = row.longitude {
                    context.coordinates[key] = Coordinate(latitude: latitude, longitude: longitude)
                }
            }
        } else {
            let sites = try await fetch(
                AssignedSiteRecord.self,
                client.from("assigned_site_customers")
                    .select(AssignedSiteRecord.columns)
                    .in("id", values: customerIDs)
            )
            for row in sites {
                context.customerNames[row.id.uuidString] = row.name
                context.customerTypes[row.id.uuidString] = row.type
                let key = row.addressID.uuidString
                context.addressLines[key] = "\(row.line1), \(row.city) \(row.state) \(row.postalCode)"
                context.accessNotes[key] = row.accessNotes?.nilIfBlank
                if let latitude = row.latitude, let longitude = row.longitude {
                    context.coordinates[key] = Coordinate(latitude: latitude, longitude: longitude)
                }
            }
        }

        return context
    }

    /// Assets installed at one site, with their service history.
    ///
    /// Narrowed to the address on purpose. `equipment_tenant_select` would
    /// return the company's whole asset register to anyone holding
    /// `equipmentRead`; an engineer is shown what is at the sites they work,
    /// which is what the job actually requires.
    private func equipmentAtAddress(_ addressID: String, _ session: TenantSession) async throws -> [EquipmentProjection] {
        guard session.can(.equipmentRead) else { return [] }

        let units = try await fetch(
            EquipmentRecord.self,
            client.from("equipment")
                .select(EquipmentRecord.columns)
                .eq("address_id", value: addressID)
        )
        guard !units.isEmpty else { return [] }

        let history = try await fetch(
            EquipmentHistoryRecord.self,
            client.from("equipment_history")
                .select(EquipmentHistoryRecord.columns)
                .in("equipment_id", values: units.map { $0.id.uuidString })
        )
        let byEquipment = Dictionary(grouping: history, by: { $0.equipmentID.uuidString })

        return units.map { unit in
            let key = unit.id.uuidString
            let rows = (byEquipment[key] ?? [])
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

            return EquipmentProjection(
                id: key,
                displayName: unit.displayName.nilIfBlank ?? "Unit",
                subtitle: subtitle,
                serialNumber: unit.serialNumber,
                warrantyLabel: warranty,
                attributes: unit.attributes.map { "\($0.name) · \($0.value)" },
                history: rows
            )
        }
    }

    private func equipmentCountsByAddress(addressIDs: [String], _ session: TenantSession) async throws -> [String: Int] {
        guard session.can(.equipmentRead), !addressIDs.isEmpty else { return [:] }
        let units = try await fetch(
            EquipmentRecord.self,
            client.from("equipment")
                .select(EquipmentRecord.columns)
                .in("address_id", values: addressIDs)
        )
        var counts: [String: Int] = [:]
        for unit in units {
            guard let addressID = unit.addressID?.uuidString else { continue }
            counts[addressID, default: 0] += 1
        }
        return counts
    }

    // MARK: - Local helpers

    /// Named distinctly from the gateway's own private helpers so this file
    /// stays self-contained and cannot collide with them.
    nonisolated static func engineerInitials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "··" : String(letters).uppercased()
    }

    nonisolated static var engineerFallbackLatitude: Double { 27.9506 }
    nonisolated static var engineerFallbackLongitude: Double { -82.4572 }
}

/// Reference data for a set of engineer-visible jobs, already narrowed to
/// whatever the caller's policies were willing to return.
private nonisolated struct EngineerSiteContext: Sendable {
    var customerNames: [String: String] = [:]
    var customerTypes: [String: CustomerType] = [:]
    var addressLines: [String: String] = [:]
    /// Only ever holds a real note. A site with nothing recorded is absent from
    /// this map rather than present with a nil value, so a lookup answers
    /// `String?` and not `String??`.
    var accessNotes: [String: String] = [:]
    var coordinates: [String: Coordinate] = [:]
}
