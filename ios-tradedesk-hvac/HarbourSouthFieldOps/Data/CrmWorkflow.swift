import Foundation

// MARK: - Drafts

/// A customer as the office fills one in.
///
/// `companyID` is absent on purpose: the gateway takes it from the authenticated
/// session, so a caller can never write into another tenant.
///
/// First name, last name, phone and email describe the customer's **primary
/// contact**, because that is where the live schema keeps them
/// (`customer_contacts`). The customer record itself carries the account name,
/// its classification, billing terms and notes.
nonisolated struct CustomerDraft: Hashable, Sendable {
    /// Account name — a household name or a company name.
    var name: String = ""
    var type: CustomerType = .residential
    var billingTerms: String = "Net 30"
    var notes: String = ""

    // Primary contact
    var firstName: String = ""
    var lastName: String = ""
    var contactRole: String = ""
    var phone: String = ""
    var email: String = ""

    // Billing / first service address. Only used when creating.
    var line1: String = ""
    var line2: String = ""
    var city: String = ""
    var state: String = ""
    var postalCode: String = ""
    var accessNotes: String = ""

    var contactName: String {
        "\(firstName.tidied) \(lastName.tidied)".trimmingCharacters(in: .whitespaces)
    }

    var hasContact: Bool { !contactName.isEmpty || !phone.tidied.isEmpty || !email.tidied.isEmpty }

    /// The single reason this draft can't be saved, or `nil`.
    ///
    /// Deliberately one message at a time: a form that lists five problems at
    /// once is read by nobody.
    func validationMessage(requiresAddress: Bool) -> String? {
        if name.tidied.isEmpty { return "Give the customer a name." }
        if !email.tidied.isEmpty, !email.contains("@") || email.contains(" ") {
            return "That email address doesn't look right."
        }
        guard requiresAddress else { return nil }
        if line1.tidied.isEmpty { return "Add the street address for the first service site." }
        if city.tidied.isEmpty { return "Add the city for the service address." }
        if state.tidied.isEmpty { return "Add the state for the service address." }
        if postalCode.tidied.isEmpty { return "Add the ZIP code for the service address." }
        return nil
    }
}

/// One service address, as the office fills it in. `id` nil creates, a real id
/// edits that row in place.
nonisolated struct AddressDraft: Hashable, Sendable, Identifiable {
    var id: String?
    var line1: String = ""
    var line2: String = ""
    var city: String = ""
    var state: String = ""
    var postalCode: String = ""
    var accessNotes: String = ""
    /// Recorded only where the company has one. Never invented.
    var latitude: Double?
    var longitude: Double?

    var validationMessage: String? {
        if line1.tidied.isEmpty { return "Add the street address." }
        if city.tidied.isEmpty { return "Add the city." }
        if state.tidied.isEmpty { return "Add the state." }
        if postalCode.tidied.isEmpty { return "Add the ZIP code." }
        return nil
    }
}

/// A serviceable asset, as the office or the engineer records it.
///
/// `category`, `make`, `model` and `serialNumber` are columns. Everything a
/// specific trade cares about — where the unit sits, its refrigerant, its
/// circuit rating — goes into `attributes`, which is a `jsonb` column, so a new
/// trade never needs a schema change.
nonisolated struct EquipmentDraft: Hashable, Sendable, Identifiable {
    var id: String?
    var addressID: String = ""
    var category: String = ""
    var make: String = ""
    var model: String = ""
    var serialNumber: String = ""
    var installedOn: Date = Date()
    var hasWarranty: Bool = false
    var warrantyExpiresOn: Date = Date()
    /// Where on site the unit is — "Roof, north bay", "Utility cupboard".
    var location: String = ""
    var systemNotes: String = ""
    var isActive: Bool = true

    var validationMessage: String? {
        if addressID.isEmpty { return "Choose the site this unit is installed at." }
        if category.tidied.isEmpty { return "Say what kind of unit this is." }
        if make.tidied.isEmpty && model.tidied.isEmpty {
            return "Add at least a manufacturer or a model."
        }
        return nil
    }

    /// The trade-specific facts, folded into the `attributes` column.
    var attributePairs: [EquipmentAttribute] {
        var pairs: [EquipmentAttribute] = []
        if !location.tidied.isEmpty { pairs.append(EquipmentAttribute(name: "Location", value: location.tidied)) }
        if !systemNotes.tidied.isEmpty { pairs.append(EquipmentAttribute(name: "Notes", value: systemNotes.tidied)) }
        if !isActive { pairs.append(EquipmentAttribute(name: "Status", value: "Inactive")) }
        return pairs
    }
}

/// One more person at a customer. The primary contact is created with the
/// customer; this adds the site manager, the caretaker, the accounts clerk.
nonisolated struct ContactDraft: Hashable, Sendable, Identifiable {
    var id: String?
    var name: String = ""
    var contactRole: String = ""
    var phone: String = ""
    var email: String = ""
    var isPrimary: Bool = false
    var isBillingContact: Bool = false

    var validationMessage: String? {
        if name.tidied.isEmpty { return "Give the contact a name." }
        if !email.tidied.isEmpty, !email.contains("@") || email.contains(" ") {
            return "That email address doesn't look right."
        }
        return nil
    }
}

// MARK: - Projections

nonisolated struct CustomerContactProjection: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let initials: String
    let roleTitle: String?
    let phone: String?
    /// Only assembled for roles holding `customerBillingDetailsRead`.
    let email: String?
    let isPrimary: Bool
    let isBillingContact: Bool
}

nonisolated struct CustomerAddressProjection: Identifiable, Hashable, Sendable {
    let id: String
    let line1: String
    let line2: String?
    let city: String
    let state: String
    let postalCode: String
    let accessNotes: String?
    let latitude: Double?
    let longitude: Double?
    /// The oldest address on the account — the one the office treats as the
    /// main site until a job says otherwise.
    let isPrimarySite: Bool
    let equipmentCount: Int

    var singleLine: String {
        let second = line2.map { $0.isEmpty ? "" : "\($0), " } ?? ""
        return "\(line1), \(second)\(city) \(state) \(postalCode)"
    }

    var draft: AddressDraft {
        AddressDraft(
            id: id,
            line1: line1,
            line2: line2 ?? "",
            city: city,
            state: state,
            postalCode: postalCode,
            accessNotes: accessNotes ?? "",
            latitude: latitude,
            longitude: longitude
        )
    }
}

/// A serviceable asset as the customer screen and the engineer's job screen show
/// it. Carries the address it sits at so a site can be listed with its units.
nonisolated struct CustomerEquipmentProjection: Identifiable, Hashable, Sendable {
    let id: String
    let addressID: String
    let displayName: String
    let category: String
    let serialNumber: String
    let installedLabel: String?
    let warrantyLabel: String?
    let attributes: [String]
    let isActive: Bool
    let historyCount: Int

    var draft: EquipmentDraft {
        var draft = EquipmentDraft(id: id, addressID: addressID)
        draft.category = category
        let parts = displayName.split(separator: " ", maxSplits: 1).map(String.init)
        draft.make = parts.first ?? ""
        draft.model = parts.count > 1 ? parts[1] : ""
        draft.serialNumber = serialNumber
        draft.isActive = isActive
        for attribute in attributes {
            let pieces = attribute.split(separator: "·", maxSplits: 1).map { String($0).tidied }
            guard pieces.count == 2 else { continue }
            if pieces[0].caseInsensitiveCompare("Location") == .orderedSame { draft.location = pieces[1] }
            if pieces[0].caseInsensitiveCompare("Notes") == .orderedSame { draft.systemNotes = pieces[1] }
        }
        return draft
    }
}

/// One job in a customer's history, money-free by construction.
nonisolated struct CustomerJobProjection: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let dateLabel: String
    let badge: StatusBadge
    let isOpen: Bool
    let workerName: String?
}

/// A document reference on the customer screen. Carries a money label only when
/// the caller's role holds the matching financial read permission.
nonisolated struct CustomerDocumentProjection: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let badge: StatusBadge
    let dateLabel: String
    /// Nil unless the role may see the money on this kind of document.
    let amountLabel: String?
}

/// Everything the customer screen shows, already narrowed to what this caller's
/// role was allowed to read.
nonisolated struct CustomerProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let initials: String
    let type: CustomerType
    let typeTitle: String
    let billingTerms: String
    let notes: String?
    let createdLabel: String

    let contacts: [CustomerContactProjection]
    let addresses: [CustomerAddressProjection]
    let equipment: [CustomerEquipmentProjection]
    let openJobs: [CustomerJobProjection]
    let closedJobs: [CustomerJobProjection]
    /// Present only with `quotesRead`.
    let quotes: [CustomerDocumentProjection]
    /// Present only with `invoicesRead`.
    let invoices: [CustomerDocumentProjection]
    /// Outstanding balance across this customer's invoices. Present only with
    /// `customerBillingDetailsRead` **and** `invoicesRead`.
    let outstandingLabel: String?

    let canManage: Bool
    let canManageEquipment: Bool
    /// False whenever the customer still has jobs, quotes or invoices attached —
    /// history is not something a field-service business throws away.
    let canDelete: Bool
    let deleteBlockedReason: String?

    /// The editor's starting values, primary contact folded back in.
    var draft: CustomerDraft {
        var draft = CustomerDraft()
        draft.name = name
        draft.type = type
        draft.billingTerms = billingTerms
        draft.notes = notes ?? ""
        if let primary = contacts.first(where: \.isPrimary) ?? contacts.first {
            let parts = primary.name.split(separator: " ", maxSplits: 1).map(String.init)
            draft.firstName = parts.first ?? ""
            draft.lastName = parts.count > 1 ? parts[1] : ""
            draft.contactRole = primary.roleTitle ?? ""
            draft.phone = primary.phone ?? ""
            draft.email = primary.email ?? ""
        }
        return draft
    }
}

// MARK: - Gateway surface

extension DataGateway {
    /// The full customer record. The development stack has no CRM writes, so it
    /// answers plainly rather than pretending.
    func customerProfile(session: TenantSession, customerID: String) async throws -> CustomerProfile {
        throw DataError.rejected(Self.crmUnavailable)
    }

    func createCustomer(session: TenantSession, draft: CustomerDraft) async throws -> String {
        throw DataError.rejected(Self.crmUnavailable)
    }

    func updateCustomer(session: TenantSession, customerID: String, draft: CustomerDraft) async throws {
        throw DataError.rejected(Self.crmUnavailable)
    }

    func deleteCustomer(session: TenantSession, customerID: String) async throws {
        throw DataError.rejected(Self.crmUnavailable)
    }

    func saveCustomerAddress(session: TenantSession, customerID: String, draft: AddressDraft) async throws -> String {
        throw DataError.rejected(Self.crmUnavailable)
    }

    func saveCustomerContact(session: TenantSession, customerID: String, draft: ContactDraft) async throws -> String {
        throw DataError.rejected(Self.crmUnavailable)
    }

    func saveEquipment(session: TenantSession, customerID: String, draft: EquipmentDraft) async throws -> String {
        throw DataError.rejected(Self.crmUnavailable)
    }

    fileprivate static var crmUnavailable: String {
        "Customer records are managed against the live database. Sign in with your company account to use this."
    }
}

// MARK: - Small helpers

nonisolated extension String {
    /// Whitespace-trimmed text. Deliberately not `trimmed`, which also swaps a
    /// comma for a decimal point and exists only for numeric entry.
    var tidied: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nil rather than an empty string, so a blank field is stored as an absent
    /// value instead of an empty one.
    var nilIfBlank: String? {
        let value = tidied
        return value.isEmpty ? nil : value
    }
}
