import SwiftUI
import Foundation

@main
struct HybridApp: App {
    private let dbManager: DatabaseManager? = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("Hybrid.sqlite")
        return (try? DatabaseManager(url: url)) ?? (try? DatabaseManager(url: nil))
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.databaseManager, dbManager)
        }
    }
}
