import Foundation

// MARK: - DatabaseError

public enum DatabaseError: Error, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case notFound
    case conflict(String)
}
