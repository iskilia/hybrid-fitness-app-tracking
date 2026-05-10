import Foundation

// MARK: - Enums

enum RunType: String, Codable, Sendable {
    case steady    = "STEADY"
    case threshold = "THRESHOLD"
    case endurance = "ENDURANCE"
    case intervals = "INTERVALS"
    case fartlek   = "FARTLEK"
    case recovery  = "RECOVERY"
}

enum IntervalBlockType: String, Codable, Sendable {
    case warmup   = "WARMUP"
    case work     = "WORK"
    case recovery = "RECOVERY"
    case rest     = "REST"
    case cooldown = "COOLDOWN"
    case tempo    = "TEMPO"
}

// MARK: - run_template

struct RunTemplate: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let clientUUID: UUID
    let name: String
    let runType: RunType
    let targetTotalDistanceKm: Double?
    let targetWorkDistanceKm: Double?
    let targetPaceSecsMin: Int?
    let targetPaceSecsMax: Int?
    let hrZoneMin: Int?
    let hrZoneMax: Int?
    let hrBpmMin: Int?
    let hrBpmMax: Int?
    let isCustom: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case clientUUID              = "client_uuid"
        case name
        case runType                 = "run_type"
        case targetTotalDistanceKm   = "target_total_distance_km"
        case targetWorkDistanceKm    = "target_work_distance_km"
        case targetPaceSecsMin       = "target_pace_secs_min"
        case targetPaceSecsMax       = "target_pace_secs_max"
        case hrZoneMin               = "hr_zone_min"
        case hrZoneMax               = "hr_zone_max"
        case hrBpmMin                = "hr_bpm_min"
        case hrBpmMax                = "hr_bpm_max"
        case isCustom                = "is_custom"
        case createdAt               = "created_at"
        case updatedAt               = "updated_at"
        case deletedAt               = "deleted_at"
    }
}

// MARK: - run_interval_block

struct RunIntervalBlock: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let runTemplateID: Int
    let sortOrder: Int
    let blockType: IntervalBlockType
    let repeatCount: Int
    let distanceKm: Double?
    let durationSecs: Int?
    let targetPaceSecs: Int?
    let hrZone: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case runTemplateID  = "run_template_id"
        case sortOrder      = "sort_order"
        case blockType      = "block_type"
        case repeatCount    = "repeat_count"
        case distanceKm     = "distance_km"
        case durationSecs   = "duration_secs"
        case targetPaceSecs = "target_pace_secs"
        case hrZone         = "hr_zone"
        case notes
    }
}
