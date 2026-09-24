import Foundation
import Supabase

/// Payload for a row this app inserts directly, where a single table and the
/// RLS policy on it express the whole rule.
private nonisolated struct JobNotePayload: Encodable, Sendable {
    let id: String
    let company_id: String
    let job_id: String
    let user_id: String
    let body: String
    let visibility: String
    let created_at: String
}

private nonisolated struct JobPhotoPayload: Encodable, Sendable {
    let id: String
    let company_id: String
    let job_id: String
    let user_id: String
    let storage_reference: String
    let caption: String?
    let kind: String
    let captured_at: String
}

private nonisolated struct LocationPayload: Encodable, Sendable {
    let id: String
    let company_id: String
    let user_id: String
    let latitude: Double
    let longitude: Double
    let accuracy_meters: Double
    let heading: Double?
    let speed_meters_per_second: Double?
    let job_id: String?
    let recorded_at: String
    let capture_event: String
    let is_simulated: Bool
}

/// Writes against Supabase.
///
/// Two shapes of write appear here, and the difference is deliberate.
///
/// A single-table write that one RLS policy fully describes — a job note, a job
/// photo, a location fix — is an ordinary insert. The policy on the table is the
/// rule, and the app does not restate it.
///
/// Anything that spans rows or carries a workflow rule goes through a database
/// function instead: creating a job also issues its number and writes its
/// history, recording a payment also re-derives the invoice's balance and
/// status, converting a quote also writes the job it produced. Those are single
/// statements in one transaction, so a half-finished write is not expressible —
/// and the rules that decide them (the workflow table, the numbering sequence,
/// the overpayment refusal) live next to the data rather than in this file.
///
/// Every one of those functions runs as the caller, so Row Level Security still
/// applies inside them. The one exception is documented on `apply_job_status`.
extension SupabaseDataGateway {

    // MARK: - Jobs

    func createJob(session: TenantSession, input: NewJobInput) async throws -> String {
        try require(.jobsManage, session, query: "jobs.create")

        let id = try await performReturningID(
            "create_job",
            [
                "p_customer_id": .string(input.customerID),
                "p_address_id": .string(input.addressID),
                "p_title": .string(input.title),
                "p_job_description": .string(input.jobDescription),
                "p_kind": .string(input.kind.rawValue),
                "p_priority": .string(input.priority.rawValue),
                "p_scheduled_start": SupabaseCoding.json(timestamp: input.scheduledStart),
                "p_scheduled_end": SupabaseCoding.json(timestamp: input.scheduledEnd),
                "p_equipment_id": SupabaseCoding.json(id: input.equipmentID),
                "p_quote_id": SupabaseCoding.json(id: input.quoteID),
                "p_field_worker_user_id": SupabaseCoding.json(id: input.fieldWorkerUserID)
            ]
        )

        record(
            "jobs.create",
            session,
            allowed: true,
            "Job created in one transaction — number issued, status history written\(input.fieldWorkerUserID == nil ? "" : ", worker assigned")"
        )
        return id
    }

    func updateJobStatus(
        session: TenantSession,
        jobID: String,
        to status: JobStatus,
        locationFix: LocationFix?
    ) async throws {
        try requireWritableWorkspace(session, query: "jobs.updateStatus")
        try await perform(
            "update_job_status",
            [
                "p_job": .string(jobID),
                "p_to": .string(status.rawValue),
                "p_latitude": locationFix.map { AnyJSON.double($0.coordinate.latitude) } ?? .null,
                "p_longitude": locationFix.map { AnyJSON.double($0.coordinate.longitude) } ?? .null
            ]
        )

        record(
            "jobs.updateStatus",
            session,
            allowed: true,
            "Moved to \(status.title(session.terms)); history row written by the database\(locationFix == nil ? "" : " with a captured position")"
        )
    }

    /// Assignment from a job's own screen.
    ///
    /// Routed through the dispatch path so there is exactly one conflict rule in
    /// the app: the check runs once, an unacknowledged overlap is refused and
    /// returned as a clash, and the acknowledgement travels honestly to the
    /// database — which re-applies the rule itself regardless of what we send.
    func assignFieldWorker(
        session: TenantSession,
        jobID: String,
        workerUserID: String?,
        acknowledgesConflict: Bool
    ) async throws {
        _ = try await assignJob(
            session: session,
            jobID: jobID,
            input: AssignmentInput(workerUserID: workerUserID, acknowledgesConflict: acknowledgesConflict)
        )
    }

    func addJobNote(session: TenantSession, jobID: String, body: String, visibility: NoteVisibility) async throws {
        try require(.jobNotesCreate, session, query: "jobs.addNote")
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DataError.rejected("Write something before saving the note.") }

        try await performWrite(
            client.from("job_notes").insert(
                JobNotePayload(
                    id: UUID().uuidString,
                    company_id: session.companyID,
                    job_id: jobID,
                    user_id: session.userID,
                    body: trimmed,
                    visibility: visibility.rawValue,
                    created_at: SupabaseCoding.timestamp(Date())
                )
            )
        )
        record("jobs.addNote", session, allowed: true, "Note written; the policy required it to be authored by the caller")
    }

    func addJobPhoto(session: TenantSession, jobID: String, kind: JobPhotoKind, caption: String?) async throws {
        try require(.jobPhotosCreate, session, query: "jobs.addPhoto")

        // DEVELOPMENT: no camera or upload is involved. The row is real, the
        // file reference is explicitly simulated.
        let reference = "sim://jobs/\(jobID)/\(kind.rawValue)-\(Int(Date().timeIntervalSince1970)).jpg"
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)

        try await performWrite(
            client.from("job_photos").insert(
                JobPhotoPayload(
                    id: UUID().uuidString,
                    company_id: session.companyID,
                    job_id: jobID,
                    user_id: session.userID,
                    storage_reference: reference,
                    caption: (trimmed?.isEmpty ?? true) ? nil : trimmed,
                    kind: kind.rawValue,
                    captured_at: SupabaseCoding.timestamp(Date())
                )
            )
        )
        record("jobs.addPhoto", session, allowed: true, "Simulated \(kind.title.lowercased()) photo recorded — no file was uploaded")
    }

    // MARK: - Dispatch

    func assignJob(session: TenantSession, jobID: String, input: AssignmentInput) async throws -> SchedulingCheck {
        try require(.assignmentsManage, session, query: "dispatch.assign")

        var check = SchedulingCheck.clear
        if input.workerUserID != nil {
            check = try await checkAssignment(session: session, jobID: jobID, workerUserID: input.workerUserID)

            // An overlap is allowed, but only deliberately. The first attempt is
            // refused and returns the clash; a second attempt carrying the
            // acknowledgement goes through. The database applies the same rule
            // independently, so nobody is double-booked silently.
            if check.hasConflicts, !input.acknowledgesConflict {
                record("dispatch.assign", session, allowed: false, "Refused pending acknowledgement — \(check.summary)")
                throw DataError.rejected(check.summary)
            }
        }

        try await perform(
            "assign_job",
            [
                "p_job": .string(jobID),
                "p_worker": SupabaseCoding.json(id: input.workerUserID),
                "p_acknowledges_conflict": .bool(input.acknowledgesConflict)
            ]
        )

        record(
            "dispatch.assign",
            session,
            allowed: true,
            check.hasConflicts ? "Assigned with an acknowledged overlap — \(check.summary)" : "Assigned cleanly"
        )
        return check
    }

    func rescheduleJob(session: TenantSession, jobID: String, input: RescheduleInput) async throws -> SchedulingCheck {
        try require(.jobsManage, session, query: "dispatch.reschedule")

        if let start = input.scheduledStart, let end = input.scheduledEnd, end < start {
            throw DataError.rejected("A job can't finish before it starts.")
        }

        let check = try await checkReschedule(session: session, jobID: jobID, input: input)
        if check.hasConflicts, !input.acknowledgesConflict {
            record("dispatch.reschedule", session, allowed: false, "Refused pending acknowledgement — \(check.summary)")
            throw DataError.rejected(check.summary)
        }

        try await perform(
            "reschedule_job",
            [
                "p_job": .string(jobID),
                "p_start": SupabaseCoding.json(timestamp: input.scheduledStart),
                "p_end": SupabaseCoding.json(timestamp: input.scheduledEnd),
                "p_acknowledges_conflict": .bool(input.acknowledgesConflict)
            ]
        )

        let to = input.scheduledStart.map { Formatters.dayAndTime($0) } ?? "unscheduled"
        record(
            "dispatch.reschedule",
            session,
            allowed: true,
            "Moved to \(to)\(check.hasConflicts ? " with an acknowledged overlap" : "")"
        )
        return check
    }

    // MARK: - Location

    func recordLocationFix(
        session: TenantSession,
        jobID: String?,
        event: LocationCaptureEvent,
        fix: LocationFix
    ) async throws {
        try requireWritableWorkspace(session, query: "location.record")
        // The policy on this table requires the row to be the caller's own, so
        // the company and user are taken from the session and can't be spoofed.
        try await performWrite(
            client.from("field_worker_locations").insert(
                LocationPayload(
                    id: UUID().uuidString,
                    company_id: session.companyID,
                    user_id: session.userID,
                    latitude: fix.coordinate.latitude,
                    longitude: fix.coordinate.longitude,
                    accuracy_meters: fix.accuracyMeters,
                    heading: fix.heading,
                    speed_meters_per_second: fix.speedMetersPerSecond,
                    job_id: jobID,
                    recorded_at: SupabaseCoding.timestamp(fix.capturedAt),
                    capture_event: event.rawValue,
                    is_simulated: fix.simulated
                )
            )
        )
        record(
            "location.capture",
            session,
            allowed: true,
            "\(event.title) fix stored\(fix.simulated ? " (SIMULATED)" : "")"
        )
    }

    // MARK: - Quotes

    func createQuote(session: TenantSession, input: NewQuoteInput) async throws -> String {
        try require(.quotesManage, session, query: "quotes.create")

        let id = try await performReturningID(
            "create_quote",
            [
                "p_customer_id": .string(input.customerID),
                "p_address_id": .string(input.addressID),
                "p_title": .string(input.title),
                "p_scope_of_work": .string(input.scopeOfWork),
                "p_valid_until": SupabaseCoding.json(day: input.validUntil)
            ]
        )
        record("quotes.create", session, allowed: true, "Quote created as a draft with a company-scoped number")
        return id
    }

    func updateQuoteStatus(session: TenantSession, quoteID: String, to status: QuoteStatus) async throws {
        try require(.quotesManage, session, query: "quotes.updateStatus")
        try await perform("update_quote_status", ["p_quote": .string(quoteID), "p_to": .string(status.rawValue)])
        record("quotes.updateStatus", session, allowed: true, "Moved to \(status.title), timestamped by the database")
    }

    func saveQuoteLineItem(session: TenantSession, quoteID: String, draft: QuoteLineItemDraft) async throws {
        try require(.quotesManage, session, query: "quotes.saveLineItem")
        try require(.quoteFinancialsRead, session, query: "quotes.saveLineItem")

        try await perform(
            "save_quote_line_item",
            [
                "p_quote": .string(quoteID),
                "p_line": SupabaseCoding.json(id: draft.id),
                "p_description": .string(draft.itemDescription),
                "p_quantity": .string("\(draft.quantity)"),
                "p_unit_price": .string("\(draft.unitPrice)"),
                "p_tax_rate": .string("\(draft.taxRate)")
            ]
        )
        record(
            "quotes.saveLineItem",
            session,
            allowed: true,
            "\(draft.id == nil ? "Line added" : "Line updated"); totals recalculated from the lines in the same transaction"
        )
    }

    func deleteQuoteLineItem(session: TenantSession, quoteID: String, lineItemID: String) async throws {
        try require(.quotesManage, session, query: "quotes.deleteLineItem")
        try await perform("delete_quote_line_item", ["p_quote": .string(quoteID), "p_line": .string(lineItemID)])
        record("quotes.deleteLineItem", session, allowed: true, "Line removed, sort order closed up, totals recalculated")
    }

    func reorderQuoteLineItems(session: TenantSession, quoteID: String, orderedIDs: [String]) async throws {
        try require(.quotesManage, session, query: "quotes.reorderLineItems")
        try await perform(
            "reorder_quote_line_items",
            ["p_quote": .string(quoteID), "p_ids": .array(orderedIDs.map { AnyJSON.string($0) })]
        )
        record("quotes.reorderLineItems", session, allowed: true, "\(orderedIDs.count) lines reordered")
    }

    func convertQuoteToJob(session: TenantSession, quoteID: String, input: QuoteConversionInput) async throws -> String {
        try require(.quotesManage, session, query: "quotes.convert")
        try require(.jobsManage, session, query: "quotes.convert")

        let id = try await performReturningID(
            "convert_quote_to_job",
            [
                "p_quote": .string(quoteID),
                "p_kind": .string(input.kind.rawValue),
                "p_priority": .string(input.priority.rawValue),
                "p_scheduled_start": SupabaseCoding.json(timestamp: input.scheduledStart),
                "p_scheduled_end": SupabaseCoding.json(timestamp: input.scheduledEnd),
                "p_field_worker_user_id": SupabaseCoding.json(id: input.fieldWorkerUserID)
            ]
        )
        record(
            "quotes.convert",
            session,
            allowed: true,
            "Job raised from the quote; the quote keeps its status, dates, lines and totals and gains only the back-reference"
        )
        return id
    }

    // MARK: - Invoices

    func createInvoice(session: TenantSession, input: NewInvoiceInput) async throws -> String {
        try require(.invoicesManage, session, query: "invoices.create")

        let id = try await performReturningID(
            "create_invoice",
            [
                "p_customer_id": .string(input.customerID),
                "p_address_id": SupabaseCoding.json(id: input.addressID),
                "p_title": .string(input.title),
                "p_scope_of_work": .string(input.scopeOfWork),
                "p_payment_terms_label": input.paymentTermsLabel.map { AnyJSON.string($0) } ?? .null,
                "p_issue_date": SupabaseCoding.json(day: input.issueDate),
                "p_due_date": SupabaseCoding.json(day: input.dueDate)
            ]
        )
        record(
            "invoices.create",
            session,
            allowed: true,
            "Draft invoice raised; currency and payment terms snapshotted onto the document"
        )
        return id
    }

    func createInvoiceFromJob(session: TenantSession, jobID: String, input: InvoiceConversionInput) async throws -> String {
        try require(.invoicesManage, session, query: "invoices.createFromJob")

        let id = try await performReturningID(
            "create_invoice_from_job",
            [
                "p_job": .string(jobID),
                "p_payment_terms_label": input.paymentTermsLabel.map { AnyJSON.string($0) } ?? .null,
                "p_issue_date": SupabaseCoding.json(day: input.issueDate),
                "p_due_date": SupabaseCoding.json(day: input.dueDate),
                "p_copy_line_items": .bool(input.copyLineItems),
                "p_advance_job_status": .bool(input.advanceJobStatus)
            ]
        )
        record(
            "invoices.createFromJob",
            session,
            allowed: true,
            "Invoice raised from the job\(input.copyLineItems ? ", quote lines snapshotted by value" : "")\(input.advanceJobStatus ? "; job advanced as a recorded transition" : "")"
        )
        return id
    }

    func createInvoiceFromQuote(session: TenantSession, quoteID: String, input: InvoiceConversionInput) async throws -> String {
        try require(.invoicesManage, session, query: "invoices.createFromQuote")

        let id = try await performReturningID(
            "create_invoice_from_quote",
            [
                "p_quote": .string(quoteID),
                "p_payment_terms_label": input.paymentTermsLabel.map { AnyJSON.string($0) } ?? .null,
                "p_issue_date": SupabaseCoding.json(day: input.issueDate),
                "p_due_date": SupabaseCoding.json(day: input.dueDate),
                "p_copy_line_items": .bool(input.copyLineItems),
                "p_advance_job_status": .bool(input.advanceJobStatus)
            ]
        )
        record(
            "invoices.createFromQuote",
            session,
            allowed: true,
            "Invoice raised from the quote; the quote itself is left exactly as the customer accepted it"
        )
        return id
    }

    func saveInvoiceLineItem(session: TenantSession, invoiceID: String, draft: InvoiceLineItemDraft) async throws {
        try require(.invoicesManage, session, query: "invoices.saveLineItem")

        try await perform(
            "save_invoice_line_item",
            [
                "p_invoice": .string(invoiceID),
                "p_line": SupabaseCoding.json(id: draft.id),
                "p_description": .string(draft.itemDescription),
                "p_quantity": .string("\(draft.quantity)"),
                "p_unit_price": .string("\(draft.unitPrice)"),
                "p_tax_rate": .string("\(draft.taxRate)")
            ]
        )
        record(
            "invoices.saveLineItem",
            session,
            allowed: true,
            "\(draft.id == nil ? "Line added" : "Line updated"); totals, balance and status re-derived by the database"
        )
    }

    func deleteInvoiceLineItem(session: TenantSession, invoiceID: String, lineItemID: String) async throws {
        try require(.invoicesManage, session, query: "invoices.deleteLineItem")
        try await perform("delete_invoice_line_item", ["p_invoice": .string(invoiceID), "p_line": .string(lineItemID)])
        record("invoices.deleteLineItem", session, allowed: true, "Line removed, sort order closed up, totals re-derived")
    }

    func updateInvoiceStatus(session: TenantSession, invoiceID: String, to status: InvoiceStatus) async throws {
        try require(.invoicesManage, session, query: "invoices.updateStatus")
        try await perform("update_invoice_status", ["p_invoice": .string(invoiceID), "p_to": .string(status.rawValue)])
        record("invoices.updateStatus", session, allowed: true, "Moved to \(status.title), timestamped by the database")
    }

    // MARK: - Payments

    func recordPayment(session: TenantSession, invoiceID: String, draft: PaymentDraft) async throws {
        try require(.paymentsManage, session, query: "payments.record")

        // DEVELOPMENT: nothing is charged and no processor is contacted. The row
        // is real; the settlement is marked simulated on the record itself.
        try await perform(
            "record_payment",
            [
                "p_invoice": .string(invoiceID),
                "p_amount": .string("\(Money.rounded(draft.amount))"),
                "p_method": .string(draft.method.rawValue),
                "p_received_at": SupabaseCoding.json(timestamp: draft.receivedAt),
                "p_reference": draft.reference.map { AnyJSON.string($0) } ?? .null,
                "p_note": draft.note.map { AnyJSON.string($0) } ?? .null
            ]
        )
        record(
            "payments.record",
            session,
            allowed: true,
            "\(draft.method.title) payment recorded (SIMULATED); balance and status re-derived from the invoice's own payments"
        )
    }
}
