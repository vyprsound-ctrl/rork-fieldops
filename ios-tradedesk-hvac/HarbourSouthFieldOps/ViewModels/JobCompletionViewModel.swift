import Foundation
import Observation

/// Drives the completion sheet.
///
/// The draft lives here rather than in the view so a mis-tap outside the sheet
/// cannot lose an engineer's notes, and so the submit path is one function with
/// one error surface.
@Observable
final class JobCompletionViewModel {
    var draft = JobCompletionDraft()
    private(set) var isSubmitting: Bool = false
    private(set) var outcome: JobCompletionOutcome?
    var errorMessage: String?

    var canSubmit: Bool { draft.validationMessage == nil && !isSubmitting }

    func addPartLine() {
        draft.parts.append(JobPartLine())
    }

    func removePart(_ id: UUID) {
        draft.parts.removeAll { $0.id == id }
    }

    /// Submits the completion, capturing a position first if the workflow calls
    /// for one at this step.
    ///
    /// The position never gates the completion: a refused permission or a
    /// device that cannot get a fix leaves the job completed and the location
    /// simply absent, exactly as every other field transition behaves.
    func submit(
        gateway: DataGateway,
        location: LocationService,
        session: TenantSession,
        jobID: String,
        destination: Coordinate?
    ) async -> Bool {
        if let problem = draft.validationMessage {
            errorMessage = problem
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        var fix: LocationFix?
        if let event = LocationCaptureEvent.forTransition(to: .completed) {
            var state = await location.authorizationState
            if state == .notDetermined { state = await location.requestAuthorization() }
            if state.canCapture {
                fix = await location.captureFix(for: event, near: destination)
            }
        }

        do {
            let result = try await gateway.completeJob(
                session: session,
                jobID: jobID,
                draft: draft,
                locationFix: fix
            )
            outcome = result
            return result.completed
        } catch {
            errorMessage = DataError.wrap(error).errorDescription
            return false
        }
    }
}
