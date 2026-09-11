import Foundation
import Supabase

/// Decoding for PostgREST payloads.
///
/// Two things need care. `timestamptz` arrives as ISO-8601 with a variable
/// number of fractional digits, while `date` arrives as a bare `yyyy-MM-dd`, so
/// one strategy has to handle both. And every `numeric` column is requested as
/// `::text` in the select list, because a JSON number round-trips through a
/// binary double and money must not be re-derived from an approximation.
nonisolated enum SupabaseCoding {
    // Confined to `SupabaseDataGateway`, which is an actor, so every decode is
    // already serialised behind that actor's isolation.
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let plainDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(from raw: String) -> Date? {
        withFraction.date(from: raw)
            ?? withoutFraction.date(from: raw)
            ?? plainDay.date(from: raw)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let parsed = date(from: raw) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unrecognised timestamp format"
                    )
                )
            }
            return parsed
        }
        return decoder
    }()

    /// `numeric::text` → `Decimal`, exactly as stored.
    static func decimal(_ raw: String?) -> Decimal {
        guard let raw, let value = Decimal(string: raw) else { return 0 }
        return value
    }

    // MARK: - Encoding

    nonisolated(unsafe) private static let timestampOut: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// A `timestamptz` value.
    static func timestamp(_ date: Date) -> String { timestampOut.string(from: date) }

    /// A bare `date` value. Written in the current time zone, because a due date
    /// or an issue date is the calendar day the person chose, not an instant.
    static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    static func json(timestamp date: Date?) -> AnyJSON {
        date.map { AnyJSON.string(timestamp($0)) } ?? .null
    }

    static func json(day date: Date?) -> AnyJSON {
        date.map { AnyJSON.string(day($0)) } ?? .null
    }

    /// An optional identifier. Absent means null, never an empty string, so a
    /// blank id can't be mistaken for a real row by the database.
    static func json(id value: String?) -> AnyJSON {
        guard let value, !value.isEmpty else { return .null }
        return .string(value)
    }
}

// MARK: - Rows

nonisolated struct CompanyRecord: Decodable, Sendable {
    let id: UUID
    let name: String
    let trade: Trade
    let countryCode: String
    let currencyCode: String
    let defaultTaxRate: String?
    /// The company's own online payment destination. A URL and nothing else —
    /// Harbour South holds no processor account, credential or integration.
    let onlinePaymentLinkURL: String?
    /// The business's own customer-facing email identity, used as the reply
    /// address on the invoices its customers receive. Presentation only: no
    /// DNS, SPF, DKIM or API key is involved.
    let businessEmail: String?

    enum CodingKeys: String, CodingKey {
        case id, name, trade
        case countryCode = "country_code"
        case currencyCode = "currency_code"
        case defaultTaxRate = "default_tax_rate"
        case onlinePaymentLinkURL = "online_payment_link_url"
        case businessEmail = "business_email"
    }

    static let columns = "id,name,trade,country_code,currency_code,default_tax_rate::text,online_payment_link_url,business_email"
}

nonisolated struct AppUserRecord: Decodable, Sendable {
    let id: UUID
    let name: String
    let phone: String?
    let role: Role
    let status: UserStatus

    enum CodingKeys: String, CodingKey {
        case id, name, phone, role, status
    }

    static let columns = "id,name,phone,role,status"
}

nonisolated struct CustomerRecord: Decodable, Sendable {
    let id: UUID
    let name: String
    let type: CustomerType

    static let columns = "id,name,type"
}

/// Just enough of a job to count open work per customer, for the customer list.
nonisolated struct JobCountRecord: Decodable, Sendable {
    let customerID: UUID
    let status: JobStatus

    enum CodingKeys: String, CodingKey {
        case status
        case customerID = "customer_id"
    }

    static let columns = "customer_id,status"
}

nonisolated struct AddressRecord: Decodable, Sendable {
    let id: UUID
    let customerID: UUID
    let line1: String
    let city: String
    let state: String
    let postalCode: String
    let latitude: Double?
    let longitude: Double?
    let accessNotes: String?

    enum CodingKeys: String, CodingKey {
        case id, line1, city, state, latitude, longitude
        case customerID = "customer_id"
        case postalCode = "postal_code"
        case accessNotes = "access_notes"
    }

    static let columns = "id,customer_id,line1,city,state,postal_code,latitude,longitude,access_notes"
}

/// `assigned_site_customers` — the field worker's site context. The view has no
/// `billing_terms` and no `notes` column, so neither can arrive here.
nonisolated struct AssignedSiteRecord: Decodable, Sendable {
    let id: UUID
    let name: String
    let type: CustomerType
    let addressID: UUID
    let line1: String
    let city: String
    let state: String
    let postalCode: String
    let latitude: Double?
    let longitude: Double?
    let accessNotes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, line1, city, state, latitude, longitude
        case addressID = "address_id"
        case postalCode = "postal_code"
        case accessNotes = "access_notes"
    }

    static let columns = "id,name,type,address_id,line1,city,state,postal_code,latitude,longitude,access_notes"
}

/// `site_contacts_operational` — primary contact only, and no `email` or
/// `is_billing_contact` column at all.
nonisolated struct SiteContactRecord: Decodable, Sendable {
    let id: UUID
    let customerID: UUID
    let name: String
    let contactRole: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case id, name, phone
        case customerID = "customer_id"
        case contactRole = "contact_role"
    }

    static let columns = "id,customer_id,name,contact_role,phone"
}

nonisolated struct JobRecord: Decodable, Sendable {
    let id: UUID
    let customerID: UUID
    let addressID: UUID
    let equipmentID: UUID?
    let quoteID: UUID?
    let serviceAgreementID: UUID?
    let number: String
    let title: String
    let jobDescription: String?
    let kind: JobKind
    let priority: JobPriority
    let status: JobStatus
    let scheduledStart: Date?
    let scheduledEnd: Date?
    let actualStart: Date?
    let actualEnd: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, number, title, kind, priority, status
        case customerID = "customer_id"
        case addressID = "address_id"
        case equipmentID = "equipment_id"
        case quoteID = "quote_id"
        case serviceAgreementID = "service_agreement_id"
        case jobDescription = "job_description"
        case scheduledStart = "scheduled_start"
        case scheduledEnd = "scheduled_end"
        case actualStart = "actual_start"
        case actualEnd = "actual_end"
        case createdAt = "created_at"
    }

    static let columns = """
    id,customer_id,address_id,equipment_id,quote_id,service_agreement_id,number,title,\
    job_description,kind,priority,status,scheduled_start,scheduled_end,actual_start,actual_end,created_at
    """

    /// The domain model the projections are assembled from.
    ///
    /// `companyID` is taken from the authenticated session rather than from the
    /// payload: RLS has already proved every returned row belongs to that
    /// company, and the column is deliberately not selected so a client-side
    /// value can never become the basis of a tenant decision.
    func model(companyID: String) -> Job {
        Job(
            id: id.uuidString,
            companyID: companyID,
            customerID: customerID.uuidString,
            addressID: addressID.uuidString,
            equipmentID: equipmentID?.uuidString,
            quoteID: quoteID?.uuidString,
            number: number,
            title: title,
            jobDescription: jobDescription ?? "",
            kind: kind,
            priority: priority,
            status: status,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd,
            actualStart: actualStart,
            actualEnd: actualEnd,
            serviceAgreementID: serviceAgreementID?.uuidString,
            createdAt: createdAt
        )
    }
}

nonisolated struct AssignmentRecord: Decodable, Sendable {
    let jobID: UUID
    let userID: UUID
    let isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case userID = "user_id"
        case isPrimary = "is_primary"
    }

    static let columns = "job_id,user_id,is_primary"
}

nonisolated struct StatusHistoryRecord: Decodable, Sendable {
    let id: UUID
    let jobID: UUID
    let fromStatus: JobStatus?
    let toStatus: JobStatus
    let changedByUserID: UUID?
    let changedAt: Date
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude
        case jobID = "job_id"
        case fromStatus = "from_status"
        case toStatus = "to_status"
        case changedByUserID = "changed_by_user_id"
        case changedAt = "changed_at"
    }

    static let columns = "id,job_id,from_status,to_status,changed_by_user_id,changed_at,latitude,longitude"
}

nonisolated struct JobNoteRecord: Decodable, Sendable {
    let id: UUID
    let jobID: UUID
    let userID: UUID?
    let body: String
    let visibility: NoteVisibility
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body, visibility
        case jobID = "job_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }

    static let columns = "id,job_id,user_id,body,visibility,created_at"
}

nonisolated struct JobPhotoRecord: Decodable, Sendable {
    let id: UUID
    let jobID: UUID
    let userID: UUID?
    let storageReference: String
    let caption: String?
    let kind: JobPhotoKind
    let capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, caption, kind
        case jobID = "job_id"
        case userID = "user_id"
        case storageReference = "storage_reference"
        case capturedAt = "captured_at"
    }

    static let columns = "id,job_id,user_id,storage_reference,caption,kind,captured_at"
}

/// `attributes` is `jsonb`. A malformed or unexpected shape yields no attributes
/// rather than failing the whole read — one bad row must not empty a job list.
nonisolated struct EquipmentRecord: Decodable, Sendable {
    let id: UUID
    let addressID: UUID?
    let make: String
    let model: String
    let serialNumber: String
    let category: String
    let installedOn: Date?
    let warrantyExpiresOn: Date?
    let attributes: [EquipmentAttribute]

    enum CodingKeys: String, CodingKey {
        case id, make, model, category, attributes
        case addressID = "address_id"
        case serialNumber = "serial_number"
        case installedOn = "installed_on"
        case warrantyExpiresOn = "warranty_expires_on"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        addressID = try container.decodeIfPresent(UUID.self, forKey: .addressID)
        make = try container.decodeIfPresent(String.self, forKey: .make) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        installedOn = try container.decodeIfPresent(Date.self, forKey: .installedOn)
        warrantyExpiresOn = try container.decodeIfPresent(Date.self, forKey: .warrantyExpiresOn)
        attributes = (try? container.decodeIfPresent([EquipmentAttribute].self, forKey: .attributes)) as? [EquipmentAttribute] ?? []
    }

    var displayName: String { "\(make) \(model)".trimmingCharacters(in: .whitespaces) }

    static let columns = "id,address_id,make,model,serial_number,category,installed_on,warranty_expires_on,attributes"
}

nonisolated struct EquipmentHistoryRecord: Decodable, Sendable {
    let id: UUID
    let equipmentID: UUID
    let summary: String
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id, summary
        case equipmentID = "equipment_id"
        case occurredAt = "occurred_at"
    }

    static let columns = "id,equipment_id,summary,occurred_at"
}

nonisolated struct ServiceAgreementRecord: Decodable, Sendable {
    let id: UUID
    let frequency: ServiceFrequency
    let nextDueDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, frequency
        case nextDueDate = "next_due_date"
    }

    static let columns = "id,frequency,next_due_date"
}

/// `quotes_operational` — the money-free quote surface. There is no `total`,
/// `subtotal` or `tax` column on this view, so a role reading it cannot be
/// handed quote money by accident.
nonisolated struct QuoteOperationalRecord: Decodable, Sendable {
    let id: UUID
    let number: String
    let status: QuoteStatus

    static let columns = "id,number,status"
}

/// The priced quote row, from the base table. Reachable only with
/// `quoteFinancialsRead`; every other role gets zero rows from RLS.
nonisolated struct QuoteFinancialRecord: Decodable, Sendable {
    let id: UUID
    let number: String
    let status: QuoteStatus
    let total: String?

    static let columns = "id,number,status,total::text"
}

nonisolated struct WorkerLocationRecord: Decodable, Sendable {
    let id: UUID
    let userID: UUID
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let heading: Double?
    let speedMetersPerSecond: Double?
    let jobID: UUID?
    let recordedAt: Date
    let isSimulated: Bool

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, heading
        case userID = "user_id"
        case accuracyMeters = "accuracy_meters"
        case speedMetersPerSecond = "speed_meters_per_second"
        case jobID = "job_id"
        case recordedAt = "recorded_at"
        case isSimulated = "is_simulated"
    }

    static let columns = """
    id,user_id,latitude,longitude,accuracy_meters,heading,speed_meters_per_second,\
    job_id,recorded_at,is_simulated
    """
}
