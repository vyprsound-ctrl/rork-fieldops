import Foundation

/// A customer's vehicle, used by Automotive companies.
///
/// Every field is optional: a technician can record a registration alone, a
/// VIN alone, or just "blue Transit van". Vehicles are never deleted — not by
/// the app and not by a business-type change — so job history keeps pointing
/// at them.
nonisolated struct Vehicle: Identifiable, Hashable, Sendable {
    let id: String
    let customerID: String
    let registration: String
    let vin: String
    let make: String
    let model: String

    /// "Ford Transit" or "Vehicle" when nothing describes it yet.
    var title: String {
        let name = [make, model].map(\.tidied).filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty { return name }
        if !registration.tidied.isEmpty { return registration.tidied.uppercased() }
        return "Vehicle"
    }

    /// The secondary line: registration and VIN where known.
    var subtitle: String? {
        var parts: [String] = []
        let reg = registration.tidied
        if !reg.isEmpty, !(make.tidied.isEmpty && model.tidied.isEmpty) { parts.append(reg.uppercased()) }
        if !vin.tidied.isEmpty { parts.append("VIN \(vin.tidied.uppercased())") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

nonisolated struct VehicleDraft: Hashable, Sendable {
    var registration: String = ""
    var vin: String = ""
    var make: String = ""
    var model: String = ""

    init() {}

    init(_ vehicle: Vehicle) {
        registration = vehicle.registration
        vin = vehicle.vin
        make = vehicle.make
        model = vehicle.model
    }

    var isEmpty: Bool {
        [registration, vin, make, model].allSatisfy { $0.tidied.isEmpty }
    }
}

/// One job a vehicle was on, for its service history.
nonisolated struct VehicleJobEntry: Identifiable, Hashable, Sendable {
    let id: String
    let reference: String
    let title: String
    let status: JobStatus
    let dateLabel: String?
}

// MARK: - Gateway surface

extension DataGateway {
    func vehicles(session: TenantSession, customerID: String) async throws -> [Vehicle] { [] }

    func saveVehicle(
        session: TenantSession,
        customerID: String,
        vehicleID: String?,
        draft: VehicleDraft
    ) async throws -> Vehicle {
        throw DataError.rejected(Self.vehiclesUnavailable)
    }

    func vehicleJobs(session: TenantSession, vehicleID: String) async throws -> [VehicleJobEntry] { [] }

    func jobVehicle(session: TenantSession, jobID: String) async throws -> Vehicle? { nil }

    func setJobVehicle(session: TenantSession, jobID: String, vehicleID: String?) async throws {
        throw DataError.rejected(Self.vehiclesUnavailable)
    }

    fileprivate static var vehiclesUnavailable: String {
        "Vehicles are kept in the live database. Sign in with your company account to use this."
    }
}
