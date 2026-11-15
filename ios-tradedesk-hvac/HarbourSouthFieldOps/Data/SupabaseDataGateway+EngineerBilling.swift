import Foundation
import Supabase

private nonisolated struct FinancialPermissionRecord: Decodable, Sendable {
    let userID: UUID
    let canInvoice: Bool
    let canCollectPayments: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case canInvoice = "can_invoice"
        case canCollectPayments = "can_collect_payments"
    }
}

/// The engineer's email request. Same function as the office's send, but the
/// function routes it through the engineer's grant-checked database path:
/// email only, to the address the engineer confirmed.
private nonisolated struct EngineerSendInvoiceRequest: Encodable, Sendable {
    let invoiceId: String
    let channels: [String]
    let email: String
}

/// Per-engineer invoicing and payment collection.
///
/// Nothing here is the boundary. Every call lands on a `security definer`
/// function that re-checks the engineer's live grant, their active status and
/// their assignment to the job, so switching a grant off in the office stops
/// the very next request — whatever this device still has on screen.
extension SupabaseDataGateway {

    // MARK: - Grants (office side)

    /// Grants for everyone in the company. RLS returns rows only to a viewer
    /// with `usersManage` (or each person their own row).
    func financialPermissionsByUser() async throws -> [String: FinancialPermissions] {
        let rows = try await fetch(
            FinancialPermissionRecord.self,
            client.from("member_financial_permissions").select("user_id,can_invoice,can_collect_payments")
        )
        var map: [String: FinancialPermissions] = [:]
        for row in rows {
            map[row.userID.uuidString.lowercased()] = FinancialPermissions(
                canInvoice: row.canInvoice,
                canCollectPayments: row.canCollectPayments
            )
        }
        return map
    }

    func setFinancialPermissions(
        session: TenantSession,
        userID: String,
        permissions: FinancialPermissions
    ) async throws {
        try require(.usersManage, session, query: "team.financialPermissions")
        guard userID.lowercased() != session.userID.lowercased() else {
            throw DataError.rejected("You can't change your own invoicing or payment permissions.")
        }
        try await perform(
            "set_member_financial_permissions",
            [
                "p_user": .string(userID),
                "p_can_invoice": .bool(permissions.canInvoice),
                "p_can_collect": .bool(permissions.canCollectPayments)
            ]
        )
        record(
            "team.financialPermissions",
            session,
            allowed: true,
            "Invoicing \(permissions.canInvoice ? "on" : "off"), payment collection \(permissions.canCollectPayments ? "on" : "off") — enforced by the database on the engineer's next request"
        )
    }

    // MARK: - Engineer side

    func engineerJobBilling(session: TenantSession, jobID: String) async throws -> EngineerJobBilling {
        guard session.role == .fieldWorker else { return .hidden }
        return try await performDecoding(
            EngineerJobBilling.self,
            "engineer_job_invoice",
            ["p_job": .string(jobID)]
        )
    }

    func engineerCreateInvoice(session: TenantSession, jobID: String) async throws -> String {
        try requireWritableWorkspace(session, query: "engineer.invoice.create")
        let id = try await performReturningID("engineer_create_invoice_from_job", ["p_job": .string(jobID)])
        record("engineer.invoice.create", session, allowed: true, "Draft invoice raised from the engineer's own completed job")
        return id
    }

    func engineerSaveInvoiceLine(
        session: TenantSession,
        invoiceID: String,
        lineID: String?,
        description: String,
        quantity: Decimal,
        unitPrice: Decimal
    ) async throws {
        try requireWritableWorkspace(session, query: "engineer.invoice.line")
        guard !description.tidied.isEmpty else { throw DataError.rejected("Describe the work or part.") }
        guard quantity > 0 else { throw DataError.rejected("Quantity must be more than zero.") }
        guard unitPrice >= 0 else { throw DataError.rejected("Price can't be negative.") }

        try await perform(
            "engineer_save_invoice_line",
            [
                "p_invoice": .string(invoiceID),
                "p_line": lineID.map { AnyJSON.string($0) } ?? .null,
                "p_description": .string(description.tidied),
                "p_quantity": .double(NSDecimalNumber(decimal: quantity).doubleValue),
                "p_unit_price": .double(NSDecimalNumber(decimal: unitPrice).doubleValue)
            ]
        )
        record("engineer.invoice.line", session, allowed: true, lineID == nil ? "Line added to a draft invoice" : "Draft invoice line updated")
    }

    func engineerDeleteInvoiceLine(session: TenantSession, invoiceID: String, lineID: String) async throws {
        try requireWritableWorkspace(session, query: "engineer.invoice.deleteLine")
        try await perform(
            "engineer_delete_invoice_line",
            ["p_invoice": .string(invoiceID), "p_line": .string(lineID)]
        )
        record("engineer.invoice.deleteLine", session, allowed: true, "Line removed from a draft invoice")
    }

    func engineerIssueInvoice(session: TenantSession, invoiceID: String) async throws {
        try requireWritableWorkspace(session, query: "engineer.invoice.issue")
        try await perform("engineer_issue_invoice", ["p_invoice": .string(invoiceID)])
        record("engineer.invoice.issue", session, allowed: true, "Draft invoice issued by the assigned engineer")
    }

    func engineerEmailInvoice(
        session: TenantSession,
        invoiceID: String,
        recipient: String
    ) async throws -> InvoiceSendOutcome {
        let address = recipient.tidied
        guard address.contains("@"), !address.contains(" ") else {
            throw DataError.rejected("Enter a valid email address for the customer.")
        }

        do {
            let response: SendInvoiceResponse = try await client.functions.invoke(
                "send-invoice",
                options: .init(
                    body: EngineerSendInvoiceRequest(invoiceId: invoiceID, channels: ["email"], email: address)
                )
            )
            let results = response.results.map { result in
                InvoiceSendResult(
                    channel: NotificationChannel(rawValue: result.channel) ?? .email,
                    recipient: result.recipient,
                    delivered: result.status == "sent",
                    providerConfigured: result.configured,
                    detail: result.detail
                )
            }
            record("engineer.invoice.email", session, allowed: true, "Invoice emailed by the engineer — recorded in the notifications ledger")
            return InvoiceSendOutcome(results: results)
        } catch let error as FunctionsError {
            guard case .httpError(let code, let data) = error else {
                throw DataError.unexpected("Couldn't reach the server to send this invoice. Try again in a moment.")
            }
            let decoded = try? JSONDecoder().decode(EdgeFunctionError.self, from: data)
            switch code {
            case 401: throw DataError.unexpected("Your session has expired. Sign in again.")
            case 403: throw DataError.rejected("Your invoicing permission is turned off. Ask your office to turn it on.")
            case 404: throw DataError.notFound
            case 422: throw DataError.rejected(decoded?.message ?? "That invoice can't be sent as it stands.")
            default: throw DataError.unexpected("The server couldn't send this invoice. Try again in a moment.")
            }
        } catch let error as DataError {
            throw error
        } catch {
            print("[data] engineer send-invoice failed: \(error)")
            throw DataError.unexpected("Couldn't reach the server to send this invoice. Try again in a moment.")
        }
    }

    func engineerPaymentLink(session: TenantSession, invoiceID: String) async throws -> String {
        let token = try await performReturningID("engineer_invoice_payment_link", ["p_invoice": .string(invoiceID)])
        guard let url = BackendConfiguration.invoiceViewURL(token: token) else {
            throw DataError.unexpected("The payment link was created but this build has no address to build it from.")
        }
        record("engineer.invoice.paymentLink", session, allowed: true, "Customer payment link handed out by the engineer — payment runs through the existing Stripe page")
        return url
    }
}
