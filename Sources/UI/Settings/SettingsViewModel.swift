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
            dbSizeBytes = dbFileSize()
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
        dbSizeBytes = dbFileSize()
        #if DEBUG
        await debugRefreshLogical()   // TEMP PASS-2 TESTING — keep live readout in sync after eviction.
        #endif
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

    // MARK: - TEMP PASS-2 TESTING — TODO(pass-4): remove this whole harness once Pass 4 ships.
    #if DEBUG
    var debugBusy = false
    var debugLogicalMB: Double = 0

    /// Live logical size = (page_count − freelist_count) × page_size — the measure the
    /// storage engine actually enforces against (NOT the on-disk .sqlite footer above).
    func debugRefreshLogical() async {
        let bytes = (try? await dbManager.read { db in try self.storageGuard.logicalSizeBytes(db) }) ?? 0
        debugLogicalMB = Double(bytes) / (1024.0 * 1024.0)
    }

    /// Bulk-inserts `n` finished LIFT sessions (5 sets each, ~1 KB/session) so the DB can be
    /// pushed past a small limit by hand. ~900 sessions ≈ 1 MB.
    func debugSeed(_ n: Int) async {
        debugBusy = true
        let sessions = SessionRepository(dbManager: dbManager)
        let sets = SessionSetRepository(dbManager: dbManager)
        let exID = (try? await dbManager.read { db -> Int in
            let s = try prepare(db, "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
            defer { finalize(s) }
            guard try step(s) else { return 1 }
            return Int(sqlite3_column_int64(s, 0))
        }) ?? 1
        for _ in 0..<n {
            guard let ses = try? await sessions.start(routineID: nil, type: .lift) else { continue }
            for k in 1...5 {
                try? await sets.append(SessionSet(
                    id: 0, clientUUID: UUID(), sessionID: ses.id, exerciseID: exID,
                    exerciseOrder: 1, setNumber: k, setType: .working, weightKg: 80, reps: 5,
                    durationSecs: nil, distanceM: nil, rpe: 8, completedAt: Date(),
                    notes: nil, updatedAt: Date()))
            }
            try? await sessions.finish(id: ses.clientUUID)
        }
        await load()
        await debugRefreshLogical()
        debugBusy = false
    }
    #endif
}
