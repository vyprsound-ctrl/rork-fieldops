import CryptoKit
import Foundation

/// The contract between `PermissionMatrix` (Swift) and `public.role_permissions`
/// (PostgreSQL).
///
/// Both sides express the same 39 permissions and the same 105 role grants, and
/// both reduce that set to the same checksum: every `role:permission` pair,
/// sorted in byte order, joined by newlines, hashed with MD5. Postgres computes
/// it with
///
/// ```sql
/// select md5(string_agg(role::text || ':' || permission::text,
///                       chr(10) order by (role::text || ':' || permission::text) collate "C"))
/// from public.role_permissions;
/// ```
///
/// The live value is stored in `public.permission_matrix_contract` by the
/// reconcile migration, and pinned here as `databaseFingerprint`. If either side
/// is edited without the other, the two stop matching and
/// `DevelopmentTestSuite` fails loudly.
///
/// This is a pinned-contract check, not a live query — it needs no network, no
/// credentials, and runs in the same pass as every other development scenario.
/// Re-running `backend/migrations` reconcile is what makes a new pin legitimate.
nonisolated enum PermissionMatrixContract {
    /// Checksum of `public.role_permissions` as reconciled on 2026-08-27.
    /// Update this ONLY together with a migration that re-reconciles the table.
    static let databaseFingerprint = "77456d73c93f1b72ca02e02d3cf4f290"

    /// Size of the PostgreSQL `app_permission` enum at the same moment.
    static let databasePermissionCount = 39

    /// Row count of `public.role_permissions` at the same moment.
    static let databaseGrantCount = 105

    /// Every grant the Swift matrix currently expresses, in the canonical order
    /// both sides agree on.
    static var canonicalGrants: [String] {
        Role.allCases
            .flatMap { role in
                PermissionMatrix.permissions(for: role).map { "\(role.rawValue):\($0.rawValue)" }
            }
            .sorted()
    }

    /// The exact byte sequence that is hashed. Kept separate so a failing test
    /// can show the input rather than just a mismatched digest.
    static var canonicalForm: String {
        canonicalGrants.joined(separator: "\n")
    }

    /// MD5 of `canonicalForm`, lowercase hex — the same digest Postgres produces.
    static var fingerprint: String {
        Insecure.MD5
            .hash(data: Data(canonicalForm.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static var permissionCount: Int { Permission.allCases.count }

    static var grantCount: Int { canonicalGrants.count }

    /// True when Swift and the pinned database state agree on every count and on
    /// the checksum.
    static var matchesDatabase: Bool {
        fingerprint == databaseFingerprint
            && permissionCount == databasePermissionCount
            && grantCount == databaseGrantCount
    }

    /// Human-readable drift, empty when the two sides agree.
    static var driftDescription: String {
        var problems: [String] = []
        if permissionCount != databasePermissionCount {
            problems.append("permission count \(permissionCount) vs database \(databasePermissionCount)")
        }
        if grantCount != databaseGrantCount {
            problems.append("grant count \(grantCount) vs database \(databaseGrantCount)")
        }
        if fingerprint != databaseFingerprint {
            problems.append("checksum \(fingerprint) vs database \(databaseFingerprint)")
        }
        guard problems.isEmpty else {
            return problems.joined(separator: " · ")
                + " — re-run the role_permissions reconcile migration, then re-pin databaseFingerprint"
        }
        return ""
    }

    /// Grants per role, for evidence in the development report.
    static var grantsByRole: [(role: Role, count: Int)] {
        Role.allCases.map { ($0, PermissionMatrix.permissions(for: $0).count) }
    }
}
