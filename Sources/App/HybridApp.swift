import SwiftUI
import Foundation

@main
struct HybridApp: App {
    // Opens the on-disk database and remembers WHY it failed if it did. A previous
    // `(try? DatabaseManager(url: url)) ?? (try? DatabaseManager(url: nil))` silently
    // substituted an in-memory database whenever the file open threw — that store is
    // wiped on every app termination, so anything the user created vanished on the
    // next launch while seed data reappeared. We never substitute an ephemeral store
    // now: on failure `manager` is nil and we surface the underlying error instead of
    // masking it with disappearing data.
    private let bootstrap: DatabaseBootstrap = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("Hybrid.sqlite")
        do {
            return DatabaseBootstrap(manager: try DatabaseManager(url: url), errorMessage: nil)
        } catch {
            return DatabaseBootstrap(manager: nil, errorMessage: DatabaseBootstrap.describe(error))
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView(databaseErrorMessage: bootstrap.errorMessage)
                .environment(\.databaseManager, bootstrap.manager)
        }
    }
}

// MARK: - DatabaseBootstrap

/// Result of trying to open the persistent database at launch: the live manager, or
/// the human-readable reason it could not open (shown on the "Database unavailable"
/// screen so an on-device failure reports its actual cause instead of staying silent).
private struct DatabaseBootstrap {
    let manager: DatabaseManager?
    let errorMessage: String?

    /// Unwraps the SQLite text from `DatabaseError.openFailed` so the surfaced message
    /// is the raw cause (e.g. "unable to open database file") rather than a Swift dump.
    static func describe(_ error: Error) -> String {
        if case let DatabaseError.openFailed(message) = error { return message }
        return String(describing: error)
    }
}
