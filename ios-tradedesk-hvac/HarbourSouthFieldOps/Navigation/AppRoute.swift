import Foundation

/// Sections reachable from the More tab. Each declares the permission the data
/// layer will require, so the UI and the gateway can never drift apart.
nonisolated enum MoreSection: String, Hashable, CaseIterable, Identifiable, Sendable {
    case dispatch
    case fieldWorkers
    case workerLocations
    case quotes
    case invoices
    case payments
    case reports
    case notifications
    case recurring
    case subscription
    case smsCredits
    case paymentTerms
    case companyProfile
    case settings
    /// The central Stripe and payment-model screen. Offered at the top level of
    /// More as "Connect Stripe" (see `menuTitle(_:)`) and still reachable from
    /// Settings → Integrations → Payments and from Subscription. Every entry
    /// opens this same route, so there is one Stripe surface, not three.
    case payments_integration
    /// The company's own external payment URL, reached from the Payments
    /// screen. No longer a top-level settings row: a pasted link is one of two
    /// models now, not the headline way to take money.
    case paymentLink
    /// The business's own customer-facing email identity. Reachable from the
    /// top level of More as "Set up your email", because an owner who has not
    /// set it yet will never go looking three levels down in Settings for it.
    case businessEmail
    /// ISSUE #13 — the office's own view of field worker conversations.
    ///
    /// The database already delivered these threads to office roles; there was
    /// simply no screen to open them from. Placed at the top level of More
    /// because an owner who has been messaged will not go hunting for it.
    case messages
    case dataAccess
    case integrations
    case developmentTests

    var id: String { rawValue }

    /// Trade-neutral title. Use `title(_:)` where a company context exists.
    var title: String {
        switch self {
        case .dispatch: return "Dispatch"
        case .fieldWorkers: return "Field workers"
        case .workerLocations: return "Field worker locations"
        case .quotes: return "Quotes"
        case .invoices: return "Invoices"
        case .payments: return "Accounts receivable"
        case .reports: return "Reports"
        case .recurring: return "Recurring service"
        case .subscription: return "Subscription & Users"
        case .smsCredits: return "SMS credits"
        case .paymentTerms: return "Payment terms"
        case .companyProfile: return "Company profile"
        case .notifications: return "Job alerts"
        case .settings: return "Settings"
        case .payments_integration: return "Payments"
        case .paymentLink: return "My payment link"
        case .businessEmail: return "Set up your email"
        case .messages: return "Messages"
        case .dataAccess: return "Role & data access"
        case .integrations: return "Integrations"
        case .developmentTests: return "Development tests"
        }
    }

    func title(_ terms: Terminology) -> String {
        switch self {
        case .fieldWorkers: return terms.WorkerPlural
        case .workerLocations: return "\(terms.Worker) locations"
        default: return title
        }
    }

    /// The row label in the More menu.
    ///
    /// The same as `title(_:)` except for the Payments screen, which the menu
    /// names by the action an owner is looking for. The row opens the existing
    /// screen unchanged; only the label on the way in differs.
    func menuTitle(_ terms: Terminology) -> String {
        switch self {
        case .payments_integration: return "Connect Stripe"
        default: return title(terms)
        }
    }

    var symbolName: String {
        switch self {
        case .dispatch: return "antenna.radiowaves.left.and.right"
        case .fieldWorkers: return "person.2.fill"
        case .workerLocations: return "location.fill"
        case .quotes: return "doc.text.fill"
        case .invoices: return "doc.plaintext.fill"
        case .payments: return "chart.line.uptrend.xyaxis"
        case .reports: return "chart.bar.fill"
        case .recurring: return "arrow.triangle.2.circlepath"
        case .subscription: return "creditcard.fill"
        case .smsCredits: return "message.fill"
        case .paymentTerms: return "calendar.badge.clock"
        case .companyProfile: return "building.2.fill"
        case .notifications: return "bell.fill"
        case .settings: return "gearshape.fill"
        case .payments_integration: return "creditcard.and.123"
        case .paymentLink: return "link"
        case .businessEmail: return "envelope.fill"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .dataAccess: return "lock.shield.fill"
        case .integrations: return "app.connected.to.app.below.fill"
        case .developmentTests: return "checklist"
        }
    }

    /// Permission the data layer enforces for this section.
    var requiredPermission: Permission? {
        switch self {
        case .dispatch: return .calendarReadAll
        case .fieldWorkers: return .usersRead
        case .workerLocations: return .fieldWorkerLocationReadAll
        case .quotes: return .quotesRead
        case .invoices: return .invoicesRead
        case .payments: return .paymentsRead
        // Reports carries no single permission: operational and financial
        // reporting are separate grants held by different roles, so each block
        // is gated inside the screen instead.
        case .reports: return nil
        // Recurring visits produce jobs, so seeing them is a jobs read.
        case .recurring: return .jobsReadAll
        case .subscription: return .saasBillingRead
        // The SMS screen serves three different people: whoever reads the
        // ledger, whoever sends, and whoever buys. The narrowest of those is
        // the gate; the screen gates each block individually beneath it.
        case .smsCredits: return .smsLedgerRead
        case .paymentTerms: return .companyProfileRead
        // Readable by every office role; the save button is gated separately on
        // `companyProfileManage` inside the screen.
        case .companyProfile: return .companyProfileRead
        // Anyone with a session may manage their own device's alerts.
        case .notifications: return nil
        case .settings: return .companyProfileRead
        // Stripe onboarding and the commercial model are billing acts. The
        // screen is gated on the SaaS billing read, which in the shipped
        // matrix only the owner holds — and the database refuses the
        // underlying call to anyone else regardless of this.
        case .payments_integration: return .saasBillingRead
        case .paymentLink: return .companyProfileRead
        case .businessEmail: return .companyProfileRead
        // Messaging is gated by the same rule the database uses: the
        // `office_threads_select` policy admits a caller who holds
        // `assignmentsManage` or `usersManage` (its `is_office_user()`). Naming
        // `assignmentsManage` here keeps the menu honest — a role that would be
        // shown an empty inbox is not offered the row at all.
        case .messages: return .assignmentsManage
        case .dataAccess: return nil
        case .integrations: return nil
        case .developmentTests: return nil
        }
    }

    var isBuilt: Bool {
        switch self {
        case .dispatch, .workerLocations, .fieldWorkers, .quotes, .invoices, .payments, .reports,
             .recurring, .subscription, .smsCredits, .paymentTerms, .notifications, .dataAccess,
             .integrations, .settings, .paymentLink, .companyProfile, .developmentTests,
             .payments_integration, .businessEmail, .messages: return true
        }
    }
}

nonisolated enum AppRoute: Hashable, Sendable {
    case job(String)
    case quote(String)
    case invoice(String)
    case customer(String)
    /// One field worker ↔ office conversation, by thread id.
    case message(String)
    case more(MoreSection)

    /// ISSUE #11 — the invoice list, opened on a specific filter.
    ///
    /// Reports showed "Overdue · $4,180" and stopped there: a figure with no way
    /// to reach the invoices behind it. Rather than build a second list screen
    /// with its own querying (and its own chance of disagreeing with the real
    /// one), a report metric now opens the existing Invoices screen with its
    /// filter already applied. One list, one source of truth, one set of
    /// permissions.
    case invoiceList(InvoiceListFilter)

    /// #11 — the jobs list, opened on a specific filter, for the same reason.
    case jobList(JobListFilter)
}

extension AppRoute: Identifiable {
    /// Lets a route be presented directly, which is what a notification tap
    /// needs: the destination has to open from wherever the person already was,
    /// not from one particular tab's navigation stack.
    var id: String {
        switch self {
        case .job(let value): return "job-\(value)"
        case .quote(let value): return "quote-\(value)"
        case .invoice(let value): return "invoice-\(value)"
        case .customer(let value): return "customer-\(value)"
        case .message(let value): return "message-\(value)"
        case .more(let section): return "more-\(section.rawValue)"
        case .invoiceList(let filter): return "invoiceList-\(filter.rawValue)"
        case .jobList(let filter): return "jobList-\(filter.rawValue)"
        }
    }
}

/// Actions on the office home grid.
nonisolated enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    case newJob
    case newQuote
    case newInvoice
    case addCustomer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newJob: return "New Job"
        case .newQuote: return "New Quote"
        case .newInvoice: return "New Invoice"
        case .addCustomer: return "Add Customer"
        }
    }

    var symbolName: String {
        switch self {
        case .newJob: return "briefcase.fill"
        case .newQuote: return "doc.text.fill"
        case .newInvoice: return "doc.plaintext.fill"
        case .addCustomer: return "person.badge.plus.fill"
        }
    }

    var requiredPermission: Permission {
        switch self {
        case .newJob: return .jobsManage
        case .newQuote: return .quotesManage
        case .newInvoice: return .invoicesManage
        case .addCustomer: return .customersManage
        }
    }
}
