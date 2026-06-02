import Foundation

// MARK: - Enums

enum WeightUnit: String, Codable, Sendable {
    case kg = "KG"
    case lb = "LB"
}

enum DistanceUnit: String, Codable, Sendable {
    case km = "KM"
    case mi = "MI"
}

// MARK: - user_profile

struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let clientUUID: UUID
    let name: String
    let weightUnit: WeightUnit
    let distanceUnit: DistanceUnit
    let maxDataMb: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case clientUUID    = "client_uuid"
        case name
        case weightUnit    = "weight_unit"
        case distanceUnit  = "distance_unit"
        case maxDataMb     = "max_data_mb"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
    }
}
