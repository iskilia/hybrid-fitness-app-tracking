import Foundation
import Observation
import SQLite3

@Observable
@MainActor
final class SettingsViewModel {
    var weightUnit: WeightUnit = .kg
    var distanceUnit: DistanceUnit = .km
    var maxDataMb: Int = 10
    var sessionCount: Int = 0
    var dbSizeBytes: Int64 = 0

    private let dbManager: DatabaseManager
    private let profileRepo: UserProfileRepository
    private let storageGuard: StorageGuard
    private var previousMaxDataMb: Int = 10
    var showLimitDecreaseConfirm = false
    var storageErrorMessage: String?

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
        self.profileRepo = UserProfileRepository(dbManager: dbManager)
        self.storageGuard = StorageGuard(dbManager: dbManager)
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
                maxDataMb = p.maxDataMb
                previousMaxDataMb = p.maxDataMb
            }
            sessionCount = try await countSessions()
            dbSizeBytes = await logicalSizeBytes()
        } catch {
            sessionCount = 0
        }
    }

    func save() async {
        try? await profileRepo.upsert(
            weightUnit: weightUnit,
            distanceUnit: distanceUnit,
            maxDataMb: maxDataMb
        )
    }

    func handleMaxDataChange(to newValue: Int) async {
        let old = previousMaxDataMb
        if newValue >= old {                       // increase or no change
            previousMaxDataMb = newValue
            await persistLimit(newValue)
            await refreshFooter()
            return
        }
        let over = (try? await storageGuard.isOverLimit(maxDataMb: newValue)) ?? false
        if !over {                                 // decrease but still fits
            previousMaxDataMb = newValue
            await persistLimit(newValue)
            await refreshFooter()
            return
        }
        showLimitDecreaseConfirm = true            // decrease, over → warn
    }

    func confirmLimitDecrease() async {
        previousMaxDataMb = maxDataMb
        await persistLimit(maxDataMb)
        do {
            _ = try await storageGuard.reconcile(maxDataMb: maxDataMb)   // may clear all history
        } catch {
            // Limit is already persisted (lower); cleanup failed, so the DB may still be over.
            storageErrorMessage = "Couldn't free space: \(error.localizedDescription)"
        }
        await refreshFooter()
    }

    func cancelLimitDecrease() {
        maxDataMb = previousMaxDataMb              // revert picker; persist nothing
    }

    private func persistLimit(_ mb: Int) async {
        try? await profileRepo.upsert(weightUnit: weightUnit, distanceUnit: distanceUnit, maxDataMb: mb)
    }

    private func refreshFooter() async {
        sessionCount = (try? await countSessions()) ?? sessionCount
        dbSizeBytes = await logicalSizeBytes()
    }

    private func countSessions() async throws -> Int {
        try await dbManager.read { db in
            let stmt = try prepare(db, "SELECT COUNT(*) FROM session WHERE deleted_at IS NULL;")
            defer { finalize(stmt) }
            guard try step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    /// Logical size the storage limit is enforced against:
    /// (page_count − freelist_count) × page_size. NOT the on-disk .sqlite file size,
    /// which keeps freed pages as unreclaimed slack after eviction.
    private func logicalSizeBytes() async -> Int64 {
        (try? await dbManager.read { try storageGuard.logicalSizeBytes($0) }) ?? 0
    }

}
