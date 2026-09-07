import Foundation
import Observation

@Observable
final class PaymentLinkViewModel {
    private(set) var state: LoadState<PaymentLinkSettings> = .idle
    private(set) var isWorking: Bool = false
    var draft: String = ""
    var actionError: String?
    var savedNotice: String?

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            let settings = try await gateway.companyPaymentLink(session: session)
            draft = settings.url ?? ""
            state = .loaded(settings)
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    var isDirty: Bool {
        let current = state.value?.url ?? ""
        return draft.trimmingCharacters(in: .whitespacesAndNewlines) != current
    }

    /// Live feedback while typing, so the rule is visible before saving.
    var draftProblem: String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try OnlinePaymentLink.normalise(trimmed)
            return nil
        } catch let error as OnlinePaymentLink.ValidationError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    func save(gateway: DataGateway, session: TenantSession) async {
        await perform(gateway: gateway, session: session) {
            try await gateway.updateCompanyPaymentLink(session: session, url: self.draft)
        }
        if actionError == nil {
            savedNotice = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Payment link cleared. Customers won't see a pay button."
                : "Payment link saved."
        }
    }

    func clear(gateway: DataGateway, session: TenantSession) async {
        draft = ""
        await perform(gateway: gateway, session: session) {
            try await gateway.updateCompanyPaymentLink(session: session, url: nil)
        }
        if actionError == nil {
            savedNotice = "Payment link cleared. Customers won't see a pay button."
        }
    }

    private func perform(
        gateway: DataGateway,
        session: TenantSession,
        _ work: () async throws -> Void
    ) async {
        isWorking = true
        actionError = nil
        savedNotice = nil
        do {
            try await work()
            await load(gateway: gateway, session: session, showLoading: false)
        } catch let error as OnlinePaymentLink.ValidationError {
            actionError = error.errorDescription
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
