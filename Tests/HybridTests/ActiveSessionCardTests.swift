import XCTest
import SQLite3
@testable import Hybrid

/// Pass 7 — Sessions feedback: typed run entry, unified lift card, empty history state.
@MainActor
final class ActiveSessionCardTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass7-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
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

    private func makeExercise(id: Int, db: DatabaseManager) async throws -> Exercise {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, """
                SELECT id, client_uuid, name, abbreviation, equipment_id, metric_type,
                       is_custom, notes, form_link, created_at, updated_at, deleted_at
                FROM exercise WHERE id = ?;
                """)
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, id)
            guard try Hybrid.step(stmt) else { throw DatabaseError.notFound }
            guard
                let uuidStr = Hybrid.columnText(stmt, 1),
                let uuid = UUID(uuidString: uuidStr),
                let name = Hybrid.columnText(stmt, 2),
                let abbr = Hybrid.columnText(stmt, 3),
                let metricRaw = Hybrid.columnText(stmt, 5),
                let metric = MetricType(rawValue: metricRaw),
                let createdAt = Hybrid.columnDate(stmt, 9),
                let updatedAt = Hybrid.columnDate(stmt, 10)
            else { throw DatabaseError.stepFailed("exercise row mapping failed") }
            return Exercise(
                id: Int(sqlite3_column_int64(stmt, 0)),
                clientUUID: uuid,
                name: name,
                abbreviation: abbr,
                equipmentID: Int(sqlite3_column_int64(stmt, 4)),
                metricType: metric,
                isCustom: sqlite3_column_int(stmt, 6) != 0,
                notes: Hybrid.columnText(stmt, 7),
                formLink: Hybrid.columnText(stmt, 8),
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: Hybrid.columnDate(stmt, 11)
            )
        }
    }

    // MARK: - Item 3: Run typed-entry persists on finish

    /// Type distance + HR WITHOUT any stepper button. finish() must commit values to session_run.
    func testRunTypedEntryPersistsOnFinish() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)

        let session = try await sessionRepo.start(routineID: nil, type: .run)

        let vm = RunActiveSessionViewModel(dbManager: db)
        await vm.start(sessionID: session.clientUUID)

        // Type values without calling any stepper
        vm.distanceText = "5.25"
        vm.hrText = "162"

        await vm.finish()

        // Assert session_run row has the typed values
        let result = try await db.read { handle -> (Double?, Int?) in
            let stmt = try Hybrid.prepare(handle, """
                SELECT actual_distance_km, avg_hr
                FROM session_run
                WHERE session_id = ?;
                """)
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, session.id)
            guard try Hybrid.step(stmt) else { return (nil, nil) }
            let dist: Double? = sqlite3_column_type(stmt, 0) != SQLITE_NULL
                ? sqlite3_column_double(stmt, 0) : nil
            let hr: Int? = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                ? Int(sqlite3_column_int64(stmt, 1)) : nil
            return (dist, hr)
        }
        XCTAssertNotNil(result.0, "actual_distance_km must not be nil")
        XCTAssertEqual(result.0 ?? 0, 5.25, accuracy: 0.001,
            "actual_distance_km must be 5.25 from typed distanceText")
        XCTAssertEqual(result.1, 162,
            "avg_hr must be 162 from typed hrText")
    }

    // MARK: - Item 3: Blank/invalid typed metrics are safe

    func testRunBlankOrInvalidTypedMetricsAreSafe() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)

        let session = try await sessionRepo.start(routineID: nil, type: .run)

        let vm = RunActiveSessionViewModel(dbManager: db)
        await vm.start(sessionID: session.clientUUID)

        // Leave distanceText empty; set hrText to garbage
        vm.distanceText = ""
        vm.hrText = "abc"

        // Must not crash
        await vm.finish()

        let result = try await db.read { handle -> (Double?, Bool) in
            let stmt = try Hybrid.prepare(handle, """
                SELECT actual_distance_km, avg_hr IS NULL
                FROM session_run
                WHERE session_id = ?;
                """)
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, session.id)
            guard try Hybrid.step(stmt) else { return (nil, true) }
            let dist: Double? = sqlite3_column_type(stmt, 0) != SQLITE_NULL
                ? sqlite3_column_double(stmt, 0) : nil
            let hrIsNull = sqlite3_column_int(stmt, 1) != 0
            return (dist, hrIsNull)
        }
        // blank distance leaves distanceKm at 0.0 default
        XCTAssertEqual(result.0 ?? 0.0, 0.0, accuracy: 0.001,
            "actual_distance_km must be 0.0 when distanceText is blank")
        XCTAssertTrue(result.1,
            "avg_hr must be NULL when hrText is invalid/blank")
    }

    // MARK: - Item 2: Unified lift screen still flushes typed-but-unchecked sets

    func testUnifiedLiftCardFlushesTypedButUncheckedSets() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)
        let sessionSetRepo = SessionSetRepository(dbManager: db)

        let exerciseID = try await anyExerciseID(db)
        let exercise = try await makeExercise(id: exerciseID, db: db)
        let routineRepo = RoutineRepository(dbManager: db)
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "Pass7 Flush Test",
            type: .lift, sortOrder: 1,
            createdAt: now, updatedAt: now, deletedAt: nil
        )
        let re = RoutineExercise(
            id: 0, clientUUID: UUID(), routineID: 0,
            exerciseID: exercise.id, sortOrder: 1,
            targetSets: 1, targetRepMin: nil, targetRepMax: nil,
            targetRPE: nil, targetDurationSecsMin: nil,
            targetDurationSecsMax: nil, notes: nil, updatedAt: now
        )
        try await routineRepo.create(routine, exerciseEntries: [re], runEntries: [])

        let session = try await sessionRepo.start(routineID: routineUUID, type: .lift)
        let vm = LiftActiveSessionViewModel(sessionID: session.clientUUID, dbManager: db)
        await vm.load()

        XCTAssertGreaterThan(vm.cards.count, 0, "Precondition: VM must load at least one card")
        let card = vm.cards[0]
        XCTAssertFalse(card.rows.isEmpty, "Precondition: card must have at least one row")
        let row = card.rows[0]
        row.weightText = "60"
        row.repsText = "5"
        // isCompleted stays false — data-loss scenario

        let setsBefore = try await countRows(db,
            sql: "SELECT COUNT(*) FROM session_set WHERE session_id = \(session.id);")
        XCTAssertEqual(setsBefore, 0, "Precondition: no session_set rows before persistAllRows()")

        await vm.persistAllRows()

        let setsAfter = try await countRows(db,
            sql: "SELECT COUNT(*) FROM session_set WHERE session_id = \(session.id);")
        XCTAssertGreaterThan(setsAfter, 0,
            "session_set rows must be written by persistAllRows() even when isCompleted=false")

        _ = await vm.finishAndCheckStorage()
        let history = try await sessionSetRepo.historyByExercise(
            exerciseID: exercise.clientUUID, monthsBack: 12)
        XCTAssertFalse(history.isEmpty,
            "historyByExercise must return the typed set after persistAllRows() + finish")
    }

    private func twoDistinctExerciseIDs(_ db: DatabaseManager) async throws -> (Int, Int) {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle,
                "SELECT id FROM exercise WHERE is_custom = 0 ORDER BY id LIMIT 2;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { throw DatabaseError.notFound }
            let id1 = Int(sqlite3_column_int64(stmt, 0))
            guard try Hybrid.step(stmt) else { return (id1, id1) }
            let id2 = Int(sqlite3_column_int64(stmt, 0))
            return (id1, id2)
        }
    }

    // MARK: - Item 2: markCardDone persists and advances

    func testMarkCardDonePersistsAndAdvances() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)

        // Create a routine with 2 distinct exercises so VM builds 2 distinct cards
        let (ex1ID, ex2ID) = try await twoDistinctExerciseIDs(db)
        let exercise1 = try await makeExercise(id: ex1ID, db: db)
        let routineRepo = RoutineRepository(dbManager: db)
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "Pass7 MarkDone Test",
            type: .lift, sortOrder: 1,
            createdAt: now, updatedAt: now, deletedAt: nil
        )
        let re1 = RoutineExercise(
            id: 0, clientUUID: UUID(), routineID: 0,
            exerciseID: ex1ID, sortOrder: 1,
            targetSets: 1, targetRepMin: nil, targetRepMax: nil,
            targetRPE: nil, targetDurationSecsMin: nil,
            targetDurationSecsMax: nil, notes: nil, updatedAt: now
        )
        let re2 = RoutineExercise(
            id: 0, clientUUID: UUID(), routineID: 0,
            exerciseID: ex2ID, sortOrder: 2,
            targetSets: 1, targetRepMin: nil, targetRepMax: nil,
            targetRPE: nil, targetDurationSecsMin: nil,
            targetDurationSecsMax: nil, notes: nil, updatedAt: now
        )
        let entries: [RoutineExercise] = ex1ID == ex2ID ? [re1] : [re1, re2]
        try await routineRepo.create(routine, exerciseEntries: entries, runEntries: [])

        let session = try await sessionRepo.start(routineID: routineUUID, type: .lift)
        let vm = LiftActiveSessionViewModel(sessionID: session.clientUUID, dbManager: db)
        await vm.load()

        XCTAssertGreaterThan(vm.cards.count, 0, "Precondition: VM must load at least one card")
        let card0 = vm.cards[0]
        card0.rows[0].weightText = "80"
        card0.rows[0].repsText = "5"

        await vm.markCardDone(card0, exerciseOrder: 1)

        XCTAssertTrue(vm.doneCardIDs.contains(card0.id),
            "doneCardIDs must contain card0 after markCardDone")

        // session_set rows must exist
        let setsCount = try await countRows(db,
            sql: "SELECT COUNT(*) FROM session_set WHERE session_id = \(session.id);")
        XCTAssertGreaterThan(setsCount, 0,
            "session_set rows must be written by markCardDone")

        // All rows for card0 must be marked completed
        for row in card0.rows {
            XCTAssertTrue(row.isCompleted, "markCardDone must set isCompleted on all rows")
        }

        // If 2 distinct exercises → 2 distinct cards; expandedCardID must point to card1
        if vm.cards.count >= 2 && ex1ID != ex2ID {
            let card1 = vm.cards[1]
            XCTAssertEqual(vm.expandedCardID, card1.id,
                "expandedCardID must advance to card1 after marking card0 done")
        }
    }
}

