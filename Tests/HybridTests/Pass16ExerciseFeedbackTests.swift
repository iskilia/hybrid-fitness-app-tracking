import XCTest
import SQLite3
@testable import Hybrid

/// Pass 16 — Exercise feedback: routine-builder entry removal, multi-add,
/// custom-exercise hard delete with cascade, and editor prefill/update.
@MainActor
final class Pass16ExerciseFeedbackTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass16-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    private func countRows(_ db: DatabaseManager, sql: String, bindID: Int? = nil) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, sql)
            defer { Hybrid.finalize(stmt) }
            if let id = bindID { Hybrid.bindInt(stmt, 1, id) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    private func anyBaseExercise(_ db: DatabaseManager) async throws -> Exercise {
        let repo = ExerciseRepository(dbManager: db)
        let base = try await repo.listBase()
        return try XCTUnwrap(base.first)
    }

    /// Encodes integer muscle ID the same way CustomExerciseEditorViewModel does.
    private func muscleUUID(_ id: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-" + String(format: "%012x", id))!
    }

    private func makeCustomExercise(
        _ db: DatabaseManager,
        name: String,
        muscles: [(UUID, MuscleRole)] = []
    ) async throws -> Exercise {
        let repo = ExerciseRepository(dbManager: db)
        let now = Date()
        let exercise = Exercise(
            id: 0, clientUUID: UUID(), name: name, abbreviation: "TST",
            equipmentID: 1, metricType: .reps, isCustom: true,
            notes: "test notes", formLink: nil,
            createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await repo.create(exercise, muscles: muscles)
        let custom = try await repo.listCustom()
        return try XCTUnwrap(custom.first { $0.name == name })
    }

    // MARK: - 1. Routine builder: remove entry

    func testBuilderRemoveEntry() async throws {
        let db = try makeTempDB()
        let vm = RoutineBuilderViewModel(dbManager: db)
        let repo = ExerciseRepository(dbManager: db)
        let base = try await repo.listBase()
        let first = try XCTUnwrap(base.first)
        let second = try XCTUnwrap(base.dropFirst().first)

        vm.add(first)
        vm.add(second)
        XCTAssertEqual(vm.entries.count, 2)

        let entryToRemove = vm.entries[0]
        vm.remove(entryToRemove)

        XCTAssertEqual(vm.entries.count, 1)
        XCTAssertEqual(vm.entries[0].exercise.clientUUID, second.clientUUID,
            "remove() must delete exactly the requested entry")
    }

    // MARK: - 2. Routine builder: multi-add keeps unique entry identities

    func testBuilderMultiAddSameExerciseKeepsUniqueIDs() async throws {
        let db = try makeTempDB()
        let vm = RoutineBuilderViewModel(dbManager: db)
        let exercise = try await anyBaseExercise(db)

        vm.add(exercise)
        vm.add(exercise)

        XCTAssertEqual(vm.entries.count, 2, "adding the same exercise twice must create two entries")
        XCTAssertNotEqual(vm.entries[0].id, vm.entries[1].id,
            "entries must have unique identities even for the same exercise")

        // Removing one of the duplicates must remove only that one.
        vm.remove(vm.entries[0])
        XCTAssertEqual(vm.entries.count, 1)
    }

    // MARK: - 3. Hard delete custom exercise cascades to all associated data

    func testHardDeleteCustomExerciseCascades() async throws {
        let db = try makeTempDB()
        let exerciseRepo = ExerciseRepository(dbManager: db)
        let routineRepo = RoutineRepository(dbManager: db)
        let sessionRepo = SessionRepository(dbManager: db)
        let setRepo = SessionSetRepository(dbManager: db)

        let custom = try await makeCustomExercise(
            db, name: "Cascade Delete Test",
            muscles: [(muscleUUID(1), .primary), (muscleUUID(5), .secondary)]
        )

        // Routine referencing the exercise
        let now = Date()
        let routine = Routine(
            id: 0, clientUUID: UUID(), name: "Pass16 Routine", type: .lift,
            sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil
        )
        let re = RoutineExercise(
            id: 0, clientUUID: UUID(), routineID: 0, exerciseID: custom.id,
            sortOrder: 1, targetSets: 3, targetRepMin: 8, targetRepMax: 12,
            targetRPE: nil, targetDurationSecsMin: nil, targetDurationSecsMax: nil,
            notes: nil, updatedAt: now
        )
        try await routineRepo.create(routine, exerciseEntries: [re], runEntries: [])

        // Session set referencing the exercise
        let session = try await sessionRepo.start(routineID: nil, type: .lift)
        try await setRepo.append(SessionSet(
            id: 0, clientUUID: UUID(), sessionID: session.id, exerciseID: custom.id,
            exerciseOrder: 1, setNumber: 1, setType: .working,
            weightKg: 50, reps: 10, durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: now, notes: nil, updatedAt: now
        ))

        // Preconditions
        let muscleBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle WHERE exercise_id = ?;", bindID: custom.id)
        XCTAssertEqual(muscleBefore, 2, "Precondition: exercise_muscle rows must exist")
        let reBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM routine_exercise WHERE exercise_id = ?;", bindID: custom.id)
        XCTAssertEqual(reBefore, 1, "Precondition: routine_exercise row must exist")
        let setBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM session_set WHERE exercise_id = ?;", bindID: custom.id)
        XCTAssertEqual(setBefore, 1, "Precondition: session_set row must exist")
        let baseCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise WHERE is_custom = 0;")
        let routineCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM routine WHERE deleted_at IS NULL;")
        let sessionCountBefore = try await countRows(db, sql: "SELECT COUNT(*) FROM session;")

        // Hard delete
        try await exerciseRepo.hardDelete(id: custom.clientUUID)

        // Exercise row gone (not just soft-deleted)
        let exerciseAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise WHERE id = ?;", bindID: custom.id)
        XCTAssertEqual(exerciseAfter, 0, "exercise row must be hard-deleted")

        // All associated data gone
        let muscleAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise_muscle WHERE exercise_id = ?;", bindID: custom.id)
        XCTAssertEqual(muscleAfter, 0, "exercise_muscle rows must be deleted")
        let reAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM routine_exercise WHERE exercise_id = ?;", bindID: custom.id)
        XCTAssertEqual(reAfter, 0, "routine_exercise rows must be deleted")
        let setAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM session_set WHERE exercise_id = ?;", bindID: custom.id)
        XCTAssertEqual(setAfter, 0, "session_set rows must be deleted")

        // Unrelated data intact
        let baseCountAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM exercise WHERE is_custom = 0;")
        XCTAssertEqual(baseCountAfter, baseCountBefore, "base exercises must be untouched")
        let routineAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM routine WHERE deleted_at IS NULL;")
        XCTAssertEqual(routineAfter, routineCountBefore, "the routine itself must survive")
        let sessionAfter = try await countRows(db, sql: "SELECT COUNT(*) FROM session;")
        XCTAssertEqual(sessionAfter, sessionCountBefore, "the session itself must survive")
    }

    // MARK: - 4. Editor prefills existing exercise and updates in place

    func testEditorPrefillsAndUpdatesExistingExercise() async throws {
        let db = try makeTempDB()
        let custom = try await makeCustomExercise(
            db, name: "Prefill Test",
            muscles: [(muscleUUID(1), .primary)]
        )

        let vm = CustomExerciseEditorViewModel(dbManager: db, editingExerciseID: custom.id)
        await vm.load()

        XCTAssertEqual(vm.name, "Prefill Test", "editor must prefill the existing name")
        XCTAssertEqual(vm.abbreviation, "TST", "editor must prefill the existing abbreviation")
        XCTAssertEqual(vm.selectedEquipmentID, custom.equipmentID, "editor must prefill the existing equipment")
        XCTAssertEqual(vm.notes, "test notes", "editor must prefill the existing notes")
        let selected = vm.muscleSelections.filter { $0.isSelected }
        XCTAssertEqual(selected.map { $0.muscle.id }, [1], "editor must prefill the existing muscle selection")

        // Update the name and save
        vm.name = "Prefill Test Renamed"
        await vm.save()
        XCTAssertTrue(vm.didSave, "save() must succeed in edit mode: \(vm.errorMessage ?? "")")

        let repo = ExerciseRepository(dbManager: db)
        let customList = try await repo.listCustom()
        XCTAssertEqual(customList.count, 1, "edit must update in place, not create a new exercise")
        let updated = try XCTUnwrap(customList.first)
        XCTAssertEqual(updated.name, "Prefill Test Renamed", "name change must persist")
        XCTAssertEqual(updated.clientUUID, custom.clientUUID, "clientUUID must be preserved on edit")
    }

    // MARK: - 5. Library list reflects newly created custom exercise after reload

    func testLibraryReloadIncludesNewCustomExercise() async throws {
        let db = try makeTempDB()
        let vm = ExerciseLibraryViewModel(dbManager: db)
        await vm.load()
        let countBefore = vm.exercises.count

        _ = try await makeCustomExercise(db, name: "Fresh Custom")
        await vm.load()

        XCTAssertEqual(vm.exercises.count, countBefore + 1)
        XCTAssertTrue(vm.exercises.contains { $0.name == "Fresh Custom" },
            "reload must surface the newly created custom exercise")
    }
}
