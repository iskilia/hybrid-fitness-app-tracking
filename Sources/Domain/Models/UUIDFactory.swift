import Foundation

enum UUIDFactory: Sendable {
    static func new() -> UUID { UUID() }
}
