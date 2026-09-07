import Foundation
import Supabase

// MARK: - Rows read only by the CRM surface

/// The customer record in full. The list surface reads a narrower shape; this
/// one adds the billing terms, the notes and the creation date the profile
/// screen shows.
nonisolated struct CustomerDetailRecord: Decodable, Sendable {
    let id: UUID
    let name: String
    let type: CustomerType
    let billingTerms: String?
    let notes: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, type, notes
        case billingTerms = "billing_terms"
        case createdAt = "created_at"
    }

    static let columns = "id,name,type,billing_terms,notes,created_at"
}

/// A service address in full, including the second line and the creation date
/// the profile screen orders sites by.
nonisolated struct FullAddressRecord: Decodable, Sendable {
    let id: UUID
    let customerID: UUID
    let line1: String
    let line2: String?
    let city: String
    let state: String
    let postalCode: String
    let latitude: Double?
    let longitude: Double?
    let accessNotes: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, line1, line2, city, state, latitude, longitude
        case customerID = "customer_id"
        case postalCode = "postal_code"
        case accessNotes = "access_notes"
        case createdAt = "created_at"
    }

    static let columns = """
    id,customer_id,line1,line2,city,state,postal_code,latitude,longitude,access_notes,created_at
    """
}

// MARK: - Payloads

private nonisolated struct CustomerInsertPayload: Encodable, Sendable {
    let id: String
    let company_id: String
    let name: String
    let type: String
    let billing_terms: String
    let notes: String?
    let created_at: String
    let updated_at: String
}

private nonisolated struct CustomerUpdatePayload: Encodable, Sendable {
    let name: String
    let type: String
    let billing_terms: String
    let notes: String?
    let updated_at: String
}

private nonisolated struct AddressInsertPayload: Encodable, Sendable {
    let id: String
    let company_id: String
    let customer_id: String
    let line1: String
    let line2: String?
    let city: String
    let state: String
    let postal_code: String
    let latitude: Double
    let longitude: Double
    let access_notes: String?
    let created_at: String
    let updated_at: String
}

private nonisolated struct AddressUpdatePayload: Encodable, Sendable {
    let line1: String
    let line2: String?
    let city: String
    let state: String
    let postal_code: String
    let access_notes: String?
    let updated_at: String
}

private nonisolated struct ContactInsertPayload: Encodable, Sendable {
    let id: String
    let company_id: String
    let customer_id: String
    let name: String
    let contact_role: String
    let phone: String
    let email: String?
    let is_primary: Bool
    let is_billing_contact: Bool
    let created_at: String
    let updated_at: String
}

private nonisolated struct ContactUpdatePayload: Encodable, Sendable {
    let name: String
    let contact_role: String
    let phone: String
    let email: String?
    let is_primary: Bool
    let is_billing_contact: Bool
    let updated_at: String
}

private nonisolated struct ContactPrimaryFlagPayload: Encodable, Sendable {
    let is_primary: Bool
    let updated_at: String
}

private nonisolated struct EquipmentInsertPayload: Encodable, Sendable {
    let id: String
    let company_id: String
    let address_id: String
    let category: String
    let make: String
    let model: String
    let serial_number: String
    let installed_on: String
    let warranty_expires_on: String?
    let attributes: [EquipmentAttribute]
    let created_at: String
    let updated_at: String
}

private nonisolated struct EquipmentUpdatePayload: Encodable, Sendable {
    let address_id: String
    let category: String
    let make: String
    let model: String
    let serial_number: String
    let installed_on: String
    let warranty_expires_on: String?
    let attributes: [EquipmentAttribute]
    let updated_at: String
}

/// Customer, site, contact and asset records against Supabase.
///
/// These are ordinary table writes rather than database functions, because each
/// one is a single row that a single Row Level Security policy fully describes:
/// `company_id = current_company_id()` for the tenant, `has_perm('customersManage')`
/// or `has_perm('equipmentManage')` for the role. The permission checks in this
/// file are not the boundary — they exist so a refusal arrives as a sentence
/// instead of an empty screen, exactly as elsewhere in this gateway.
///
/// Creating a customer touches three tables. PostgREST has no transaction across
/// requests, so the customer is written first and its children afterwards; if a
/// child write fails the customer is removed again before the error is raised,
/// so a half-made customer is never left behind.
extension SupabaseDataGateway {

    // MARK: - Reads

    func customerProfile(session: TenantSession, customerID: String) async throws -> CustomerProfile {
        try require(.customersReadAll, session, query: "customers.profile")
        guard UUID(uuidString: customerID) != nil else { throw DataError.notFound }

        let customers = try await fetch(
            CustomerDetailRecord.self,
            client.from("customers").select(CustomerDetailRecord.columns).eq("id", value: customerID).limit(1)
        )
        guard let customer = customers.first else {
            record("customers.profile", session, allowed: false, "Row outside scope — answered notFound")
            throw DataError.notFound
        }

        let addressRows = try await fetch(
            FullAddressRecord.self,
            client.from("addresses").select(FullAddressRecord.columns).eq("customer_id", value: customerID)
        ).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }

        let contacts = try await customerContacts(customerID, session)
        let equipment = try await customerEquipment(addressIDs: addressRows.map { $0.id.uuidString }, session)
        let equipmentCountByAddress = equipment.reduce(into: [String: Int]()) { counts, unit in
            counts[unit.addressID, default: 0] += 1
        }

        let (openJobs, closedJobs) = try await customerJobs(customerID, session)
        let quotes = try await customerQuotes(customerID, session)
        let (invoices, outstanding) = try await customerInvoices(customerID, session)

        let hasHistory = !openJobs.isEmpty || !closedJobs.isEmpty || !quotes.isEmpty || !invoices.isEmpty
        let canManage = session.can(.customersManage)

        record(
            "customers.profile",
            session,
            allowed: true,
            "\(addressRows.count) site(s), \(contacts.count) contact(s), \(equipment.count) asset(s) returned by RLS"
        )

        return CustomerProfile(
            id: customer.id.uuidString,
            name: customer.name,
            initials: Self.crmInitials(customer.name),
            type: customer.type,
            typeTitle: customer.type.title,
            billingTerms: customer.billingTerms?.nilIfBlank ?? "Not set",
            notes: customer.notes?.nilIfBlank,
            createdLabel: customer.createdAt.map { "Added \(Formatters.shortDate($0))" } ?? "",
            contacts: contacts,
            addresses: addressRows.enumerated().map { index, row in
                CustomerAddressProjection(
                    id: row.id.uuidString,
                    line1: row.line1,
                    line2: row.line2?.nilIfBlank,
                    city: row.city,
                    state: row.state,
                    postalCode: row.postalCode,
                    accessNotes: row.accessNotes?.nilIfBlank,
                    latitude: row.latitude,
                    longitude: row.longitude,
                    isPrimarySite: index == 0,
                    equipmentCount: equipmentCountByAddress[row.id.uuidString] ?? 0
                )
            },
            equipment: equipment,
            openJobs: openJobs,
            closedJobs: closedJobs,
            quotes: quotes,
            invoices: invoices,
            outstandingLabel: outstanding,
            canManage: canManage,
            canManageEquipment: session.can(.equipmentManage),
            canDelete: canManage && !hasHistory,
            deleteBlockedReason: hasHistory
                ? "This customer has jobs or documents against them. Their history stays on the account."
                : nil
        )
    }

    private func customerContacts(
        _ customerID: String,
        _ session: TenantSession
    ) async throws -> [CustomerContactProjection] {
        // Email and the billing flag are billing data. Without that permission
        // the operational view is used instead — it has neither column, so
        // there is nothing for this method to strip.
        if session.can(.customerBillingDetailsRead) {
            let rows = try await fetch(
                BillingContactRecord.self,
                client.from("customer_contacts")
                    .select(BillingContactRecord.columns)
                    .eq("customer_id", value: customerID)
            )
            return rows
                .sorted { ($0.isPrimary ? 0 : 1, $0.name) < ($1.isPrimary ? 0 : 1, $1.name) }
                .map {
                    CustomerContactProjection(
                        id: $0.id.uuidString,
                        name: $0.name,
                        initials: Self.crmInitials($0.name),
                        roleTitle: $0.contactRole?.nilIfBlank,
                        phone: $0.phone?.nilIfBlank,
                        email: $0.email?.nilIfBlank,
                        isPrimary: $0.isPrimary,
                        isBillingContact: $0.isBillingContact
                    )
                }
        }

        let rows = try await fetch(
            SiteContactRecord.self,
            client.from("site_contacts_operational")
                .select(SiteContactRecord.columns)
                .eq("customer_id", value: customerID)
        )
        return rows.map {
            CustomerContactProjection(
                id: $0.id.uuidString,
                name: $0.name,
                initials: Self.crmInitials($0.name),
                roleTitle: $0.contactRole?.nilIfBlank,
                phone: $0.phone?.nilIfBlank,
                email: nil,
                isPrimary: true,
                isBillingContact: false
            )
        }
    }

    /// Assets at a set of sites. Empty without `equipmentRead`, which is also
    /// what the policy on `equipment` returns for such a role.
    func customerEquipment(
        addressIDs: [String],
        _ session: TenantSession
    ) async throws -> [CustomerEquipmentProjection] {
        guard session.can(.equipmentRead), !addressIDs.isEmpty else { return [] }

        let units = try await fetch(
            EquipmentRecord.self,
            client.from("equipment").select(EquipmentRecord.columns).in("address_id", values: addressIDs)
        )
        guard !units.isEmpty else { return [] }

        let history = try await fetch(
            EquipmentHistoryRecord.self,
            client.from("equipment_history")
                .select(EquipmentHistoryRecord.columns)
                .in("equipment_id", values: units.map { $0.id.uuidString })
        )
        let historyCounts = history.reduce(into: [String: Int]()) { counts, row in
            counts[row.equipmentID.uuidString, default: 0] += 1
        }

        return units
            .sorted { $0.displayName < $1.displayName }
            .map { unit in
                var warranty: String?
                if let expires = unit.warrantyExpiresOn {
                    warranty = expires > Date()
                        ? "Warranty to \(Formatters.shortDate(expires))"
                        : "Warranty expired \(Formatters.shortDate(expires))"
                }
                let isActive = !unit.attributes.contains {
                    $0.name.caseInsensitiveCompare("Status") == .orderedSame
                        && $0.value.caseInsensitiveCompare("Inactive") == .orderedSame
                }
                return CustomerEquipmentProjection(
                    id: unit.id.uuidString,
                    addressID: unit.addressID?.uuidString ?? "",
                    displayName: unit.displayName.isEmpty ? unit.category : unit.displayName,
                    category: unit.category,
                    serialNumber: unit.serialNumber,
                    installedLabel: unit.installedOn.map { "Installed \(Formatters.shortDate($0))" },
                    warrantyLabel: warranty,
                    attributes: unit.attributes.map { "\($0.name) · \($0.value)" },
                    isActive: isActive,
                    historyCount: historyCounts[unit.id.uuidString] ?? 0
                )
            }
    }

    private func customerJobs(
        _ customerID: String,
        _ session: TenantSession
    ) async throws -> (open: [CustomerJobProjection], closed: [CustomerJobProjection]) {
        guard session.can(.jobsReadAll) else { return ([], []) }

        let rows = try await fetch(
            JobRecord.self,
            client.from("jobs").select(JobRecord.columns).eq("customer_id", value: customerID)
        )
        guard !rows.isEmpty else { return ([], []) }

        let assignmentRows = try await fetch(
            AssignmentRecord.self,
            client.from("field_worker_assignments")
                .select(AssignmentRecord.columns)
                .in("job_id", values: rows.map { $0.id.uuidString })
        )
        var workerByJob: [String: String] = [:]
        for row in assignmentRows where row.isPrimary {
            workerByJob[row.jobID.uuidString] = row.userID.uuidString
        }
        let people = try await users(ids: Array(Set(workerByJob.values)))

        let projections = rows
            .sorted { ($0.scheduledStart ?? $0.createdAt) > ($1.scheduledStart ?? $1.createdAt) }
            .map { job -> CustomerJobProjection in
                let workerID = workerByJob[job.id.uuidString]
                return CustomerJobProjection(
                    id: job.id.uuidString,
                    number: job.number,
                    title: job.title,
                    dateLabel: job.scheduledStart.map { Formatters.dayAndTime($0) } ?? "Not scheduled",
                    badge: StatusBadge(text: job.status.title(session.terms), tone: job.status.tone),
                    isOpen: job.status.isOpen,
                    workerName: workerID.flatMap { people[$0]?.name }
                )
            }

        return (projections.filter(\.isOpen), projections.filter { !$0.isOpen })
    }

    private func customerQuotes(
        _ customerID: String,
        _ session: TenantSession
    ) async throws -> [CustomerDocumentProjection] {
        guard session.can(.quotesRead) else { return [] }

        if session.can(.quoteFinancialsRead) {
            let code = try await currencyCode(session)
            let rows = try await fetch(
                QuoteRecord.self,
                client.from("quotes").select(QuoteRecord.columns).eq("customer_id", value: customerID)
            )
            return rows
                .sorted { $0.createdAt > $1.createdAt }
                .map {
                    CustomerDocumentProjection(
                        id: $0.id.uuidString,
                        number: $0.number,
                        title: $0.title,
                        badge: StatusBadge(text: $0.status.title, tone: $0.status.tone),
                        dateLabel: Formatters.shortDate($0.createdAt),
                        amountLabel: Formatters.currency(SupabaseCoding.decimal($0.total), code: code)
                    )
                }
        }

        let rows = try await fetch(
            QuoteOperationalRecord.self,
            client.from("quotes_operational")
                .select("id,number,status,title,created_at")
                .eq("customer_id", value: customerID)
        )
        return rows.map {
            CustomerDocumentProjection(
                id: $0.id.uuidString,
                number: $0.number,
                title: $0.number,
                badge: StatusBadge(text: $0.status.title, tone: $0.status.tone),
                dateLabel: "",
                amountLabel: nil
            )
        }
    }

    private func customerInvoices(
        _ customerID: String,
        _ session: TenantSession
    ) async throws -> (documents: [CustomerDocumentProjection], outstanding: String?) {
        guard session.can(.invoicesRead) else { return ([], nil) }

        let rows = try await fetch(
            InvoiceRecord.self,
            client.from("invoices").select(InvoiceRecord.columns).eq("customer_id", value: customerID)
        )
        guard !rows.isEmpty else { return ([], nil) }

        let code = try await currencyCode(session)
        let documents = rows
            .sorted { $0.issueDate > $1.issueDate }
            .map {
                CustomerDocumentProjection(
                    id: $0.id.uuidString,
                    number: $0.number,
                    title: $0.title,
                    badge: StatusBadge(text: $0.status.title, tone: $0.status.tone),
                    dateLabel: Formatters.shortDate($0.issueDate),
                    amountLabel: Formatters.currency(
                        SupabaseCoding.decimal($0.total),
                        code: $0.currencyCode.nilIfBlank ?? code
                    )
                )
            }

        // The balance is a billing fact, so it is only assembled for a role
        // that may read billing details.
        guard session.can(.customerBillingDetailsRead) else { return (documents, nil) }
        let outstanding = rows
            .filter { $0.status != .void && $0.status != .paid }
            .reduce(Decimal(0)) { $0 + SupabaseCoding.decimal($1.balance) }
        return (documents, Formatters.currency(outstanding, code: code))
    }

    // MARK: - Customer writes

    func createCustomer(session: TenantSession, draft: CustomerDraft) async throws -> String {
        try require(.customersManage, session, query: "customers.create")
        if let problem = draft.validationMessage(requiresAddress: true) {
            throw DataError.rejected(problem)
        }

        let now = SupabaseCoding.timestamp(Date())
        let customerID = UUID().uuidString

        try await performWrite(
            client.from("customers").insert(
                CustomerInsertPayload(
                    id: customerID,
                    company_id: session.companyID,
                    name: draft.name.tidied,
                    type: draft.type.rawValue,
                    billing_terms: draft.billingTerms.nilIfBlank ?? "Net 30",
                    notes: draft.notes.nilIfBlank,
                    created_at: now,
                    updated_at: now
                )
            )
        )

        // The children follow. Anything that fails here takes the customer with
        // it, so the directory never gains a name with no site behind it.
        do {
            _ = try await insertAddress(
                session: session,
                customerID: customerID,
                draft: AddressDraft(
                    line1: draft.line1,
                    line2: draft.line2,
                    city: draft.city,
                    state: draft.state,
                    postalCode: draft.postalCode,
                    accessNotes: draft.accessNotes
                )
            )

            if draft.hasContact {
                _ = try await insertContact(
                    session: session,
                    customerID: customerID,
                    draft: ContactDraft(
                        name: draft.contactName.isEmpty ? draft.name.tidied : draft.contactName,
                        contactRole: draft.contactRole,
                        phone: draft.phone,
                        email: draft.email,
                        isPrimary: true,
                        isBillingContact: true
                    )
                )
            }
        } catch {
            try? await performWrite(client.from("customers").delete().eq("id", value: customerID))
            record("customers.create", session, allowed: false, "Rolled back — the site or contact could not be written")
            throw error
        }

        record("customers.create", session, allowed: true, "Customer, first site and primary contact written in company scope")
        return customerID
    }

    func updateCustomer(session: TenantSession, customerID: String, draft: CustomerDraft) async throws {
        try require(.customersManage, session, query: "customers.update")
        if let problem = draft.validationMessage(requiresAddress: false) {
            throw DataError.rejected(problem)
        }

        try await performWrite(
            client.from("customers")
                .update(
                    CustomerUpdatePayload(
                        name: draft.name.tidied,
                        type: draft.type.rawValue,
                        billing_terms: draft.billingTerms.nilIfBlank ?? "Net 30",
                        notes: draft.notes.nilIfBlank,
                        updated_at: SupabaseCoding.timestamp(Date())
                    )
                )
                .eq("id", value: customerID)
        )

        // The primary contact rides along with the customer form, because that
        // is how the office thinks about it: one customer, one person to call.
        if draft.hasContact, session.can(.customerBillingDetailsRead) {
            let existing = try await fetch(
                BillingContactRecord.self,
                client.from("customer_contacts")
                    .select(BillingContactRecord.columns)
                    .eq("customer_id", value: customerID)
                    .eq("is_primary", value: true)
                    .limit(1)
            )
            let contact = ContactDraft(
                id: existing.first?.id.uuidString,
                name: draft.contactName.isEmpty ? draft.name.tidied : draft.contactName,
                contactRole: draft.contactRole,
                phone: draft.phone,
                email: draft.email,
                isPrimary: true,
                isBillingContact: existing.first?.isBillingContact ?? true
            )
            _ = try await saveCustomerContact(session: session, customerID: customerID, draft: contact)
        }

        record("customers.update", session, allowed: true, "Customer record updated in company scope")
    }

    /// Removes a customer that has no history.
    ///
    /// A customer with jobs, quotes or invoices is never removed — a
    /// field-service business does not discard its own record of work done. The
    /// check runs here for a clear message, and the database's foreign keys
    /// refuse it independently.
    func deleteCustomer(session: TenantSession, customerID: String) async throws {
        try require(.customersManage, session, query: "customers.delete")

        let jobs = try await fetch(
            JobCountRecord.self,
            client.from("jobs").select(JobCountRecord.columns).eq("customer_id", value: customerID).limit(1)
        )
        guard jobs.isEmpty else {
            record("customers.delete", session, allowed: false, "Refused — the customer has job history")
            throw DataError.rejected("This customer has jobs against them, so their record stays on the account.")
        }

        let addresses = try await fetch(
            FullAddressRecord.self,
            client.from("addresses").select(FullAddressRecord.columns).eq("customer_id", value: customerID)
        )
        let addressIDs = addresses.map { $0.id.uuidString }
        if !addressIDs.isEmpty {
            try await performWrite(client.from("equipment").delete().in("address_id", values: addressIDs))
        }
        try await performWrite(client.from("customer_contacts").delete().eq("customer_id", value: customerID))
        try await performWrite(client.from("addresses").delete().eq("customer_id", value: customerID))
        try await performWrite(client.from("customers").delete().eq("id", value: customerID))

        record("customers.delete", session, allowed: true, "Customer with no job history removed, sites and contacts with it")
    }

    // MARK: - Address writes

    func saveCustomerAddress(session: TenantSession, customerID: String, draft: AddressDraft) async throws -> String {
        try require(.customersManage, session, query: "customers.saveAddress")
        if let problem = draft.validationMessage { throw DataError.rejected(problem) }

        if let addressID = draft.id {
            try await performWrite(
                client.from("addresses")
                    .update(
                        AddressUpdatePayload(
                            line1: draft.line1.tidied,
                            line2: draft.line2.nilIfBlank,
                            city: draft.city.tidied,
                            state: draft.state.tidied,
                            postal_code: draft.postalCode.tidied,
                            access_notes: draft.accessNotes.nilIfBlank,
                            updated_at: SupabaseCoding.timestamp(Date())
                        )
                    )
                    .eq("id", value: addressID)
            )
            record("customers.saveAddress", session, allowed: true, "Site updated in company scope")
            return addressID
        }

        let id = try await insertAddress(session: session, customerID: customerID, draft: draft)
        record("customers.saveAddress", session, allowed: true, "Site added in company scope")
        return id
    }

    private func insertAddress(session: TenantSession, customerID: String, draft: AddressDraft) async throws -> String {
        if let problem = draft.validationMessage { throw DataError.rejected(problem) }
        let id = UUID().uuidString
        let now = SupabaseCoding.timestamp(Date())

        try await performWrite(
            client.from("addresses").insert(
                AddressInsertPayload(
                    id: id,
                    company_id: session.companyID,
                    customer_id: customerID,
                    line1: draft.line1.tidied,
                    line2: draft.line2.nilIfBlank,
                    city: draft.city.tidied,
                    state: draft.state.tidied,
                    postal_code: draft.postalCode.tidied,
                    // Not invented. Zero means "no position recorded", which is
                    // exactly how the read path already treats it.
                    latitude: draft.latitude ?? 0,
                    longitude: draft.longitude ?? 0,
                    access_notes: draft.accessNotes.nilIfBlank,
                    created_at: now,
                    updated_at: now
                )
            )
        )
        return id
    }

    // MARK: - Contact writes

    func saveCustomerContact(session: TenantSession, customerID: String, draft: ContactDraft) async throws -> String {
        try require(.customersManage, session, query: "customers.saveContact")
        if let problem = draft.validationMessage { throw DataError.rejected(problem) }

        let now = SupabaseCoding.timestamp(Date())

        if let contactID = draft.id {
            if draft.isPrimary { try await clearOtherPrimaryContacts(customerID: customerID, except: contactID) }
            try await performWrite(
                client.from("customer_contacts")
                    .update(
                        ContactUpdatePayload(
                            name: draft.name.tidied,
                            contact_role: draft.contactRole.nilIfBlank ?? "Contact",
                            phone: draft.phone.tidied,
                            email: draft.email.nilIfBlank,
                            is_primary: draft.isPrimary,
                            is_billing_contact: draft.isBillingContact,
                            updated_at: now
                        )
                    )
                    .eq("id", value: contactID)
            )
            record("customers.saveContact", session, allowed: true, "Contact updated in company scope")
            return contactID
        }

        let id = try await insertContact(session: session, customerID: customerID, draft: draft)
        record("customers.saveContact", session, allowed: true, "Contact added in company scope")
        return id
    }

    private func insertContact(session: TenantSession, customerID: String, draft: ContactDraft) async throws -> String {
        let id = UUID().uuidString
        let now = SupabaseCoding.timestamp(Date())
        if draft.isPrimary { try await clearOtherPrimaryContacts(customerID: customerID, except: id) }

        try await performWrite(
            client.from("customer_contacts").insert(
                ContactInsertPayload(
                    id: id,
                    company_id: session.companyID,
                    customer_id: customerID,
                    name: draft.name.tidied,
                    contact_role: draft.contactRole.nilIfBlank ?? "Contact",
                    phone: draft.phone.tidied,
                    email: draft.email.nilIfBlank,
                    is_primary: draft.isPrimary,
                    is_billing_contact: draft.isBillingContact,
                    created_at: now,
                    updated_at: now
                )
            )
        )
        return id
    }

    /// Exactly one primary contact per customer. Demoting the others is part of
    /// promoting this one, not a separate thing the caller has to remember.
    private func clearOtherPrimaryContacts(customerID: String, except contactID: String) async throws {
        try await performWrite(
            client.from("customer_contacts")
                .update(ContactPrimaryFlagPayload(is_primary: false, updated_at: SupabaseCoding.timestamp(Date())))
                .eq("customer_id", value: customerID)
                .eq("is_primary", value: true)
                .neq("id", value: contactID)
        )
    }

    // MARK: - Equipment writes

    func saveEquipment(session: TenantSession, customerID: String, draft: EquipmentDraft) async throws -> String {
        try require(.equipmentManage, session, query: "equipment.save")
        if let problem = draft.validationMessage { throw DataError.rejected(problem) }

        let now = SupabaseCoding.timestamp(Date())
        let warranty = draft.hasWarranty ? SupabaseCoding.day(draft.warrantyExpiresOn) : nil

        if let equipmentID = draft.id {
            try await performWrite(
                client.from("equipment")
                    .update(
                        EquipmentUpdatePayload(
                            address_id: draft.addressID,
                            category: draft.category.tidied,
                            make: draft.make.tidied,
                            model: draft.model.tidied,
                            serial_number: draft.serialNumber.tidied,
                            installed_on: SupabaseCoding.day(draft.installedOn),
                            warranty_expires_on: warranty,
                            attributes: draft.attributePairs,
                            updated_at: now
                        )
                    )
                    .eq("id", value: equipmentID)
            )
            record("equipment.save", session, allowed: true, "Asset updated at a site in company scope")
            return equipmentID
        }

        let id = UUID().uuidString
        try await performWrite(
            client.from("equipment").insert(
                EquipmentInsertPayload(
                    id: id,
                    company_id: session.companyID,
                    address_id: draft.addressID,
                    category: draft.category.tidied,
                    make: draft.make.tidied,
                    model: draft.model.tidied,
                    serial_number: draft.serialNumber.tidied,
                    installed_on: SupabaseCoding.day(draft.installedOn),
                    warranty_expires_on: warranty,
                    attributes: draft.attributePairs,
                    created_at: now,
                    updated_at: now
                )
            )
        )
        record("equipment.save", session, allowed: true, "Asset registered at a site in company scope")
        return id
    }

    // MARK: - Helper

    nonisolated static func crmInitials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "··" : String(letters).uppercased()
    }
}
