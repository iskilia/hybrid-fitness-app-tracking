import XCTest
import SQLite3
@testable import Hybrid

/// Pass 3 — Session-tracking tests.
/// Bug #2: weekStats counts only COMPLETED sessions.
/// Bug #1: Home count survives a Settings round-trip.
final class Pass3SessionTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass3-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    /// Raw COMPLETED session count directly from the table.
    private func completedSessionCount(_ db: DatabaseManager) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle,
                "SELECT COUNT(*) FROM session WHERE status = 'COMPLETED';")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    /// weekStart for the current calendar week (mirrors HomeViewModel.load()).
    private func currentWeekStart() -> Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        ) ?? .now
    }

    // MARK: - Bug #2 tests

    func testWeekStatsCountsCompletedSession() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)

        let s = try await sessions.start(routineID: nil, type: .lift)
        try await sessions.finish(id: s.clientUUID)

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.sessionCount, 1, "A COMPLETED session must be counted")
    }

    func testWeekStatsDoesNotCountInProgressSession() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)

        _ = try await sessions.start(routineID: nil, type: .lift)
        // no finish — stays IN_PROGRESS

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.sessionCount, 0, "An IN_PROGRESS session must NOT be counted")
    }

    func testWeekStatsDoesNotCountAbandonedSession() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)

        let s = try await sessions.start(routineID: nil, type: .lift)
        try await sessions.abandon(id: s.clientUUID)

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.sessionCount, 0, "An ABANDONED session must NOT be counted")
    }

    func testWeekStatsDoesNotCountSoftDeletedSession() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)

        let s = try await sessions.start(routineID: nil, type: .lift)
        try await sessions.finish(id: s.clientUUID)

        // Soft-delete directly in the DB
        try await db.transaction { handle in
            let stmt = try Hybrid.prepare(handle,
                "UPDATE session SET deleted_at = ? WHERE client_uuid = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindDate(stmt, 1, Date())
            Hybrid.bindUUID(stmt, 2, s.clientUUID)
            _ = try Hybrid.step(stmt)
        }

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.sessionCount, 0, "A soft-deleted session must NOT be counted")
    }

    func testWeekStatsMixedStatusCount() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)

        // 2 COMPLETED
        let c1 = try await sessions.start(routineID: nil, type: .lift)
        try await sessions.finish(id: c1.clientUUID)
        let c2 = try await sessions.start(routineID: nil, type: .lift)
        try await sessions.finish(id: c2.clientUUID)

        // 1 IN_PROGRESS
        _ = try await sessions.start(routineID: nil, type: .lift)

        // 1 ABANDONED
        let ab = try await sessions.start(routineID: nil, type: .lift)
        try await sessions.abandon(id: ab.clientUUID)

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.sessionCount, 2,
            "Mixed: only 2 COMPLETED sessions must be counted")
    }

    // MARK: - Bug #2: tonnage excludes non-COMPLETED sessions

    func testWeekStatsTonnageExcludesInProgressSets() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)
        let exerciseID = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle,
                "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }

        // IN_PROGRESS session with a set — should not contribute tonnage
        let inProg = try await sessions.start(routineID: nil, type: .lift)
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: inProg.id, exerciseID: exerciseID,
            exerciseOrder: 1, setNumber: 1,
            setType: .working, weightKg: 100.0, reps: 5,
            durationSecs: nil, distanceM: nil,
            rpe: 8.0, completedAt: Date(), notes: nil, updatedAt: Date()
        ))
        // no finish

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.totalTonnageKg, 0.0,
            "Tonnage from an IN_PROGRESS session must be 0")
    }

    func testWeekStatsTonnageExcludesAbandonedSets() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)
        let exerciseID = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle,
                "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }

        // ABANDONED session with a set — should not contribute tonnage
        let ab = try await sessions.start(routineID: nil, type: .lift)
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: ab.id, exerciseID: exerciseID,
            exerciseOrder: 1, setNumber: 1,
            setType: .working, weightKg: 200.0, reps: 3,
            durationSecs: nil, distanceM: nil,
            rpe: 9.0, completedAt: Date(), notes: nil, updatedAt: Date()
        ))
        try await sessions.abandon(id: ab.clientUUID)

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.totalTonnageKg, 0.0,
            "Tonnage from an ABANDONED session must be 0")
    }

    // MARK: - Bug #2: distance excludes non-COMPLETED sessions

    func testWeekStatsDistanceExcludesInProgressRun() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let runs = SessionRunRepository(dbManager: db)

        // IN_PROGRESS session with a run — should not contribute distance
        let inProg = try await sessions.start(routineID: nil, type: .run)
        try await runs.append(SessionRun(
            id: 0, clientUUID: UUID(),
            sessionID: inProg.id, runTemplateID: nil,
            runOrder: 1, actualDistanceKm: 5.0,
            durationSecs: 1800, avgPaceSecs: nil,
            avgHR: nil, maxHR: nil,
            targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: Date()
        ))
        // no finish

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.totalDistanceKm, 0.0,
            "Distance from an IN_PROGRESS session must be 0")
    }

    func testWeekStatsDistanceExcludesAbandonedRun() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let runs = SessionRunRepository(dbManager: db)

        // ABANDONED session with a run — should not contribute distance
        let ab = try await sessions.start(routineID: nil, type: .run)
        try await runs.append(SessionRun(
            id: 0, clientUUID: UUID(),
            sessionID: ab.id, runTemplateID: nil,
            runOrder: 1, actualDistanceKm: 10.0,
            durationSecs: 3600, avgPaceSecs: nil,
            avgHR: nil, maxHR: nil,
            targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: Date()
        ))
        try await sessions.abandon(id: ab.clientUUID)

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.totalDistanceKm, 0.0,
            "Distance from an ABANDONED session must be 0")
    }

    // MARK: - Bug #2: soft-deleted sessions excluded from tonnage + distance

    func testWeekStatsSoftDeletedExcludedFromTonnageAndDistance() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)
        let runs = SessionRunRepository(dbManager: db)
        let exerciseID = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle,
                "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }

        // COMPLETED session with a set + run, then soft-deleted
        let s = try await sessions.start(routineID: nil, type: .lift)
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: s.id, exerciseID: exerciseID,
            exerciseOrder: 1, setNumber: 1,
            setType: .working, weightKg: 100.0, reps: 10,
            durationSecs: nil, distanceM: nil,
            rpe: 7.0, completedAt: Date(), notes: nil, updatedAt: Date()
        ))
        try await runs.append(SessionRun(
            id: 0, clientUUID: UUID(),
            sessionID: s.id, runTemplateID: nil,
            runOrder: 1, actualDistanceKm: 3.0,
            durationSecs: 900, avgPaceSecs: nil,
            avgHR: nil, maxHR: nil,
            targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: Date()
        ))
        try await sessions.finish(id: s.clientUUID)

        // Soft-delete the session
        try await db.transaction { handle in
            let stmt = try Hybrid.prepare(handle,
                "UPDATE session SET deleted_at = ? WHERE client_uuid = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindDate(stmt, 1, Date())
            Hybrid.bindUUID(stmt, 2, s.clientUUID)
            _ = try Hybrid.step(stmt)
        }

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.totalTonnageKg, 0.0,
            "Soft-deleted session must NOT contribute to tonnage")
        XCTAssertEqual(stats.totalDistanceKm, 0.0,
            "Soft-deleted session must NOT contribute to distance")
    }

    // MARK: - Bug #2: full matrix — COMPLETED session contributes to all three outputs

    func testWeekStatsCompletedContributesToTonnageAndDistance() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)
        let runs = SessionRunRepository(dbManager: db)
        let exerciseID = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle,
                "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }

        // COMPLETED session — set 80 kg × 5 reps + run 4.0 km
        let c = try await sessions.start(routineID: nil, type: .lift)
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: c.id, exerciseID: exerciseID,
            exerciseOrder: 1, setNumber: 1,
            setType: .working, weightKg: 80.0, reps: 5,
            durationSecs: nil, distanceM: nil,
            rpe: 7.0, completedAt: Date(), notes: nil, updatedAt: Date()
        ))
        try await runs.append(SessionRun(
            id: 0, clientUUID: UUID(),
            sessionID: c.id, runTemplateID: nil,
            runOrder: 1, actualDistanceKm: 4.0,
            durationSecs: 1200, avgPaceSecs: nil,
            avgHR: nil, maxHR: nil,
            targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: Date()
        ))
        try await sessions.finish(id: c.clientUUID)

        // Also seed an ABANDONED session with sets+run that must NOT contribute
        let ab = try await sessions.start(routineID: nil, type: .lift)
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: ab.id, exerciseID: exerciseID,
            exerciseOrder: 1, setNumber: 1,
            setType: .working, weightKg: 150.0, reps: 10,
            durationSecs: nil, distanceM: nil,
            rpe: 9.0, completedAt: Date(), notes: nil, updatedAt: Date()
        ))
        try await runs.append(SessionRun(
            id: 0, clientUUID: UUID(),
            sessionID: ab.id, runTemplateID: nil,
            runOrder: 1, actualDistanceKm: 99.0,
            durationSecs: 9999, avgPaceSecs: nil,
            avgHR: nil, maxHR: nil,
            targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: Date()
        ))
        try await sessions.abandon(id: ab.clientUUID)

        // Also seed an IN_PROGRESS session with sets+run that must NOT contribute
        let ip = try await sessions.start(routineID: nil, type: .lift)
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: ip.id, exerciseID: exerciseID,
            exerciseOrder: 1, setNumber: 1,
            setType: .working, weightKg: 200.0, reps: 10,
            durationSecs: nil, distanceM: nil,
            rpe: 9.0, completedAt: Date(), notes: nil, updatedAt: Date()
        ))
        try await runs.append(SessionRun(
            id: 0, clientUUID: UUID(),
            sessionID: ip.id, runTemplateID: nil,
            runOrder: 1, actualDistanceKm: 88.0,
            durationSecs: 8888, avgPaceSecs: nil,
            avgHR: nil, maxHR: nil,
            targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: Date()
        ))
        // no finish (remains IN_PROGRESS)

        let stats = try await sessions.weekStats(weekStart: currentWeekStart())
        XCTAssertEqual(stats.sessionCount, 1,
            "Only 1 COMPLETED session in window")
        XCTAssertEqual(stats.totalTonnageKg, 400.0,
            "Tonnage must reflect only the COMPLETED session: 80 × 5 = 400 kg")
        XCTAssertEqual(stats.totalDistanceKm, 4.0,
            "Distance must reflect only the COMPLETED session: 4.0 km")
    }

    // MARK: - Bug #1 eviction-on-open probe

    func testSettingsOpenDoesNotEvictSessions() async throws {
        let db = try makeTempDB()
        let profileRepo = UserProfileRepository(dbManager: db)

        // Persist a small limit (1 MB) so the over-limit check in handleMaxDataChange
        // would matter if called with a stale previousMaxDataMb
        try await profileRepo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 1)

        // Seed enough sessions to exceed 1 MB so isOverLimit(maxDataMb:1) == true
        let guard1 = StorageGuard(dbManager: db)
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)
        let exerciseID = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle,
                "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        // Seed in batches until over the 1 MB limit
        var seeded = 0
        repeat {
            for _ in 0..<150 {
                let s = try await sessions.start(routineID: nil, type: .lift)
                for k in 1...5 {
                    try await sets.append(SessionSet(
                        id: 0, clientUUID: UUID(),
                        sessionID: s.id, exerciseID: exerciseID,
                        exerciseOrder: 1, setNumber: k,
                        setType: .working, weightKg: 80.0, reps: 5,
                        durationSecs: nil, distanceM: nil,
                        rpe: 8.0, completedAt: Date(), notes: nil, updatedAt: Date()
                    ))
                }
                try await sessions.finish(id: s.clientUUID)
            }
            seeded += 150
        } while try await db.read({ try guard1.logicalSizeBytes($0) }) <= 1_048_576 && seeded < 4500

        let countBefore = try await completedSessionCount(db)
        XCTAssertGreaterThan(countBefore, 0, "Precondition: sessions were seeded")

        // Instantiate SettingsViewModel and call load() — this is what opening Settings does.
        // At this point load() sets maxDataMb = 1 AND previousMaxDataMb = 1 synchronously,
        // so a subsequent handleMaxDataChange(to: 1) must see newValue >= old and NOT evict.
        let vm = await MainActor.run { SettingsViewModel(dbManager: db) }
        await vm.load()

        // Simulate the .onChange(of: maxDataMb) firing with the loaded value — the eviction
        // suspect path. If previousMaxDataMb was still 10 (the default) when this fires,
        // 1 < 10 and the DB is over limit, so eviction would run. The fix is that load()
        // sets previousMaxDataMb = 1 BEFORE (or at the same time as) maxDataMb = 1.
        let loadedValue = await MainActor.run { vm.maxDataMb }
        await vm.handleMaxDataChange(to: loadedValue)

        // Assert no dialog was raised (would indicate the decrease path was NOT triggered)
        let confirmShown = await MainActor.run { vm.showLimitDecreaseConfirm }
        XCTAssertFalse(confirmShown,
            "showLimitDecreaseConfirm must be false: simulated .onChange on load must not trigger the eviction dialog")

        // Assert no sessions were deleted
        let countAfter = try await completedSessionCount(db)
        XCTAssertEqual(countAfter, countBefore,
            "Session count must be unchanged: simulated Settings open must not evict sessions")
    }

    // MARK: - Bug #1 reproduction test

    func testHomeCountSurvivesSettingsRoundTrip() async throws {
        let db = try makeTempDB()

        // Persist a profile so Settings load is realistic
        let profileRepo = UserProfileRepository(dbManager: db)
        try await profileRepo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 10)

        // Start + finish one session dated now (lands in current week)
        let sessions = SessionRepository(dbManager: db)
        let s = try await sessions.start(routineID: nil, type: .lift)
        try await sessions.finish(id: s.clientUUID)

        // Sanity: raw table has 1 completed session
        let rawBefore = try await completedSessionCount(db)
        XCTAssertEqual(rawBefore, 1, "Precondition: 1 completed session in table")

        // Load Home and assert count = 1
        let home = await MainActor.run { HomeViewModel(dbManager: db) }
        await home.load()
        let count1 = await MainActor.run { home.stats?.sessionCount }
        XCTAssertEqual(count1, 1, "Home must see 1 session before Settings round-trip")

        // Settings round-trip (the only part XCTest can drive — .onChange does NOT fire here)
        let settings = await MainActor.run { SettingsViewModel(dbManager: db) }
        await settings.load()

        // Sanity: raw table still has 1 completed session after Settings load
        let rawAfter = try await completedSessionCount(db)
        XCTAssertEqual(rawAfter, 1,
            "Settings.load() must not delete sessions (raw table count unchanged)")

        // Re-instantiate + reload Home (mirrors returning to a fresh .task)
        let home2 = await MainActor.run { HomeViewModel(dbManager: db) }
        await home2.load()
        let count2 = await MainActor.run { home2.stats?.sessionCount }
        XCTAssertEqual(count2, 1,
            "Home count must still be 1 after Settings round-trip")
    }

    /// Bug #1 root cause: the rendered HomeViewModel must be RETAINED across a Settings
    /// round-trip, not rebuilt. The real defect lived in RootView, which minted a fresh
    /// HomeViewModel (stats == nil → count 0) on every body re-evaluation; pushing/popping
    /// Settings mutates router.path and re-runs body. The fix holds the VM in @State.
    ///
    /// XCTest can't render RootView or fire `.task`, so it can't observe the binding swap.
    /// What it CAN guard: a retained HomeViewModel keeps its loaded stats across a Settings
    /// round-trip WITHOUT a reload — the invariant the @State ownership provides. The actual
    /// view-binding behaviour is verified manually per .pipeline/debug-bug1.md.
    func testRetainedHomeViewModelKeepsCountAcrossSettingsRoundTrip() async throws {
        let db = try makeTempDB()

        let profileRepo = UserProfileRepository(dbManager: db)
        try await profileRepo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 10)

        let sessions = SessionRepository(dbManager: db)
        let s = try await sessions.start(routineID: nil, type: .lift)
        try await sessions.finish(id: s.clientUUID)

        // Load Home once and capture the instance — this is the @State-owned VM.
        let home = await MainActor.run { HomeViewModel(dbManager: db) }
        await home.load()
        let countBefore = await MainActor.run { home.stats?.sessionCount }
        XCTAssertEqual(countBefore, 1, "Precondition: retained Home sees 1 session")

        // Settings round-trip.
        let settings = await MainActor.run { SettingsViewModel(dbManager: db) }
        await settings.load()

        // Same instance, no reload: stats must persist (would be nil → 0 on a fresh VM).
        let count = await MainActor.run { home.stats?.sessionCount }
        XCTAssertEqual(count, 1,
            "Retained Home VM must keep its count without reloading after a Settings round-trip")
    }
}
