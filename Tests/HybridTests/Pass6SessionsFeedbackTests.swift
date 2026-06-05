import XCTest
import SQLite3
@testable import Hybrid

/// Pass 6 — Sessions feedback: persist-on-finish, builder targets, mixed detail, mixed session, type round-trip.
@MainActor
final class Pass6SessionsFeedbackTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass6-\(UUID().uuidString).sqlite")
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

    private func anyRunTemplateID(_ db: DatabaseManager) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM run_template WHERE is_custom = 0 LIMIT 1;")
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

    private func anyRunTemplate(_ db: DatabaseManager) async throws -> RunTemplate {
        let repo = RunTemplateRepository(dbManager: db)
        let all = try await repo.listAll()
        guard let tmpl = all.first(where: { !$0.isCustom }) else {
            throw DatabaseError.notFound
        }
        return tmpl
    }

    // MARK: - Item 5: Typed-but-unchecked lift sets persist after persistAllRows() + finish

    /// Start a lift session, type weight/reps WITHOUT toggling isCompleted, call persistAllRows(),
    /// then finishAndCheckStorage(). Assert session_set rows exist for that exercise.
    func testLiftPersistAllRowsFlushesUncheckedSetsBeforeFinish() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)
        let sessionSetRepo = SessionSetRepository(dbManager: db)

        // Create a minimal lift routine with one exercise
        let exerciseID = try await anyExerciseID(db)
        let exercise = try await makeExercise(id: exerciseID, db: db)
        let routineRepo = RoutineRepository(dbManager: db)
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "Flush Test Routine",
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

        // Start a session
        let session = try await sessionRepo.start(routineID: routineUUID, type: .lift)

        // Drive the VM
        let vm = LiftActiveSessionViewModel(sessionID: session.clientUUID, dbManager: db)
        await vm.load()

        // Verify cards loaded
        let cardCount = vm.cards.count
        XCTAssertGreaterThan(cardCount, 0, "Precondition: VM must load at least one exercise card")

        // Type weight/reps WITHOUT toggling isCompleted
        let card = vm.cards[0]
        XCTAssertFalse(card.rows.isEmpty, "Precondition: card must have at least one row")
        let row = card.rows[0]
        row.weightText = "100"
        row.repsText = "5"
        // isCompleted stays false — this is the data-loss scenario

        // Precondition: no session_set rows yet
        let setsBefore = try await countRows(db,
            sql: "SELECT COUNT(*) FROM session_set WHERE session_id = \(session.id);")
        XCTAssertEqual(setsBefore, 0, "Precondition: session_set must be empty before persistAllRows()")

        // Call persistAllRows() — must flush typed-but-unchecked rows
        await vm.persistAllRows()

        // Assert session_set rows now exist
        let setsAfter = try await countRows(db,
            sql: "SELECT COUNT(*) FROM session_set WHERE session_id = \(session.id);")
        XCTAssertGreaterThan(setsAfter, 0,
            "session_set rows must be written by persistAllRows() even when isCompleted=false")

        // Verify via historyByExercise that the set appears
        _ = await vm.finishAndCheckStorage()
        let history = try await sessionSetRepo.historyByExercise(
            exerciseID: exercise.clientUUID, monthsBack: 12)
        XCTAssertFalse(history.isEmpty,
            "historyByExercise must return the typed set after persistAllRows() + finish")
    }

    // MARK: - Item 2: Builder create() persists targetSets / repMin / repMax

    /// Drive RoutineBuilderViewModel with targetSets=3, targetRepMin=8, targetRepMax=12.
    /// Assert via listExercises (and direct SQL on routine_exercise) that the values persist.
    func testBuilderCreatePersistsTargetSetsRepMinRepMax() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)

        let exerciseID = try await anyExerciseID(db)
        let exercise = try await makeExercise(id: exerciseID, db: db)

        let vm = RoutineBuilderViewModel(dbManager: db)
        await vm.load()
        vm.name = "Target Sets Test Routine"
        vm.add(exercise)

        // Set targets on the entry
        let entry = vm.entries[0]
        entry.targetSets = 3
        entry.targetRepMin = 8
        entry.targetRepMax = 12

        await vm.create()

        XCTAssertTrue(vm.didCreate, "didCreate must be true after valid create()")

        // Fetch the created routine
        let routines = try await routineRepo.list()
        let created = try XCTUnwrap(routines.first { $0.name == "Target Sets Test Routine" },
            "Routine must appear in list() after create()")

        // Verify via listExercises
        let reRows = try await routineRepo.listExercises(routineID: created.clientUUID)
        XCTAssertEqual(reRows.count, 1, "One routine_exercise row must exist")
        let reRow = try XCTUnwrap(reRows.first)
        XCTAssertEqual(reRow.targetSets, 3, "routine_exercise.target_sets must be 3")
        XCTAssertEqual(reRow.targetRepMin, 8, "routine_exercise.target_rep_min must be 8")
        XCTAssertEqual(reRow.targetRepMax, 12, "routine_exercise.target_rep_max must be 12")

        // Also verify directly via SQL
        let targetSetsFromDB = try await db.read { handle -> (Int?, Int?, Int?) in
            let stmt = try Hybrid.prepare(handle, """
                SELECT target_sets, target_rep_min, target_rep_max
                FROM routine_exercise
                WHERE routine_id = ?
                LIMIT 1;
                """)
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, created.id)
            guard try Hybrid.step(stmt) else { return (nil, nil, nil) }
            let ts: Int? = sqlite3_column_type(stmt, 0) != SQLITE_NULL
                ? Int(sqlite3_column_int64(stmt, 0)) : nil
            let rm: Int? = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                ? Int(sqlite3_column_int64(stmt, 1)) : nil
            let rx: Int? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                ? Int(sqlite3_column_int64(stmt, 2)) : nil
            return (ts, rm, rx)
        }
        XCTAssertEqual(targetSetsFromDB.0, 3, "SQL: routine_exercise.target_sets must be 3")
        XCTAssertEqual(targetSetsFromDB.1, 8, "SQL: routine_exercise.target_rep_min must be 8")
        XCTAssertEqual(targetSetsFromDB.2, 12, "SQL: routine_exercise.target_rep_max must be 12")
    }

    /// Nil targets (not set by user) must remain nil — CREATE must not coerce blank fields to 0.
    func testBuilderCreateNilTargetsShouldNotCoerceToZero() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)

        let exerciseID = try await anyExerciseID(db)
        let exercise = try await makeExercise(id: exerciseID, db: db)

        let vm = RoutineBuilderViewModel(dbManager: db)
        await vm.load()
        vm.name = "Nil Targets Routine"
        vm.add(exercise)
        // Leave entry.targetSets/targetRepMin/targetRepMax as nil (defaults)

        await vm.create()
        XCTAssertTrue(vm.didCreate)

        let routines = try await routineRepo.list()
        let created = try XCTUnwrap(routines.first { $0.name == "Nil Targets Routine" })
        let reRows = try await routineRepo.listExercises(routineID: created.clientUUID)
        let reRow = try XCTUnwrap(reRows.first)
        XCTAssertNil(reRow.targetSets, "targetSets must remain nil when not set by the user")
        XCTAssertNil(reRow.targetRepMin, "targetRepMin must remain nil when not set by the user")
        XCTAssertNil(reRow.targetRepMax, "targetRepMax must remain nil when not set by the user")
    }

    // MARK: - Item 4a: Mixed routine load returns both entries and runEntries

    /// Create a mixed routine (≥1 exercise + ≥1 run), drive LiftRoutineDetailViewModel.load,
    /// assert entries.count >= 1 AND runEntries.count >= 1.
    func testMixedRoutineDetailLoadReturnsBothExercisesAndRuns() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)

        let exerciseID = try await anyExerciseID(db)
        let runTemplateID = try await anyRunTemplateID(db)
        let now = Date()

        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "Mixed Detail Test",
            type: .mixed, sortOrder: 1,
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

        let vm = LiftRoutineDetailViewModel(dbManager: db)
        await vm.load(routineID: routineUUID)

        XCTAssertNil(vm.errorMessage, "errorMessage must be nil after a successful load")
        XCTAssertGreaterThanOrEqual(vm.entries.count, 1,
            "entries.count must be >= 1 for a mixed routine with exercises")
        XCTAssertGreaterThanOrEqual(vm.runEntries.count, 1,
            "runEntries.count must be >= 1 for a mixed routine with runs")
    }

    /// Pure lift routine must not populate runEntries (regression guard).
    func testLiftOnlyRoutineDetailLoadHasNoRunEntries() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)

        let exerciseID = try await anyExerciseID(db)
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "Lift Only Detail Test",
            type: .lift, sortOrder: 1,
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

        let vm = LiftRoutineDetailViewModel(dbManager: db)
        await vm.load(routineID: routineUUID)

        XCTAssertEqual(vm.runEntries.count, 0,
            "runEntries must be empty for a lift-only routine")
        XCTAssertGreaterThanOrEqual(vm.entries.count, 1,
            "entries must still load correctly for a lift-only routine")
    }

    // MARK: - Item 4b: Finishing a mixed session writes both session_set and session_run rows

    /// Start a .mixed session, drive MixedActiveSessionViewModel.load, enter lift data and run data,
    /// markLiftBlockDone/markRunBlockDone (or persistAll), finish().
    /// Assert session_set count > 0 AND session_run count > 0; session status COMPLETED.
    func testMixedSessionFinishWritesBothSessionSetAndSessionRun() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)
        let routineRepo = RoutineRepository(dbManager: db)

        // Create a mixed routine
        let exerciseID = try await anyExerciseID(db)
        let runTemplateID = try await anyRunTemplateID(db)
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "Mixed Session Test",
            type: .mixed, sortOrder: 1,
            createdAt: now, updatedAt: now, deletedAt: nil
        )
        let re = RoutineExercise(
            id: 0, clientUUID: UUID(), routineID: 0,
            exerciseID: exerciseID, sortOrder: 1,
            targetSets: 1, targetRepMin: 5, targetRepMax: 5,
            targetRPE: nil, targetDurationSecsMin: nil,
            targetDurationSecsMax: nil, notes: nil, updatedAt: now
        )
        let rr = RoutineRun(
            id: 0, clientUUID: UUID(), routineID: 0,
            runTemplateID: runTemplateID,
            sortOrder: 1, notes: nil, updatedAt: now
        )
        try await routineRepo.create(routine, exerciseEntries: [re], runEntries: [rr])

        // Start a .mixed session
        let session = try await sessionRepo.start(routineID: routineUUID, type: .mixed)

        // Drive the VM
        let vm = MixedActiveSessionViewModel(sessionID: session.clientUUID, dbManager: db)
        await vm.load()

        XCTAssertNil(vm.errorMessage, "VM must load without error")
        XCTAssertFalse(vm.blocks.isEmpty, "Blocks must be non-empty after load")

        // Find the lift block and set data
        let liftBlocks = vm.blocks.filter { $0.kind == .lift }
        XCTAssertGreaterThan(liftBlocks.count, 0, "Must have at least one lift block")
        let liftBlock = liftBlocks[0]
        XCTAssertFalse(liftBlock.rows.isEmpty, "Lift block must have rows")
        liftBlock.rows[0].weightText = "80"
        liftBlock.rows[0].repsText = "5"

        // Find the run block and set distance
        let runBlocks = vm.blocks.filter { $0.kind == .run }
        XCTAssertGreaterThan(runBlocks.count, 0, "Must have at least one run block")
        let runBlock = runBlocks[0]
        runBlock.runDistanceText = "5.0"

        // Mark both done (also exercises persistAll path)
        await vm.markLiftBlockDone(liftBlock)
        await vm.markRunBlockDone(runBlock)

        // Call finish
        let done = await vm.finish()
        XCTAssertTrue(done, "finish() must return true when storage is within limit")

        // Assert session_set rows exist for this session
        let setCount = try await countRows(db,
            sql: "SELECT COUNT(*) FROM session_set WHERE session_id = \(session.id);")
        XCTAssertGreaterThan(setCount, 0,
            "session_set rows must be written after markLiftBlockDone + finish")

        // Assert session_run rows exist for this session
        let runCount = try await countRows(db,
            sql: "SELECT COUNT(*) FROM session_run WHERE session_id = \(session.id);")
        XCTAssertGreaterThan(runCount, 0,
            "session_run rows must be written (created on load) for this session")

        // Assert session status is COMPLETED
        let status = try await db.read { handle -> String? in
            let stmt = try Hybrid.prepare(handle,
                "SELECT status FROM session WHERE id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, session.id)
            guard try Hybrid.step(stmt) else { return nil }
            return Hybrid.columnText(stmt, 0)
        }
        XCTAssertEqual(status, "COMPLETED",
            "session.status must be COMPLETED after finish()")
    }

    /// persistAll() via saveAndExit path must also flush data (session remains IN_PROGRESS).
    func testMixedSessionSaveAndExitFlushesDataWithoutCompleting() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)
        let routineRepo = RoutineRepository(dbManager: db)

        let exerciseID = try await anyExerciseID(db)
        let runTemplateID = try await anyRunTemplateID(db)
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "Mixed SaveExit Test",
            type: .mixed, sortOrder: 1,
            createdAt: now, updatedAt: now, deletedAt: nil
        )
        let re = RoutineExercise(
            id: 0, clientUUID: UUID(), routineID: 0,
            exerciseID: exerciseID, sortOrder: 1,
            targetSets: 1, targetRepMin: nil, targetRepMax: nil,
            targetRPE: nil, targetDurationSecsMin: nil,
            targetDurationSecsMax: nil, notes: nil, updatedAt: now
        )
        let rr = RoutineRun(
            id: 0, clientUUID: UUID(), routineID: 0,
            runTemplateID: runTemplateID,
            sortOrder: 1, notes: nil, updatedAt: now
        )
        try await routineRepo.create(routine, exerciseEntries: [re], runEntries: [rr])

        let session = try await sessionRepo.start(routineID: routineUUID, type: .mixed)
        let vm = MixedActiveSessionViewModel(sessionID: session.clientUUID, dbManager: db)
        await vm.load()

        // Enter lift data
        if let block = vm.blocks.first(where: { $0.kind == .lift }),
           let row = block.rows.first {
            row.weightText = "60"
            row.repsText = "3"
        }

        await vm.saveAndExit()

        // session_set must be flushed
        let setCount = try await countRows(db,
            sql: "SELECT COUNT(*) FROM session_set WHERE session_id = \(session.id);")
        XCTAssertGreaterThan(setCount, 0,
            "session_set rows must be written by saveAndExit()")

        // Session must NOT be COMPLETED (saveAndExit leaves it IN_PROGRESS)
        let status = try await db.read { handle -> String? in
            let stmt = try Hybrid.prepare(handle,
                "SELECT status FROM session WHERE id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, session.id)
            guard try Hybrid.step(stmt) else { return nil }
            return Hybrid.columnText(stmt, 0)
        }
        XCTAssertEqual(status, "IN_PROGRESS",
            "session.status must remain IN_PROGRESS after saveAndExit()")
    }

    // MARK: - Item 4 (dispatch data level): SessionRepository.start records type; get returns it

    /// .lift round-trip
    func testSessionRepositoryStartRecordsLiftType() async throws {
        let db = try makeTempDB()
        let repo = SessionRepository(dbManager: db)

        let session = try await repo.start(routineID: nil, type: .lift)
        XCTAssertEqual(session.type, .lift, "start() must return session with type .lift")

        let fetched = try await repo.get(id: session.clientUUID)
        let fs = try XCTUnwrap(fetched, "get() must return the session after start()")
        XCTAssertEqual(fs.type, .lift, "get() must return type .lift for a .lift session")
    }

    /// .run round-trip
    func testSessionRepositoryStartRecordsRunType() async throws {
        let db = try makeTempDB()
        let repo = SessionRepository(dbManager: db)

        let session = try await repo.start(routineID: nil, type: .run)
        XCTAssertEqual(session.type, .run, "start() must return session with type .run")

        let fetched = try await repo.get(id: session.clientUUID)
        let fs = try XCTUnwrap(fetched, "get() must return the session after start()")
        XCTAssertEqual(fs.type, .run, "get() must return type .run for a .run session")
    }

    /// .mixed round-trip
    func testSessionRepositoryStartRecordsMixedType() async throws {
        let db = try makeTempDB()
        let repo = SessionRepository(dbManager: db)

        let session = try await repo.start(routineID: nil, type: .mixed)
        XCTAssertEqual(session.type, .mixed, "start() must return session with type .mixed")

        let fetched = try await repo.get(id: session.clientUUID)
        let fs = try XCTUnwrap(fetched, "get() must return the session after start()")
        XCTAssertEqual(fs.type, .mixed, "get() must return type .mixed for a .mixed session")
    }

    /// All three types are distinct — a .lift session is not returned as .run or .mixed.
    func testSessionTypeDistinctnessAllThreeTypes() async throws {
        let db = try makeTempDB()
        let repo = SessionRepository(dbManager: db)

        let liftSession  = try await repo.start(routineID: nil, type: .lift)
        let runSession   = try await repo.start(routineID: nil, type: .run)
        let mixedSession = try await repo.start(routineID: nil, type: .mixed)

        let fetchedLift  = try await repo.get(id: liftSession.clientUUID)
        let fetchedRun   = try await repo.get(id: runSession.clientUUID)
        let fetchedMixed = try await repo.get(id: mixedSession.clientUUID)

        XCTAssertEqual(fetchedLift?.type,  .lift,  "Distinct sessions must retain their own type")
        XCTAssertEqual(fetchedRun?.type,   .run,   "Distinct sessions must retain their own type")
        XCTAssertEqual(fetchedMixed?.type, .mixed, "Distinct sessions must retain their own type")

        // Cross-check: each session must NOT have another's type
        XCTAssertNotEqual(fetchedLift?.type,  .run)
        XCTAssertNotEqual(fetchedLift?.type,  .mixed)
        XCTAssertNotEqual(fetchedRun?.type,   .lift)
        XCTAssertNotEqual(fetchedRun?.type,   .mixed)
        XCTAssertNotEqual(fetchedMixed?.type, .lift)
        XCTAssertNotEqual(fetchedMixed?.type, .run)
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
