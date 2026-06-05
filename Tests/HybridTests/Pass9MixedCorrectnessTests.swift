import XCTest
import SQLite3
@testable import Hybrid

/// PR #9 review remediation (PR A) — mixed-session correctness.
@MainActor
final class Pass9MixedCorrectnessTests: XCTestCase {

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass9-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    private func anyTimeExerciseUUID(_ db: DatabaseManager) async throws -> (id: Int, uuid: UUID) {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle,
                "SELECT id, client_uuid FROM exercise WHERE metric_type = 'TIME' AND is_custom = 0 LIMIT 1;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt),
                  let uuidStr = Hybrid.columnText(stmt, 1),
                  let uuid = UUID(uuidString: uuidStr)
            else { throw DatabaseError.notFound }
            return (Int(sqlite3_column_int64(stmt, 0)), uuid)
        }
    }

    /// A `.time` exercise inside a MIXED routine must round-trip `duration_secs`.
    /// Guards the persistence contract that the hardcoded `metricType: .reps` bug
    /// (MixedActiveSessionView) violated — KG/REPS were shown so the duration was dropped.
    func testMixedTimeExercisePersistsDuration() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)
        let routineRepo = RoutineRepository(dbManager: db)

        let timeEx = try await anyTimeExerciseUUID(db)
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "Pass9 Mixed Time",
            type: .mixed, sortOrder: 1,
            createdAt: now, updatedAt: now, deletedAt: nil
        )
        let re = RoutineExercise(
            id: 0, clientUUID: UUID(), routineID: 0,
            exerciseID: timeEx.id, sortOrder: 1,
            targetSets: 1, targetRepMin: nil, targetRepMax: nil,
            targetRPE: nil, targetDurationSecsMin: nil,
            targetDurationSecsMax: nil, notes: nil, updatedAt: now
        )
        try await routineRepo.create(routine, exerciseEntries: [re], runEntries: [])

        let session = try await sessionRepo.start(routineID: routineUUID, type: .mixed)
        let vm = MixedActiveSessionViewModel(sessionID: session.clientUUID, dbManager: db)
        await vm.load()

        guard let liftBlock = vm.blocks.first(where: { $0.kind == .lift }) else {
            return XCTFail("Precondition: mixed VM must build a lift block")
        }
        XCTAssertEqual(liftBlock.exercise?.metricType, .time,
            "Precondition: the block's exercise must be a .time exercise")
        XCTAssertFalse(liftBlock.rows.isEmpty, "Precondition: lift block must have a row")

        // Simulate the user typing into the SECS field (what the fixed UI now exposes).
        liftBlock.rows[0].durationSecsText = "45"

        await vm.markLiftBlockDone(liftBlock)

        let duration = try await db.read { handle -> Int? in
            let stmt = try Hybrid.prepare(handle,
                "SELECT duration_secs FROM session_set WHERE session_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, session.id)
            guard try Hybrid.step(stmt) else { return nil }
            return sqlite3_column_type(stmt, 0) != SQLITE_NULL
                ? Int(sqlite3_column_int64(stmt, 0)) : nil
        }
        XCTAssertEqual(duration, 45,
            "duration_secs must persist for a .time exercise in a mixed routine")
    }
}
