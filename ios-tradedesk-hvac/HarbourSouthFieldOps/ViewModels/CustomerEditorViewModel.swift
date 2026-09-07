import Foundation
import Observation

/// Drives the customer form for both creating and editing.
///
/// One view model for both because the difference is a single fact — whether an
/// id exists — and duplicating the form to express it would guarantee the two
/// copies drift.
@Observable
final class CustomerEditorViewModel {
    /// Nil while creating.
    let customerID: String?
    var draft: CustomerDraft

    private(set) var isSaving: Bool = false
    private(set) var savedCustomerID: String?
    var errorMessage: String?

    var isEditing: Bool { customerID != nil }

    var validationMessage: String? {
        draft.validationMessage(requiresAddress: !isEditing)
    }

    var canSave: Bool { validationMessage == nil && !isSaving }

    init(customerID: String? = nil, draft: CustomerDraft = CustomerDraft()) {
        self.customerID = customerID
        self.draft = draft
    }

    @discardableResult
    func save(gateway: DataGateway, session: TenantSession) async -> Bool {
        if let problem = validationMessage {
            errorMessage = problem
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let customerID {
                try await gateway.updateCustomer(session: session, customerID: customerID, draft: draft)
                savedCustomerID = customerID
            } else {
                savedCustomerID = try await gateway.createCustomer(session: session, draft: draft)
            }
            return true
        } catch {
            errorMessage = DataError.wrap(error).errorDescription
            return false
        }
    }
}
