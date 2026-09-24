import Foundation

// MARK: - Message kinds (the operational template catalogue)

/// Every operational SMS a company can send. Raw values are the server's
/// template keys. The server is the authority on the saved wording and on
/// which variables are valid; this copy exists so the composer can offer the
/// right variable chips and so the development build has the same catalogue.
nonisolated enum SmsMessageKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case appointmentConfirmation = "appointment_confirmation"
    case appointmentReminder = "appointment_reminder"
    case appointmentRescheduled = "appointment_rescheduled"
    case appointmentCancelled = "appointment_cancelled"
    case engineerOnTheWay = "engineer_on_the_way"
    case etaUpdate = "eta_update"
    case engineerArrived = "engineer_arrived"
    case jobStarted = "job_started"
    case jobUpdate = "job_update"
    case jobCompleted = "job_completed"
    case quoteSent = "quote_sent"
    case quoteReminder = "quote_reminder"
    case quoteAccepted = "quote_accepted"
    case quoteDeclined = "quote_declined"
    case invoiceSent = "invoice_sent"
    case paymentReminder = "payment_reminder"
    case overdueReminder = "overdue_reminder"
    case paymentReceived = "payment_received"
    case generalCustomerMessage = "general_customer_message"
    case generalJobUpdate = "general_job_update"
    case customerFollowUp = "customer_follow_up"
    case customMessage = "custom_message"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appointmentConfirmation: return "Appointment Confirmation"
        case .appointmentReminder: return "Appointment Reminder"
        case .appointmentRescheduled: return "Appointment Rescheduled"
        case .appointmentCancelled: return "Appointment Cancelled"
        case .engineerOnTheWay: return "Engineer On The Way"
        case .etaUpdate: return "ETA Update"
        case .engineerArrived: return "Engineer Arrived"
        case .jobStarted: return "Job Started"
        case .jobUpdate: return "Job Update"
        case .jobCompleted: return "Job Completed"
        case .quoteSent: return "Quote Sent"
        case .quoteReminder: return "Quote Reminder"
        case .quoteAccepted: return "Quote Accepted"
        case .quoteDeclined: return "Quote Declined"
        case .invoiceSent: return "Invoice Sent"
        case .paymentReminder: return "Payment Reminder"
        case .overdueReminder: return "Overdue Invoice Reminder"
        case .paymentReceived: return "Payment Received"
        case .generalCustomerMessage: return "General Customer Message"
        case .generalJobUpdate: return "General Job Update"
        case .customerFollowUp: return "Customer Follow-Up"
        case .customMessage: return "Custom Message"
        }
    }

    var category: SmsMessageCategory {
        switch self {
        case .appointmentConfirmation, .appointmentReminder, .appointmentRescheduled, .appointmentCancelled: return .appointment
        case .engineerOnTheWay, .etaUpdate, .engineerArrived: return .engineer
        case .jobStarted, .jobUpdate, .jobCompleted: return .job
        case .quoteSent, .quoteReminder, .quoteAccepted, .quoteDeclined: return .quote
        case .invoiceSent, .paymentReminder, .overdueReminder, .paymentReceived: return .invoice
        case .generalCustomerMessage, .generalJobUpdate, .customerFollowUp, .customMessage: return .general
        }
    }

    /// What record the message must be sent from.
    var context: SmsMessageContext {
        switch category {
        case .appointment, .engineer, .job: return .job
        case .quote: return .quote
        case .invoice: return .invoice
        case .general: return self == .generalJobUpdate ? .job : .customer
        }
    }

    var symbolName: String {
        switch self {
        case .appointmentConfirmation: return "calendar.badge.checkmark"
        case .appointmentReminder: return "bell.badge"
        case .appointmentRescheduled: return "calendar.badge.clock"
        case .appointmentCancelled: return "calendar.badge.minus"
        case .engineerOnTheWay: return "car.fill"
        case .etaUpdate: return "clock.arrow.circlepath"
        case .engineerArrived: return "mappin.and.ellipse"
        case .jobStarted: return "wrench.and.screwdriver"
        case .jobUpdate, .generalJobUpdate: return "text.bubble"
        case .jobCompleted: return "checkmark.seal"
        case .quoteSent: return "doc.text"
        case .quoteReminder: return "doc.badge.clock"
        case .quoteAccepted: return "hand.thumbsup"
        case .quoteDeclined: return "hand.thumbsdown"
        case .invoiceSent: return "doc.plaintext"
        case .paymentReminder: return "creditcard"
        case .overdueReminder: return "exclamationmark.circle"
        case .paymentReceived: return "checkmark.circle"
        case .generalCustomerMessage: return "message"
        case .customerFollowUp: return "arrow.uturn.left.circle"
        case .customMessage: return "square.and.pencil"
        }
    }

    var allowedVariables: [SmsTemplateVariable] {
        let person: [SmsTemplateVariable] = [.customerFirstName, .customerLastName, .companyName]
        switch self {
        case .appointmentConfirmation, .appointmentReminder, .appointmentRescheduled, .jobUpdate, .generalJobUpdate:
            return person + [.engineerName, .jobNumber, .appointmentDate, .appointmentTime]
        case .appointmentCancelled:
            return person + [.jobNumber, .appointmentDate, .appointmentTime]
        case .engineerOnTheWay, .etaUpdate:
            return person + [.engineerName, .jobNumber, .appointmentDate, .appointmentTime, .eta]
        case .engineerArrived, .jobStarted, .jobCompleted:
            return person + [.engineerName, .jobNumber]
        case .quoteSent, .quoteReminder:
            return person + [.quoteNumber, .quoteLink]
        case .quoteAccepted, .quoteDeclined:
            return person + [.quoteNumber]
        case .invoiceSent, .paymentReminder, .overdueReminder:
            return person + [.invoiceNumber, .invoiceBalance, .invoiceLink, .paymentLink]
        case .paymentReceived:
            return person + [.invoiceNumber, .invoiceBalance]
        case .generalCustomerMessage, .customerFollowUp, .customMessage:
            return person
        }
    }

    var isAutomatable: Bool { category != .general }

    /// Automations that are on until the company turns them off. Everything
    /// else starts off, so nothing surprising goes to a customer.
    var automationDefault: Bool {
        switch self {
        case .appointmentConfirmation, .appointmentReminder, .appointmentRescheduled, .appointmentCancelled,
             .engineerOnTheWay, .paymentReceived: return true
        default: return false
        }
    }

    var automationDescription: String? {
        switch self {
        case .appointmentConfirmation: return "When a job is booked with a time."
        case .appointmentReminder: return "24 hours before the appointment."
        case .appointmentRescheduled: return "When a booked job moves to a new time."
        case .appointmentCancelled: return "When a job is cancelled."
        case .engineerOnTheWay: return "When the engineer taps Start travel."
        case .etaUpdate: return "When the arrival time changes while the engineer is travelling."
        case .engineerArrived: return "When the engineer taps Arrived."
        case .jobStarted: return "When work starts on site."
        case .jobUpdate: return "When a customer-visible note is added to a job."
        case .jobCompleted: return "When a job is marked complete."
        case .quoteSent: return "When a quote is marked as sent."
        case .quoteReminder: return "3 days after a quote is sent, if it is still open."
        case .quoteAccepted: return "When a quote is accepted."
        case .quoteDeclined: return "When a quote is declined."
        case .invoiceSent: return "When an invoice is marked as sent."
        case .paymentReminder: return "3 days before an invoice is due, if unpaid."
        case .overdueReminder: return "The day after an invoice is due, if unpaid."
        case .paymentReceived: return "When a payment is recorded as received."
        default: return nil
        }
    }

    /// The development catalogue's default wording (the live one comes from the server).
    var defaultBody: String {
        switch self {
        case .appointmentConfirmation: return "{{company_name}}: Hi {{customer_first_name}}, your appointment is confirmed for {{appointment_date}} at {{appointment_time}} (job {{job_number}}). Reply STOP to opt out."
        case .appointmentReminder: return "{{company_name}}: Reminder, we're scheduled to visit on {{appointment_date}} at {{appointment_time}}. Reply to this message if you need to change it."
        case .appointmentRescheduled: return "{{company_name}}: Your appointment (job {{job_number}}) has moved to {{appointment_date}} at {{appointment_time}}. Reply if this doesn't work for you."
        case .appointmentCancelled: return "{{company_name}}: Your appointment for job {{job_number}} has been cancelled. Reply or call us to rebook."
        case .engineerOnTheWay: return "{{company_name}}: {{engineer_name}} is on the way to you now."
        case .etaUpdate: return "{{company_name}}: Updated arrival time for job {{job_number}}: {{eta}}."
        case .engineerArrived: return "{{company_name}}: {{engineer_name}} has arrived for your appointment."
        case .jobStarted: return "{{company_name}}: Work has started on job {{job_number}}. We'll let you know when it's done."
        case .jobUpdate: return "{{company_name}}: There's an update on job {{job_number}}. Reply with any questions."
        case .jobCompleted: return "{{company_name}}: Job {{job_number}} is complete. Thank you for choosing us, {{customer_first_name}}."
        case .quoteSent: return "{{company_name}}: Hi {{customer_first_name}}, your quote {{quote_number}} is ready to view: {{quote_link}} Reply STOP to opt out."
        case .quoteReminder: return "{{company_name}}: A reminder that quote {{quote_number}} is waiting for you: {{quote_link}}"
        case .quoteAccepted: return "{{company_name}}: Thanks, {{customer_first_name}}. Quote {{quote_number}} is accepted and we'll be in touch to schedule the work."
        case .quoteDeclined: return "{{company_name}}: We've noted that quote {{quote_number}} was declined. Reply any time if we can help."
        case .invoiceSent: return "{{company_name}}: Invoice {{invoice_number}} for {{invoice_balance}} is ready. View and pay: {{invoice_link}} Reply STOP to opt out."
        case .paymentReminder: return "{{company_name}}: A friendly reminder that invoice {{invoice_number}} ({{invoice_balance}}) is due. Pay here: {{payment_link}}"
        case .overdueReminder: return "{{company_name}}: Invoice {{invoice_number}} is overdue with {{invoice_balance}} outstanding. Pay here: {{payment_link}} or reply to talk to us."
        case .paymentReceived: return "{{company_name}}: Thank you, we've received your payment for invoice {{invoice_number}}."
        case .generalCustomerMessage: return "{{company_name}}: Hi {{customer_first_name}}, "
        case .generalJobUpdate: return "{{company_name}}: An update on job {{job_number}}: "
        case .customerFollowUp: return "{{company_name}}: Hi {{customer_first_name}}, just following up on our recent visit. How is everything working? Reply to let us know."
        case .customMessage: return ""
        }
    }

    /// Kinds offered from a given record.
    static func offered(for context: SmsMessageContext) -> [SmsMessageKind] {
        switch context {
        case .customer: return [.generalCustomerMessage, .customerFollowUp, .customMessage]
        case .job:
            return [.appointmentConfirmation, .appointmentReminder, .engineerOnTheWay, .etaUpdate, .engineerArrived,
                    .jobUpdate, .jobCompleted, .generalJobUpdate, .customMessage]
        case .quote: return [.quoteSent, .quoteReminder, .customMessage]
        case .invoice: return [.invoiceSent, .paymentReminder, .overdueReminder, .paymentReceived, .customMessage]
        }
    }
}

nonisolated enum SmsMessageCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case appointment, engineer, job, quote, invoice, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appointment: return "Appointment"
        case .engineer: return "Engineer"
        case .job: return "Job"
        case .quote: return "Quote"
        case .invoice: return "Invoice"
        case .general: return "General"
        }
    }
}

nonisolated enum SmsMessageContext: String, Hashable, Sendable {
    case customer, job, quote, invoice
}

nonisolated enum SmsTemplateVariable: String, CaseIterable, Identifiable, Hashable, Sendable {
    case customerFirstName = "customer_first_name"
    case customerLastName = "customer_last_name"
    case companyName = "company_name"
    case engineerName = "engineer_name"
    case jobNumber = "job_number"
    case appointmentDate = "appointment_date"
    case appointmentTime = "appointment_time"
    case eta
    case quoteNumber = "quote_number"
    case invoiceNumber = "invoice_number"
    case invoiceBalance = "invoice_balance"
    case paymentLink = "payment_link"
    case quoteLink = "quote_link"
    case invoiceLink = "invoice_link"

    var id: String { rawValue }
    var token: String { "{{\(rawValue)}}" }

    var label: String {
        switch self {
        case .customerFirstName: return "First name"
        case .customerLastName: return "Last name"
        case .companyName: return "Company"
        case .engineerName: return "Engineer"
        case .jobNumber: return "Job #"
        case .appointmentDate: return "Date"
        case .appointmentTime: return "Time"
        case .eta: return "ETA"
        case .quoteNumber: return "Quote #"
        case .invoiceNumber: return "Invoice #"
        case .invoiceBalance: return "Balance"
        case .paymentLink: return "Pay link"
        case .quoteLink: return "Quote link"
        case .invoiceLink: return "Invoice link"
        }
    }

    /// A plausible length used only for the segment estimate before the
    /// server renders the real value.
    var sampleValue: String {
        switch self {
        case .customerFirstName: return "Jane"
        case .customerLastName: return "Doe"
        case .companyName: return "Your Company"
        case .engineerName: return "Mike"
        case .jobNumber: return "J-1047"
        case .appointmentDate: return "Tue, Oct 6"
        case .appointmentTime: return "9:00 AM"
        case .eta: return "around 9:40 AM"
        case .quoteNumber: return "Q-2087"
        case .invoiceNumber: return "INV-1180"
        case .invoiceBalance: return "$1,240.00"
        case .paymentLink, .invoiceLink: return "https://field-ops-backend.rork.app/i?t=" + String(repeating: "a", count: 64)
        case .quoteLink: return "https://field-ops-backend.rork.app/q?t=" + String(repeating: "a", count: 64)
        }
    }
}

// MARK: - Template validation (mirrors the server rule)

nonisolated enum SmsTemplateValidator {
    static let maxCharacters = 640

    /// Every `{{variable}}` in the text, in order.
    static func variables(in text: String) -> [String] {
        var found: [String] = []
        var rest = Substring(text)
        while let open = rest.range(of: "{{") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else { break }
            let name = after[..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            found.append(name)
            rest = after[close.upperBound...]
        }
        return found
    }

    /// Nil when the text is acceptable for this message kind.
    static func problem(kind: SmsMessageKind, body: String) -> String? {
        if body.count > maxCharacters { return "Keep the message under \(maxCharacters) characters." }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && kind != .customMessage {
            return "The message can't be empty."
        }
        let allowed = Set(kind.allowedVariables.map(\.rawValue))
        for name in variables(in: body) where !allowed.contains(name) {
            return "{{\(name)}} can't be used in this message."
        }
        var stripped = body
        for name in variables(in: body) {
            stripped = stripped.replacingOccurrences(of: "{{\(name)}}", with: "")
            stripped = stripped.replacingOccurrences(of: "{{ \(name) }}", with: "")
        }
        if stripped.contains("{") || stripped.contains("}") {
            return "Remove the stray { or } characters, or pick a variable from the list."
        }
        return nil
    }

    /// The text with every variable replaced by a typical value, for the
    /// segment estimate shown before sending.
    static func estimate(_ body: String) -> String {
        var text = body
        for variable in SmsTemplateVariable.allCases {
            text = text.replacingOccurrences(of: variable.token, with: variable.sampleValue)
        }
        return text
    }
}

// MARK: - Segments (1 credit = 1 segment)

/// Carrier segment counting, identical to the server's `sms_segment_info`:
/// GSM-7 is 160 characters in one segment and 153 per part, extension
/// characters count twice and never split; anything else is UCS-2 at 70 / 67,
/// and characters outside the Basic Multilingual Plane (emoji) count twice.
nonisolated enum SmsSegmentCounter {
    private static let basic: Set<Unicode.Scalar> = Set(
        ("@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà").unicodeScalars
    )
    private static let extended: Set<Unicode.Scalar> = Set("^{}\\[~]|€\u{0C}".unicodeScalars)

    nonisolated struct Result: Hashable, Sendable {
        let segments: Int
        let encoding: String
        let units: Int
        var credits: Int { segments }
        var isUnicode: Bool { encoding == "UCS-2" }
    }

    static func count(_ text: String) -> Result {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return Result(segments: 0, encoding: "GSM-7", units: 0) }
        let isGSM = scalars.allSatisfy { basic.contains($0) || extended.contains($0) }
        let single = isGSM ? 160 : 70
        let part = isGSM ? 153 : 67
        var total = 0
        var segments = 1
        var current = 0
        for scalar in scalars {
            let width: Int
            if isGSM { width = extended.contains(scalar) ? 2 : 1 } else { width = scalar.value > 0xFFFF ? 2 : 1 }
            total += width
            if current + width > part { segments += 1; current = 0 }
            current += width
        }
        return Result(segments: total <= single ? 1 : segments, encoding: isGSM ? "GSM-7" : "UCS-2", units: total)
    }
}

// MARK: - Setup status

/// The six states a business owner ever sees. Never a provider code.
nonisolated enum SmsFriendlyStatus: String, Hashable, Sendable {
    case notSetUp, settingUp, waitingApproval, ready, needsAttention, suspended

    var title: String {
        switch self {
        case .notSetUp: return "SMS Not Set Up"
        case .settingUp: return "Setting Up SMS"
        case .waitingApproval: return "Waiting for Approval"
        case .ready: return "SMS Ready"
        case .needsAttention: return "SMS Needs Attention"
        case .suspended: return "SMS Suspended"
        }
    }

    var symbolName: String {
        switch self {
        case .notSetUp: return "message.badge"
        case .settingUp: return "gearshape.2.fill"
        case .waitingApproval: return "hourglass"
        case .ready: return "checkmark.message.fill"
        case .needsAttention: return "exclamationmark.bubble.fill"
        case .suspended: return "pause.circle.fill"
        }
    }

    var tone: StatusTone {
        switch self {
        case .ready: return .success
        case .needsAttention, .suspended: return .danger
        case .waitingApproval, .settingUp: return .warning
        case .notSetUp: return .neutral
        }
    }

    var canSend: Bool { self == .ready }
}

nonisolated struct MessagingSetupStatus: Hashable, Sendable {
    let friendly: SmsFriendlyStatus
    let registrationRoute: SmsRegistrationRoute?
    let phoneNumber: String?
    let billingState: String
    let nextFeeDueAt: Date?
    let numberFeeCents: Int
    let numberFeeCredits: Int
    let setupFeeCents: Int
    let retentionDays: Int
    let graceDays: Int
    let attention: String?
    let businessName: String?
    let canManage: Bool
    let hasSubscription: Bool
    let balance: Int
    let needsNumberChoice: Bool
    let solePropVerificationPending: Bool
    let providerAvailable: Bool

    var numberFeeLabel: String { String(format: "$%.2f", Double(numberFeeCents) / 100) }
    var displayNumber: String? { phoneNumber.map(PhoneFormatting.pretty) }
}

nonisolated enum SmsRegistrationRoute: String, CaseIterable, Identifiable, Hashable, Sendable {
    case standard
    case lowVolume = "low_volume"
    case soleProprietor = "sole_proprietor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Registered business"
        case .lowVolume: return "Registered business, low volume"
        case .soleProprietor: return "Sole proprietor (no EIN)"
        }
    }

    var detail: String {
        switch self {
        case .standard: return "You have an EIN and send more than a few thousand texts a month."
        case .lowVolume: return "You have an EIN and send fewer than about 6,000 texts a month. Cheapest for most trade businesses."
        case .soleProprietor: return "You trade as yourself without an EIN. You'll confirm a one-time text on your own mobile."
        }
    }

    var needsEIN: Bool { self != .soleProprietor }
}

nonisolated enum SmsBusinessStructure: String, CaseIterable, Identifiable, Hashable, Sendable {
    case llc = "Limited Liability Corporation"
    case corporation = "Corporation"
    case partnership = "Partnership"
    case coOperative = "Co-operative"
    case nonProfit = "Non-profit Corporation"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .llc: return "LLC"
        case .corporation: return "Corporation"
        case .partnership: return "Partnership"
        case .coOperative: return "Co-operative"
        case .nonProfit: return "Non-profit"
        }
    }
}

/// What the owner submits for their own carrier registration. Nothing here is
/// pre-filled with invented information.
nonisolated struct SmsBusinessDetailsDraft: Hashable, Sendable {
    var route: SmsRegistrationRoute = .lowVolume
    var legalName: String = ""
    var structure: SmsBusinessStructure = .llc
    var ein: String = ""
    var website: String = ""
    var street: String = ""
    var street2: String = ""
    var city: String = ""
    var state: String = ""
    var postalCode: String = ""
    var repFirstName: String = ""
    var repLastName: String = ""
    var repTitle: String = "Owner"
    var repEmail: String = ""
    var repPhone: String = ""
    var mobilePhone: String = ""
    var optInDescription: String = ""
    var acceptedResponsibility: Bool = false

    /// Nil when ready to submit; otherwise the first thing to fix.
    var problem: String? {
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if blank(legalName) { return "Enter your legal business name." }
        if blank(street) || blank(city) || blank(state) || blank(postalCode) { return "Enter your full business address." }
        if state.trimmingCharacters(in: .whitespaces).count != 2 { return "Use the two-letter state code, like FL." }
        if postalCode.filter(\.isNumber).count < 5 { return "Enter a valid ZIP code." }
        if blank(repFirstName) || blank(repLastName) { return "Enter the authorized representative's name." }
        if !repEmail.contains("@") || !repEmail.contains(".") { return "Enter a valid email for the representative." }
        if repPhone.filter(\.isNumber).count < 10 { return "Enter a valid phone number for the representative." }
        if optInDescription.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
            return "Describe how customers agree to receive texts (at least a sentence)."
        }
        if route.needsEIN {
            if ein.filter(\.isNumber).count != 9 { return "Enter your 9-digit EIN, like 12-3456789." }
            let site = website.lowercased()
            if !(site.hasPrefix("http://") || site.hasPrefix("https://")) || !site.contains(".") {
                return "Enter your business website, starting with https://"
            }
        } else if mobilePhone.filter(\.isNumber).count < 10 {
            return "Enter your own mobile number for the one-time verification text."
        }
        if !acceptedResponsibility { return "Confirm the responsibilities below to continue." }
        return nil
    }
}

nonisolated struct AvailableSmsNumber: Identifiable, Hashable, Sendable {
    let phoneNumber: String
    let locality: String?
    let region: String?
    var id: String { phoneNumber }
    var pretty: String { PhoneFormatting.pretty(phoneNumber) }
    var place: String { [locality, region].compactMap { $0 }.joined(separator: ", ") }
}

nonisolated struct SmsSetupResult: Hashable, Sendable {
    let status: MessagingSetupStatus
    let message: String?
    let numberUnavailable: Bool
}

nonisolated enum PhoneFormatting {
    static func pretty(_ e164: String) -> String {
        let digits = e164.filter(\.isNumber)
        let local = digits.count == 11 && digits.hasPrefix("1") ? String(digits.dropFirst()) : digits
        guard local.count == 10 else { return e164 }
        let a = local.prefix(3), b = local.dropFirst(3).prefix(3), c = local.suffix(4)
        return "(\(a)) \(b)-\(c)"
    }
}

// MARK: - Conversations and history

nonisolated struct CommunicationsUnread: Hashable, Sendable {
    let customerUnread: Int
    let officeUnread: Int
    let latestTitle: String?
    let latestBody: String?
    let latestLink: String?
    let latestAt: Date?

    var total: Int { customerUnread + officeUnread }
    static let none = CommunicationsUnread(customerUnread: 0, officeUnread: 0, latestTitle: nil, latestBody: nil, latestLink: nil, latestAt: nil)
}

nonisolated struct SmsConversationRow: Identifiable, Hashable, Sendable {
    let id: String
    let phone: String
    let customerID: String?
    let customerName: String?
    let jobID: String?
    let jobNumber: String?
    let lastMessageAt: Date
    let lastPreview: String
    let lastWasInbound: Bool
    let unread: Int
    let optedOut: Bool

    var displayName: String { customerName ?? PhoneFormatting.pretty(phone) }
}

nonisolated enum SmsDirection: String, Hashable, Sendable {
    case inbound, outbound
}

nonisolated struct SmsThreadMessage: Identifiable, Hashable, Sendable {
    let id: String
    let conversationID: String?
    let direction: SmsDirection
    let body: String
    let at: Date
    let status: String
    let kind: SmsMessageKind?
    let segments: Int?
    let creditsCharged: Int
    let creditsRefunded: Int
    let jobID: String?
    let failureReason: String?

    var statusLabel: String {
        switch status {
        case "received": return "Received"
        case "delivered": return "Delivered"
        case "failed", "undelivered": return creditsRefunded > 0 ? "Not delivered · credit returned" : "Not delivered"
        case "queued": return "Sending"
        default: return "Sent"
        }
    }

    var statusTone: StatusTone {
        switch status {
        case "delivered": return .success
        case "failed", "undelivered": return .danger
        default: return .neutral
        }
    }

    var kindTitle: String {
        switch body.uppercased().trimmingCharacters(in: .whitespaces) {
        case "STOP" where direction == .inbound: return "Opted out"
        case "START" where direction == .inbound: return "Opted back in"
        default: return direction == .inbound ? "Reply" : (kind?.title ?? "Message")
        }
    }
}

nonisolated struct SmsConversationDetail: Hashable, Sendable {
    let conversation: SmsConversationRow
    let messages: [SmsThreadMessage]
    let recipientName: String
}

nonisolated struct ScheduledMessageRow: Identifiable, Hashable, Sendable {
    let id: String
    let customerID: String
    let customerName: String
    let jobNumber: String?
    let kind: SmsMessageKind
    let preview: String
    let scheduledFor: Date
    let status: String
    let isAutomation: Bool
    let failureReason: String?

    var isCancellable: Bool { status == "scheduled" }
    var statusLabel: String {
        switch status {
        case "scheduled": return isAutomation ? "Automatic" : "Scheduled"
        case "sending": return "Sending"
        case "sent": return "Sent"
        case "cancelled": return "Cancelled"
        case "skipped": return "Not sent"
        default: return "Failed"
        }
    }
}

nonisolated struct SentMessageRow: Identifiable, Hashable, Sendable {
    let id: String
    let recipient: String
    let customerID: String?
    let customerName: String?
    let jobNumber: String?
    let kind: SmsMessageKind?
    let body: String
    let at: Date
    let state: SmsDeliveryState
    let segments: Int?
    let creditsCharged: Int
    let creditsRefunded: Int
    let failureReason: String?
}

nonisolated struct SmsTemplateEntry: Identifiable, Hashable, Sendable {
    let kind: SmsMessageKind
    let body: String
    let defaultBody: String
    let allowedVariables: [SmsTemplateVariable]
    let isCustomised: Bool
    let isAutomatable: Bool
    let automationEnabled: Bool
    let automationDescription: String?
    var id: String { kind.rawValue }
}

nonisolated struct SmsUsageSummary: Hashable, Sendable {
    let balance: Int
    let purchased: Int
    let used: Int
    let refunded: Int
    let numberFees: Int
    let segments30d: Int
    let sent30d: Int
    let failed30d: Int
    let received30d: Int
}

// MARK: - Composing

nonisolated struct SmsComposeDraft: Hashable, Sendable {
    let customerID: String
    var jobID: String?
    var quoteID: String?
    var invoiceID: String?
    var kind: SmsMessageKind
    var body: String
    var phone: String?
    var eta: String?
}

nonisolated struct SmsPreview: Hashable, Sendable {
    let body: String
    let recipient: String
    let segments: Int
    let encoding: String
    let blockerMessage: String?
}

nonisolated struct SmsDispatchOutcome: Hashable, Sendable {
    let sent: Bool
    let scheduled: Bool
    let creditsCharged: Int
    let segments: Int?
    let balance: Int?
    let conversationID: String?
    let detail: String
}
