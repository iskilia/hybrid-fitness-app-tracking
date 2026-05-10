import Foundation

// MARK: - Enums

enum MetricType: String, Codable, Sendable {
    case reps             = "REPS"
    case time             = "TIME"
    case distance         = "DISTANCE"
    case repsBodyweight   = "REPS_BODYWEIGHT"
}

enum MuscleRole: String, Codable, Sendable {
    case primary   = "PRIMARY"
    case secondary = "SECONDARY"
}

// MARK: - exercise

struct Exercise: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let clientUUID: UUID
    let name: String
    let abbreviation: String
    let equipmentID: Int
    let metricType: MetricType
    let isCustom: Bool
    let notes: String?
    let formLink: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case clientUUID  = "client_uuid"
        case name
        case abbreviation
        case equipmentID = "equipment_id"
        case metricType  = "metric_type"
        case isCustom    = "is_custom"
        case notes
        case formLink    = "form_link"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
        case deletedAt   = "deleted_at"
    }
}

// MARK: - exercise_muscle

struct ExerciseMuscle: Codable, Hashable, Sendable {
    let exerciseID: Int
    let muscleID: Int
    let role: MuscleRole

    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case muscleID   = "muscle_id"
        case role
    }
}

// Identifiable conformance using a composite key
extension ExerciseMuscle: Identifiable {
    var id: String { "\(exerciseID)-\(muscleID)" }
}
