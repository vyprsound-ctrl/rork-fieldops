import Foundation
import Observation

@Observable
final class JobEditorViewModel {
    private(set) var options: JobFormOptions = .empty
    private(set) var isLoadingOptions: Bool = true
    private(set) var isSaving: Bool = false
    var errorMessage: String?
    var createdJobID: String?

    var customerID: String = ""
    var equipmentID: String?
    var title: String = ""
    var jobDescription: String = ""
    var kind: JobKind = .callOut
    var priority: JobPriority = .standard
    var isScheduled: Bool = true
    var scheduledStart: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    var durationMinutes: Int = 90
    var workerUserID: String?

    var selectedCustomer: CustomerOption? {
        options.customers.first { $0.id == customerID }
    }

    var canSave: Bool {
        !customerID.isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCustomer != nil
    }

    func loadOptions(gateway: DataGateway, session: TenantSession) async {
        isLoadingOptions = true
        options = (try? await gateway.jobFormOptions(session: session)) ?? .empty
        if customerID.isEmpty, let first = options.customers.first {
            customerID = first.id
        }
        isLoadingOptions = false
    }

    func save(gateway: DataGateway, session: TenantSession) async {
        guard let customer = selectedCustomer else { return }
        isSaving = true
        errorMessage = nil

        let end = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: scheduledStart)
        let input = NewJobInput(
            customerID: customer.id,
            addressID: customer.addressID,
            equipmentID: equipmentID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            jobDescription: jobDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            priority: priority,
            scheduledStart: isScheduled ? scheduledStart : nil,
            scheduledEnd: isScheduled ? end : nil,
            fieldWorkerUserID: workerUserID,
            quoteID: nil
        )

        do {
            createdJobID = try await gateway.createJob(session: session, input: input)
        } catch {
            errorMessage = DataError.wrap(error).errorDescription
        }
        isSaving = false
    }
}
