import Foundation

/// The trade a company operates in.
///
/// This is **configuration, not architecture**. Every trade runs the same
/// Customer → Site → Asset → Job → Field worker → Quote → Invoice → Payment
/// workflow on the same schema; the trade only decides what things are *called*
/// and, later, which job templates and optional fields are offered.
///
/// Adding a trade must never require a new table, a new gateway or a new app.
nonisolated enum Trade: String, Codable, CaseIterable, Sendable, Identifiable {
    case hvac
    case plumbing
    case electrical
    case roofing
    case applianceRepair
    case locksmith
    case generalMaintenance
    case pestControl
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hvac: return "HVAC"
        case .plumbing: return "Plumbing"
        case .electrical: return "Electrical"
        case .roofing: return "Roofing"
        case .applianceRepair: return "Appliance repair"
        case .locksmith: return "Locksmith"
        case .generalMaintenance: return "General maintenance"
        case .pestControl: return "Pest control"
        case .other: return "Field service"
        }
    }

    /// What this trade calls the people and things the platform models.
    var terminology: Terminology {
        switch self {
        // ISSUE #14 — "engineer" is too narrow for the people doing this work,
        // and in US field service it actively misreads as a chartered
        // profession. The customer-facing word is now "field worker".
        //
        // This is the ONLY place the word needed to change: every screen already
        // asks `Terminology` what to call the role, so correcting it here moves
        // the whole app at once. The `fieldWorker` role identifier, the database
        // enum and the RLS policies that depend on it are untouched — renaming
        // those would be a migration with real risk and no user-visible benefit.
        case .hvac:
            return Terminology(worker: "field worker", workerPlural: "field workers", asset: "unit", assetPlural: "units")
        case .plumbing:
            return Terminology(worker: "plumber", workerPlural: "plumbers", asset: "fixture", assetPlural: "fixtures")
        case .electrical:
            return Terminology(worker: "electrician", workerPlural: "electricians", asset: "installation", assetPlural: "installations")
        case .roofing:
            return Terminology(worker: "roofer", workerPlural: "roofers", asset: "structure", assetPlural: "structures")
        case .applianceRepair:
            return Terminology(worker: "technician", workerPlural: "technicians", asset: "appliance", assetPlural: "appliances")
        case .locksmith:
            return Terminology(worker: "locksmith", workerPlural: "locksmiths", asset: "lock", assetPlural: "locks")
        case .generalMaintenance, .other:
            return Terminology(worker: "technician", workerPlural: "technicians", asset: "asset", assetPlural: "assets")
        case .pestControl:
            return Terminology(worker: "technician", workerPlural: "technicians", asset: "treatment area", assetPlural: "treatment areas")
        }
    }
}

/// The words a company sees for the platform's generic concepts.
///
/// Internally the platform only knows about field workers, assets and jobs.
/// This type is the single place those concepts are turned into the language of
/// a particular trade, so no screen has to hard-code a trade's vocabulary.
nonisolated struct Terminology: Hashable, Sendable {
    /// "engineer", "plumber", "technician"
    let worker: String
    let workerPlural: String
    /// "unit", "fixture", "appliance"
    let asset: String
    let assetPlural: String
    /// Generic across trades today; kept here so a trade could later prefer
    /// "work order" or "visit" without touching any screen.
    let job: String = "job"
    let jobPlural: String = "jobs"
    let site: String = "site"

    var Worker: String { worker.capitalizedFirst }
    var WorkerPlural: String { workerPlural.capitalizedFirst }
    var Asset: String { asset.capitalizedFirst }
    var AssetPlural: String { assetPlural.capitalizedFirst }
    var Job: String { job.capitalizedFirst }

    /// Fallback for screens rendered before a company is known (previews,
    /// sign-in). Deliberately neutral rather than HVAC.
    static let generic = Trade.other.terminology

    /// Substitutes `{worker}` / `{asset}` / `{job}` tokens in stored strings so
    /// tables of actions can stay trade-neutral.
    func resolve(_ template: String) -> String {
        template
            .replacingOccurrences(of: "{worker}", with: worker)
            .replacingOccurrences(of: "{workerPlural}", with: workerPlural)
            .replacingOccurrences(of: "{asset}", with: asset)
            .replacingOccurrences(of: "{job}", with: job)
    }
}

nonisolated extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
