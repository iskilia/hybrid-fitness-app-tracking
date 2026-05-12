import Foundation
import Observation
import SQLite3

@Observable
@MainActor
final class SettingsViewModel {
    var weightUnit: WeightUnit = .kg
    var distanceUnit: DistanceUnit = .km
    var bodyWeightInput: String = ""
    var sessionCount: Int = 0
    var dbSizeBytes: Int64 = 0
    var isExporting = false

    private let dbManager: DatabaseManager
    private let profileRepo: UserProfileRepository

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
        self.profileRepo = UserProfileRepository(dbManager: dbManager)
    }

    var footerText: String {
        let mb = Double(dbSizeBytes) / (1024.0 * 1024.0)
        return String(format: "%d SESSIONS \u{B7} %.1f MB", sessionCount, mb)
    }

    func load() async {
        do {
            if let p = try await profileRepo.get() {
                weightUnit = p.weightUnit
                distanceUnit = p.distanceUnit
                bodyWeightInput = p.bodyWeightKg.map { String(format: "%.1f", $0) } ?? ""
            }
            sessionCount = try await countSessions()
            dbSizeBytes = dbFileSize()
        } catch {
            sessionCount = 0
        }
    }

    func save() async {
        let weight = Double(bodyWeightInput.trimmingCharacters(in: .whitespaces))
        try? await profileRepo.upsert(
            weightUnit: weightUnit,
            distanceUnit: distanceUnit,
            bodyWeightKg: weight
        )
    }

    func exportCSV() async -> URL? {
        isExporting = true
        defer { isExporting = false }
        return try? await CSVExporter(dbManager: dbManager).export()
    }

    func exportJSON() async -> URL? {
        isExporting = true
        defer { isExporting = false }
        return try? await JSONExporter(dbManager: dbManager).export()
    }

    private func countSessions() async throws -> Int {
        try await dbManager.read { db in
            let stmt = try prepare(db, "SELECT COUNT(*) FROM session WHERE deleted_at IS NULL;")
            defer { finalize(stmt) }
            guard try step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    private func dbFileSize() -> Int64 {
        guard let dir = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false)
        else { return 0 }
        let url = dir.appendingPathComponent("Hybrid.sqlite")
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
