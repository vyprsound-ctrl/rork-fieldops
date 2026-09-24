import Foundation
import Testing
@testable import HarbourSouthFieldOps

// =============================================================================
// Communications, SMS segments, templates, legal documents and deep links.
// Pure logic only; the server-side rules have their own SQL suite
// (backend/tests/sms-multitenant-suite.sql).
// =============================================================================

struct SmsSegmentTests {
    @Test("GSM-7: 160 characters is one segment, 161 is two")
    func gsmBoundary() {
        #expect(SmsSegmentCounter.count(String(repeating: "a", count: 160)).segments == 1)
        #expect(SmsSegmentCounter.count(String(repeating: "a", count: 161)).segments == 2)
        #expect(SmsSegmentCounter.count(String(repeating: "a", count: 306)).segments == 2)
        #expect(SmsSegmentCounter.count(String(repeating: "a", count: 307)).segments == 3)
    }

    @Test("A five-segment message costs five credits")
    func fiveSegments() {
        let result = SmsSegmentCounter.count(String(repeating: "a", count: 765))
        #expect(result.segments == 5)
        #expect(result.credits == 5)
    }

    @Test("GSM extension characters count twice")
    func extensionCharacters() {
        #expect(SmsSegmentCounter.count(String(repeating: "{", count: 80)).segments == 1)
        #expect(SmsSegmentCounter.count(String(repeating: "{", count: 81)).segments == 2)
        #expect(SmsSegmentCounter.count("€").units == 2)
    }

    @Test("Accented GSM letters stay GSM-7")
    func accentedStaysGSM() {
        let result = SmsSegmentCounter.count(String(repeating: "é", count: 160))
        #expect(result.encoding == "GSM-7")
        #expect(result.segments == 1)
    }

    @Test("Unicode: 70 characters is one segment, 71 is two")
    func unicodeBoundary() {
        #expect(SmsSegmentCounter.count(String(repeating: "ł", count: 70)).isUnicode)
        #expect(SmsSegmentCounter.count(String(repeating: "ł", count: 70)).segments == 1)
        #expect(SmsSegmentCounter.count(String(repeating: "ł", count: 71)).segments == 2)
    }

    @Test("Emoji force Unicode and count as two units")
    func emoji() {
        let result = SmsSegmentCounter.count("See you soon 😊")
        #expect(result.isUnicode)
        #expect(result.units == 15)
        #expect(SmsSegmentCounter.count(String(repeating: "😊", count: 35)).segments == 1)
        #expect(SmsSegmentCounter.count(String(repeating: "😊", count: 36)).segments == 2)
    }

    @Test("Empty text is zero segments")
    func empty() {
        #expect(SmsSegmentCounter.count("").segments == 0)
    }
}

struct SmsTemplateTests {
    @Test("All 22 operational message types exist, 18 of them automatable")
    func catalogue() {
        #expect(SmsMessageKind.allCases.count == 22)
        #expect(SmsMessageKind.allCases.filter(\.isAutomatable).count == 18)
    }

    @Test("Every default template uses only its own variables and is valid")
    func defaultsAreValid() {
        for kind in SmsMessageKind.allCases {
            #expect(SmsTemplateValidator.problem(kind: kind, body: kind.defaultBody) == nil, "\(kind.rawValue)")
        }
    }

    @Test("Operational templates identify the company")
    func companyIdentified() {
        for kind in SmsMessageKind.allCases where kind != .customMessage {
            #expect(kind.defaultBody.contains("{{company_name}}"), "\(kind.rawValue)")
        }
    }

    @Test("A variable not valid for the template is refused")
    func invalidVariable() {
        #expect(SmsTemplateValidator.problem(kind: .appointmentConfirmation, body: "Pay {{invoice_link}}") != nil)
        #expect(SmsTemplateValidator.problem(kind: .quoteSent, body: "Hi {{engineer_name}}") != nil)
    }

    @Test("Misspelt and malformed variables are refused")
    func malformed() {
        #expect(SmsTemplateValidator.problem(kind: .jobUpdate, body: "Hi {{customer_firstname}}") != nil)
        #expect(SmsTemplateValidator.problem(kind: .jobUpdate, body: "Hi {{customer_first_name}") != nil)
        #expect(SmsTemplateValidator.problem(kind: .jobUpdate, body: "Hi {customer_first_name}") != nil)
    }

    @Test("Empty and over-length templates are refused")
    func length() {
        #expect(SmsTemplateValidator.problem(kind: .quoteSent, body: "   ") != nil)
        #expect(SmsTemplateValidator.problem(kind: .customMessage, body: String(repeating: "a", count: 641)) != nil)
    }

    @Test("Only the right variables are offered per template")
    func offeredVariables() {
        #expect(SmsMessageKind.quoteSent.allowedVariables.contains(.quoteLink))
        #expect(!SmsMessageKind.quoteSent.allowedVariables.contains(.invoiceLink))
        #expect(SmsMessageKind.overdueReminder.allowedVariables.contains(.paymentLink))
        #expect(SmsMessageKind.etaUpdate.allowedVariables.contains(.eta))
        #expect(!SmsMessageKind.jobCompleted.allowedVariables.contains(.eta))
    }

    @Test("Segment estimate fills variables with realistic values")
    func estimate() {
        let estimate = SmsTemplateValidator.estimate(SmsMessageKind.quoteSent.defaultBody)
        #expect(!estimate.contains("{{"))
        #expect(SmsSegmentCounter.count(estimate).segments >= 1)
    }

    @Test("Marketing is never automatic: only operational defaults start on")
    func automationDefaults() {
        let on = SmsMessageKind.allCases.filter { $0.isAutomatable && $0.automationDefault }
        #expect(Set(on) == [.appointmentConfirmation, .appointmentReminder, .appointmentRescheduled,
                            .appointmentCancelled, .engineerOnTheWay, .paymentReceived])
    }
}

struct SmsSetupDraftTests {
    private func complete(_ route: SmsRegistrationRoute) -> SmsBusinessDetailsDraft {
        var d = SmsBusinessDetailsDraft()
        d.route = route
        d.legalName = "Gulf Coast Air LLC"
        d.ein = "12-3456789"
        d.website = "https://gulfcoastair.com"
        d.street = "2200 W Kennedy Blvd"; d.city = "Tampa"; d.state = "FL"; d.postalCode = "33606"
        d.repFirstName = "Tom"; d.repLastName = "Ellison"; d.repEmail = "tom@example.com"; d.repPhone = "(813) 555-0110"
        d.mobilePhone = "(813) 555-0199"
        d.optInDescription = "Customers give their mobile number when booking and agree to texts about their jobs."
        d.acceptedResponsibility = true
        return d
    }

    @Test("A complete registered-business draft is ready")
    func ready() {
        #expect(complete(.lowVolume).problem == nil)
        #expect(complete(.standard).problem == nil)
    }

    @Test("EIN is required for registered businesses but not sole proprietors")
    func einRule() {
        var standard = complete(.standard); standard.ein = ""
        #expect(standard.problem != nil)
        var sole = complete(.soleProprietor); sole.ein = ""; sole.website = ""
        #expect(sole.problem == nil)
    }

    @Test("Sole proprietors need their own mobile for verification")
    func soleMobile() {
        var sole = complete(.soleProprietor); sole.mobilePhone = ""
        #expect(sole.problem != nil)
    }

    @Test("Responsibility confirmation is required")
    func responsibility() {
        var d = complete(.lowVolume); d.acceptedResponsibility = false
        #expect(d.problem != nil)
    }
}

struct CommunicationsStatusTests {
    @Test("Friendly statuses never expose provider wording")
    func friendly() {
        #expect(SmsFriendlyStatus.notSetUp.title == "SMS Not Set Up")
        #expect(SmsFriendlyStatus.settingUp.title == "Setting Up SMS")
        #expect(SmsFriendlyStatus.waitingApproval.title == "Waiting for Approval")
        #expect(SmsFriendlyStatus.ready.title == "SMS Ready")
        #expect(SmsFriendlyStatus.needsAttention.title == "SMS Needs Attention")
        #expect(SmsFriendlyStatus.suspended.title == "SMS Suspended")
        #expect(SmsFriendlyStatus.ready.canSend)
        #expect(!SmsFriendlyStatus.waitingApproval.canSend)
    }

    @Test("Phone numbers display in US format")
    func phoneFormat() {
        #expect(PhoneFormatting.pretty("+18135550101") == "(813) 555-0101")
    }

    @Test("A customer reply push deep-links to its conversation")
    func smsDeepLink() {
        #expect(PushDeepLink.route(fromLink: "tradedesk://sms/abc-123") == .smsConversation("abc-123"))
        #expect(PushDeepLink.link(for: .smsConversation("abc-123")) == "tradedesk://sms/abc-123")
        #expect(PushDeepLink.route(fromLink: "tradedesk://sms") == .more(.communications))
        #expect(PushDeepLink.route(fromLink: "tradedesk://message/t1") == .message("t1"))
    }

    @Test("Communications is for roles that text customers; setup is owner billing")
    func permissions() {
        #expect(MoreSection.communications.requiredPermission == .smsCreditsConsume)
        #expect(MoreSection.smsMessaging.requiredPermission == .saasBillingRead)
        #expect(MoreSection.legal.requiredPermission == nil)
        #expect(!PermissionMatrix.permissions(for: .fieldWorker).contains(.smsCreditsConsume))
        #expect(!PermissionMatrix.permissions(for: .accounts).contains(.smsCreditsConsume))
        #expect(PermissionMatrix.permissions(for: .dispatcher).contains(.smsCreditsConsume))
        #expect(PermissionMatrix.permissions(for: .owner).contains(.saasBillingRead))
        #expect(!PermissionMatrix.permissions(for: .admin).contains(.saasBillingRead))
    }

    @Test("Unread total adds customer and office messages")
    func unreadTotal() {
        let unread = CommunicationsUnread(customerUnread: 2, officeUnread: 3, latestTitle: nil, latestBody: nil,
                                          latestLink: nil, latestAt: nil)
        #expect(unread.total == 5)
        #expect(CommunicationsUnread.none.total == 0)
    }
}

struct LegalDocumentTests {
    @Test("Four in-app legal documents, each with real content")
    func fourDocuments() {
        #expect(LegalDocument.allCases.map(\.title) == ["Privacy Policy", "Terms of Service", "SMS & Messaging Terms", "Account & Data Deletion"])
        for document in LegalDocument.allCases {
            #expect(document.sections.count >= 4, "\(document.title)")
            #expect(document.fullText.count > 1500, "\(document.title)")
        }
    }

    @Test("No document says coming soon or links a Harbour South privacy website")
    func noPlaceholders() {
        for document in LegalDocument.allCases {
            let text = document.fullText.lowercased()
            #expect(!text.contains("coming soon"))
            #expect(!text.contains("harboursouth.com"))
            #expect(!text.contains("http"))
        }
    }

    @Test("The privacy policy covers the required topics")
    func privacyCoverage() {
        let text = LegalDocument.privacyPolicy.fullText.lowercased()
        for topic in ["location", "photos", "invoices", "quotes", "push notification", "twilio", "stripe",
                      "apple", "google play", "sms credits", "inbound", "retention", "anonymis", "delete", "security"] {
            #expect(text.contains(topic), "missing: \(topic)")
        }
    }

    @Test("SMS terms cover credits, segments, STOP/START/HELP and the number fee")
    func smsCoverage() {
        let text = LegalDocument.smsTerms.fullText
        for topic in ["one SMS segment", "STOP", "START", "HELP", "monthly fee", "Twilio", "not guaranteed", "consent"] {
            #expect(text.contains(topic), "missing: \(topic)")
        }
    }

    @Test("Customer responsibility wording is present and not replaced by Harbour South's")
    func customerResponsibility() {
        let sentence = "Your business is responsible for providing accurate business information, maintaining any required website or privacy information, obtaining appropriate customer consent, and complying with applicable messaging requirements."
        #expect(LegalDocument.smsTerms.fullText.contains(sentence))
        #expect(LegalDocument.privacyPolicy.fullText.contains("do not replace your business's own obligations"))
    }

    @Test("Deletion document matches the real deletion behaviour")
    func deletion() {
        let text = LegalDocument.accountDeletion.fullText
        #expect(text.contains("second time"))
        #expect(text.contains("Stripe account"))
        #expect(text.contains("does not cancel an Apple subscription"))
        #expect(text.contains("retained, not deleted"))
    }

    @Test("The contact sentence never invents an address")
    func contact() {
        #expect(LegalDocument.contactSentence.contains("App Store") || LegalDocument.contactSentence.contains("@"))
    }
}
