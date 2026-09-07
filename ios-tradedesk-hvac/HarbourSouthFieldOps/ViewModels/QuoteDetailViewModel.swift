import Foundation
import Observation

@Observable
final class QuoteDetailViewModel {
    private(set) var state: LoadState<QuoteDetailProjection> = .idle
    private(set) var isWorking: Bool = false
    private(set) var options: JobFormOptions = .empty
    var actionError: String?
    var convertedJobID: String?

    func load(gateway: DataGateway, session: TenantSession, quoteID: String, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.quoteDetail(session: session, quoteID: quoteID))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func loadOptions(gateway: DataGateway, session: TenantSession) async {
        options = (try? await gateway.jobFormOptions(session: session)) ?? .empty
    }

    func updateStatus(gateway: DataGateway, session: TenantSession, quoteID: String, to status: QuoteStatus) async {
        await perform(gateway: gateway, session: session, quoteID: quoteID) {
            try await gateway.updateQuoteStatus(session: session, quoteID: quoteID, to: status)
        }
    }

    func saveLine(gateway: DataGateway, session: TenantSession, quoteID: String, draft: QuoteLineItemDraft) async {
        await perform(gateway: gateway, session: session, quoteID: quoteID) {
            try await gateway.saveQuoteLineItem(session: session, quoteID: quoteID, draft: draft)
        }
    }

    func deleteLine(gateway: DataGateway, session: TenantSession, quoteID: String, lineItemID: String) async {
        await perform(gateway: gateway, session: session, quoteID: quoteID) {
            try await gateway.deleteQuoteLineItem(session: session, quoteID: quoteID, lineItemID: lineItemID)
        }
    }

    func reorder(gateway: DataGateway, session: TenantSession, quoteID: String, orderedIDs: [String]) async {
        await perform(gateway: gateway, session: session, quoteID: quoteID) {
            try await gateway.reorderQuoteLineItems(session: session, quoteID: quoteID, orderedIDs: orderedIDs)
        }
    }

    func convert(gateway: DataGateway, session: TenantSession, quoteID: String, input: QuoteConversionInput) async {
        isWorking = true
        actionError = nil
        do {
            convertedJobID = try await gateway.convertQuoteToJob(session: session, quoteID: quoteID, input: input)
            await load(gateway: gateway, session: session, quoteID: quoteID, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }

    private func perform(
        gateway: DataGateway,
        session: TenantSession,
        quoteID: String,
        _ work: () async throws -> Void
    ) async {
        isWorking = true
        actionError = nil
        do {
            try await work()
            await load(gateway: gateway, session: session, quoteID: quoteID, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
