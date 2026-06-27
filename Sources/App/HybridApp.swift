import SwiftUI
import Foundation

@main
struct HybridApp: App {
    private let dbManager: DatabaseManager? = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("Hybrid.sqlite")
        // Open the on-disk database only. A previous `?? DatabaseManager(url: nil)`
        // fallback silently substituted an in-memory database whenever the file open
        // threw — that store is wiped on every app termination, so anything the user
        // created vanished on the next launch while seed data reappeared. If the file
        // genuinely can't open we return nil and RootView shows "Database unavailable"
        // rather than masking the failure with disappearing data.
        return try? DatabaseManager(url: url)
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.databaseManager, dbManager)
        }
    }
}
