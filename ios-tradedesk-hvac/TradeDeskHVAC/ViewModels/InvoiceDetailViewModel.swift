import Foundation
import Observation

@Observable
final class InvoiceDetailViewModel {
    private(set) var state: LoadState<InvoiceDetailProjection> = .idle
    private(set) var isWorking: Bool = false
    var actionError: String?

    /// Customer-facing delivery. Loaded alongside the invoice but kept separate,
    /// so a role that can read an invoice but not its delivery history simply
    /// gets nothing here rather than an error on the whole screen.
    private(set) var sharing: InvoiceSharing?
    private(set) var isSending: Bool = false
    /// The outcome of the last send, reported exactly as the server described it.
    var lastSendOutcome: InvoiceSendOutcome?

    func load(gateway: DataGateway, session: TenantSession, invoiceID: String, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.invoiceDetail(session: session, invoiceID: invoiceID))
        } catch {
            state = .failed(DataError.wrap(error))
        }
        await loadSharing(gateway: gateway, session: session, invoiceID: invoiceID)
    }

    func loadSharing(gateway: DataGateway, session: TenantSession, invoiceID: String) async {
        guard session.can(.invoicesRead) else { return }
        do {
            sharing = try await gateway.invoiceSharing(session: session, invoiceID: invoiceID)
        } catch {
            // Never fails the invoice screen: the document still loads.
            sharing = nil
        }
    }

    func issueShareLink(gateway: DataGateway, session: TenantSession, invoiceID: String, rotate: Bool) async {
        await perform(gateway: gateway, session: session, invoiceID: invoiceID) {
            _ = try await gateway.issueInvoiceShareLink(session: session, invoiceID: invoiceID, rotate: rotate)
        }
    }

    func revokeShareLink(gateway: DataGateway, session: TenantSession, invoiceID: String) async {
        await perform(gateway: gateway, session: session, invoiceID: invoiceID) {
            try await gateway.revokeInvoiceShareLink(session: session, invoiceID: invoiceID)
        }
    }

    func send(
        gateway: DataGateway,
        session: TenantSession,
        invoiceID: String,
        channels: Set<NotificationChannel>
    ) async {
        isSending = true
        actionError = nil
        lastSendOutcome = nil
        do {
            lastSendOutcome = try await gateway.sendInvoice(
                session: session,
                invoiceID: invoiceID,
                channels: channels
            )
            await loadSharing(gateway: gateway, session: session, invoiceID: invoiceID)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isSending = false
    }

    func updateStatus(gateway: DataGateway, session: TenantSession, invoiceID: String, to status: InvoiceStatus) async {
        await perform(gateway: gateway, session: session, invoiceID: invoiceID) {
            try await gateway.updateInvoiceStatus(session: session, invoiceID: invoiceID, to: status)
        }
    }

    func saveLine(gateway: DataGateway, session: TenantSession, invoiceID: String, draft: InvoiceLineItemDraft) async {
        await perform(gateway: gateway, session: session, invoiceID: invoiceID) {
            try await gateway.saveInvoiceLineItem(session: session, invoiceID: invoiceID, draft: draft)
        }
    }

    func deleteLine(gateway: DataGateway, session: TenantSession, invoiceID: String, lineItemID: String) async {
        await perform(gateway: gateway, session: session, invoiceID: invoiceID) {
            try await gateway.deleteInvoiceLineItem(session: session, invoiceID: invoiceID, lineItemID: lineItemID)
        }
    }

    func recordPayment(gateway: DataGateway, session: TenantSession, invoiceID: String, draft: PaymentDraft) async {
        await perform(gateway: gateway, session: session, invoiceID: invoiceID) {
            try await gateway.recordPayment(session: session, invoiceID: invoiceID, draft: draft)
        }
    }

    private func perform(
        gateway: DataGateway,
        session: TenantSession,
        invoiceID: String,
        _ work: () async throws -> Void
    ) async {
        isWorking = true
        actionError = nil
        do {
            try await work()
            await load(gateway: gateway, session: session, invoiceID: invoiceID, showLoading: false)
        } catch let error as OnlinePaymentLink.ValidationError {
            actionError = error.errorDescription
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
