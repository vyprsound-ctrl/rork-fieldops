import Foundation

/// Harbour South FieldOps legal documents, shipped inside the app.
///
/// These are the in-app source of truth — there is deliberately no external
/// Harbour South privacy-policy URL. Nothing here invents a Harbour South
/// postal address, company number, phone number, website or jurisdiction:
/// the only contact is `Brand.legalContactEmail` (configuration-driven), and
/// where that is not configured the documents point to the support contact on
/// the App Store listing.
nonisolated enum LegalDocument: String, CaseIterable, Identifiable, Hashable, Sendable {
    case privacyPolicy
    case termsOfService
    case smsTerms
    case accountDeletion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy: return "Privacy Policy"
        case .termsOfService: return "Terms of Service"
        case .smsTerms: return "SMS & Messaging Terms"
        case .accountDeletion: return "Account & Data Deletion"
        }
    }

    var summary: String {
        switch self {
        case .privacyPolicy: return "What we collect, why, who processes it and your choices."
        case .termsOfService: return "The rules for using Harbour South FieldOps."
        case .smsTerms: return "Texting customers: credits, numbers, consent and opt-outs."
        case .accountDeletion: return "How to delete your account and what happens to data."
        }
    }

    var symbolName: String {
        switch self {
        case .privacyPolicy: return "hand.raised.fill"
        case .termsOfService: return "doc.text.fill"
        case .smsTerms: return "message.fill"
        case .accountDeletion: return "person.crop.circle.badge.xmark"
        }
    }

    static let lastUpdated = "September 24, 2026"

    /// The contact sentence used by every document.
    static var contactSentence: String {
        if let email = Brand.legalContactEmail {
            return "Contact Harbour South at \(email)."
        }
        return "Contact Harbour South through the support contact shown on the Harbour South FieldOps page in the App Store."
    }

    var sections: [LegalSection] {
        switch self {
        case .privacyPolicy: return LegalText.privacy
        case .termsOfService: return LegalText.terms
        case .smsTerms: return LegalText.sms
        case .accountDeletion: return LegalText.deletion
        }
    }

    /// Every word of the document, for search and tests.
    var fullText: String {
        ([title] + sections.flatMap { [$0.heading] + $0.paragraphs }).joined(separator: "\n")
    }
}

nonisolated struct LegalSection: Identifiable, Hashable, Sendable {
    let heading: String
    let paragraphs: [String]
    var id: String { heading }
}

private nonisolated enum LegalText {
    static let customerResponsibility = "Your business is responsible for providing accurate business information, maintaining any required website or privacy information, obtaining appropriate customer consent, and complying with applicable messaging requirements. Harbour South's legal documents describe Harbour South's own practices; they do not replace your business's own obligations to your customers."

    // MARK: Privacy Policy

    static let privacy: [LegalSection] = [
        LegalSection(heading: "About this policy", paragraphs: [
            "This Privacy Policy explains how Harbour South (\"Harbour South\", \"we\", \"us\") handles information in the Harbour South FieldOps app and its related services (the \"Service\"). Harbour South FieldOps is field-service software used by trade businesses (such as HVAC, plumbing and electrical companies) to run their jobs, teams, quotes, invoices and customer communications.",
            "Two kinds of information are involved. Account information about the people who use the app is handled by Harbour South for its own purposes described below. Business information that a trade business enters about its own customers, sites, jobs and money belongs to that business: Harbour South processes it on the business's behalf to provide the Service, and the business decides what to collect and how it is used.",
            "Last updated: \(LegalDocument.lastUpdated)."
        ]),
        LegalSection(heading: "Information about you as a user", paragraphs: [
            "Account information: your name, work email address, phone number (if provided), password (stored only in hashed form by our authentication provider), role, account status and the company you belong to.",
            "Usage and device information: sign-in times, the app version and device model used to register for notifications, a push-notification device token when you allow notifications, and technical logs needed to operate, secure and troubleshoot the Service.",
            "Location information (engineers): if you are an engineer and allow location access, your device location is recorded at workflow moments (starting travel, arriving, completing) and, only while you are travelling to a job, periodically so the office can see your progress. Location capture stops when the travel leg ends. You can turn location access off in iOS Settings at any time; some travel features will then be unavailable."
        ]),
        LegalSection(heading: "Business information entered by trade businesses", paragraphs: [
            "Company information: business name, trade, address, phone, email, time zone, currency, tax settings and payment terms.",
            "Customer information: customer names, contacts, phone numbers, email addresses, service addresses, access notes and equipment records.",
            "Work records: jobs, scheduling, assignments, job notes, job status history, parts and labour, completion records, signatures and job photos (including photos shared in conversations).",
            "Financial records: quotes, invoices, line items, balances, payment records and receivables.",
            "Communications: internal messages between office staff and engineers (text and photos), customer SMS messages sent and received through the company's dedicated number, message delivery status, opt-out status, message templates, automation settings and scheduled messages.",
            "This information is provided by the trade business and its staff. If you are a customer of a trade business and have a question about your information, please contact that business first; Harbour South will support the business in responding."
        ]),
        LegalSection(heading: "How we use information", paragraphs: [
            "To provide the Service: authenticating users, applying roles and permissions, showing each company only its own data, scheduling and dispatching work, recording job evidence, producing quotes and invoices, taking customer payments, and sending and receiving messages.",
            "To send notifications: push notifications about jobs, office messages and customer replies to the people in the company who are authorised to receive them.",
            "To bill for the Service: managing Harbour South subscriptions, SMS credits (purchases, the credit ledger and segment usage) and dedicated-number fees.",
            "To keep the Service secure and reliable: preventing abuse and spam, investigating problems, enforcing our terms and meeting legal obligations.",
            "We do not sell personal information, and we do not use customer information entered by trade businesses for advertising."
        ]),
        LegalSection(heading: "Customer SMS and inbound messages", paragraphs: [
            "When a trade business turns on SMS, Harbour South creates a separate messaging account and dedicated phone number for that business with our messaging provider, Twilio. Outbound texts, customer replies, delivery status and opt-out requests (such as STOP and START) are processed to deliver messages, show conversation history to the business, alert authorised staff to replies, and honour opt-outs.",
            "To register the business with mobile carriers, the business provides its own business identity and contact details (for example legal name, business type, tax identifier where required, address, website and an authorised representative). These are passed to Twilio and carriers for that registration only.",
            customerResponsibility
        ]),
        LegalSection(heading: "Who processes information for us", paragraphs: [
            "We use service providers that process information on our behalf, only as needed to run the Service:",
            "Supabase — database, authentication, file storage and server functions.",
            "Cloudflare — hosting for customer-facing invoice and quote pages and related web endpoints.",
            "Twilio — SMS sending and receiving, phone numbers and carrier registration.",
            "Stripe and Stripe Connect — card and bank payments made by a trade business's customers to that business's own Stripe account. Harbour South does not store full card numbers. Stripe also processes SMS credit purchases.",
            "Apple — App Store subscriptions and push notifications (Apple Push Notification service). Where the Service is offered through Google Play, Google processes Google Play subscriptions.",
            "Resend — delivery of emails such as invitations and invoices.",
            "These providers act under their own terms and privacy policies. We may also disclose information where required by law, to protect the rights and safety of users and others, or as part of a business transfer, subject to this policy."
        ]),
        LegalSection(heading: "Payments and subscriptions", paragraphs: [
            "Harbour South subscriptions are billed by Apple (or Google, where applicable) to your store account. Harbour South receives confirmation of the subscription and its status, not your full payment details.",
            "Customer payments to a trade business are processed by Stripe into that business's own Stripe account. Harbour South records the payment outcome, amounts and fees against the invoice so the business's records are accurate."
        ]),
        LegalSection(heading: "Security", paragraphs: [
            "Each company's data is separated at the database level so one company cannot read another's. Access inside a company follows the role permissions the owner assigns. Messaging-provider credentials are held only on our servers, never in the app. No method of transmission or storage is completely secure, but we work to protect information using appropriate technical and organisational measures."
        ]),
        LegalSection(heading: "Retention, deletion and anonymisation", paragraphs: [
            "Account information is kept while your account is active. When you delete your account, your name, email and phone number are removed from Harbour South, your sign-in is permanently disabled and your sessions and notification devices are removed.",
            "Business and financial records (customers, jobs, quotes, invoices, payments, photos, messages and SMS records) belong to the trade business and are retained as operational and financial records, including after a workspace is closed, so that records such as invoices and payments remain intact. Work you recorded stays with the company without your name attached.",
            "When a company closes, SMS stops immediately, its dedicated number is kept for a retention period and then released, and its messaging account is closed. See Account & Data Deletion for details."
        ]),
        LegalSection(heading: "Your choices and rights", paragraphs: [
            "You can update your details in the app, turn notifications and location access off in iOS Settings, and delete your account from More → Delete account.",
            "Depending on where you live, you may have rights to access, correct, delete or obtain a copy of your personal information, or to object to certain processing. To make a request, \(LegalDocument.contactSentence) We may need to verify your identity. If your information was entered by a trade business about you as its customer, we may refer your request to that business.",
            "The Service is intended for businesses and is not directed to children."
        ]),
        LegalSection(heading: "Changes and contact", paragraphs: [
            "We may update this policy as the Service changes. The date above shows the latest version, and material changes will be highlighted in the app.",
            "Questions about this policy: \(LegalDocument.contactSentence)"
        ])
    ]

    // MARK: Terms of Service

    static let terms: [LegalSection] = [
        LegalSection(heading: "Agreement", paragraphs: [
            "These Terms of Service (\"Terms\") govern your use of Harbour South FieldOps (the \"Service\") provided by Harbour South. By creating an account, accepting an invitation or using the Service you agree to these Terms. If you use the Service for a company, you confirm you are authorised to do so.",
            "Last updated: \(LegalDocument.lastUpdated)."
        ]),
        LegalSection(heading: "Accounts and security", paragraphs: [
            "You must provide accurate information and keep your sign-in details confidential. You are responsible for activity under your account. Tell the company owner and Harbour South promptly if you believe your account has been compromised.",
            "The person who creates a company is its owner. The owner is responsible for the company's use of the Service, including who is invited, which role each person has, and deactivating people who should no longer have access."
        ]),
        LegalSection(heading: "Roles and authorised use", paragraphs: [
            "Access inside a company follows roles (Owner, Admin, Dispatcher, Engineer, Accounts). You may only access information your role allows and only for the company's legitimate business purposes.",
            "You must not attempt to access another company's data, interfere with the Service, reverse engineer it, bypass security or permissions, or use it to break any law."
        ]),
        LegalSection(heading: "Your data", paragraphs: [
            "The company owns the business information it enters — customers, sites, equipment, jobs, photos, quotes, invoices, payments and messages. You grant Harbour South permission to host, process and transmit that information only to provide and support the Service.",
            "The company is responsible for having the right to enter and use that information, including any notices or consents its own customers require. Engineers' location is captured at workflow moments and during travel legs as described in the Privacy Policy; the company must use location information only for operational purposes."
        ]),
        LegalSection(heading: "Communications and SMS", paragraphs: [
            "Internal messaging, notifications and customer SMS are provided to support field-service operations. Customer SMS is optional and governed by the SMS & Messaging Terms, which form part of these Terms.",
            "Prohibited use includes spam, bulk or unsolicited marketing, harassment, deceptive content, messages to people who have not consented, and any content that is unlawful or violates carrier or messaging-provider rules. Harbour South may suspend messaging or accounts involved in abuse.",
            LegalText.customerResponsibility
        ]),
        LegalSection(heading: "Subscriptions and billing", paragraphs: [
            "Harbour South is offered on paid plans (Starter, Team and Business), billed through Apple's App Store (or Google Play, where offered). Plans renew automatically until cancelled in your store account settings. Trials and offer codes are provided through the store. Prices, taxes and refunds are handled under the store's terms.",
            "A company without an active subscription loses normal access: the owner keeps read-only access to put the subscription right, and other members cannot use the workspace. Downgrading to a plan with fewer users requires the owner to choose who to deactivate; Harbour South never deactivates people on the owner's behalf.",
            "SMS credits and dedicated-number fees are separate from the subscription. See the SMS & Messaging Terms."
        ]),
        LegalSection(heading: "Payments through Stripe", paragraphs: [
            "Companies can take customer payments through their own Stripe account (Stripe Connect). The company's relationship with Stripe is governed by Stripe's terms. Harbour South charges a platform fee on eligible payments as shown in the app. Harbour South is not a party to the payment between the company and its customer."
        ]),
        LegalSection(heading: "Third-party services", paragraphs: [
            "The Service relies on third parties including Apple, Google, Supabase, Cloudflare, Twilio, Stripe and Resend. Their availability and terms can affect the Service, and Harbour South is not responsible for third-party services outside its control."
        ]),
        LegalSection(heading: "Availability and changes", paragraphs: [
            "We work to keep the Service available and reliable but do not guarantee it will be uninterrupted or error-free. We may change, add or remove features. Where a change materially reduces the Service, we will give reasonable notice in the app where practical."
        ]),
        LegalSection(heading: "Suspension and termination", paragraphs: [
            "We may suspend or end access for breach of these Terms, non-payment, abuse, security risk or legal requirement. You may stop using the Service at any time and delete your account from More → Delete account. Deleting an account does not cancel a store subscription; cancel that in your store account settings."
        ]),
        LegalSection(heading: "Account deletion and data", paragraphs: [
            "Account deletion is described in Account & Data Deletion. Business and financial records are retained as described in the Privacy Policy so that the company's records remain intact."
        ]),
        LegalSection(heading: "Disclaimers and limitation of liability", paragraphs: [
            "To the extent permitted by law, the Service is provided \"as is\" and \"as available\", without warranties of any kind, including fitness for a particular purpose. Message delivery, carrier approval and third-party availability are not guaranteed.",
            "To the extent permitted by law, Harbour South will not be liable for indirect, incidental, special, consequential or punitive damages, or for lost profits, revenue or data, arising from use of the Service. Nothing in these Terms limits liability that cannot be limited under applicable law.",
            "You are responsible for your company's use of the Service, including its communications with its own customers, and agree to cover Harbour South for claims arising from your breach of these Terms or misuse of the Service, to the extent permitted by law."
        ]),
        LegalSection(heading: "Changes to these Terms", paragraphs: [
            "We may update these Terms. The date above shows the latest version. Continued use after an update means you accept the updated Terms; material changes will be highlighted in the app."
        ]),
        LegalSection(heading: "Contact", paragraphs: [LegalDocument.contactSentence])
    ]

    // MARK: SMS & Messaging Terms

    static let sms: [LegalSection] = [
        LegalSection(heading: "Optional service", paragraphs: [
            "Customer SMS in Harbour South FieldOps is optional. A company's owner chooses whether to turn it on. These SMS & Messaging Terms form part of the Terms of Service.",
            "Last updated: \(LegalDocument.lastUpdated)."
        ]),
        LegalSection(heading: "Your dedicated number", paragraphs: [
            "When SMS is set up, Harbour South arranges a dedicated US phone number for your business through our messaging provider, Twilio, in a messaging account that belongs to your business alone. Your number is never shared with another business, and you do not need your own Twilio account.",
            "The dedicated number has a monthly fee, shown in More → SMS & Messaging, which is taken from your SMS credits each month. If there aren't enough credits, you'll be notified and given a grace period. After the grace period SMS is paused. The number is kept for a retention period (currently 60 days) and may then be released if the fee remains unpaid."
        ]),
        LegalSection(heading: "SMS credits and segment charging", paragraphs: [
            "Texts are paid for with prepaid SMS credits bought in the app. One credit pays for one SMS segment.",
            "A segment is up to 160 standard characters, or up to 153 characters per part in a longer message. Messages containing emoji or other special characters use a different encoding: up to 70 characters in one segment, or 67 per part. A five-segment message uses five credits. The app shows the number of segments and credits before you send.",
            "Credits are only used when a message is ready to send. If the provider refuses a message before sending, or a carrier reports it undelivered, the credits are returned. Credits are separate from your Harbour South subscription and are not refundable as cash except where required by law. Balances can never go below zero.",
            "Prices for credits and the number fee are shown in the app and may change for future purchases."
        ]),
        LegalSection(heading: "Registration and approval", paragraphs: [
            "US carriers require every business that texts customers to be registered. Your business provides its own accurate business identity, contact details, use case, consent description and sample messages, which Harbour South submits for your business's own registration. Approval is decided by carriers and Twilio, can take several days, and is not guaranteed.",
            "You must not provide false or misleading information. Registration fees charged by carriers may apply as described in the app."
        ]),
        LegalSection(heading: "Customer consent and your responsibilities", paragraphs: [
            LegalText.customerResponsibility,
            "Only text people who have agreed to receive texts from your business about their service, and only about that service. Identify your business in messages. Keep your message content accurate and lawful. You are responsible for the content of messages you and your staff send, including automated and scheduled messages you enable."
        ]),
        LegalSection(heading: "STOP, START and HELP", paragraphs: [
            "Customers can reply STOP (or similar words such as UNSUBSCRIBE, CANCEL, END or QUIT) to opt out of texts from your business. Opted-out customers are blocked from further texts from your business, and no credits are used for blocked messages. Customers can reply START to opt back in, or HELP for help information.",
            "Opt-outs apply to your business's number only. Harbour South does not let anyone bypass an opt-out."
        ]),
        LegalSection(heading: "Prohibited messaging", paragraphs: [
            "SMS in Harbour South FieldOps is for operational field-service messages: appointments, engineer updates, job updates, quotes, invoices and payments. It must not be used for bulk marketing, promotional blasts, purchased or rented contact lists, spam, phishing, harassment, illegal content, or content prohibited by carriers or Twilio (for example certain high-risk financial, gambling, adult or controlled-substance content)."
        ]),
        LegalSection(heading: "Delivery and dependencies", paragraphs: [
            "Messages are delivered through Twilio and mobile carriers. Delivery is not guaranteed and may be delayed, filtered or blocked by carriers or recipient devices. The Service depends on Twilio, carriers and Harbour South's own systems being available."
        ]),
        LegalSection(heading: "Suspension and number release", paragraphs: [
            "Harbour South, Twilio or carriers may suspend a business's messaging for suspected abuse, complaints, non-compliance, failed registration or non-payment. Suspended messaging cannot send or receive texts.",
            "A dedicated number is released only when the owner turns SMS off and confirms, when the company closes and the retention period has passed, or when the number fee has remained unpaid past the retention period. Released numbers may be reassigned by carriers and cannot always be recovered."
        ]),
        LegalSection(heading: "Contact", paragraphs: [LegalDocument.contactSentence])
    ]

    // MARK: Account & Data Deletion

    static let deletion: [LegalSection] = [
        LegalSection(heading: "Deleting your account", paragraphs: [
            "You can delete your own account at any time from More → Delete account. Deletion happens immediately on our servers and cannot be undone.",
            "Last updated: \(LegalDocument.lastUpdated)."
        ]),
        LegalSection(heading: "If you are not the company's only owner", paragraphs: [
            "Your name, email and phone number are removed and your account is anonymised and deactivated. Your password is removed, every session is ended, your notification devices are removed and the account can never sign in again.",
            "Your company keeps running: its other people, customers, jobs, quotes, invoices, payments and other records are not affected. Work you recorded stays with the company without your name attached. The company's Stripe account is not touched."
        ]),
        LegalSection(heading: "If you are the company's only owner", paragraphs: [
            "Deleting your account also closes the company's Harbour South workspace. You'll be asked to confirm this a second time.",
            "When the workspace closes: other members are deactivated, open invitations are cancelled, recurring job generation stops, public invoice links stop working, notification devices are removed and your own account is anonymised as above. Customer SMS stops immediately; the company's dedicated number is kept for the retention period and then released, and its messaging account is closed.",
            "Business and financial records (customers, jobs, quotes, invoices, payments, photos and messages) are retained, not deleted, so financial records remain intact. They can no longer be opened in the app.",
            "Your company's Stripe account belongs to your company and isn't touched; manage or close it with Stripe.",
            "Deleting your account does not cancel an Apple subscription. Cancel it in iOS Settings → your name → Subscriptions. To keep the company running instead, make someone else an Owner before deleting your account."
        ]),
        LegalSection(heading: "Customers of a trade business", paragraphs: [
            "If you are a customer of a business that uses Harbour South FieldOps and want your information changed or removed, contact that business. You can stop texts from a business at any time by replying STOP."
        ]),
        LegalSection(heading: "Questions", paragraphs: [LegalDocument.contactSentence])
    ]
}
