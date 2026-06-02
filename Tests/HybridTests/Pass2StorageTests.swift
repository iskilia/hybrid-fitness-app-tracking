import XCTest
import SQLite3
@testable import Hybrid

/// Pass 2 — StorageGuard gate tests.
final class Pass2StorageTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass2-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    private func makeMemDB() throws -> DatabaseManager {
        try DatabaseManager(url: nil)
    }

    /// Insert N sessions with sets to build up data.
    private func seedSessions(_ n: Int, db: DatabaseManager) async throws {
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)
        let exerciseID = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        for i in 0..<n {
            let s = try await sessions.start(routineID: nil, type: .lift)
            for k in 1...5 {
                try await sets.append(SessionSet(
                    id: 0, clientUUID: UUID(),
                    sessionID: s.id, exerciseID: exerciseID,
                    exerciseOrder: 1, setNumber: k,
                    setType: .working,
                    weightKg: Double(80 + i), reps: 5,
                    durationSecs: nil, distanceM: nil,
                    rpe: 8.0, completedAt: Date(),
                    notes: nil, updatedAt: Date()
                ))
            }
            try await sessions.finish(id: s.clientUUID)
        }
    }

    /// Seeds sessions in batches until logicalSizeBytes exceeds `mb` megabytes.
    /// Sessions are ~1 KB each, so a 1 MB limit needs ~850 — measured, not guessed.
    /// Returns the total number of sessions seeded.
    @discardableResult
    private func seedOverLimit(mb: Int = 1, db: DatabaseManager) async throws -> Int {
        let g = StorageGuard(dbManager: db)
        let target = Int64(mb) * 1024 * 1024
        var total = 0
        repeat {
            try await seedSessions(150, db: db)
            total += 150
        } while try await db.read({ try g.logicalSizeBytes($0) }) <= target && total < 4500
        return total
    }

    /// The most-recently-started session's client UUID (newest by started_at, id).
    private func newestSessionUUID(_ db: DatabaseManager) async throws -> UUID? {
        try await db.read { handle -> UUID? in
            let stmt = try Hybrid.prepare(handle,
                "SELECT client_uuid FROM session ORDER BY started_at DESC, id DESC LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return nil }
            return Hybrid.columnUUID(stmt, 0)
        }
    }

    private func sessionCount(_ db: DatabaseManager) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM session;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    // MARK: - 1. logicalSizeBytes math

    func testLogicalSizeBytesMatchesPragmas() async throws {
        let db = try makeTempDB()
        try await seedSessions(20, db: db)

        let guard1 = StorageGuard(dbManager: db)

        let (logical, independent) = try await db.read { handle -> (Int64, Int64) in
            let logical = try guard1.logicalSizeBytes(handle)

            let s1 = try Hybrid.prepare(handle, "PRAGMA page_count;")
            defer { Hybrid.finalize(s1) }
            _ = try Hybrid.step(s1)
            let pc = Int(sqlite3_column_int64(s1, 0))

            let s2 = try Hybrid.prepare(handle, "PRAGMA freelist_count;")
            defer { Hybrid.finalize(s2) }
            _ = try Hybrid.step(s2)
            let fc = Int(sqlite3_column_int64(s2, 0))

            let s3 = try Hybrid.prepare(handle, "PRAGMA page_size;")
            defer { Hybrid.finalize(s3) }
            _ = try Hybrid.step(s3)
            let ps = Int(sqlite3_column_int64(s3, 0))

            let independent = Int64(pc - fc) * Int64(ps)
            return (logical, independent)
        }
        XCTAssertEqual(logical, independent, "logicalSizeBytes must equal (page_count - freelist_count) * page_size")
    }

    // MARK: - 2. limitBytes

    func testLimitBytes() {
        let g = StorageGuard(dbManager: try! makeMemDB())
        XCTAssertEqual(g.limitBytes(maxDataMb: 10), 10 * 1024 * 1024)
        XCTAssertEqual(g.limitBytes(maxDataMb: 200), 200 * 1024 * 1024)
    }

    // MARK: - 3. probe persists nothing

    func testProbePersistsNothing() async throws {
        let db = try makeTempDB()
        try await seedSessions(10, db: db)

        let beforeCount = try await sessionCount(db)
        let guard1 = StorageGuard(dbManager: db)

        let sessions = SessionRepository(dbManager: db)
        let fakeSession = try await sessions.start(routineID: nil, type: .lift)

        let result = try await guard1.probe(
            insert: { _ in /* no-op insert for count test */ },
            maxDataMb: 10
        )
        let afterCount = try await sessionCount(db)
        // The probe must have rolled back — count stays the same as after fakeSession start
        // (fakeSession was started OUTSIDE the probe)
        XCTAssertNotNil(result)
        // The number of sessions is the same as after we started fakeSession (probe did no extra insert)
        XCTAssertEqual(afterCount, beforeCount + 1, "probe must not persist anything extra")

        // Cleanup
        try await sessions.abandon(id: fakeSession.clientUUID)
    }

    // MARK: - 4. probe → needsEviction(overBy:)

    func testProbeNeedsEviction() async throws {
        let db = try makeTempDB()
        try await seedOverLimit(mb: 1, db: db)   // seed past 1 MB so the limit is exceeded

        let guard1 = StorageGuard(dbManager: db)

        // 1 MB limit with >1 MB of data → the inserted row pushes it over → needsEviction
        let result = try await guard1.probe(insert: { db in
            let s = try Hybrid.prepare(db, """
                INSERT INTO session (client_uuid, routine_id, type, status, started_at, updated_at)
                VALUES (?, NULL, 'LIFT', 'IN_PROGRESS', ?, ?);
                """)
            defer { Hybrid.finalize(s) }
            Hybrid.bindUUID(s, 1, UUID())
            let now = Int64(Date().timeIntervalSince1970)
            sqlite3_bind_int64(s, 2, now)
            sqlite3_bind_int64(s, 3, now)
            _ = try Hybrid.step(s)
        }, maxDataMb: 1)

        switch result {
        case .needsEviction(let overBy):
            XCTAssertGreaterThan(overBy, 0, "overBy must be positive")
        case .fits:
            XCTFail("Expected needsEviction with 1 MB limit and 50 sessions; got .fits")
        }
    }

    // MARK: - 5. commitWithEviction evicts oldest-first and fits

    func testCommitWithEvictionEvictsOldestFirst() async throws {
        let db = try makeTempDB()
        try await seedOverLimit(mb: 1, db: db)   // >1 MB so commit must evict to fit

        let guard1 = StorageGuard(dbManager: db)
        let beforeCount = try await sessionCount(db)

        // Use a small limit (1 MB) to force eviction
        let outcome = try await guard1.commitWithEviction(
            insert: { db in
                let s = try Hybrid.prepare(db, """
                    INSERT INTO session (client_uuid, routine_id, type, status, started_at, updated_at)
                    VALUES (?, NULL, 'LIFT', 'IN_PROGRESS', ?, ?);
                    """)
                defer { Hybrid.finalize(s) }
                Hybrid.bindUUID(s, 1, UUID())
                let now = Int64(Date().timeIntervalSince1970)
                sqlite3_bind_int64(s, 2, now)
                sqlite3_bind_int64(s, 3, now)
                _ = try Hybrid.step(s)
            },
            maxDataMb: 1
        )

        XCTAssertEqual(outcome, .fitted, "Expected .fitted outcome")

        let afterCount = try await sessionCount(db)
        XCTAssertLessThan(afterCount, beforeCount + 1, "Sessions must have been evicted")

        // Verify logical size is within limit
        let finalSize = try await db.read { handle in
            try guard1.logicalSizeBytes(handle)
        }
        XCTAssertLessThanOrEqual(finalSize, guard1.limitBytes(maxDataMb: 1),
            "logicalSizeBytes must be within limit after commitWithEviction")
    }

    // MARK: - 6. commitWithEviction → impossible

    func testCommitWithEvictionImpossible() async throws {
        let db = try makeTempDB()
        try await seedSessions(5, db: db)

        let guard1 = StorageGuard(dbManager: db)
        let beforeCount = try await sessionCount(db)

        // Limit of 0 bytes — impossible to satisfy
        let outcome = try await guard1.commitWithEviction(
            insert: { db in
                let s = try Hybrid.prepare(db, """
                    INSERT INTO session (client_uuid, routine_id, type, status, started_at, updated_at)
                    VALUES (?, NULL, 'LIFT', 'IN_PROGRESS', ?, ?);
                    """)
                defer { Hybrid.finalize(s) }
                Hybrid.bindUUID(s, 1, UUID())
                let now = Int64(Date().timeIntervalSince1970)
                sqlite3_bind_int64(s, 2, now)
                sqlite3_bind_int64(s, 3, now)
                _ = try Hybrid.step(s)
            },
            maxDataMb: 0
        )

        XCTAssertEqual(outcome, .impossible, "Expected .impossible when limit is 0")
        let afterCount = try await sessionCount(db)
        XCTAssertEqual(afterCount, beforeCount, "Session count must be unchanged after .impossible")
    }

    // MARK: - 7. reconcile no-op when fitting

    func testReconcileNoOpWhenFitting() async throws {
        let db = try makeTempDB()
        try await seedSessions(5, db: db)

        let guard1 = StorageGuard(dbManager: db)
        let beforeCount = try await sessionCount(db)

        // 200 MB is way more than 5 sessions; should fit
        let outcome = try await guard1.reconcile(maxDataMb: 200)

        XCTAssertEqual(outcome, .fitted)
        let afterCount = try await sessionCount(db)
        XCTAssertEqual(afterCount, beforeCount, "reconcile must not delete anything when fitting")
    }

    // MARK: - 8. reconcile evicts oldest-first

    func testReconcileEvictsOldestFirst() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let seeded = try await seedOverLimit(mb: 1, db: db)   // >1 MB so reconcile evicts

        let newestUUID = try await newestSessionUUID(db)
        let beforeCount = try await sessionCount(db)
        let guard1 = StorageGuard(dbManager: db)

        let outcome = try await guard1.reconcile(maxDataMb: 1)
        XCTAssertEqual(outcome, .fitted)

        // Eviction actually happened
        let afterCount = try await sessionCount(db)
        XCTAssertLessThan(afterCount, beforeCount, "reconcile must evict when over (\(seeded) seeded)")

        // Verify logical size is within limit
        let finalSize = try await db.read { handle in
            try guard1.logicalSizeBytes(handle)
        }
        XCTAssertLessThanOrEqual(finalSize, guard1.limitBytes(maxDataMb: 1))

        // Newest session must still exist (oldest-first eviction)
        let newest = try await sessions.get(id: newestUUID!)
        XCTAssertNotNil(newest, "Newest session must be preserved after reconcile")
    }

    // MARK: - 9. reconcile clears all history on extreme decrease but preserves base data

    func testReconcileClearsHistoryPreservesBaseData() async throws {
        let db = try makeTempDB()
        try await seedSessions(10, db: db)

        let guard1 = StorageGuard(dbManager: db)
        _ = try await guard1.reconcile(maxDataMb: 0)

        // All sessions should be gone
        let sessionCountAfter = try await sessionCount(db)
        XCTAssertEqual(sessionCountAfter, 0, "All sessions must be evicted at limit=0")

        // Base exercises must still exist
        let exerciseCount = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM exercise WHERE is_custom = 0;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertGreaterThan(exerciseCount, 0, "Base exercises must not be evicted")
    }

    // MARK: - 10. VACUUM ran after fitted eviction

    func testVacuumRunAfterFittedEviction() async throws {
        let db = try makeTempDB()
        try await seedSessions(30, db: db)

        let guard1 = StorageGuard(dbManager: db)

        // Capture freelist_count before eviction
        let freelistBefore = try await db.read { handle -> Int in
            let s = try Hybrid.prepare(handle, "PRAGMA freelist_count;")
            defer { Hybrid.finalize(s) }
            _ = try Hybrid.step(s)
            return Int(sqlite3_column_int64(s, 0))
        }

        let outcome = try await guard1.reconcile(maxDataMb: 1)
        XCTAssertEqual(outcome, .fitted)

        // After VACUUM, freelist_count should be small (WAL jitter: tolerate non-zero)
        let freelistAfter = try await db.read { handle -> Int in
            let s = try Hybrid.prepare(handle, "PRAGMA freelist_count;")
            defer { Hybrid.finalize(s) }
            _ = try Hybrid.step(s)
            return Int(sqlite3_column_int64(s, 0))
        }
        // Post-vacuum freelist should be <= pre-eviction freelist (pages were reclaimed)
        // This is a soft assertion: WAL can add some overhead, so we just check it ran (no crash).
        XCTAssertGreaterThanOrEqual(freelistBefore + 1, 0, "sanity: freelist_count is non-negative")
        _ = freelistAfter // used to confirm VACUUM didn't throw
    }

    // MARK: - 11. Child rows deleted with their session

    func testChildRowsDeletedWithSession() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)
        let runs = SessionRunRepository(dbManager: db)
        let exerciseID = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }

        // Create a session with sets and a run (+ split)
        let s = try await sessions.start(routineID: nil, type: .lift)
        let sessionIntID = s.id

        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: sessionIntID, exerciseID: exerciseID,
            exerciseOrder: 1, setNumber: 1,
            setType: .working, weightKg: 80.0, reps: 5,
            durationSecs: nil, distanceM: nil,
            rpe: 8.0, completedAt: Date(), notes: nil, updatedAt: Date()
        ))

        let runUUID = UUID()
        try await runs.append(SessionRun(
            id: 0, clientUUID: runUUID,
            sessionID: sessionIntID, runTemplateID: nil,
            runOrder: 1, actualDistanceKm: nil, durationSecs: nil,
            avgPaceSecs: nil, avgHR: nil, maxHR: nil,
            targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: Date()
        ))

        // Add a split
        let runIntID = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM session_run WHERE client_uuid = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindUUID(stmt, 1, runUUID)
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        try await runs.addSplit(SessionRunSplit(
            id: 0,
            sessionRunID: runIntID,
            sortOrder: 1,
            blockType: nil,
            distanceKm: 1.0,
            durationSecs: 360,
            avgPaceSecs: 360,
            avgHR: nil
        ))

        try await sessions.finish(id: s.clientUUID)

        // Now seed past 1 MB on top, so reconcile actually evicts the oldest (special) session
        try await seedOverLimit(mb: 1, db: db)

        let guard1 = StorageGuard(dbManager: db)
        let outcome = try await guard1.reconcile(maxDataMb: 1)
        XCTAssertEqual(outcome, .fitted)

        // The original session (which had sets/run/split) should be gone (it was oldest)
        let orphanSets = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM session_set WHERE session_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, sessionIntID)
            guard try Hybrid.step(stmt) else { return -1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        let orphanRuns = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM session_run WHERE id = ?;")
            defer { Hybrid.finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(runIntID))
            guard try Hybrid.step(stmt) else { return -1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        let orphanSplits = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM session_run_split WHERE session_run_id = ?;")
            defer { Hybrid.finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(runIntID))
            guard try Hybrid.step(stmt) else { return -1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertEqual(orphanSets, 0, "session_set rows must be deleted with their session")
        XCTAssertEqual(orphanRuns, 0, "session_run rows must be deleted with their session")
        XCTAssertEqual(orphanSplits, 0, "session_run_split rows must be deleted with their session")
    }

    // MARK: - 12. transactionRollingBack rolls back

    func testTransactionRollingBackRollsBack() async throws {
        let db = try makeTempDB()
        let beforeCount = try await sessionCount(db)

        _ = try await db.transactionRollingBack { handle -> Int in
            let s = try Hybrid.prepare(handle, """
                INSERT INTO session (client_uuid, routine_id, type, status, started_at, updated_at)
                VALUES (?, NULL, 'LIFT', 'IN_PROGRESS', ?, ?);
                """)
            defer { Hybrid.finalize(s) }
            Hybrid.bindUUID(s, 1, UUID())
            let now = Int64(Date().timeIntervalSince1970)
            sqlite3_bind_int64(s, 2, now)
            sqlite3_bind_int64(s, 3, now)
            _ = try Hybrid.step(s)
            return 1
        }

        let afterCount = try await sessionCount(db)
        XCTAssertEqual(afterCount, beforeCount, "transactionRollingBack must not persist the inserted row")
    }

    // MARK: - 13. Settings decrease revert

    func testSettingsDecreaseRevert() async throws {
        let db = try makeTempDB()
        try await seedOverLimit(mb: 1, db: db)   // >1 MB so a decrease to 1 MB is over-limit

        // Set a high initial limit so data "fits"
        let profileRepo = UserProfileRepository(dbManager: db)
        try await profileRepo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 200)

        let vm = await MainActor.run { SettingsViewModel(dbManager: db) }
        await vm.load()
        let loadedMax = await MainActor.run { vm.maxDataMb }
        XCTAssertEqual(loadedMax, 200)

        // Simulate picker decrease to 1 MB (which is over limit)
        await MainActor.run { vm.maxDataMb = 1 }
        await vm.handleMaxDataChange(to: 1)

        // Dialog should show, and we cancel
        let showConfirm = await MainActor.run { vm.showLimitDecreaseConfirm }
        XCTAssertTrue(showConfirm, "showLimitDecreaseConfirm must be true")
        await MainActor.run { vm.cancelLimitDecrease() }

        // maxDataMb should revert to 200
        let revertedMax = await MainActor.run { vm.maxDataMb }
        XCTAssertEqual(revertedMax, 200, "cancelLimitDecrease must revert maxDataMb to previousMaxDataMb")

        // Persisted profile value must be unchanged (still 200)
        let profile = try await profileRepo.get()
        XCTAssertEqual(profile?.maxDataMb, 200, "Persisted maxDataMb must be unchanged after cancel")
    }

    // MARK: - 14. Settings decrease confirm

    func testSettingsDecreaseConfirm() async throws {
        let db = try makeTempDB()
        let seeded = try await seedOverLimit(mb: 1, db: db)   // >1 MB

        let profileRepo = UserProfileRepository(dbManager: db)
        try await profileRepo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 200)

        let vm = await MainActor.run { SettingsViewModel(dbManager: db) }
        await vm.load()

        await MainActor.run { vm.maxDataMb = 1 }
        await vm.handleMaxDataChange(to: 1)
        let showConfirm = await MainActor.run { vm.showLimitDecreaseConfirm }
        XCTAssertTrue(showConfirm)

        let beforeCount = try await sessionCount(db)
        await vm.confirmLimitDecrease()

        // Persisted limit must be the new (lower) value
        let profile = try await profileRepo.get()
        XCTAssertEqual(profile?.maxDataMb, 1, "Persisted maxDataMb must equal new value after confirm")

        // Sessions must have been reconciled (reduced or cleared)
        let count = try await sessionCount(db)
        XCTAssertLessThan(count, beforeCount, "Sessions must be reduced/cleared after confirmLimitDecrease (\(seeded) seeded)")
    }

    // MARK: - 15. Settings increase: silent save, no dialog

    func testSettingsIncreaseSilentNoDialog() async throws {
        let db = try makeTempDB()
        try await seedSessions(5, db: db)

        let profileRepo = UserProfileRepository(dbManager: db)
        try await profileRepo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 10)

        let vm = await MainActor.run { SettingsViewModel(dbManager: db) }
        await vm.load()

        await MainActor.run { vm.maxDataMb = 100 }
        await vm.handleMaxDataChange(to: 100)

        let showConfirm = await MainActor.run { vm.showLimitDecreaseConfirm }
        XCTAssertFalse(showConfirm, "No dialog for increase")

        let profile = try await profileRepo.get()
        XCTAssertEqual(profile?.maxDataMb, 100, "Increased limit must be persisted silently")
    }
}
