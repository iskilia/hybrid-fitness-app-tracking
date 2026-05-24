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
    let targetDurationSecsMin: Int?
    let targetDurationSecsMax: Int?
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
        case targetDurationSecsMin = "target_duration_secs_min"
        case targetDurationSecsMax = "target_duration_secs_max"
        case notes
        case updatedAt   = "updated_at"
    }
}

// MARK: - routine_exercise_set (V3)

enum RoutineExerciseSetType: String, Codable, Sendable {
    case warmup  = "WARMUP"
    case working = "WORKING"
    case backoff = "BACKOFF"
}

struct RoutineExerciseSet: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let clientUUID: UUID
    let routineExerciseID: Int
    let setNumber: Int
    let setType: RoutineExerciseSetType
    let targetWeightKg: Double?
    let targetRepsMin: Int?
    let targetRepsMax: Int?
    let targetDurationSecsMin: Int?
    let targetDurationSecsMax: Int?
    let notes: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case clientUUID            = "client_uuid"
        case routineExerciseID     = "routine_exercise_id"
        case setNumber             = "set_number"
        case setType               = "set_type"
        case targetWeightKg        = "target_weight_kg"
        case targetRepsMin         = "target_reps_min"
        case targetRepsMax         = "target_reps_max"
        case targetDurationSecsMin = "target_duration_secs_min"
        case targetDurationSecsMax = "target_duration_secs_max"
        case notes
        case updatedAt             = "updated_at"
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
