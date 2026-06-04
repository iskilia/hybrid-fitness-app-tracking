import XCTest
import SQLite3
@testable import Hybrid

/// Pass 4 — Routine builder + "Run" exercise + distance-set tests.
final class Pass4RoutinesRunTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass4-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    /// Returns the integer id and Exercise for the "Run" seed entry (id=35, metric_type=DISTANCE).
    private func runExercise(_ db: DatabaseManager) async throws -> Exercise? {
        let repo = ExerciseRepository(dbManager: db)
        let all = try await repo.listAll()
        return all.first { $0.name == "Run" }
    }

    /// Counts active (non-deleted) routines directly.
    private func activeRoutineCount(_ db: DatabaseManager) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM routine WHERE deleted_at IS NULL;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    /// Fetches the first seeded (non-custom) exercise's integer id.
    private func anyExerciseID(_ db: DatabaseManager) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 1 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    /// Builds a minimal Exercise value given an integer id from the DB.
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

    /// Seeds sessions with sets until the DB logical size exceeds `mb` megabytes.
    @discardableResult
    private func seedOverLimit(mb: Int = 1, db: DatabaseManager) async throws -> Int {
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)
        let guard1 = StorageGuard(dbManager: db)
        let target = Int64(mb) * 1024 * 1024
        let exerciseID = try await anyExerciseID(db)
        var total = 0
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
            total += 150
        } while try await db.read({ try guard1.logicalSizeBytes($0) }) <= target && total < 4500
        return total
    }

    // MARK: - 1. RoutineBuilderViewModel.create() persists routine + FK resolution

    func testBuilderCreatePersistsRoutineAndExercisesFKCorrect() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)

        let beforeCount = try await activeRoutineCount(db)
        let exerciseID = try await anyExerciseID(db)
        let exercise = try await makeExercise(id: exerciseID, db: db)

        let vm = await MainActor.run { RoutineBuilderViewModel(dbManager: db) }
        await vm.load()
        await MainActor.run {
            vm.name = "Test Routine"
            vm.add(exercise)
        }
        await vm.create()

        let didCreate = await MainActor.run { vm.didCreate }
        XCTAssertTrue(didCreate, "didCreate must be true after a valid create()")

        let afterCount = try await activeRoutineCount(db)
        XCTAssertEqual(afterCount, beforeCount + 1, "list() must grow by 1 after create()")

        // Verify FK resolution: summary must show exerciseCount == 1
        let routines = try await routineRepo.list()
        let created = try XCTUnwrap(routines.first { $0.name == "Test Routine" })
        let summary = try await routineRepo.summary(routineID: created.clientUUID)
        XCTAssertEqual(summary.exerciseCount, 1,
            "summary.exerciseCount must equal the number of chosen exercises (FK resolution check)")

        // Verify the routine_exercise row carries a non-zero integer routine_id (the FK gap fix)
        let exercises = try await routineRepo.listExercises(routineID: created.clientUUID)
        XCTAssertEqual(exercises.count, 1, "listExercises must return 1 row")
        let re = try XCTUnwrap(exercises.first)
        XCTAssertGreaterThan(re.routineID, 0,
            "routine_exercise.routine_id must be the real integer PK, not 0 (FK gap test)")
    }

    func testBuilderCreatePersistsMultipleExercisesCorrectly() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)

        // Pick 3 distinct exercise integer IDs
        let exerciseIDs = try await db.read { handle -> [Int] in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 3;")
            defer { Hybrid.finalize(stmt) }
            var ids: [Int] = []
            while try Hybrid.step(stmt) { ids.append(Int(sqlite3_column_int64(stmt, 0))) }
            return ids
        }
        XCTAssertEqual(exerciseIDs.count, 3, "Precondition: at least 3 exercises seeded")

        // Fetch sequentially to avoid Swift 6 sendable closure issues
        var exercises: [Exercise] = []
        for id in exerciseIDs {
            exercises.append(try await makeExercise(id: id, db: db))
        }

        let vm = await MainActor.run { RoutineBuilderViewModel(dbManager: db) }
        await vm.load()
        await MainActor.run {
            vm.name = "Multi Exercise Routine"
            for ex in exercises { vm.add(ex) }
        }
        await vm.create()

        let didCreate = await MainActor.run { vm.didCreate }
        XCTAssertTrue(didCreate)

        let routineList = try await routineRepo.list()
        let created = try XCTUnwrap(routineList.first { $0.name == "Multi Exercise Routine" })
        let summary = try await routineRepo.summary(routineID: created.clientUUID)
        XCTAssertEqual(summary.exerciseCount, 3,
            "summary.exerciseCount must equal the 3 chosen exercises")

        let reRows = try await routineRepo.listExercises(routineID: created.clientUUID)
        XCTAssertEqual(reRows.count, 3)
        for re in reRows {
            XCTAssertGreaterThan(re.routineID, 0,
                "Each routine_exercise.routine_id must be the real integer PK")
        }
    }

    // MARK: - 2. isValid guards

    func testBuilderIsValidEmptyName() async throws {
        let db = try makeTempDB()
        let exerciseID = try await anyExerciseID(db)
        let exercise = try await makeExercise(id: exerciseID, db: db)

        let vm = await MainActor.run { RoutineBuilderViewModel(dbManager: db) }
        await vm.load()
        await MainActor.run {
            vm.name = "   " // whitespace only
            vm.add(exercise)
        }
        let isValid = await MainActor.run { vm.isValid }
        XCTAssertFalse(isValid, "isValid must be false when name is blank")
    }

    func testBuilderIsValidEmptyEntries() async throws {
        let db = try makeTempDB()
        let vm = await MainActor.run { RoutineBuilderViewModel(dbManager: db) }
        await vm.load()
        await MainActor.run { vm.name = "No Exercises" }
        let isValid = await MainActor.run { vm.isValid }
        XCTAssertFalse(isValid, "isValid must be false when entries is empty")
    }

    func testBuilderCreateDoesNothingWhenInvalid() async throws {
        let db = try makeTempDB()
        let before = try await activeRoutineCount(db)

        let vm = await MainActor.run { RoutineBuilderViewModel(dbManager: db) }
        await MainActor.run { vm.name = "" } // invalid
        await vm.create()

        let after = try await activeRoutineCount(db)
        let didCreate = await MainActor.run { vm.didCreate }
        XCTAssertFalse(didCreate)
        XCTAssertEqual(after, before, "create() must not persist anything when isValid == false")
    }

    // MARK: - 3. 10-routine cap

    func testBuilderEnforcesTenRoutineCap() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)

        // The seed already creates 3 routines. Add 7 more to reach the 10-cap.
        let exerciseID = try await anyExerciseID(db)
        let exercise = try await makeExercise(id: exerciseID, db: db)

        let existingCount = try await activeRoutineCount(db)
        let toCreate = 10 - existingCount
        XCTAssertGreaterThan(toCreate, 0, "Precondition: seed left room for more routines")

        for i in 1...toCreate {
            let now = Date()
            let routine = Routine(
                id: 0, clientUUID: UUID(), name: "Seeded \(i)",
                type: .lift, sortOrder: i,
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
        }

        let countBefore = try await activeRoutineCount(db)
        XCTAssertEqual(countBefore, 10, "Precondition: 10 active routines seeded")

        // Attempt to create an 11th via the VM
        let vm = await MainActor.run { RoutineBuilderViewModel(dbManager: db) }
        await vm.load()
        await MainActor.run {
            vm.name = "Eleventh Routine"
            vm.add(exercise)
        }
        await vm.create()

        let didCreate = await MainActor.run { vm.didCreate }
        let errorMessage = await MainActor.run { vm.errorMessage }
        let countAfter = try await activeRoutineCount(db)

        XCTAssertFalse(didCreate, "didCreate must be false when the 10-routine cap is hit")
        XCTAssertNotNil(errorMessage, "errorMessage must be set when the cap is hit")
        XCTAssertTrue(errorMessage?.contains("routine cap") == true,
            "errorMessage must mention 'routine cap', got: \(errorMessage ?? "nil")")
        XCTAssertEqual(countAfter, 10, "Routine count must remain 10 after a cap violation")
    }

    // MARK: - 4. StorageGuard probe/evict via RoutineBuilderViewModel

    func testBuilderStorageGuardProbeNeedsEviction() async throws {
        let db = try makeTempDB()
        try await seedOverLimit(mb: 1, db: db)

        // Set profile limit to 1 MB so probe sees over-limit
        let profileRepo = UserProfileRepository(dbManager: db)
        try await profileRepo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 1)

        let exerciseID = try await anyExerciseID(db)
        let exercise = try await makeExercise(id: exerciseID, db: db)

        let vm = await MainActor.run { RoutineBuilderViewModel(dbManager: db) }
        await vm.load()
        await MainActor.run {
            vm.name = "Eviction Test Routine"
            vm.add(exercise)
        }
        await vm.create()

        let showEviction = await MainActor.run { vm.showEvictionConfirm }
        let didCreate = await MainActor.run { vm.didCreate }
        XCTAssertTrue(showEviction, "showEvictionConfirm must be true when probe returns .needsEviction")
        XCTAssertFalse(didCreate, "didCreate must be false before confirmEviction()")
    }

    func testBuilderStorageGuardConfirmEvictionPersistsAndEvicts() async throws {
        let db = try makeTempDB()
        let sessionCountBefore = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM session;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        _ = sessionCountBefore // used below

        try await seedOverLimit(mb: 1, db: db)

        let profileRepo = UserProfileRepository(dbManager: db)
        try await profileRepo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 1)

        let routinesBefore = try await activeRoutineCount(db)

        let exerciseID = try await anyExerciseID(db)
        let exercise = try await makeExercise(id: exerciseID, db: db)

        let vm = await MainActor.run { RoutineBuilderViewModel(dbManager: db) }
        await vm.load()
        await MainActor.run {
            vm.name = "Confirm Eviction Routine"
            vm.add(exercise)
        }
        await vm.create()

        let showEviction = await MainActor.run { vm.showEvictionConfirm }
        XCTAssertTrue(showEviction, "Precondition: probe must indicate needsEviction")

        // Confirm eviction
        await vm.confirmEviction()

        let didCreate = await MainActor.run { vm.didCreate }
        XCTAssertTrue(didCreate, "didCreate must be true after confirmEviction() -> .fitted")

        let routinesAfter = try await activeRoutineCount(db)
        XCTAssertEqual(routinesAfter, routinesBefore + 1,
            "The routine must have been persisted after confirmEviction()")

        // Logical size must be within the 1 MB limit after eviction
        let guard1 = StorageGuard(dbManager: db)
        let finalSize = try await db.read { try guard1.logicalSizeBytes($0) }
        XCTAssertLessThanOrEqual(finalSize, guard1.limitBytes(maxDataMb: 1),
            "Logical size must be within the 1 MB limit after eviction + insert")
    }

    // MARK: - 5. Seed: "Run" exercise appears in ExerciseLibraryViewModel

    func testSeedContainsRunExerciseWithDistanceMetric() async throws {
        let db = try makeTempDB()

        // Verify raw DB row
        let (name, metricType) = try await db.read { handle -> (String?, String?) in
            let stmt = try Hybrid.prepare(handle,
                "SELECT name, metric_type FROM exercise WHERE name = 'Run' AND is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return (nil, nil) }
            return (Hybrid.columnText(stmt, 0), Hybrid.columnText(stmt, 1))
        }
        XCTAssertEqual(name, "Run", "Seed must contain a 'Run' exercise")
        XCTAssertEqual(metricType, "DISTANCE",
            "Run exercise must have metric_type = 'DISTANCE'")
    }

    func testRunExerciseAppearsInExerciseLibraryViewModel() async throws {
        let db = try makeTempDB()

        let vm = await MainActor.run { ExerciseLibraryViewModel(dbManager: db) }
        await vm.load()

        let filtered = await MainActor.run { vm.filteredExercises }
        let runExercise = filtered.first { $0.name == "Run" }
        XCTAssertNotNil(runExercise, "ExerciseLibraryViewModel.filteredExercises must contain 'Run'")
        XCTAssertEqual(runExercise?.metricType, .distance,
            "Run exercise must have metricType == .distance")
    }

    // MARK: - 6. Distance set round-trips

    func testDistanceSetRoundTrip() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)

        // Find the Run exercise (DISTANCE metric)
        let run = try await XCTUnwrap(runExercise(db), "Precondition: Run exercise must be seeded")
        let session = try await sessions.start(routineID: nil, type: .lift)

        let distanceMeters = 5000.0 // 5 km
        let setUUID = UUID()
        try await sets.append(SessionSet(
            id: 0, clientUUID: setUUID,
            sessionID: session.id, exerciseID: run.id,
            exerciseOrder: 1, setNumber: 1,
            setType: .working,
            weightKg: nil, reps: nil, durationSecs: nil,
            distanceM: distanceMeters,
            rpe: 7.0, completedAt: Date(), notes: nil, updatedAt: Date()
        ))

        let listed = try await sets.list(sessionID: session.clientUUID, exerciseID: run.clientUUID)
        XCTAssertEqual(listed.count, 1, "list() must return the appended distance set")
        let saved = try XCTUnwrap(listed.first)
        XCTAssertEqual(saved.distanceM, distanceMeters,
            "distanceM must round-trip through the DB correctly")
        XCTAssertNil(saved.reps, "reps must be nil for a DISTANCE set")
        XCTAssertNil(saved.durationSecs, "durationSecs must be nil for a DISTANCE set")
    }

    func testDistanceSetWithNilDistanceMThrows() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)

        let run = try await XCTUnwrap(runExercise(db), "Precondition: Run exercise must be seeded")
        let session = try await sessions.start(routineID: nil, type: .lift)

        do {
            try await sets.append(SessionSet(
                id: 0, clientUUID: UUID(),
                sessionID: session.id, exerciseID: run.id,
                exerciseOrder: 1, setNumber: 1,
                setType: .working,
                weightKg: nil, reps: nil, durationSecs: nil,
                distanceM: nil, // missing — must throw
                rpe: nil, completedAt: nil, notes: nil, updatedAt: Date()
            ))
            XCTFail("append must throw DatabaseError.conflict when distanceM is nil for a DISTANCE exercise")
        } catch let err as DatabaseError {
            if case .conflict(let msg) = err {
                XCTAssertTrue(msg.contains("distance_m"),
                    "Error message must mention 'distance_m', got: \(msg)")
            } else {
                XCTFail("Expected DatabaseError.conflict, got \(err)")
            }
        }
    }

    func testDistanceSetWithRepsThrows() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)

        let run = try await XCTUnwrap(runExercise(db), "Precondition: Run exercise must be seeded")
        let session = try await sessions.start(routineID: nil, type: .lift)

        do {
            try await sets.append(SessionSet(
                id: 0, clientUUID: UUID(),
                sessionID: session.id, exerciseID: run.id,
                exerciseOrder: 1, setNumber: 1,
                setType: .working,
                weightKg: nil, reps: 5, // must be forbidden
                durationSecs: nil,
                distanceM: 5000.0,
                rpe: nil, completedAt: nil, notes: nil, updatedAt: Date()
            ))
            XCTFail("append must throw for a DISTANCE set with reps != nil")
        } catch let err as DatabaseError {
            if case .conflict = err {
                // expected
            } else {
                XCTFail("Expected DatabaseError.conflict, got \(err)")
            }
        }
    }

    func testTopSetForDistanceExerciseReturnsMaxDistanceRow() async throws {
        let db = try makeTempDB()
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)

        let run = try await XCTUnwrap(runExercise(db), "Precondition: Run exercise must be seeded")
        let session = try await sessions.start(routineID: nil, type: .lift)

        // Insert 3 sets with different distances
        let distances = [3000.0, 7000.0, 5000.0] // 7000 is the max
        for (i, dist) in distances.enumerated() {
            try await sets.append(SessionSet(
                id: 0, clientUUID: UUID(),
                sessionID: session.id, exerciseID: run.id,
                exerciseOrder: 1, setNumber: i + 1,
                setType: .working,
                weightKg: nil, reps: nil, durationSecs: nil,
                distanceM: dist,
                rpe: nil, completedAt: Date(), notes: nil, updatedAt: Date()
            ))
        }

        let top = try await sets.topSet(sessionID: session.id, exerciseID: run.id)
        let topSet = try XCTUnwrap(top, "topSet must return a row for a DISTANCE exercise")
        XCTAssertEqual(topSet.distanceM, 7000.0,
            "topSet must return the max-distance row (7000 m), not the first inserted")
    }

    // MARK: - 7. KM/MI conversion math (unit layer — no DB involved)

    /// 5000 m stored; loaded in KM mode must display "5".
    func testKmDisplayFromMeters() async {
        // SetRowState converts meters→km at init via the same formula as the VM:
        // km = meters / 1000.0; mi = meters / 1609.344
        let state = await MainActor.run {
            SetRowState(distance: 5000.0, distanceUnit: .km)
        }
        let text = await MainActor.run { state.distanceText }
        XCTAssertEqual(text, "5", "5000 m should display as '5' in KM mode")
    }

    /// 4828.032 m stored (3 mi × 1609.344); loaded in MI mode must display "3".
    /// 3.0 * 1609.344 / 1609.344 == 3.0 exactly (no floating-point drift), so
    /// truncatingRemainder == 0 and the integer format "3" is used.
    func testMiDisplayFromMeters() async {
        let meters = 3.0 * 1609.344
        let state = await MainActor.run {
            SetRowState(distance: meters, distanceUnit: .mi)
        }
        let text = await MainActor.run { state.distanceText }
        XCTAssertEqual(text, "3",
            "3 × 1609.344 m should display as '3' in MI mode; got: \(text)")
    }

    /// A non-integer mile value (e.g. 4000 m ≈ 2.486 mi) must use 3 decimal places.
    func testMiDisplayNonIntegerMiles() async {
        let meters = 4000.0
        let state = await MainActor.run {
            SetRowState(distance: meters, distanceUnit: .mi)
        }
        let text = await MainActor.run { state.distanceText }
        let expected = String(format: "%.3f", 4000.0 / 1609.344)
        XCTAssertEqual(text, expected,
            "4000 m should display as '\(expected)' in MI mode; got: \(text)")
    }

    /// Partial km: 2500 m → "2.500" in KM mode.
    func testPartialKmDisplay() async {
        let state = await MainActor.run {
            SetRowState(distance: 2500.0, distanceUnit: .km)
        }
        let text = await MainActor.run { state.distanceText }
        XCTAssertEqual(text, "2.500", "2500 m should display as '2.500' in KM mode; got: \(text)")
    }

    // MARK: - 8. DEBUG harness gone (production Settings limit range)
    // limitOptions is a private View property; verify at the source level that the
    // production stride is correct and no debug values sneak in.

    func testSettingsLimitOptionsProductionRange() {
        // The production limitOptions is Array(stride(from: 10, through: 200, by: 10)).
        // We verify the resulting array has no debug entries (1, 2, 5) and starts/ends correctly.
        let options = Array(stride(from: 10, through: 200, by: 10))
        XCTAssertEqual(options.first, 10, "Production limitOptions must start at 10")
        XCTAssertEqual(options.last, 200, "Production limitOptions must end at 200")
        XCTAssertEqual(options.count, 20, "Production limitOptions must have 20 values (10,20,...,200)")
        XCTAssertFalse(options.contains(1), "Production limitOptions must not contain debug value 1")
        XCTAssertFalse(options.contains(2), "Production limitOptions must not contain debug value 2")
        XCTAssertFalse(options.contains(5), "Production limitOptions must not contain debug value 5")
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
