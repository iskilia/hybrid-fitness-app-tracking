import Foundation

// MARK: - Enums

enum SessionStatus: String, Codable, Sendable {
    case inProgress = "IN_PROGRESS"
    case completed  = "COMPLETED"
    case abandoned  = "ABANDONED"
}

enum SetType: String, Codable, Sendable {
    case warmup  = "WARMUP"
    case working = "WORKING"
    case dropset = "DROPSET"
    case amrap   = "AMRAP"
    case failure = "FAILURE"
}

// MARK: - session

struct Session: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let clientUUID: UUID
    let routineID: Int?
    let type: WorkoutType
    let status: SessionStatus
    let startedAt: Date
    let finishedAt: Date?
    let bodyWeightKg: Double?
    let notes: String?
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case clientUUID  = "client_uuid"
        case routineID   = "routine_id"
        case type
        case status
        case startedAt   = "started_at"
        case finishedAt  = "finished_at"
        case bodyWeightKg = "body_weight_kg"
        case notes
        case updatedAt   = "updated_at"
        case deletedAt   = "deleted_at"
    }
}

// MARK: - session_tag

struct SessionTag: Codable, Hashable, Sendable {
    let sessionID: Int
    let tagID: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case tagID     = "tag_id"
    }
}

extension SessionTag: Identifiable {
    var id: String { "\(sessionID)-\(tagID)" }
}

// MARK: - session_set

struct SessionSet: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let clientUUID: UUID
    let sessionID: Int
    let exerciseID: Int
    let exerciseOrder: Int
    let setNumber: Int
    let setType: SetType
    let weightKg: Double?
    let reps: Int?
    let durationSecs: Int?
    let distanceM: Double?
    let rpe: Double?
    let completedAt: Date?
    let notes: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case clientUUID    = "client_uuid"
        case sessionID     = "session_id"
        case exerciseID    = "exercise_id"
        case exerciseOrder = "exercise_order"
        case setNumber     = "set_number"
        case setType       = "set_type"
        case weightKg      = "weight_kg"
        case reps
        case durationSecs  = "duration_secs"
        case distanceM     = "distance_m"
        case rpe
        case completedAt   = "completed_at"
        case notes
        case updatedAt     = "updated_at"
    }
}

// MARK: - session_run

struct SessionRun: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let clientUUID: UUID
    let sessionID: Int
    let runTemplateID: Int?
    let runOrder: Int
    let actualDistanceKm: Double?
    let durationSecs: Int?
    let avgPaceSecs: Int?
    let avgHR: Int?
    let maxHR: Int?
    let targetHRMin: Int?
    let targetHRMax: Int?
    let notes: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case clientUUID      = "client_uuid"
        case sessionID       = "session_id"
        case runTemplateID   = "run_template_id"
        case runOrder        = "run_order"
        case actualDistanceKm = "actual_distance_km"
        case durationSecs    = "duration_secs"
        case avgPaceSecs     = "avg_pace_secs"
        case avgHR           = "avg_hr"
        case maxHR           = "max_hr"
        case targetHRMin     = "target_hr_min"
        case targetHRMax     = "target_hr_max"
        case notes
        case updatedAt       = "updated_at"
    }
}

// MARK: - session_run_split

struct SessionRunSplit: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let sessionRunID: Int
    let sortOrder: Int
    let blockType: IntervalBlockType?
    let distanceKm: Double?
    let durationSecs: Int?
    let avgPaceSecs: Int?
    let avgHR: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionRunID = "session_run_id"
        case sortOrder    = "sort_order"
        case blockType    = "block_type"
        case distanceKm   = "distance_km"
        case durationSecs = "duration_secs"
        case avgPaceSecs  = "avg_pace_secs"
        case avgHR        = "avg_hr"
    }
}
