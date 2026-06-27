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
        // Library/Application Support is Apple's home for a private SQLite store the user
        // never opens directly (Documents is for user-facing files / file sharing). The
        // "Hybrid" subdirectory is internal — DatabaseManager creates it on first launch.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport
            .appendingPathComponent("Hybrid", isDirectory: true)
            .appendingPathComponent("Hybrid.sqlite")
        do {
            return DatabaseBootstrap(manager: try DatabaseManager(url: url), errorMessage: nil)
        } catch {
            let message = DatabaseBootstrap.diagnose(error, url: url)
            NSLog("[Hybrid] database bootstrap failed:\n%@", message)
            return DatabaseBootstrap(manager: nil, errorMessage: message)
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

    /// Builds a diagnostic message naming the failing step, the raw cause and the
    /// filesystem state, so an on-device failure reports exactly where it broke rather
    /// than a bare "unable to open database file" we then have to guess about.
    static func diagnose(_ error: Error, url: URL) -> String {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()

        let cause: String
        if case let DatabaseError.openFailed(message) = error {
            // Reached sqlite3_open_v2 — directory creation already succeeded.
            cause = "open: \(message)"
        } else {
            // Threw before the open — almost certainly createDirectory.
            cause = "\((error as NSError).domain) \((error as NSError).code): \((error as NSError).localizedDescription)"
        }

        return """
        \(cause)
        path: \(url.path)
        dir exists: \(fm.fileExists(atPath: dir.path)) · writable: \(fm.isWritableFile(atPath: dir.path))
        """
    }
}
