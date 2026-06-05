import XCTest
import SQLite3
@testable import Hybrid

/// Pass 5 — Delete routine, delete-all-history, Muscle enum seed parity.
final class Pass5DeletesTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass5-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    private func activeRoutineCount(_ db: DatabaseManager) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM routine WHERE deleted_at IS NULL;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    private func countRows(_ db: DatabaseManager, sql: String) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, sql)
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    private func anyExerciseID(_ db: DatabaseManager) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    private func anyRunTemplateID(_ db: DatabaseManager) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM run_template WHERE is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    // MARK: - 1. Delete-routine removes routine + children and decrements active count

    func testDeleteRoutineRemovesRoutineAndChildren() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)

        let exerciseID = try await anyExerciseID(db)
        let runTemplateID = try await anyRunTemplateID(db)

        let beforeCount = try await activeRoutineCount(db)

        let now = Date()
        let routine = Routine(
            id: 0, clientUUID: UUID(), name: "Delete Test Routine",
            type: .mixed, sortOrder: 99,
            createdAt: now, updatedAt: now, deletedAt: nil
        )
        let re = RoutineExercise(
            id: 0, clientUUID: UUID(), routineID: 0,
            exerciseID: exerciseID, sortOrder: 1,
            targetSets: nil, targetRepMin: nil, targetRepMax: nil,
            targetRPE: nil, targetDurationSecsMin: nil,
            targetDurationSecsMax: nil, notes: nil, updatedAt: now
        )
        let rr = RoutineRun(
            id: 0, clientUUID: UUID(), routineID: 0,
            runTemplateID: runTemplateID,
            sortOrder: 1, notes: nil, updatedAt: now
        )
        try await routineRepo.create(routine, exerciseEntries: [re], runEntries: [rr])

        let afterCreateCount = try await activeRoutineCount(db)
        XCTAssertEqual(afterCreateCount, beforeCount + 1, "active count must increment after create()")

        // Find the created routine to get its integer id
        let routines = try await routineRepo.list()
        let created = try XCTUnwrap(routines.first { $0.name == "Delete Test Routine" })

        // Verify child rows exist
        let exCount = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM routine_exercise WHERE routine_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, created.id)
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertGreaterThan(exCount, 0, "routine_exercise rows must exist before delete")

        let runCount = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM routine_run WHERE routine_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, created.id)
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertGreaterThan(runCount, 0, "routine_run rows must exist before delete")

        // Hard-delete
        try await routineRepo.delete(clientUUID: created.clientUUID)

        // get(id:) returns nil
        let fetched = try await routineRepo.get(id: created.clientUUID)
        XCTAssertNil(fetched, "get(id:) must return nil after hard-delete")

        // routine_exercise rows for this routine_id are gone
        let exCountAfter = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM routine_exercise WHERE routine_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, created.id)
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertEqual(exCountAfter, 0, "routine_exercise rows must be gone after hard-delete")

        // routine_run rows for this routine_id are gone
        let runCountAfter = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM routine_run WHERE routine_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, created.id)
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertEqual(runCountAfter, 0, "routine_run rows must be gone after hard-delete")

        // active count decremented back
        let afterDeleteCount = try await activeRoutineCount(db)
        XCTAssertEqual(afterDeleteCount, beforeCount,
            "active count must decrement back to pre-create value after hard-delete")
    }

    // MARK: - 2. Delete-all-history zeroes sessions but keeps routines/exercises/profile

    func testDeleteAllHistoryZeroesSessionsKeepsOther() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)
        let sessionsRepo = SessionRepository(dbManager: db)
        let setsRepo = SessionSetRepository(dbManager: db)
        let runsRepo = SessionRunRepository(dbManager: db)
        let guard1 = StorageGuard(dbManager: db)

        // Create a routine (ensures routines are non-zero after delete-all-history)
        let exerciseID = try await anyExerciseID(db)
        let now = Date()
        let routine = Routine(
            id: 0, clientUUID: UUID(), name: "History Test Routine",
            type: .lift, sortOrder: 88,
            createdAt: now, updatedAt: now, deletedAt: nil
        )
        let re = RoutineExercise(
            id: 0, clientUUID: UUID(), routineID: 0,
            exerciseID: exerciseID, sortOrder: 1,
            targetSets: nil, targetRepMin: nil, targetRepMax: nil,
            targetRPE: nil, targetDurationSecsMin: nil,
            targetDurationSecsMax: nil, notes: nil, updatedAt: now
        )
        try await routineRepo.create(routine, exerciseEntries: [re], runEntries: [])

        // Insert a session
        let session = try await sessionsRepo.start(routineID: nil, type: .lift)

        // Insert a session_set row
        try await setsRepo.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: exerciseID,
            exerciseOrder: 1, setNumber: 1,
            setType: .working, weightKg: 60.0, reps: 10,
            durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: now, notes: nil, updatedAt: now
        ))

        // Insert a session_run row; capture its integer id for the split
        let runUUID = UUID()
        try await runsRepo.append(SessionRun(
            id: 0, clientUUID: runUUID,
            sessionID: session.id, runTemplateID: nil,
            runOrder: 1, actualDistanceKm: 5.0,
            durationSecs: 1800, avgPaceSecs: nil,
            avgHR: nil, maxHR: nil,
            targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: now
        ))
        let runRowID = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM session_run WHERE client_uuid = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindUUID(stmt, 1, runUUID)
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }

        // Insert a session_run_split row (references the run's integer id)
        try await runsRepo.addSplit(SessionRunSplit(
            id: 0, sessionRunID: runRowID, sortOrder: 1,
            blockType: nil, distanceKm: 1.0,
            durationSecs: 360, avgPaceSecs: nil, avgHR: nil
        ))

        // Insert a session_tag row directly via SQL (no TagRepository helper)
        try await db.transaction { handle in
            let stmt = try Hybrid.prepare(handle,
                "INSERT INTO session_tag (session_id, tag_id) VALUES (?, 1);")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, session.id)
            _ = try Hybrid.step(stmt)
        }

        // Precondition: all 5 tables are populated
        let sessionCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM session;")
        XCTAssertGreaterThan(sessionCountBefore, 0, "Precondition: session must exist before delete-all-history")

        let setCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM session_set;")
        XCTAssertGreaterThan(setCountBefore, 0, "Precondition: session_set must exist before delete-all-history")

        let runCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM session_run;")
        XCTAssertGreaterThan(runCountBefore, 0, "Precondition: session_run must exist before delete-all-history")

        let splitCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM session_run_split;")
        XCTAssertGreaterThan(splitCountBefore, 0, "Precondition: session_run_split must exist before delete-all-history")

        let tagCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM session_tag;")
        XCTAssertGreaterThan(tagCountBefore, 0, "Precondition: session_tag must exist before delete-all-history")

        // Snapshot counts of tables that must be preserved
        let routineCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM routine WHERE deleted_at IS NULL;")
        let exerciseCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise WHERE is_custom = 0;")
        // user_profile starts empty on a fresh DB (created on first save, not seeded);
        // snapshot it so we can confirm deleteAllHistory() leaves it unchanged.
        let profileCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM user_profile;")

        XCTAssertGreaterThan(routineCountBefore, 0, "Precondition: routines must exist")
        XCTAssertGreaterThan(exerciseCountBefore, 0, "Precondition: seeded exercises must exist")

        // Delete all history
        try await guard1.deleteAllHistory()

        // All 5 session tables must be empty
        let sessionCountAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM session;")
        XCTAssertEqual(sessionCountAfter, 0, "session must be empty after deleteAllHistory()")

        let sessionSetAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM session_set;")
        XCTAssertEqual(sessionSetAfter, 0, "session_set must be empty after deleteAllHistory()")

        let sessionRunAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM session_run;")
        XCTAssertEqual(sessionRunAfter, 0, "session_run must be empty after deleteAllHistory()")

        let sessionRunSplitAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM session_run_split;")
        XCTAssertEqual(sessionRunSplitAfter, 0, "session_run_split must be empty after deleteAllHistory()")

        let sessionTagAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM session_tag;")
        XCTAssertEqual(sessionTagAfter, 0, "session_tag must be empty after deleteAllHistory()")

        // Preserved tables unchanged
        let routineCountAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM routine WHERE deleted_at IS NULL;")
        XCTAssertEqual(routineCountAfter, routineCountBefore,
            "routine count must be unchanged after deleteAllHistory()")

        let exerciseCountAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise WHERE is_custom = 0;")
        XCTAssertEqual(exerciseCountAfter, exerciseCountBefore,
            "seeded exercise count must be unchanged after deleteAllHistory()")

        let profileCountAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM user_profile;")
        XCTAssertEqual(profileCountAfter, profileCountBefore,
            "user_profile count must be unchanged after deleteAllHistory()")
    }

    // MARK: - 5. Delete-routine preserves session history via ON DELETE SET NULL

    func testDeleteRoutinePreservesLinkedSession() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)
        let sessionsRepo = SessionRepository(dbManager: db)

        let exerciseID = try await anyExerciseID(db)
        let runTemplateID = try await anyRunTemplateID(db)
        let now = Date()

        // Create a routine
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "ON DELETE SET NULL Routine",
            type: .mixed, sortOrder: 77,
            createdAt: now, updatedAt: now, deletedAt: nil
        )
        let re = RoutineExercise(
            id: 0, clientUUID: UUID(), routineID: 0,
            exerciseID: exerciseID, sortOrder: 1,
            targetSets: nil, targetRepMin: nil, targetRepMax: nil,
            targetRPE: nil, targetDurationSecsMin: nil,
            targetDurationSecsMax: nil, notes: nil, updatedAt: now
        )
        let rr = RoutineRun(
            id: 0, clientUUID: UUID(), routineID: 0,
            runTemplateID: runTemplateID,
            sortOrder: 1, notes: nil, updatedAt: now
        )
        try await routineRepo.create(routine, exerciseEntries: [re], runEntries: [rr])

        // Start a session that references the routine
        let session = try await sessionsRepo.start(routineID: routineUUID, type: .mixed)

        // Precondition: session.routine_id is set (non-NULL)
        let routineIDBeforeDelete = try await db.read { handle -> Bool in
            let stmt = try Hybrid.prepare(handle,
                "SELECT routine_id FROM session WHERE id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, session.id)
            guard try Hybrid.step(stmt) else { return false }
            // routine_id column should be non-NULL
            return sqlite3_column_type(stmt, 0) != SQLITE_NULL
        }
        XCTAssertTrue(routineIDBeforeDelete, "Precondition: session.routine_id must be set before routine delete")

        // Hard-delete the routine
        try await routineRepo.delete(clientUUID: routineUUID)

        // Session row must still exist
        let sessionCount = try await countRows(db, sql: "SELECT COUNT(*) FROM session WHERE id = \(session.id);")
        XCTAssertEqual(sessionCount, 1, "Session row must survive after routine hard-delete")

        // session.routine_id must now be NULL (ON DELETE SET NULL)
        let routineIDAfterDelete = try await db.read { handle -> Bool in
            let stmt = try Hybrid.prepare(handle,
                "SELECT routine_id FROM session WHERE id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, session.id)
            guard try Hybrid.step(stmt) else { return true }
            return sqlite3_column_type(stmt, 0) != SQLITE_NULL
        }
        XCTAssertFalse(routineIDAfterDelete, "session.routine_id must be NULL after routine hard-delete (ON DELETE SET NULL)")
    }

    // MARK: - 3. Muscle enum raw values map to the same IDs / seed parity

    func testSeedMuscleEnumRawValues() {
        XCTAssertEqual(SeedMuscle.chest.rawValue, 1)
        XCTAssertEqual(SeedMuscle.back.rawValue, 2)
        XCTAssertEqual(SeedMuscle.lats.rawValue, 3)
        XCTAssertEqual(SeedMuscle.shoulders.rawValue, 4)
        XCTAssertEqual(SeedMuscle.biceps.rawValue, 5)
        XCTAssertEqual(SeedMuscle.triceps.rawValue, 6)
        XCTAssertEqual(SeedMuscle.quads.rawValue, 7)
        XCTAssertEqual(SeedMuscle.hamstrings.rawValue, 8)
        XCTAssertEqual(SeedMuscle.glutes.rawValue, 9)
        XCTAssertEqual(SeedMuscle.calves.rawValue, 10)
        XCTAssertEqual(SeedMuscle.core.rawValue, 11)
        XCTAssertEqual(SeedMuscle.posteriorChain.rawValue, 12)
        XCTAssertEqual(SeedMuscle.upperChest.rawValue, 13)
        XCTAssertEqual(SeedMuscle.obliques.rawValue, 14)
        XCTAssertEqual(SeedMuscle.forearms.rawValue, 15)
        XCTAssertEqual(SeedMuscle.hipFlexors.rawValue, 16)
    }

    func testSeedParityExerciseMuscleRows() async throws {
        let db = try makeTempDB()

        // Total exercise_muscle row count: sum of all primaries + secondaries from the spec table.
        // Primaries: 35 exercises × 1 each + 3 extras (ex27=2, ex28=2 → +2 extra) = 35 + 2 = 37
        // Secondaries: count from spec table:
        // ex1=2, ex2=2, ex3=3, ex4=1, ex5=2, ex6=1, ex7=2, ex8=2, ex9=1, ex10=1,
        // ex11=1, ex12=1, ex13=0, ex14=0, ex15=0, ex16=0, ex17=0, ex18=0, ex19=0, ex20=0,
        // ex21=1, ex22=1, ex23=1, ex24=2, ex25=2, ex26=2, ex27=1, ex28=1, ex29=0, ex30=0,
        // ex31=1, ex32=1, ex33=1, ex34=1, ex35=3
        // = 2+2+3+1+2+1+2+2+1+1+1+1+0+0+0+0+0+0+0+0+1+1+1+2+2+2+1+1+0+0+1+1+1+1+3 = 37
        // Total = 37 (primary) + 37 (secondary) = 74
        let totalCount = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle;")
        XCTAssertEqual(totalCount, 74, "Total exercise_muscle rows must be 74 (37 PRIMARY + 37 SECONDARY)")

        // Spot-check ex 35: (35,7,PRIMARY), (35,8,SECONDARY), (35,9,SECONDARY), (35,10,SECONDARY)
        let ex35Primary = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle WHERE exercise_id = 35 AND muscle_id = 7 AND role = 'PRIMARY';")
        XCTAssertEqual(ex35Primary, 1, "ex35 must have muscle_id=7 PRIMARY")

        let ex35Sec8 = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle WHERE exercise_id = 35 AND muscle_id = 8 AND role = 'SECONDARY';")
        XCTAssertEqual(ex35Sec8, 1, "ex35 must have muscle_id=8 SECONDARY")

        let ex35Sec9 = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle WHERE exercise_id = 35 AND muscle_id = 9 AND role = 'SECONDARY';")
        XCTAssertEqual(ex35Sec9, 1, "ex35 must have muscle_id=9 SECONDARY")

        let ex35Sec10 = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle WHERE exercise_id = 35 AND muscle_id = 10 AND role = 'SECONDARY';")
        XCTAssertEqual(ex35Sec10, 1, "ex35 must have muscle_id=10 SECONDARY")

        // Spot-check ex 3: (3,12,PRIMARY), (3,8,SECONDARY), (3,9,SECONDARY), (3,2,SECONDARY)
        let ex3Primary = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle WHERE exercise_id = 3 AND muscle_id = 12 AND role = 'PRIMARY';")
        XCTAssertEqual(ex3Primary, 1, "ex3 must have muscle_id=12 PRIMARY")

        let ex3Sec8 = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle WHERE exercise_id = 3 AND muscle_id = 8 AND role = 'SECONDARY';")
        XCTAssertEqual(ex3Sec8, 1, "ex3 must have muscle_id=8 SECONDARY")

        let ex3Sec9 = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle WHERE exercise_id = 3 AND muscle_id = 9 AND role = 'SECONDARY';")
        XCTAssertEqual(ex3Sec9, 1, "ex3 must have muscle_id=9 SECONDARY")

        let ex3Sec2 = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle WHERE exercise_id = 3 AND muscle_id = 2 AND role = 'SECONDARY';")
        XCTAssertEqual(ex3Sec2, 1, "ex3 must have muscle_id=2 SECONDARY")
    }
}

// MARK: - XCTUnwrap overload for Optional with message (convenience)

private func XCTUnwrap<T>(_ expr: T?, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let v = expr else { throw XCTUnwrapError(message, file: file, line: line) }
    return v
}
private struct XCTUnwrapError: Error, CustomStringConvertible {
    let description: String
    let file: StaticString
    let line: UInt
    init(_ msg: String, file: StaticString, line: UInt) { description = msg; self.file = file; self.line = line }
}
