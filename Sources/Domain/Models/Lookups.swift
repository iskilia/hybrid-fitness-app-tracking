import Foundation

// MARK: - muscle

struct Muscle: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let code: String
    let displayName: String
    let groupName: String

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case displayName = "display_name"
        case groupName   = "group_name"
    }
}

// MARK: - equipment

struct Equipment: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let code: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case displayName = "display_name"
    }
}

// MARK: - tag

struct Tag: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let code: String
    let displayName: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case displayName = "display_name"
        case createdAt   = "created_at"
    }
}
