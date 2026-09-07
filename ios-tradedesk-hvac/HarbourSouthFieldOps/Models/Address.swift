import Foundation

nonisolated struct Address: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let customerID: String
    var line1: String
    var line2: String?
    var city: String
    var state: String
    var postalCode: String
    var latitude: Double
    var longitude: Double
    var accessNotes: String?

    var singleLine: String {
        "\(line1), \(city) \(state) \(postalCode)"
    }

    var shortLine: String { line1 }
}
