import Foundation

// MARK: - Enums

enum WorkoutType: String, Codable, Sendable {
    case lift  = "LIFT"
    case run   = "RUN"
    case mixed = "MIXED"
}

// MARK: - routine

struct Routine: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let clientUUID: UUID
    let name: String
    let type: WorkoutType
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case clientUUID = "client_uuid"
        case name
        case type
        case sortOrder  = "sort_order"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
        case deletedAt  = "deleted_at"
    }
}

// MARK: - routine_exercise

struct RoutineExercise: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let clientUUID: UUID
    let routineID: Int
    let exerciseID: Int
    let sortOrder: Int
    let targetSets: Int?
    let targetRepMin: Int?
    let targetRepMax: Int?
    let targetRPE: Double?
    let notes: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case clientUUID  = "client_uuid"
        case routineID   = "routine_id"
        case exerciseID  = "exercise_id"
        case sortOrder   = "sort_order"
        case targetSets  = "target_sets"
        case targetRepMin = "target_rep_min"
        case targetRepMax = "target_rep_max"
        case targetRPE   = "target_rpe"
        case notes
        case updatedAt   = "updated_at"
    }
}

// MARK: - routine_run

struct RoutineRun: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let clientUUID: UUID
    let routineID: Int
    let runTemplateID: Int
    let sortOrder: Int
    let notes: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case clientUUID    = "client_uuid"
        case routineID     = "routine_id"
        case runTemplateID = "run_template_id"
        case sortOrder     = "sort_order"
        case notes
        case updatedAt     = "updated_at"
    }
}
