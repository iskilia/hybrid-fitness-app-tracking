import SwiftUI
import Foundation

@main
struct HybridApp: App {
    private let dbManager: DatabaseManager = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("Hybrid.sqlite")
        // Fall back to in-memory if init fails (should not happen in production).
        return (try? DatabaseManager(url: url)) ?? (try! DatabaseManager(url: nil))
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.databaseManager, dbManager)
                .task { await configureSnapshotHook() }
        }
    }

    // TV6.5 — Wire SnapshotWriter + first-launch schema-doc write.
    @MainActor
    private func configureSnapshotHook() async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        // Construct and register the live writer.
        let writer = SnapshotWriter(documentsURL: docs, dbManager: dbManager)
        SnapshotHook.current = writer

        // Write hybrid-schema.md if absent or version-mismatched.
        let schemaURL = docs.appendingPathComponent("hybrid-schema.md")
        let needsWrite: Bool = {
            guard let existing = try? String(contentsOf: schemaURL, encoding: .utf8) else {
                return true // file absent
            }
            return !existing.hasPrefix("# hybrid") || !existing.contains(SchemaDoc.schemaVersion)
        }()
        if needsWrite {
            do {
                try SchemaDoc.write(to: docs)
            } catch {
                print("[HybridApp] Failed to write hybrid-schema.md: \(error)")
            }
        }
    }
}
