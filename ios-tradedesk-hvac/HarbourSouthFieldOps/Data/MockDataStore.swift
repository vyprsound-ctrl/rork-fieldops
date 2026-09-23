import Foundation

/// DEVELOPMENT EXAMPLE DATA ONLY.
///
/// An in-memory store standing in for the eventual Supabase schema. Nothing
/// here is an architectural requirement: the records below are one worked
/// example of the platform's generic model, not a definition of it.
///
/// Two companies are seeded on purpose, **in two different trades**, so that
/// both tenant isolation and trade-agnosticism can be exercised:
/// * Gulf Coast Air — HVAC, six users, full workflow coverage.
/// * Northline Plumbing — plumbing, same schema, different vocabulary.
///
/// The seed is also shaped to demonstrate every phase-two test scenario: jobs
/// in each workflow state, quotes in each status, one accepted quote ready to
/// convert, and jobs assigned to two different field workers so cross-worker
/// access can be proven to fail.
nonisolated struct MockDataStore: Sendable {
    var companies: [Company]
    var subscriptions: [CompanySubscription]
    var users: [UserAccount]
    var customers: [Customer]
    var contacts: [CustomerContact]
    var addresses: [Address]
    var equipment: [Equipment]
    var equipmentHistory: [EquipmentHistoryEntry]
    var quotes: [Quote]
    var quoteLineItems: [QuoteLineItem]
    var jobs: [Job]
    var jobStatusHistory: [JobStatusHistory]
    var assignments: [FieldWorkerAssignment]
    var jobNotes: [JobNote]
    var jobPhotos: [JobPhoto]
    var workerLocations: [FieldWorkerLocation]
    var invoices: [Invoice]
    var invoiceLineItems: [InvoiceLineItem]
    var payments: [Payment]
    var notifications: [AppNotification]
    /// Devices registered for job alerts. Empty in the seed: a registration
    /// only exists once a signed-in person has granted permission on a real
    /// handset, which the development stack never does.
    var pushDevices: [PushDeviceRecord] = []
    /// Customer-facing invoice links. Empty in the seed: a link only exists
    /// once someone deliberately issues one.
    var invoiceShareTokens: [InvoiceShareToken] = []
    var smsLedger: [SmsCreditLedgerEntry]
    var serviceAgreements: [ServiceAgreement]
    /// Conversations between field workers and the office.
    ///
    /// Seeded on purpose. The development stack used to refuse messaging
    /// outright, which meant the messaging screens — including the "Open" button
    /// on a job-linked message — could not be exercised by any automated test.
    /// A defect there reached two shipped builds before a human found it.
    var officeThreads: [DevOfficeThread] = []
    var officeMessages: [DevOfficeMessage] = []
    /// Company-scoped document numbering. One row per company per document
    /// family; no prefix is hard-coded anywhere in the gateway.
    var documentSequences: [DocumentSequence]

    // MARK: - Date helpers

    private static func at(dayOffset: Int = 0, _ hour: Int, _ minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    private static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    // MARK: - Seed

    static func seeded() -> MockDataStore {
        let c1 = "cmp_gulfcoast"
        let c2 = "cmp_northline"
        let taxC1 = Money.percent("7")
        let taxC2 = Money.percent("5.5")

        let companies = [
            Company(
                id: c1,
                name: "Gulf Coast Air",
                trade: .hvac,
                countryCode: "US",
                currencyCode: "USD",
                timeZoneIdentifier: "America/New_York",
                addressLine: "2200 W Kennedy Blvd",
                city: "Tampa",
                state: "FL",
                postalCode: "33606",
                phone: "(813) 555-0110",
                defaultTaxRate: taxC1
            ),
            // Second tenant, second trade — same schema, same gateway, same
            // permissions. Only the vocabulary differs.
            Company(
                id: c2,
                name: "Northline Plumbing",
                trade: .plumbing,
                countryCode: "US",
                currencyCode: "USD",
                timeZoneIdentifier: "America/Chicago",
                addressLine: "51 Industrial Way",
                city: "Madison",
                state: "WI",
                postalCode: "53713",
                phone: "(608) 555-0177",
                defaultTaxRate: taxC2
            )
        ]

        let subscriptions = [
            CompanySubscription(
                id: "sub_1",
                companyID: c1,
                status: .active,
                plan: .team,
                billingPeriod: .monthly,
                isTrial: false,
                trialEndsAt: nil,
                currentPeriodStart: at(dayOffset: -12, 9),
                currentPeriodEnd: at(dayOffset: 18, 9),
                renewalDate: at(dayOffset: 18, 9),
                seatCount: 5,
                includedUsers: 3,
                additionalUsers: 2,
                store: .apple,
                appleOriginalTransactionID: "SIMULATED-APPLE-TXN-4471902",
                googlePurchaseToken: nil,
                cancelledAt: nil
            ),
            CompanySubscription(
                id: "sub_2",
                companyID: c2,
                status: .trialing,
                plan: .soloTrader,
                billingPeriod: .monthly,
                isTrial: true,
                trialEndsAt: at(dayOffset: 9, 9),
                currentPeriodStart: at(dayOffset: -5, 9),
                currentPeriodEnd: at(dayOffset: 9, 9),
                renewalDate: at(dayOffset: 9, 9),
                seatCount: 1,
                includedUsers: 1,
                additionalUsers: 0,
                store: .google,
                appleOriginalTransactionID: nil,
                googlePurchaseToken: "SIMULATED-GOOGLE-TOKEN-88213",
                cancelledAt: nil
            )
        ]

        let users = [
            UserAccount(id: "usr_owner", companyID: c1, name: "Tom Ellison", email: "tom@gulfcoastair.com", phone: "(813) 555-0110", role: .owner, status: .active, invitedByUserID: nil, lastActiveAt: Date(), avatarURL: nil),
            UserAccount(id: "usr_admin", companyID: c1, name: "Priya Raman", email: "priya@gulfcoastair.com", phone: "(813) 555-0112", role: .admin, status: .active, invitedByUserID: "usr_owner", lastActiveAt: daysAgo(0), avatarURL: nil),
            UserAccount(id: "usr_dispatch", companyID: c1, name: "Carla Bell", email: "carla@gulfcoastair.com", phone: "(813) 555-0113", role: .dispatcher, status: .active, invitedByUserID: "usr_owner", lastActiveAt: daysAgo(0), avatarURL: nil),
            UserAccount(id: "usr_marcus", companyID: c1, name: "Marcus Hale", email: "marcus@gulfcoastair.com", phone: "(813) 555-0121", role: .fieldWorker, status: .active, invitedByUserID: "usr_owner", lastActiveAt: Date(), avatarURL: nil),
            UserAccount(id: "usr_dee", companyID: c1, name: "Dee Nguyen", email: "dee@gulfcoastair.com", phone: "(813) 555-0122", role: .fieldWorker, status: .active, invitedByUserID: "usr_owner", lastActiveAt: Date(), avatarURL: nil),
            UserAccount(id: "usr_accounts", companyID: c1, name: "Joan Petrov", email: "joan@gulfcoastair.com", phone: "(813) 555-0114", role: .accounts, status: .active, invitedByUserID: "usr_owner", lastActiveAt: daysAgo(1), avatarURL: nil),
            // Second tenant — must never appear in Gulf Coast queries.
            UserAccount(id: "usr_north_owner", companyID: c2, name: "Erin Vaught", email: "erin@northlineplumbing.com", phone: "(608) 555-0177", role: .owner, status: .active, invitedByUserID: nil, lastActiveAt: daysAgo(2), avatarURL: nil),
            UserAccount(id: "usr_north_worker", companyID: c2, name: "Ray Kessler", email: "ray@northlineplumbing.com", phone: "(608) 555-0181", role: .fieldWorker, status: .active, invitedByUserID: "usr_north_owner", lastActiveAt: daysAgo(1), avatarURL: nil)
        ]

        let customers = [
            Customer(id: "cus_ramirez", companyID: c1, name: "Ana Ramirez", type: .residential, billingTerms: "Due on receipt", notes: nil, createdAt: daysAgo(420)),
            Customer(id: "cus_whitfield", companyID: c1, name: "Whitfield Dental", type: .commercial, billingTerms: "Net 30", notes: "Two rooftop units, service window before 8 AM.", createdAt: daysAgo(900)),
            Customer(id: "cus_delgado", companyID: c1, name: "Miguel Delgado", type: .residential, billingTerms: "Due on receipt", notes: nil, createdAt: daysAgo(260)),
            Customer(id: "cus_whitaker", companyID: c1, name: "Sam Whitaker", type: .residential, billingTerms: "Due on receipt", notes: nil, createdAt: daysAgo(75)),
            Customer(id: "cus_coastal", companyID: c1, name: "Coastal Storage", type: .propertyManagement, billingTerms: "Net 15", notes: "Managing agent — all sites billed to head office.", createdAt: daysAgo(610)),
            Customer(id: "cus_north_a", companyID: c2, name: "Lakeside Foods", type: .commercial, billingTerms: "Net 30", notes: nil, createdAt: daysAgo(120))
        ]

        let contacts = [
            CustomerContact(id: "con_1", companyID: c1, customerID: "cus_ramirez", name: "Ana Ramirez", contactRole: "Homeowner", phone: "(813) 555-0142", email: "ana.ramirez@example.com", isPrimary: true, isBillingContact: true),
            CustomerContact(id: "con_2", companyID: c1, customerID: "cus_whitfield", name: "Dr. Lena Whitfield", contactRole: "Practice owner", phone: "(813) 555-0188", email: "lena@whitfielddental.com", isPrimary: true, isBillingContact: false),
            CustomerContact(id: "con_3", companyID: c1, customerID: "cus_whitfield", name: "Roy Nesbit", contactRole: "Office manager", phone: "(813) 555-0189", email: "accounts@whitfielddental.com", isPrimary: false, isBillingContact: true),
            CustomerContact(id: "con_4", companyID: c1, customerID: "cus_delgado", name: "Miguel Delgado", contactRole: "Homeowner", phone: "(813) 555-0155", email: nil, isPrimary: true, isBillingContact: true),
            CustomerContact(id: "con_5", companyID: c1, customerID: "cus_whitaker", name: "Sam Whitaker", contactRole: "Homeowner", phone: "(813) 555-0166", email: nil, isPrimary: true, isBillingContact: true),
            CustomerContact(id: "con_6", companyID: c1, customerID: "cus_coastal", name: "Bree Santos", contactRole: "Site manager", phone: "(813) 555-0171", email: "bree@coastalstorage.com", isPrimary: true, isBillingContact: true),
            CustomerContact(id: "con_7", companyID: c2, customerID: "cus_north_a", name: "Paul Denner", contactRole: "Facilities", phone: "(608) 555-0190", email: nil, isPrimary: true, isBillingContact: true)
        ]

        let addresses = [
            Address(id: "adr_ramirez", companyID: c1, customerID: "cus_ramirez", line1: "214 Oak St", line2: nil, city: "Tampa", state: "FL", postalCode: "33604", latitude: 27.9881, longitude: -82.4585, accessNotes: "Side gate code 4417. Dog in yard."),
            Address(id: "adr_whitfield", companyID: c1, customerID: "cus_whitfield", line1: "907 E Columbus Dr", line2: "Suite 2", city: "Tampa", state: "FL", postalCode: "33605", latitude: 27.9631, longitude: -82.4419, accessNotes: "Roof access via rear stairwell, key at front desk."),
            Address(id: "adr_delgado", companyID: c1, customerID: "cus_delgado", line1: "1180 Cypress Ave", line2: nil, city: "Tampa", state: "FL", postalCode: "33607", latitude: 27.9705, longitude: -82.4890, accessNotes: nil),
            Address(id: "adr_whitaker", companyID: c1, customerID: "cus_whitaker", line1: "3320 Bayshore Blvd", line2: "Apt 5C", city: "Tampa", state: "FL", postalCode: "33629", latitude: 27.9160, longitude: -82.4841, accessNotes: "Buzzer 5C. Park on the street, no visitor bays."),
            Address(id: "adr_coastal", companyID: c1, customerID: "cus_coastal", line1: "44 Harbour Point Dr", line2: nil, city: "Tampa", state: "FL", postalCode: "33602", latitude: 27.9506, longitude: -82.4572, accessNotes: "Gate opens 7 AM. Sign in at office for roof key."),
            Address(id: "adr_north_a", companyID: c2, customerID: "cus_north_a", line1: "12 Progress Rd", line2: nil, city: "Madison", state: "WI", postalCode: "53713", latitude: 43.0389, longitude: -89.4012, accessNotes: "Plant room is behind the loading bay.")
        ]

        // Asset categories are free text supplied by the company. HVAC records
        // sit beside plumbing records with no schema difference.
        let equipment = [
            Equipment(id: "eqp_ramirez", companyID: c1, addressID: "adr_ramirez", make: "Carrier", model: "3-ton condenser", serialNumber: "CR-2019-88401", category: "Condenser", installedOn: at(dayOffset: -2400, 9), warrantyExpiresOn: at(dayOffset: 220, 9), attributes: [EquipmentAttribute(name: "Refrigerant", value: "R-410A")], photoURL: nil),
            Equipment(id: "eqp_whitfield", companyID: c1, addressID: "adr_whitfield", make: "Trane", model: "RTU 7.5-ton", serialNumber: "TR-2017-22190", category: "Rooftop unit", installedOn: at(dayOffset: -3100, 9), warrantyExpiresOn: nil, attributes: [EquipmentAttribute(name: "Refrigerant", value: "R-410A")], photoURL: nil),
            Equipment(id: "eqp_delgado", companyID: c1, addressID: "adr_delgado", make: "Goodman", model: "2.5-ton split", serialNumber: "GD-2021-55120", category: "Mini split", installedOn: at(dayOffset: -1500, 9), warrantyExpiresOn: at(dayOffset: 600, 9), attributes: [EquipmentAttribute(name: "Refrigerant", value: "R-410A")], photoURL: nil),
            Equipment(id: "eqp_whitaker", companyID: c1, addressID: "adr_whitaker", make: "Honeywell", model: "T6 Pro", serialNumber: "HW-2020-77310", category: "Thermostat", installedOn: at(dayOffset: -1900, 9), warrantyExpiresOn: nil, attributes: [], photoURL: nil),
            Equipment(id: "eqp_coastal", companyID: c1, addressID: "adr_coastal", make: "York", model: "5-ton condenser", serialNumber: "YK-2013-40277", category: "Condenser", installedOn: at(dayOffset: -4200, 9), warrantyExpiresOn: nil, attributes: [EquipmentAttribute(name: "Refrigerant", value: "R-22")], photoURL: nil),
            // Plumbing asset — same record type, different trade vocabulary.
            Equipment(id: "eqp_north", companyID: c2, addressID: "adr_north_a", make: "Rheem", model: "Commercial 199k BTU", serialNumber: "RH-2018-11002", category: "Water heater", installedOn: at(dayOffset: -2800, 9), attributes: [EquipmentAttribute(name: "Pressure rating", value: "150 psi"), EquipmentAttribute(name: "Connection", value: "1.5 in")], photoURL: nil)
        ]

        let equipmentHistory = [
            EquipmentHistoryEntry(id: "eqh_1", companyID: c1, equipmentID: "eqp_ramirez", jobID: nil, summary: "Capacitor replaced", occurredAt: at(dayOffset: -430, 11)),
            EquipmentHistoryEntry(id: "eqh_2", companyID: c1, equipmentID: "eqp_ramirez", jobID: nil, summary: "Annual service, R-410A topped up", occurredAt: at(dayOffset: -880, 10)),
            EquipmentHistoryEntry(id: "eqh_3", companyID: c1, equipmentID: "eqp_whitfield", jobID: nil, summary: "Belt and filters replaced", occurredAt: at(dayOffset: -190, 8)),
            EquipmentHistoryEntry(id: "eqh_4", companyID: c1, equipmentID: "eqp_delgado", jobID: nil, summary: "Coil clean and refrigerant check", occurredAt: at(dayOffset: -365, 13)),
            EquipmentHistoryEntry(id: "eqh_5", companyID: c1, equipmentID: "eqp_coastal", jobID: nil, summary: "Fan motor bearings replaced", occurredAt: at(dayOffset: -240, 10)),
            EquipmentHistoryEntry(id: "eqh_6", companyID: c1, equipmentID: "eqp_coastal", jobID: nil, summary: "R-22 leak sealed — unit flagged for replacement", occurredAt: at(dayOffset: -60, 9)),
            EquipmentHistoryEntry(id: "eqh_7", companyID: c2, equipmentID: "eqp_north", jobID: nil, summary: "Anode rod replaced, TPR valve tested", occurredAt: at(dayOffset: -150, 9))
        ]

        // MARK: Quote line items
        //
        // Every amount is an exact decimal built from a string, never a float
        // literal, so totals are reproducible to the cent.
        let quoteLineItems = [
            QuoteLineItem(id: "qli_1", companyID: c1, quoteID: "qte_ramirez", itemDescription: "Condenser fan motor — part", quantity: 1, unitPrice: Money.dec("185.00"), taxRate: taxC1, lineTotal: Money.dec("185.00"), sortOrder: 0),
            QuoteLineItem(id: "qli_2", companyID: c1, quoteID: "qte_ramirez", itemDescription: "Labor — 2 hrs", quantity: 2, unitPrice: Money.dec("95.00"), taxRate: taxC1, lineTotal: Money.dec("190.00"), sortOrder: 1),
            QuoteLineItem(id: "qli_3", companyID: c1, quoteID: "qte_ramirez", itemDescription: "Refrigerant top-up", quantity: 1, unitPrice: Money.dec("65.00"), taxRate: taxC1, lineTotal: Money.dec("65.00"), sortOrder: 2),

            QuoteLineItem(id: "qli_4", companyID: c1, quoteID: "qte_whitfield", itemDescription: "Compressor rebuild kit", quantity: 1, unitPrice: Money.dec("2100.00"), taxRate: taxC1, lineTotal: Money.dec("2100.00"), sortOrder: 0),
            QuoteLineItem(id: "qli_5", companyID: c1, quoteID: "qte_whitfield", itemDescription: "Labor — 6 hrs", quantity: 6, unitPrice: Money.dec("125.00"), taxRate: taxC1, lineTotal: Money.dec("750.00"), sortOrder: 1),

            QuoteLineItem(id: "qli_6", companyID: c1, quoteID: "qte_coastal", itemDescription: "York 5-ton condenser — replacement unit", quantity: 1, unitPrice: Money.dec("3240.00"), taxRate: taxC1, lineTotal: Money.dec("3240.00"), sortOrder: 0),
            QuoteLineItem(id: "qli_7", companyID: c1, quoteID: "qte_coastal", itemDescription: "Crane hire — half day", quantity: 1, unitPrice: Money.dec("480.00"), taxRate: taxC1, lineTotal: Money.dec("480.00"), sortOrder: 1),
            QuoteLineItem(id: "qli_8", companyID: c1, quoteID: "qte_coastal", itemDescription: "Labor — 8 hrs, two on site", quantity: 8, unitPrice: Money.dec("125.00"), taxRate: taxC1, lineTotal: Money.dec("1000.00"), sortOrder: 2),
            QuoteLineItem(id: "qli_9", companyID: c1, quoteID: "qte_coastal", itemDescription: "Removal and disposal of R-22 unit", quantity: 1, unitPrice: Money.dec("145.00"), taxRate: taxC1, lineTotal: Money.dec("145.00"), sortOrder: 3),

            QuoteLineItem(id: "qli_10", companyID: c1, quoteID: "qte_whitaker", itemDescription: "Smart thermostat — supply", quantity: 2, unitPrice: Money.dec("219.99"), taxRate: taxC1, lineTotal: Money.dec("439.98"), sortOrder: 0),
            QuoteLineItem(id: "qli_11", companyID: c1, quoteID: "qte_whitaker", itemDescription: "Labor — 1.5 hrs", quantity: Money.dec("1.5"), unitPrice: Money.dec("95.00"), taxRate: taxC1, lineTotal: Money.dec("142.50"), sortOrder: 1),

            QuoteLineItem(id: "qli_12", companyID: c1, quoteID: "qte_delgado", itemDescription: "Flexible duct replacement — 40 ft", quantity: 1, unitPrice: Money.dec("1860.00"), taxRate: taxC1, lineTotal: Money.dec("1860.00"), sortOrder: 0),
            QuoteLineItem(id: "qli_13", companyID: c1, quoteID: "qte_delgado", itemDescription: "Labor — 10 hrs", quantity: 10, unitPrice: Money.dec("110.00"), taxRate: taxC1, lineTotal: Money.dec("1100.00"), sortOrder: 1),

            QuoteLineItem(id: "qli_14", companyID: c1, quoteID: "qte_expired", itemDescription: "Coil clean package", quantity: 1, unitPrice: Money.dec("289.00"), taxRate: taxC1, lineTotal: Money.dec("289.00"), sortOrder: 0),

            // Second tenant, plumbing work — identical structure.
            QuoteLineItem(id: "qli_n1", companyID: c2, quoteID: "qte_north", itemDescription: "TPR valve and anode rod kit", quantity: 1, unitPrice: Money.dec("210.00"), taxRate: taxC2, lineTotal: Money.dec("210.00"), sortOrder: 0)
        ]

        func totals(_ quoteID: String) -> MoneyTotals {
            Money.totals(for: quoteLineItems.filter { $0.quoteID == quoteID })
        }

        let ramirezTotals = totals("qte_ramirez")
        let whitfieldTotals = totals("qte_whitfield")
        let coastalTotals = totals("qte_coastal")
        let whitakerTotals = totals("qte_whitaker")
        let delgadoTotals = totals("qte_delgado")
        let expiredTotals = totals("qte_expired")
        let northTotals = totals("qte_north")

        let quotes = [
            Quote(id: "qte_ramirez", companyID: c1, customerID: "cus_ramirez", addressID: "adr_ramirez", number: "Q-2087", title: "Condenser fan motor replacement", scopeOfWork: "Replace failed condenser fan motor, test operation and top up refrigerant to spec.", status: .sent, subtotal: ramirezTotals.subtotal, tax: ramirezTotals.tax, total: ramirezTotals.total, validUntil: at(dayOffset: 14, 17), createdAt: at(dayOffset: -1, 16), sentAt: at(dayOffset: -1, 16), viewedAt: nil, acceptedAt: nil, declinedAt: nil, convertedJobID: nil),
            Quote(id: "qte_whitfield", companyID: c1, customerID: "cus_whitfield", addressID: "adr_whitfield", number: "Q-2088", title: "RTU compressor rebuild", scopeOfWork: "Strip and rebuild the compressor on rooftop unit 1, replace valve plate and recommission.", status: .draft, subtotal: whitfieldTotals.subtotal, tax: whitfieldTotals.tax, total: whitfieldTotals.total, validUntil: nil, createdAt: at(0, 7), sentAt: nil, viewedAt: nil, acceptedAt: nil, declinedAt: nil, convertedJobID: nil),
            Quote(id: "qte_coastal", companyID: c1, customerID: "cus_coastal", addressID: "adr_coastal", number: "Q-2089", title: "Rooftop condenser replacement", scopeOfWork: "Remove and dispose of the failing R-22 York condenser. Supply and install a new 5-ton unit, crane lift included, commission and hand over with warranty paperwork.", status: .accepted, subtotal: coastalTotals.subtotal, tax: coastalTotals.tax, total: coastalTotals.total, validUntil: at(dayOffset: 21, 17), createdAt: daysAgo(6), sentAt: daysAgo(6), viewedAt: daysAgo(5), acceptedAt: daysAgo(2), declinedAt: nil, convertedJobID: nil),
            Quote(id: "qte_whitaker", companyID: c1, customerID: "cus_whitaker", addressID: "adr_whitaker", number: "Q-2090", title: "Smart thermostat upgrade", scopeOfWork: "Supply and fit two smart thermostats, configure schedules and demonstrate the app.", status: .viewed, subtotal: whitakerTotals.subtotal, tax: whitakerTotals.tax, total: whitakerTotals.total, validUntil: at(dayOffset: 4, 17), createdAt: daysAgo(8), sentAt: daysAgo(8), viewedAt: daysAgo(7), acceptedAt: nil, declinedAt: nil, convertedJobID: nil),
            Quote(id: "qte_delgado", companyID: c1, customerID: "cus_delgado", addressID: "adr_delgado", number: "Q-2091", title: "Duct replacement", scopeOfWork: "Replace 40 ft of degraded flexible duct in the crawl space and reseal all joints.", status: .declined, subtotal: delgadoTotals.subtotal, tax: delgadoTotals.tax, total: delgadoTotals.total, validUntil: at(dayOffset: 12, 17), createdAt: daysAgo(18), sentAt: daysAgo(18), viewedAt: daysAgo(17), acceptedAt: nil, declinedAt: daysAgo(11), convertedJobID: nil),
            Quote(id: "qte_expired", companyID: c1, customerID: "cus_ramirez", addressID: "adr_ramirez", number: "Q-2085", title: "Coil clean package", scopeOfWork: "Chemical clean of indoor and outdoor coils with drain line flush.", status: .expired, subtotal: expiredTotals.subtotal, tax: expiredTotals.tax, total: expiredTotals.total, validUntil: daysAgo(9), createdAt: daysAgo(40), sentAt: daysAgo(40), viewedAt: daysAgo(39), acceptedAt: nil, declinedAt: nil, convertedJobID: nil),
            // Second tenant.
            Quote(id: "qte_north", companyID: c2, customerID: "cus_north_a", addressID: "adr_north_a", number: "N-Q-410", title: "Water heater service kit", scopeOfWork: "Annual service: replace the anode rod, test the TPR valve and flush the tank.", status: .draft, subtotal: northTotals.subtotal, tax: northTotals.tax, total: northTotals.total, validUntil: nil, createdAt: daysAgo(3), sentAt: nil, viewedAt: nil, acceptedAt: nil, declinedAt: nil, convertedJobID: nil)
        ]

        let jobs = [
            Job(id: "job_1041", companyID: c1, customerID: "cus_delgado", addressID: "adr_delgado", equipmentID: "eqp_delgado", quoteID: nil, number: "J-1041", title: "Annual maintenance", jobDescription: "Annual service on the mini split: clean coils, flush the drain line, check refrigerant pressures and test the changeover.", kind: .maintenance, priority: .standard, status: .completed, scheduledStart: at(8), scheduledEnd: at(9, 45), actualStart: at(8, 4), actualEnd: at(9, 41), serviceAgreementID: "sa_1", createdAt: daysAgo(21)),
            Job(id: "job_1042", companyID: c1, customerID: "cus_ramirez", addressID: "adr_ramirez", equipmentID: "eqp_ramirez", quoteID: "qte_ramirez", number: "J-1042", title: "No cooling — call-out", jobDescription: "Customer reports the unit runs but blows warm since Sunday. Suspected condenser fan motor failure — quote Q-2087 issued for the replacement.", kind: .callOut, priority: .urgent, status: .travelling, scheduledStart: at(10, 30), scheduledEnd: at(12, 0), actualStart: nil, actualEnd: nil, serviceAgreementID: nil, createdAt: daysAgo(1)),
            Job(id: "job_1043", companyID: c1, customerID: "cus_whitfield", addressID: "adr_whitfield", equipmentID: "eqp_whitfield", quoteID: nil, number: "J-1043", title: "RTU maintenance", jobDescription: "Quarterly rooftop unit service. Replace belts and filters, check amp draw on both compressors.", kind: .maintenance, priority: .standard, status: .workerAssigned, scheduledStart: at(13, 0), scheduledEnd: at(14, 30), actualStart: nil, actualEnd: nil, serviceAgreementID: "sa_2", createdAt: daysAgo(9)),
            Job(id: "job_1044", companyID: c1, customerID: "cus_whitaker", addressID: "adr_whitaker", equipmentID: "eqp_whitaker", quoteID: nil, number: "J-1044", title: "Thermostat swap", jobDescription: "Swap the failed T6 Pro for the replacement unit, re-run the schedule and confirm the customer can use the app.", kind: .install, priority: .standard, status: .workerAssigned, scheduledStart: at(15, 45), scheduledEnd: at(16, 45), actualStart: nil, actualEnd: nil, serviceAgreementID: nil, createdAt: daysAgo(3)),
            Job(id: "job_1040", companyID: c1, customerID: "cus_coastal", addressID: "adr_coastal", equipmentID: "eqp_coastal", quoteID: nil, number: "J-1040", title: "Filter change — unit bank B", jobDescription: "Change all filters across unit bank B and log the condition of each return.", kind: .maintenance, priority: .standard, status: .completed, scheduledStart: at(9, 0), scheduledEnd: at(10, 0), actualStart: at(9, 2), actualEnd: at(9, 52), serviceAgreementID: nil, createdAt: daysAgo(14)),
            Job(id: "job_1049", companyID: c1, customerID: "cus_coastal", addressID: "adr_coastal", equipmentID: "eqp_coastal", quoteID: nil, number: "J-1049", title: "Condenser pressure check", jobDescription: "Follow-up on the R-22 leak repair — check standing pressures and report before the replacement is scheduled.", kind: .callOut, priority: .standard, status: .workerAssigned, scheduledStart: at(14, 0), scheduledEnd: at(15, 0), actualStart: nil, actualEnd: nil, serviceAgreementID: nil, createdAt: daysAgo(1)),
            Job(id: "job_1045", companyID: c1, customerID: "cus_coastal", addressID: "adr_coastal", equipmentID: "eqp_coastal", quoteID: nil, number: "J-1045", title: "Condenser clean", jobDescription: "Chemical clean of the outdoor coil bank and a fin comb pass on the damaged section.", kind: .maintenance, priority: .standard, status: .workerAssigned, scheduledStart: at(dayOffset: 1, 9, 30), scheduledEnd: at(dayOffset: 1, 11, 0), actualStart: nil, actualEnd: nil, serviceAgreementID: nil, createdAt: daysAgo(6)),
            Job(id: "job_1046", companyID: c1, customerID: "cus_whitfield", addressID: "adr_whitfield", equipmentID: "eqp_whitfield", quoteID: "qte_whitfield", number: "J-1046", title: "Compressor rebuild", jobDescription: "Awaiting a slot: compressor rebuild on RTU 1 per draft quote Q-2088. Needs a full day and two on site.", kind: .callOut, priority: .urgent, status: .scheduled, scheduledStart: nil, scheduledEnd: nil, actualStart: nil, actualEnd: nil, serviceAgreementID: nil, createdAt: at(0, 7)),
            Job(id: "job_1047", companyID: c1, customerID: "cus_ramirez", addressID: "adr_ramirez", equipmentID: "eqp_ramirez", quoteID: nil, number: "J-1047", title: "Duct inspection", jobDescription: "Inspect the attic duct run for the airflow complaint raised on the last visit.", kind: .maintenance, priority: .standard, status: .workerAssigned, scheduledStart: at(dayOffset: 2, 11, 0), scheduledEnd: at(dayOffset: 2, 12, 30), actualStart: nil, actualEnd: nil, serviceAgreementID: nil, createdAt: daysAgo(2)),
            Job(id: "job_1039", companyID: c1, customerID: "cus_delgado", addressID: "adr_delgado", equipmentID: "eqp_delgado", quoteID: nil, number: "J-1039", title: "Thermostat fault", jobDescription: "Control board replaced after intermittent shutdowns. Invoiced INV-1184.", kind: .callOut, priority: .standard, status: .invoiced, scheduledStart: at(dayOffset: -4, 10), scheduledEnd: at(dayOffset: -4, 11), actualStart: at(dayOffset: -4, 10, 6), actualEnd: at(dayOffset: -4, 10, 55), serviceAgreementID: nil, createdAt: daysAgo(6)),
            Job(id: "job_1038", companyID: c1, customerID: "cus_whitaker", addressID: "adr_whitaker", equipmentID: "eqp_whitaker", quoteID: nil, number: "J-1038", title: "Air handler replacement", jobDescription: "Replaced the air handler and reworked the plenum. Paid in full on completion.", kind: .install, priority: .standard, status: .paid, scheduledStart: at(dayOffset: -9, 8), scheduledEnd: at(dayOffset: -9, 15), actualStart: at(dayOffset: -9, 8, 12), actualEnd: at(dayOffset: -9, 14, 40), serviceAgreementID: nil, createdAt: daysAgo(20)),
            Job(id: "job_1037", companyID: c1, customerID: "cus_whitfield", addressID: "adr_whitfield", equipmentID: "eqp_whitfield", quoteID: nil, number: "J-1037", title: "Warranty inspection", jobDescription: "Manufacturer warranty inspection on the replacement fan assembly. Cancelled at the customer's request.", kind: .warranty, priority: .standard, status: .cancelled, scheduledStart: at(dayOffset: -2, 9), scheduledEnd: at(dayOffset: -2, 10), actualStart: nil, actualEnd: nil, serviceAgreementID: nil, createdAt: daysAgo(12)),
            // Second tenant — a plumbing job running the identical workflow.
            Job(id: "job_north_1", companyID: c2, customerID: "cus_north_a", addressID: "adr_north_a", equipmentID: "eqp_north", quoteID: nil, number: "N-3001", title: "Water heater service", jobDescription: "Annual service on the commercial water heater: flush the tank, test the TPR valve and check the flue.", kind: .maintenance, priority: .standard, status: .workerAssigned, scheduledStart: at(11, 0), scheduledEnd: at(12, 30), actualStart: nil, actualEnd: nil, serviceAgreementID: "sa_3", createdAt: daysAgo(10))
        ]

        let jobStatusHistory = [
            JobStatusHistory(id: "jsh_1", companyID: c1, jobID: "job_1041", fromStatus: .scheduled, toStatus: .workerAssigned, changedByUserID: "usr_dispatch", changedAt: daysAgo(2), latitude: nil, longitude: nil),
            JobStatusHistory(id: "jsh_2", companyID: c1, jobID: "job_1041", fromStatus: .workerAssigned, toStatus: .travelling, changedByUserID: "usr_marcus", changedAt: at(7, 42), latitude: 27.9705, longitude: -82.4890),
            JobStatusHistory(id: "jsh_3", companyID: c1, jobID: "job_1041", fromStatus: .travelling, toStatus: .arrived, changedByUserID: "usr_marcus", changedAt: at(8, 4), latitude: 27.9705, longitude: -82.4890),
            JobStatusHistory(id: "jsh_4", companyID: c1, jobID: "job_1041", fromStatus: .arrived, toStatus: .inProgress, changedByUserID: "usr_marcus", changedAt: at(8, 9), latitude: 27.9705, longitude: -82.4890),
            JobStatusHistory(id: "jsh_5", companyID: c1, jobID: "job_1041", fromStatus: .inProgress, toStatus: .completed, changedByUserID: "usr_marcus", changedAt: at(9, 41), latitude: 27.9705, longitude: -82.4890),

            JobStatusHistory(id: "jsh_6", companyID: c1, jobID: "job_1042", fromStatus: .scheduled, toStatus: .workerAssigned, changedByUserID: "usr_dispatch", changedAt: daysAgo(1), latitude: nil, longitude: nil),
            JobStatusHistory(id: "jsh_7", companyID: c1, jobID: "job_1042", fromStatus: .workerAssigned, toStatus: .travelling, changedByUserID: "usr_marcus", changedAt: at(10, 12), latitude: 27.9760, longitude: -82.4720),

            JobStatusHistory(id: "jsh_8", companyID: c1, jobID: "job_1040", fromStatus: .arrived, toStatus: .inProgress, changedByUserID: "usr_dee", changedAt: at(9, 6), latitude: 27.9506, longitude: -82.4572),
            JobStatusHistory(id: "jsh_9", companyID: c1, jobID: "job_1040", fromStatus: .inProgress, toStatus: .completed, changedByUserID: "usr_dee", changedAt: at(9, 52), latitude: 27.9506, longitude: -82.4572),

            JobStatusHistory(id: "jsh_10", companyID: c1, jobID: "job_1039", fromStatus: .completed, toStatus: .invoiced, changedByUserID: "usr_accounts", changedAt: daysAgo(4), latitude: nil, longitude: nil),
            JobStatusHistory(id: "jsh_11", companyID: c1, jobID: "job_1038", fromStatus: .completed, toStatus: .invoiced, changedByUserID: "usr_accounts", changedAt: daysAgo(9), latitude: nil, longitude: nil),
            JobStatusHistory(id: "jsh_12", companyID: c1, jobID: "job_1038", fromStatus: .invoiced, toStatus: .paid, changedByUserID: "usr_accounts", changedAt: daysAgo(2), latitude: nil, longitude: nil),
            JobStatusHistory(id: "jsh_13", companyID: c1, jobID: "job_1037", fromStatus: .workerAssigned, toStatus: .cancelled, changedByUserID: "usr_dispatch", changedAt: daysAgo(3), latitude: nil, longitude: nil),

            // Office assignments — no location is captured for desk transitions.
            JobStatusHistory(id: "jsh_14", companyID: c1, jobID: "job_1043", fromStatus: .scheduled, toStatus: .workerAssigned, changedByUserID: "usr_dispatch", changedAt: daysAgo(2), latitude: nil, longitude: nil),
            JobStatusHistory(id: "jsh_15", companyID: c1, jobID: "job_1044", fromStatus: .scheduled, toStatus: .workerAssigned, changedByUserID: "usr_dispatch", changedAt: daysAgo(2), latitude: nil, longitude: nil),
            JobStatusHistory(id: "jsh_16", companyID: c1, jobID: "job_1049", fromStatus: .scheduled, toStatus: .workerAssigned, changedByUserID: "usr_dispatch", changedAt: daysAgo(1), latitude: nil, longitude: nil),
            JobStatusHistory(id: "jsh_17", companyID: c1, jobID: "job_1045", fromStatus: .scheduled, toStatus: .workerAssigned, changedByUserID: "usr_dispatch", changedAt: daysAgo(3), latitude: nil, longitude: nil),
            JobStatusHistory(id: "jsh_18", companyID: c1, jobID: "job_1047", fromStatus: .scheduled, toStatus: .workerAssigned, changedByUserID: "usr_dispatch", changedAt: daysAgo(1), latitude: nil, longitude: nil),
            JobStatusHistory(id: "jsh_n1", companyID: c2, jobID: "job_north_1", fromStatus: .scheduled, toStatus: .workerAssigned, changedByUserID: "usr_north_owner", changedAt: daysAgo(2), latitude: nil, longitude: nil)
        ]

        let assignments = [
            FieldWorkerAssignment(id: "asg_1", companyID: c1, jobID: "job_1041", userID: "usr_marcus", assignedByUserID: "usr_dispatch", assignedAt: daysAgo(2), isPrimary: true, acceptedAt: at(7, 30), sortOrder: 0),
            FieldWorkerAssignment(id: "asg_2", companyID: c1, jobID: "job_1042", userID: "usr_marcus", assignedByUserID: "usr_dispatch", assignedAt: daysAgo(1), isPrimary: true, acceptedAt: at(7, 30), sortOrder: 1),
            FieldWorkerAssignment(id: "asg_3", companyID: c1, jobID: "job_1043", userID: "usr_marcus", assignedByUserID: "usr_dispatch", assignedAt: daysAgo(2), isPrimary: true, acceptedAt: nil, sortOrder: 2),
            FieldWorkerAssignment(id: "asg_4", companyID: c1, jobID: "job_1044", userID: "usr_marcus", assignedByUserID: "usr_dispatch", assignedAt: daysAgo(2), isPrimary: true, acceptedAt: nil, sortOrder: 3),
            FieldWorkerAssignment(id: "asg_5", companyID: c1, jobID: "job_1040", userID: "usr_dee", assignedByUserID: "usr_dispatch", assignedAt: daysAgo(3), isPrimary: true, acceptedAt: at(8, 40), sortOrder: 0),
            // Today, but Dee's — Marcus must never be able to read or write this row.
            FieldWorkerAssignment(id: "asg_8", companyID: c1, jobID: "job_1049", userID: "usr_dee", assignedByUserID: "usr_dispatch", assignedAt: daysAgo(1), isPrimary: true, acceptedAt: nil, sortOrder: 1),
            FieldWorkerAssignment(id: "asg_6", companyID: c1, jobID: "job_1045", userID: "usr_dee", assignedByUserID: "usr_dispatch", assignedAt: daysAgo(3), isPrimary: true, acceptedAt: nil, sortOrder: 2),
            FieldWorkerAssignment(id: "asg_7", companyID: c1, jobID: "job_1047", userID: "usr_dee", assignedByUserID: "usr_dispatch", assignedAt: daysAgo(1), isPrimary: true, acceptedAt: nil, sortOrder: 3),
            FieldWorkerAssignment(id: "asg_9", companyID: c1, jobID: "job_1038", userID: "usr_marcus", assignedByUserID: "usr_dispatch", assignedAt: daysAgo(20), isPrimary: true, acceptedAt: daysAgo(9), sortOrder: 0),
            FieldWorkerAssignment(id: "asg_10", companyID: c1, jobID: "job_1039", userID: "usr_marcus", assignedByUserID: "usr_dispatch", assignedAt: daysAgo(6), isPrimary: true, acceptedAt: daysAgo(4), sortOrder: 0),
            FieldWorkerAssignment(id: "asg_n1", companyID: c2, jobID: "job_north_1", userID: "usr_north_worker", assignedByUserID: "usr_north_owner", assignedAt: daysAgo(2), isPrimary: true, acceptedAt: nil, sortOrder: 0)
        ]

        let jobNotes = [
            JobNote(id: "nte_1", companyID: c1, jobID: "job_1042", userID: "usr_dispatch", body: "Customer says unit runs but blows warm since Sunday. She works from home, any time before 3 PM is fine.", visibility: .internalOnly, createdAt: at(7, 55)),
            JobNote(id: "nte_2", companyID: c1, jobID: "job_1041", userID: "usr_marcus", body: "Coil cleaned, drain line flushed. Recommend surge protector next visit.", visibility: .internalOnly, createdAt: at(9, 38)),
            JobNote(id: "nte_3", companyID: c1, jobID: "job_1043", userID: "usr_dispatch", body: "Practice opens at 8 AM — roof key is at the front desk, ask for Roy.", visibility: .internalOnly, createdAt: daysAgo(1)),
            JobNote(id: "nte_4", companyID: c1, jobID: "job_1049", userID: "usr_dee", body: "Standing pressure still dropping overnight. Replacement quote already accepted.", visibility: .internalOnly, createdAt: at(dayOffset: -1, 15))
        ]

        let jobPhotos = [
            JobPhoto(id: "pho_1", companyID: c1, jobID: "job_1041", userID: "usr_marcus", storageReference: "sim://jobs/1041/before.jpg", caption: "Coil before clean", kind: .before, capturedAt: at(8, 20)),
            JobPhoto(id: "pho_2", companyID: c1, jobID: "job_1041", userID: "usr_marcus", storageReference: "sim://jobs/1041/after.jpg", caption: "Coil after clean", kind: .after, capturedAt: at(9, 30)),
            JobPhoto(id: "pho_3", companyID: c1, jobID: "job_1040", userID: "usr_dee", storageReference: "sim://jobs/1040/filters.jpg", caption: "Return filters pulled from bank B", kind: .part, capturedAt: at(9, 20)),
            // Attached to a message in thread thr_1 as well as to the job, which
            // is the point of the shared media model: one upload, visible both
            // in the conversation and in the job's permanent evidence.
            JobPhoto(id: "pho_4", companyID: c1, jobID: "job_1042", userID: "usr_marcus", storageReference: DevSeedImages.condenser, caption: "Seized fan motor and bulging capacitor", kind: .before, capturedAt: at(10, 12), threadID: "thr_1"),
            // The office's reply on the same job thread, with a photo — so the
            // worker has a RECEIVED image to open, not only their own.
            JobPhoto(id: "pho_6", companyID: c1, jobID: "job_1042", userID: "usr_owner", storageReference: DevSeedImages.replacementPart, caption: nil, kind: .other, capturedAt: at(10, 15), threadID: "thr_1"),
            // The other half of the model: an image sent in a GENERAL
            // conversation. It has no job at all, so it is anchored to the
            // thread alone and must never appear in any job's evidence.
            JobPhoto(id: "pho_5", companyID: c1, jobID: nil, userID: "usr_marcus", storageReference: DevSeedImages.depotBays, caption: "Where the van is parked", kind: .other, capturedAt: daysAgo(1), threadID: "thr_4"),
            // Office → engineer on the general thread. No job, like pho_5.
            JobPhoto(id: "pho_7", companyID: c1, jobID: nil, userID: "usr_owner", storageReference: DevSeedImages.depotLayout, caption: nil, kind: .other, capturedAt: daysAgo(1).addingTimeInterval(60), threadID: "thr_4")
        ]

        let workerLocations = [
            FieldWorkerLocation(id: "loc_1", companyID: c1, userID: "usr_marcus", latitude: 27.9772, longitude: -82.4680, accuracyMeters: 12, heading: 74, speedMetersPerSecond: 11.2, jobID: "job_1042", recordedAt: Date()),
            FieldWorkerLocation(id: "loc_2", companyID: c1, userID: "usr_dee", latitude: 27.9506, longitude: -82.4572, accuracyMeters: 18, heading: 210, speedMetersPerSecond: 0, jobID: "job_1049", recordedAt: Date())
        ]

        // MARK: Invoice line items
        //
        // As with quotes, every amount is an exact decimal built from a string.
        // The invoice headers below are *derived* from these lines rather than
        // typed in, so the seeded documents reconcile to the cent exactly as a
        // real one raised through the gateway would.
        let invoiceLineItems = [
            InvoiceLineItem(id: "ili_1168_1", companyID: c1, invoiceID: "inv_1168", itemDescription: "Air handler — supply and install", quantity: 1, unitPrice: Money.dec("3890.00"), taxRate: taxC1, lineTotal: Money.dec("3890.00"), sortOrder: 0),
            InvoiceLineItem(id: "ili_1168_2", companyID: c1, invoiceID: "inv_1168", itemDescription: "Labor — 7 hrs", quantity: 7, unitPrice: Money.dec("95.00"), taxRate: taxC1, lineTotal: Money.dec("665.00"), sortOrder: 1),
            InvoiceLineItem(id: "ili_1168_3", companyID: c1, invoiceID: "inv_1168", itemDescription: "Plenum rework — materials", quantity: 1, unitPrice: Money.dec("245.00"), taxRate: taxC1, lineTotal: Money.dec("245.00"), sortOrder: 2),

            InvoiceLineItem(id: "ili_1184_1", companyID: c1, invoiceID: "inv_1184", itemDescription: "Thermostat control board", quantity: 1, unitPrice: Money.dec("890.00"), taxRate: taxC1, lineTotal: Money.dec("890.00"), sortOrder: 0),
            InvoiceLineItem(id: "ili_1184_2", companyID: c1, invoiceID: "inv_1184", itemDescription: "Labor — 4 hrs", quantity: 4, unitPrice: Money.dec("116.29"), taxRate: taxC1, lineTotal: Money.dec("465.16"), sortOrder: 1),

            InvoiceLineItem(id: "ili_1176_1", companyID: c1, invoiceID: "inv_1176", itemDescription: "Filter set — unit bank B", quantity: 12, unitPrice: Money.dec("34.50"), taxRate: taxC1, lineTotal: Money.dec("414.00"), sortOrder: 0),
            InvoiceLineItem(id: "ili_1176_2", companyID: c1, invoiceID: "inv_1176", itemDescription: "Labor — 4 hrs", quantity: 4, unitPrice: Money.dec("125.00"), taxRate: taxC1, lineTotal: Money.dec("500.00"), sortOrder: 1),

            InvoiceLineItem(id: "ili_1180_1", companyID: c1, invoiceID: "inv_1180", itemDescription: "Compressor rebuild kit", quantity: 1, unitPrice: Money.dec("2100.00"), taxRate: taxC1, lineTotal: Money.dec("2100.00"), sortOrder: 0),
            InvoiceLineItem(id: "ili_1180_2", companyID: c1, invoiceID: "inv_1180", itemDescription: "Labor — 6 hrs", quantity: 6, unitPrice: Money.dec("125.00"), taxRate: taxC1, lineTotal: Money.dec("750.00"), sortOrder: 1),

            InvoiceLineItem(id: "ili_1171_1", companyID: c1, invoiceID: "inv_1171", itemDescription: "Evaporator coil — replacement", quantity: 1, unitPrice: Money.dec("1180.00"), taxRate: taxC1, lineTotal: Money.dec("1180.00"), sortOrder: 0),
            InvoiceLineItem(id: "ili_1171_2", companyID: c1, invoiceID: "inv_1171", itemDescription: "Labor — 5 hrs", quantity: 5, unitPrice: Money.dec("95.00"), taxRate: taxC1, lineTotal: Money.dec("475.00"), sortOrder: 1),

            InvoiceLineItem(id: "ili_1190_1", companyID: c1, invoiceID: "inv_1190", itemDescription: "Coil clean package", quantity: 1, unitPrice: Money.dec("289.00"), taxRate: taxC1, lineTotal: Money.dec("289.00"), sortOrder: 0),

            // Second tenant, plumbing work — identical structure, its own rate.
            InvoiceLineItem(id: "ili_n1", companyID: c2, invoiceID: "inv_north_1", itemDescription: "Anode rod and TPR valve kit", quantity: 1, unitPrice: Money.dec("210.00"), taxRate: taxC2, lineTotal: Money.dec("210.00"), sortOrder: 0),
            InvoiceLineItem(id: "ili_n2", companyID: c2, invoiceID: "inv_north_1", itemDescription: "Labor — 2 hrs", quantity: 2, unitPrice: Money.dec("88.00"), taxRate: taxC2, lineTotal: Money.dec("176.00"), sortOrder: 1)
        ]

        func invoiceTotals(_ invoiceID: String) -> MoneyTotals {
            Money.totals(for: invoiceLineItems.filter { $0.invoiceID == invoiceID })
        }

        let t1168 = invoiceTotals("inv_1168")
        let t1184 = invoiceTotals("inv_1184")
        let t1176 = invoiceTotals("inv_1176")
        let t1180 = invoiceTotals("inv_1180")
        let t1171 = invoiceTotals("inv_1171")
        let t1190 = invoiceTotals("inv_1190")
        let tNorth = invoiceTotals("inv_north_1")

        // DEVELOPMENT PAYMENTS. Nothing was charged: every row is flagged
        // `isSimulated` on the record itself, and the processor references are
        // prefixed SIMULATED- so they can never be mistaken for live ones.
        let payments = [
            // Settles INV-1168 exactly — the amount is taken from the derived
            // total so the seeded "paid" invoice really does balance to zero.
            Payment(id: "pay_1", companyID: c1, invoiceID: "inv_1168", amount: t1168.total, method: .card, status: .succeeded, reference: "TERM-4417", note: "Paid on completion", receivedAt: daysAgo(2), recordedByUserID: "usr_accounts", isSimulated: true),
            // Part payment on a live invoice.
            Payment(id: "pay_2", companyID: c1, invoiceID: "inv_1176", amount: Money.dec("500.00"), method: .ach, status: .succeeded, reference: "ACH-77120", note: nil, receivedAt: daysAgo(3), recordedByUserID: "usr_accounts", isSimulated: true),
            // Part payment on an invoice that is also past its due date, so the
            // part-paid and overdue cases overlap in the seed.
            Payment(id: "pay_4", companyID: c1, invoiceID: "inv_1171", amount: Money.dec("700.00"), method: .check, status: .succeeded, reference: "Check 4471", note: "Customer paying in instalments", receivedAt: daysAgo(5), recordedByUserID: "usr_owner", isSimulated: true),
            // Kept for the audit trail; a failed payment reduces nothing.
            Payment(id: "pay_5", companyID: c1, invoiceID: "inv_1180", amount: Money.dec("1000.00"), method: .card, status: .failed, reference: nil, note: "Card declined", receivedAt: daysAgo(11), recordedByUserID: "usr_accounts", isSimulated: true)
        ]

        /// Only succeeded payments reduce a balance.
        func paidOn(_ invoiceID: String) -> Decimal {
            Money.rounded(
                payments
                    .filter { $0.invoiceID == invoiceID && $0.status.reducesBalance }
                    .reduce(Decimal(0)) { $0 + $1.amount }
            )
        }

        func balanceOn(_ invoiceID: String, _ totals: MoneyTotals) -> Decimal {
            Money.rounded(totals.total - paidOn(invoiceID))
        }

        // Overdue is never *stored*: these invoices carry the status they were
        // left in, and the ones whose due date has passed derive as overdue on
        // read. INV-1180 and INV-1171 are both past due.
        let invoices = [
            Invoice(id: "inv_1168", companyID: c1, customerID: "cus_whitaker", billingContactID: "con_5", addressID: "adr_whitaker", jobID: "job_1038", quoteID: nil, number: "INV-1168", title: "Air handler replacement", scopeOfWork: "Replaced the air handler and reworked the plenum.", status: .paid, currencyCode: "USD", paymentTermsLabel: "Due on receipt", issueDate: daysAgo(9), dueDate: daysAgo(2), subtotal: t1168.subtotal, tax: t1168.tax, total: t1168.total, amountPaid: paidOn("inv_1168"), balance: balanceOn("inv_1168", t1168), createdByUserID: "usr_accounts", sentAt: daysAgo(9), viewedAt: daysAgo(8), paidAt: daysAgo(2), voidedAt: nil),
            Invoice(id: "inv_1184", companyID: c1, customerID: "cus_delgado", billingContactID: "con_4", addressID: "adr_delgado", jobID: "job_1039", quoteID: nil, number: "INV-1184", title: "Thermostat fault", scopeOfWork: "Control board replaced after intermittent shutdowns.", status: .sent, currencyCode: "USD", paymentTermsLabel: "Due on receipt", issueDate: daysAgo(4), dueDate: at(dayOffset: 10, 9), subtotal: t1184.subtotal, tax: t1184.tax, total: t1184.total, amountPaid: paidOn("inv_1184"), balance: balanceOn("inv_1184", t1184), createdByUserID: "usr_accounts", sentAt: daysAgo(4), viewedAt: nil, paidAt: nil, voidedAt: nil),
            Invoice(id: "inv_1176", companyID: c1, customerID: "cus_coastal", billingContactID: "con_6", addressID: "adr_coastal", jobID: "job_1040", quoteID: nil, number: "INV-1176", title: "Filter change — unit bank B", scopeOfWork: "Changed all filters across unit bank B and logged the condition of each return.", status: .partPaid, currencyCode: "USD", paymentTermsLabel: "Net 15", issueDate: daysAgo(12), dueDate: at(dayOffset: 3, 9), subtotal: t1176.subtotal, tax: t1176.tax, total: t1176.total, amountPaid: paidOn("inv_1176"), balance: balanceOn("inv_1176", t1176), createdByUserID: "usr_accounts", sentAt: daysAgo(12), viewedAt: daysAgo(11), paidAt: nil, voidedAt: nil),
            Invoice(id: "inv_1180", companyID: c1, customerID: "cus_whitfield", billingContactID: "con_3", addressID: "adr_whitfield", jobID: nil, quoteID: nil, number: "INV-1180", title: "RTU compressor rebuild", scopeOfWork: "Stripped and rebuilt the compressor on rooftop unit 1.", status: .sent, currencyCode: "USD", paymentTermsLabel: "Net 30", issueDate: daysAgo(46), dueDate: daysAgo(16), subtotal: t1180.subtotal, tax: t1180.tax, total: t1180.total, amountPaid: paidOn("inv_1180"), balance: balanceOn("inv_1180", t1180), createdByUserID: "usr_accounts", sentAt: daysAgo(46), viewedAt: daysAgo(44), paidAt: nil, voidedAt: nil),
            Invoice(id: "inv_1171", companyID: c1, customerID: "cus_ramirez", billingContactID: "con_1", addressID: "adr_ramirez", jobID: nil, quoteID: nil, number: "INV-1171", title: "Evaporator coil replacement", scopeOfWork: "Replaced the evaporator coil and recommissioned the system.", status: .partPaid, currencyCode: "USD", paymentTermsLabel: "Net 30", issueDate: daysAgo(58), dueDate: daysAgo(28), subtotal: t1171.subtotal, tax: t1171.tax, total: t1171.total, amountPaid: paidOn("inv_1171"), balance: balanceOn("inv_1171", t1171), createdByUserID: "usr_accounts", sentAt: daysAgo(58), viewedAt: daysAgo(57), paidAt: nil, voidedAt: nil),
            // A draft, so the editable state is represented too.
            Invoice(id: "inv_1190", companyID: c1, customerID: "cus_whitfield", billingContactID: "con_3", addressID: "adr_whitfield", jobID: nil, quoteID: nil, number: "INV-1190", title: "Coil clean package", scopeOfWork: "Chemical clean of indoor and outdoor coils with drain line flush.", status: .draft, currencyCode: "USD", paymentTermsLabel: "Net 30", issueDate: Date(), dueDate: at(dayOffset: 30, 9), subtotal: t1190.subtotal, tax: t1190.tax, total: t1190.total, amountPaid: 0, balance: t1190.total, createdByUserID: "usr_accounts", sentAt: nil, viewedAt: nil, paidAt: nil, voidedAt: nil),
            // Second tenant: its own prefix, its own padding, its own tax rate.
            Invoice(id: "inv_north_1", companyID: c2, customerID: "cus_north_a", billingContactID: "con_7", addressID: "adr_north_a", jobID: nil, quoteID: nil, number: "N-INV-00499", title: "Water heater service", scopeOfWork: "Annual service: anode rod replaced, TPR valve tested, tank flushed.", status: .sent, currencyCode: "USD", paymentTermsLabel: "Net 30", issueDate: daysAgo(8), dueDate: at(dayOffset: 22, 9), subtotal: tNorth.subtotal, tax: tNorth.tax, total: tNorth.total, amountPaid: 0, balance: tNorth.total, createdByUserID: "usr_north_owner", sentAt: daysAgo(8), viewedAt: nil, paidAt: nil, voidedAt: nil)
        ]

        let notifications = [
            AppNotification(id: "ntf_1", companyID: c1, channel: .sms, template: "worker_on_the_way", recipient: "(813) 555-0142", jobID: "job_1042", customerID: "cus_ramirez", invoiceID: nil, status: .delivered, providerReference: "SIMULATED-SM-9912", sentAt: at(10, 12), deliveredAt: at(10, 12), failureReason: nil),
            AppNotification(id: "ntf_2", companyID: c1, channel: .sms, template: "job_complete", recipient: "(813) 555-0155", jobID: "job_1041", customerID: "cus_delgado", invoiceID: nil, status: .delivered, providerReference: "SIMULATED-SM-9908", sentAt: at(9, 43), deliveredAt: at(9, 43), failureReason: nil)
        ]

        let smsLedger = [
            SmsCreditLedgerEntry(id: "sms_1", companyID: c1, transactionType: .purchase, amount: 250, balanceAfter: 250, jobID: nil, customerID: nil, notificationID: nil, purchaseReference: "SIMULATED-APPLE-IAP-SMS250-0091", createdAt: daysAgo(30)),
            SmsCreditLedgerEntry(id: "sms_2", companyID: c1, transactionType: .adjustment, amount: -34, balanceAfter: 216, jobID: nil, customerID: nil, notificationID: nil, purchaseReference: nil, createdAt: daysAgo(7)),
            SmsCreditLedgerEntry(id: "sms_3", companyID: c1, transactionType: .consumption, amount: -1, balanceAfter: 215, jobID: "job_1041", customerID: "cus_delgado", notificationID: "ntf_2", purchaseReference: nil, createdAt: at(9, 43)),
            SmsCreditLedgerEntry(id: "sms_4", companyID: c1, transactionType: .consumption, amount: -1, balanceAfter: 214, jobID: "job_1042", customerID: "cus_ramirez", notificationID: "ntf_1", purchaseReference: nil, createdAt: at(10, 12)),
            SmsCreditLedgerEntry(id: "sms_5", companyID: c2, transactionType: .purchase, amount: 100, balanceAfter: 100, jobID: nil, customerID: nil, notificationID: nil, purchaseReference: "SIMULATED-GOOGLE-IAP-SMS100-0044", createdAt: daysAgo(4))
        ]

        let serviceAgreements = [
            ServiceAgreement(id: "sa_1", companyID: c1, customerID: "cus_delgado", addressID: "adr_delgado", equipmentID: "eqp_delgado", frequency: .annual, nextDueDate: at(dayOffset: 360, 8), templateJobKind: .maintenance, templateTitle: "Annual maintenance", isActive: true),
            ServiceAgreement(id: "sa_2", companyID: c1, customerID: "cus_whitfield", addressID: "adr_whitfield", equipmentID: "eqp_whitfield", frequency: .quarterly, nextDueDate: at(dayOffset: 88, 8), templateJobKind: .maintenance, templateTitle: "RTU maintenance", isActive: true),
            ServiceAgreement(id: "sa_3", companyID: c2, customerID: "cus_north_a", addressID: "adr_north_a", equipmentID: "eqp_north", frequency: .annual, nextDueDate: at(dayOffset: 340, 8), templateJobKind: .maintenance, templateTitle: "Water heater service", isActive: true)
        ]

        // Numbering is configuration. Gulf Coast runs the platform defaults;
        // Northline carries the numbering it migrated in with, which is exactly
        // the point — neither company's counter touches the other's.
        let documentSequences = [
            DocumentSequence(id: "seq_c1_quote", companyID: c1, kind: .quote, nextValue: 2092),
            DocumentSequence(id: "seq_c1_job", companyID: c1, kind: .job, nextValue: 1050),
            DocumentSequence(id: "seq_c1_invoice", companyID: c1, kind: .invoice, nextValue: 1185),
            DocumentSequence(id: "seq_c2_quote", companyID: c2, kind: .quote, prefix: "N-Q-", nextValue: 411),
            DocumentSequence(id: "seq_c2_job", companyID: c2, kind: .job, prefix: "N-", nextValue: 3002),
            DocumentSequence(id: "seq_c2_invoice", companyID: c2, kind: .invoice, prefix: "N-INV-", nextValue: 500, padWidth: 5)
        ]

        // Two threads against two DIFFERENT jobs, which is what makes a
        // hard-coded or "currently selected job" navigation bug visible: a test
        // can open each in turn and assert it lands on its own job.
        let officeThreads = [
            DevOfficeThread(
                id: "thr_1",
                companyID: c1,
                engineerUserID: "usr_marcus",
                subject: "Condenser fan motor",
                jobID: "job_1042",
                customerID: "cus_ramirez",
                lastMessageAt: at(10, 18),
                lastReadByEngineerAt: at(10, 18),
                lastReadByOfficeAt: nil
            ),
            DevOfficeThread(
                id: "thr_2",
                companyID: c1,
                engineerUserID: "usr_marcus",
                subject: "Roof access at Whitfield",
                jobID: "job_1043",
                customerID: "cus_whitfield",
                lastMessageAt: at(9, 5),
                lastReadByEngineerAt: at(9, 5),
                lastReadByOfficeAt: at(9, 6)
            ),
            // No job. A general conversation still carries images — they are
            // anchored to the thread rather than to a job.
            DevOfficeThread(
                id: "thr_3",
                companyID: c1,
                engineerUserID: "usr_dee",
                subject: "Timesheet question",
                jobID: nil,
                customerID: nil,
                lastMessageAt: daysAgo(1),
                lastReadByEngineerAt: daysAgo(1),
                lastReadByOfficeAt: daysAgo(1)
            ),
            // A general conversation belonging to Marcus, carrying a photo that
            // belongs to no job. This is the case that was impossible before
            // migration 0011, so it is seeded explicitly and asserted on.
            DevOfficeThread(
                id: "thr_4",
                companyID: c1,
                engineerUserID: "usr_marcus",
                subject: "Van parking at the depot",
                jobID: nil,
                customerID: nil,
                // Covers the office's reply (omsg_8, a minute later) so the
                // seeded thread stays read on both sides, as it was.
                lastMessageAt: daysAgo(1).addingTimeInterval(120),
                lastReadByEngineerAt: daysAgo(1).addingTimeInterval(120),
                lastReadByOfficeAt: daysAgo(1).addingTimeInterval(120)
            )
        ]

        let officeMessages = [
            DevOfficeMessage(id: "omsg_1", companyID: c1, threadID: "thr_1", senderUserID: "usr_marcus", body: "Fan motor is seized and the capacitor is bulging. Photo attached.", jobPhotoIDs: ["pho_4"], createdAt: at(10, 14)),
            DevOfficeMessage(id: "omsg_7", companyID: c1, threadID: "thr_1", senderUserID: "usr_owner", body: "This is the replacement we'll fit.", jobPhotoIDs: ["pho_6"], createdAt: at(10, 16)),
            DevOfficeMessage(id: "omsg_2", companyID: c1, threadID: "thr_1", senderUserID: "usr_dispatch", body: "Thanks Marcus. Quote Q-2087 is already with the customer — hold until they approve.", jobPhotoIDs: [], createdAt: at(10, 18)),
            DevOfficeMessage(id: "omsg_3", companyID: c1, threadID: "thr_2", senderUserID: "usr_marcus", body: "Front desk says the roof key is signed out. Who has it?", jobPhotoIDs: [], createdAt: at(9, 2)),
            DevOfficeMessage(id: "omsg_4", companyID: c1, threadID: "thr_2", senderUserID: "usr_owner", body: "Roy keeps it behind reception. Ask for him by name.", jobPhotoIDs: [], createdAt: at(9, 5)),
            DevOfficeMessage(id: "omsg_5", companyID: c1, threadID: "thr_3", senderUserID: "usr_dee", body: "Do call-outs after 6pm go on this week or next?", jobPhotoIDs: [], createdAt: daysAgo(1)),
            // An image on a general conversation, with text.
            DevOfficeMessage(id: "omsg_6", companyID: c1, threadID: "thr_4", senderUserID: "usr_marcus", body: "Parked in the far bay again.", jobPhotoIDs: ["pho_5"], createdAt: daysAgo(1)),
            DevOfficeMessage(id: "omsg_8", companyID: c1, threadID: "thr_4", senderUserID: "usr_owner", body: "Use bay 4 from Monday — layout attached.", jobPhotoIDs: ["pho_7"], createdAt: daysAgo(1).addingTimeInterval(60))
        ]

        return MockDataStore(
            companies: companies,
            subscriptions: subscriptions,
            users: users,
            customers: customers,
            contacts: contacts,
            addresses: addresses,
            equipment: equipment,
            equipmentHistory: equipmentHistory,
            quotes: quotes,
            quoteLineItems: quoteLineItems,
            jobs: jobs,
            jobStatusHistory: jobStatusHistory,
            assignments: assignments,
            jobNotes: jobNotes,
            jobPhotos: jobPhotos,
            workerLocations: workerLocations,
            invoices: invoices,
            invoiceLineItems: invoiceLineItems,
            payments: payments,
            notifications: notifications,
            smsLedger: smsLedger,
            serviceAgreements: serviceAgreements,
            officeThreads: officeThreads,
            officeMessages: officeMessages,
            documentSequences: documentSequences
        )
    }
}
