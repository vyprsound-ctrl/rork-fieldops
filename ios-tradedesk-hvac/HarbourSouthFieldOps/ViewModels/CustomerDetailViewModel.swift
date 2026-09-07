import Foundation
import Observation

/// Drives the customer profile screen and every write made from it.
///
/// Sites, contacts and assets are all saved through here rather than from the
/// sheets themselves, so there is exactly one place that reloads the profile
/// afterwards and exactly one error surface.
@Observable
final class CustomerDetailViewModel {
    private(set) var state: LoadState<CustomerProfile> = .idle
    private(set) var isWorking: Bool = false
    var actionError: String?
    /// Set when the customer has been removed, so the screen can pop.
    private(set) var isDeleted: Bool = false

    func load(gateway: DataGateway, session: TenantSession, customerID: String, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.customerProfile(session: session, customerID: customerID))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func saveAddress(
        gateway: DataGateway,
        session: TenantSession,
        customerID: String,
        draft: AddressDraft
    ) async {
        await perform(gateway: gateway, session: session, customerID: customerID) {
            _ = try await gateway.saveCustomerAddress(session: session, customerID: customerID, draft: draft)
        }
    }

    func saveContact(
        gateway: DataGateway,
        session: TenantSession,
        customerID: String,
        draft: ContactDraft
    ) async {
        await perform(gateway: gateway, session: session, customerID: customerID) {
            _ = try await gateway.saveCustomerContact(session: session, customerID: customerID, draft: draft)
        }
    }

    func saveEquipment(
        gateway: DataGateway,
        session: TenantSession,
        customerID: String,
        draft: EquipmentDraft
    ) async {
        await perform(gateway: gateway, session: session, customerID: customerID) {
            _ = try await gateway.saveEquipment(session: session, customerID: customerID, draft: draft)
        }
    }

    func delete(gateway: DataGateway, session: TenantSession, customerID: String) async {
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            try await gateway.deleteCustomer(session: session, customerID: customerID)
            isDeleted = true
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
    }

    private func perform(
        gateway: DataGateway,
        session: TenantSession,
        customerID: String,
        _ work: () async throws -> Void
    ) async {
        isWorking = true
        actionError = nil
        do {
            try await work()
            await load(gateway: gateway, session: session, customerID: customerID, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
