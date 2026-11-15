import Foundation
import Supabase

nonisolated struct VehicleRecord: Decodable, Sendable {
    let id: UUID
    let customerID: UUID
    let registration: String
    let vin: String
    let make: String
    let model: String

    enum CodingKeys: String, CodingKey {
        case id, registration, vin, make, model
        case customerID = "customer_id"
    }

    static let columns = "id,customer_id,registration,vin,make,model"

    var vehicle: Vehicle {
        Vehicle(
            id: id.uuidString,
            customerID: customerID.uuidString,
            registration: registration,
            vin: vin,
            make: make,
            model: model
        )
    }
}

private nonisolated struct VehicleInsertPayload: Encodable, Sendable {
    let company_id: String
    let customer_id: String
    let registration: String
    let vin: String
    let make: String
    let model: String
    let created_by_user_id: String
}

private nonisolated struct VehicleUpdatePayload: Encodable, Sendable {
    let registration: String
    let vin: String
    let make: String
    let model: String
}

private nonisolated struct JobVehicleLinkRecord: Decodable, Sendable {
    let vehicleID: UUID?
    enum CodingKeys: String, CodingKey { case vehicleID = "vehicle_id" }
}

private nonisolated struct VehicleJobRecord: Decodable, Sendable {
    let id: UUID
    let number: String
    let title: String
    let status: JobStatus
    let scheduledStart: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, number, title, status
        case scheduledStart = "scheduled_start"
        case createdAt = "created_at"
    }
}

/// Customer vehicles for Automotive companies.
///
/// The table exists for every company — a business-type change never deletes
/// a vehicle — and the screens only offer it when the company is Automotive.
/// There is no delete path at all: the database grants none.
extension SupabaseDataGateway {

    func vehicles(session: TenantSession, customerID: String) async throws -> [Vehicle] {
        let rows = try await fetch(
            VehicleRecord.self,
            client.from("vehicles")
                .select(VehicleRecord.columns)
                .eq("customer_id", value: customerID)
                .order("created_at", ascending: true)
        )
        return rows.map(\.vehicle)
    }

    func saveVehicle(
        session: TenantSession,
        customerID: String,
        vehicleID: String?,
        draft: VehicleDraft
    ) async throws -> Vehicle {
        try require(.customersManage, session, query: "vehicles.save")
        try requireWritableWorkspace(session, query: "vehicles.save")
        guard !draft.isEmpty else {
            throw DataError.rejected("Add a registration, VIN, make or model.")
        }

        let registration = draft.registration.tidied.uppercased()
        let vin = draft.vin.tidied.uppercased()
        let make = draft.make.tidied
        let model = draft.model.tidied

        let builder: PostgrestBuilder
        if let vehicleID {
            builder = try client.from("vehicles")
                .update(VehicleUpdatePayload(registration: registration, vin: vin, make: make, model: model))
                .eq("id", value: vehicleID)
                .select(VehicleRecord.columns)
        } else {
            builder = try client.from("vehicles")
                .insert(
                    VehicleInsertPayload(
                        company_id: session.companyID,
                        customer_id: customerID,
                        registration: registration,
                        vin: vin,
                        make: make,
                        model: model,
                        created_by_user_id: session.userID
                    )
                )
                .select(VehicleRecord.columns)
        }

        let rows: [VehicleRecord]
        do {
            let response: PostgrestResponse<Void> = try await builder.execute()
            rows = try SupabaseCoding.decoder.decode([VehicleRecord].self, from: response.data)
        } catch is DecodingError {
            throw DataError.unexpected("The vehicle was saved but couldn't be read back. Pull to refresh.")
        } catch {
            throw DataError.rejected("The vehicle couldn't be saved. Check you can manage customers and try again.")
        }

        guard let saved = rows.first else { throw DataError.notFound }
        record("vehicles.save", session, allowed: true, vehicleID == nil ? "Vehicle added to customer" : "Vehicle details updated")
        return saved.vehicle
    }

    func vehicleJobs(session: TenantSession, vehicleID: String) async throws -> [VehicleJobEntry] {
        let rows = try await fetch(
            VehicleJobRecord.self,
            client.from("jobs")
                .select("id,number,title,status,scheduled_start,created_at")
                .eq("vehicle_id", value: vehicleID)
                .order("created_at", ascending: false)
        )
        return rows.map { row in
            VehicleJobEntry(
                id: row.id.uuidString,
                reference: row.number,
                title: row.title,
                status: row.status,
                dateLabel: Formatters.shortDate(row.scheduledStart ?? row.createdAt)
            )
        }
    }

    func jobVehicle(session: TenantSession, jobID: String) async throws -> Vehicle? {
        let links = try await fetch(
            JobVehicleLinkRecord.self,
            client.from("jobs").select("vehicle_id").eq("id", value: jobID)
        )
        guard let vehicleID = links.first?.vehicleID else { return nil }
        let rows = try await fetch(
            VehicleRecord.self,
            client.from("vehicles").select(VehicleRecord.columns).eq("id", value: vehicleID.uuidString)
        )
        return rows.first?.vehicle
    }

    func setJobVehicle(session: TenantSession, jobID: String, vehicleID: String?) async throws {
        try require(.jobsManage, session, query: "jobs.vehicle")
        try await perform(
            "set_job_vehicle",
            ["p_job": .string(jobID), "p_vehicle": vehicleID.map { AnyJSON.string($0) } ?? .null]
        )
        record("jobs.vehicle", session, allowed: true, vehicleID == nil ? "Vehicle cleared from job" : "Vehicle linked to job")
    }
}
