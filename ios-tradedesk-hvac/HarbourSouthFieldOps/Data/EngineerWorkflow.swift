import Foundation

/// Default engineer-workspace behaviour, assembled from surfaces every gateway
/// already implements.
///
/// WHY THESE ARE DEFAULTS RATHER THAN A SECOND IMPLEMENTATION
/// The engineer screens need schedule, sites, equipment and work history. All
/// four are *views of jobs the caller is assigned to*, and both gateways
/// already answer that question correctly — the mock through its scoped store,
/// Supabase through Row Level Security. Deriving from `jobs(session:query:)`
/// here means the assigned-only rule is enforced in exactly one place per
/// gateway instead of being restated, and it cannot drift.
///
/// `SupabaseDataGateway` overrides most of these with richer, fewer-round-trip
/// versions that can also reach site notes and the asset register. The
/// behaviour is the same; only the amount of detail differs.
///
/// Messaging has no default worth having: the development stack has no office
/// to reach, so it says so rather than presenting an inbox that would never
/// fill.
extension DataGateway {

    // MARK: - Schedule

    func engineerSchedule(session: TenantSession, dayCount: Int) async throws -> EngineerSchedule {
        guard session.can(.calendarReadOwnOnly) || session.can(.calendarReadAll) else {
            throw DataError.notPermitted(.calendarReadOwnOnly)
        }

        let rows = try await jobs(session: session, query: JobQuery(dateScope: .all))
        return Self.assembleSchedule(rows: rows, dayCount: dayCount, session: session)
    }

    /// Shared by the default above and by the Supabase override, so both
    /// produce an identically shaped schedule.
    static func assembleSchedule(
        rows: [JobRow],
        dayCount: Int,
        session: TenantSession
    ) -> EngineerSchedule {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Only work that is still ahead. A schedule is what is coming, not an
        // archive — finished visits belong in My Work.
        let upcoming = rows.filter { row in
            guard let start = row.scheduledStart else { return false }
            return start >= today && row.status.isOpen
        }

        let days: [EngineerScheduleDay] = (0..<max(dayCount, 1)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let stops = upcoming
                .filter { row in
                    guard let start = row.scheduledStart else { return false }
                    return calendar.isDate(start, inSameDayAs: day)
                }
                .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }
                .map { row in
                    EngineerScheduleStop(
                        jobID: row.id,
                        number: row.number,
                        timeLabel: row.timeLabel,
                        durationLabel: nil,
                        customerName: row.customerName,
                        addressLine: row.addressShort,
                        jobTitle: row.title,
                        kindTitle: row.kindTitle,
                        status: row.status,
                        badge: row.badge,
                        isUrgent: row.isUrgent
                    )
                }

            // Today and tomorrow always appear, even when empty, because their
            // emptiness is itself the answer the engineer came for.
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
            throw DataError.notPermitted(.customersReadAssignedSiteOnly)
        }

        let rows = try await jobs(session: session, query: JobQuery(dateScope: .all))
        return Self.assembleSites(rows: rows, query: query)
    }

    static func assembleSites(rows: [JobRow], query: String) -> [EngineerSiteRow] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // Grouped by the site itself. An engineer services a place, so the
        // place is the unit — not the account it is billed to.
        let grouped = Dictionary(grouping: rows) { row in
            EngineerSiteKey.make(customer: row.customerName, address: row.addressShort)
        }

        return grouped
            .map { key, group -> EngineerSiteRow in
                let sorted = group.sorted {
                    ($0.scheduledStart ?? .distantPast) > ($1.scheduledStart ?? .distantPast)
                }
                let lastClosed = sorted.first { !$0.status.isOpen }
                return EngineerSiteRow(
                    id: key,
                    customerID: "",
                    customerName: group.first?.customerName ?? "Customer",
                    initials: Self.initials(group.first?.customerName ?? ""),
                    addressLine: group.first?.addressShort ?? "",
                    equipmentCount: 0,
                    visitCount: group.count,
                    lastVisitLabel: lastClosed?.scheduledStart.map { Formatters.shortDate($0) },
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
    }

    func engineerSiteDetail(session: TenantSession, addressID: String) async throws -> EngineerSiteDetail {
        guard session.can(.customersReadAssignedSiteOnly) || session.can(.customersReadAll) else {
            throw DataError.notPermitted(.customersReadAssignedSiteOnly)
        }

        let rows = try await jobs(session: session, query: JobQuery(dateScope: .all))
        let atSite = rows.filter {
            EngineerSiteKey.make(customer: $0.customerName, address: $0.addressShort) == addressID
        }
        guard let first = atSite.first else { throw DataError.notFound }

        // One job's full record supplies the site's contact, access notes and
        // installed asset. Reading the most recent is enough — they describe
        // the site, not the visit.
        let anchor = atSite
            .sorted { ($0.scheduledStart ?? .distantPast) > ($1.scheduledStart ?? .distantPast) }
            .first
        let detail = try? await fieldWorkerJobDetail(session: session, jobID: anchor?.id ?? first.id)

        var contacts: [EngineerSiteContact] = []
        if let name = detail?.siteContactName {
            contacts.append(
                EngineerSiteContact(id: "primary", name: name, roleTitle: "Site contact", phone: detail?.siteContactPhone)
            )
        }

        return EngineerSiteDetail(
            id: addressID,
            customerID: "",
            customerName: first.customerName,
            typeTitle: "Site",
            addressLine: detail?.addressLine ?? first.addressShort,
            latitude: detail?.latitude ?? 0,
            longitude: detail?.longitude ?? 0,
            accessNotes: detail?.accessNotes,
            siteNotes: nil,
            contacts: contacts,
            equipment: detail?.equipment.map { [$0] } ?? [],
            openVisits: atSite.filter { $0.status.isOpen }.map { Self.visitRow($0, isMine: true) },
            pastVisits: atSite.filter { !$0.status.isOpen }.map { Self.visitRow($0, isMine: true) },
            canUpdateEquipment: session.can(.equipmentManage)
        )
    }

    static func visitRow(_ row: JobRow, isMine: Bool) -> EngineerVisitRow {
        EngineerVisitRow(
            id: row.id,
            number: row.number,
            title: row.title,
            dateLabel: row.scheduledStart.map { Formatters.shortDate($0) } ?? "No date",
            kindTitle: row.kindTitle,
            badge: row.badge,
            isMine: isMine
        )
    }

    // MARK: - Work history

    func engineerWorkHistory(session: TenantSession, limit: Int) async throws -> [EngineerWorkRecord] {
        guard session.can(.jobsReadAssignedOnly) || session.can(.jobsReadAll) else {
            throw DataError.notPermitted(.jobsReadAssignedOnly)
        }

        let rows = try await jobs(session: session, query: JobQuery(dateScope: .all))
        return rows
            .filter { !$0.status.isOpen && $0.status != .cancelled }
            .sorted { ($0.scheduledStart ?? .distantPast) > ($1.scheduledStart ?? .distantPast) }
            .prefix(max(limit, 1))
            .map { row in
                let when = row.scheduledStart ?? Date()
                return EngineerWorkRecord(
                    id: row.id,
                    number: row.number,
                    title: row.title,
                    customerName: row.customerName,
                    addressLine: row.addressShort,
                    kindTitle: row.kindTitle,
                    completedAt: when,
                    completedLabel: Formatters.shortDate(when),
                    noteCount: 0,
                    photoCount: 0,
                    hasSignature: false
                )
            }
    }

    // MARK: - Profile

    func engineerProfile(session: TenantSession) async throws -> EngineerProfile {
        let overview = try? await moreOverview(session: session)
        let day = try? await fieldWorkerDay(session: session)
        let rows = (try? await jobs(session: session, query: JobQuery(dateScope: .all))) ?? []

        let stops = day?.stops ?? []
        let activeStatus = stops.first(where: { $0.status.isFieldActive })?.status

        return EngineerProfile(
            userID: session.userID,
            name: session.displayName,
            initials: Self.initials(session.displayName),
            email: session.email,
            phone: nil,
            roleTitle: session.roleTitle,
            companyName: overview?.companyName ?? "",
            tradeTitle: overview?.tradeTitle ?? session.trade.title,
            dutyState: .available,
            availability: EngineerAvailability.resolve(duty: .available, activeJobStatus: activeStatus),
            dutyChangedLabel: nil,
            activeJobNumber: stops.first(where: { $0.status.isFieldActive })?.number,
            jobsToday: stops.count,
            completedToday: stops.filter { !$0.status.isOpen }.count,
            upcomingCount: rows.filter { $0.status.isOpen }.count,
            completedAllTime: rows.filter { !$0.status.isOpen && $0.status != .cancelled }.count
        )
    }

    func updateDutyState(session: TenantSession, state: DutyState) async throws {
        throw DataError.rejected("Availability is recorded against your real company account. Sign in to your company to set it.")
    }

    // MARK: - Office messaging

    func officeInbox(session: TenantSession) async throws -> OfficeInbox {
        .unavailable("Messaging reaches your company's office through the live database. This development account has no office behind it.")
    }

    func officeConversation(session: TenantSession, threadID: String) async throws -> OfficeConversation {
        throw DataError.notFound
    }

    @discardableResult
    func sendOfficeMessage(session: TenantSession, draft: OfficeMessageDraft) async throws -> String {
        throw DataError.rejected("Messaging reaches your company's office through the live database. This development account has no office behind it.")
    }

    func markOfficeThreadRead(session: TenantSession, threadID: String) async throws {}

    // MARK: - Helpers

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "··" : String(letters).uppercased()
    }
}

/// Stable identity for a site when the gateway cannot supply a real address id.
///
/// The Supabase gateway always can, and uses the address's own id. This only
/// backs the derived default, and stays inside one gateway, so the two id
/// spaces never meet.
nonisolated enum EngineerSiteKey {
    static func make(customer: String, address: String) -> String {
        "site:\(customer.lowercased())|\(address.lowercased())"
    }
}
