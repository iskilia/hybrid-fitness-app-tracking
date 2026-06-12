import XCTest
import SQLite3
@testable import Hybrid

/// Phase 5 gate (PLAN.md line 191):
/// "end-to-end test: create routine → start → log sets/run → finish →
///  appears in history with correct aggregates."
final class SessionEndToEndTests: XCTestCase {

    private var db: DatabaseManager!
    private var routines: RoutineRepository!
    private var exercises: ExerciseRepository!
    private var sessions: SessionRepository!
    private var sets: SessionSetRepository!
    private var runs: SessionRunRepository!

    private let benchPressUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
    private let fiveByEightHundredUUID = UUID(uuidString: "00000000-0000-0000-0002-000000000004")!

    override func setUp() async throws {
        try await super.setUp()
        db = try DatabaseManager(url: nil)
        routines = RoutineRepository(dbManager: db)
        exercises = ExerciseRepository(dbManager: db)
        sessions = SessionRepository(dbManager: db)
        sets = SessionSetRepository(dbManager: db)
        runs = SessionRunRepository(dbManager: db)
    }

    override func tearDown() async throws {
        db = nil; routines = nil; exercises = nil
        sessions = nil; sets = nil; runs = nil
        try await super.tearDown()
    }

    // MARK: - Lift end-to-end

    /// Create a lift routine with bench press, start a session, log 3 sets,
    /// finish the session, then verify history aggregates.
    func testLiftSessionEndToEnd() async throws {
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID,
            name: "Heavy Lower", type: .lift,
            sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routines.create(routine, exerciseEntries: [], runEntries: [])
        let stored = try await routines.get(id: routineUUID)
        let routineRowID = stored!.id

        let benchRowID = try await rawScalarInt(
            "SELECT id FROM exercise WHERE client_uuid = '\(benchPressUUID.uuidString.lowercased())';"
        )
        let entry = RoutineExercise(
            id: 0, clientUUID: UUID(),
            routineID: routineRowID, exerciseID: benchRowID, sortOrder: 0,
            targetSets: 3, targetRepMin: 5, targetRepMax: 8,
            targetRPE: 8.0, targetDurationSecsMin: nil, targetDurationSecsMax: nil,
            notes: nil, updatedAt: now
        )
        try await routines.update(routine, exerciseEntries: [entry], runEntries: [])

        let session = try await sessions.start(routineID: routineUUID, type: .lift)
        XCTAssertEqual(session.status, .inProgress)

        let topWeight = 110.0
        let setSpecs: [(Double, Int, Int)] = [
            (100.0, 5, 1), (105.0, 5, 2), (topWeight, 5, 3),
        ]
        for (w, reps, n) in setSpecs {
            try await sets.append(SessionSet(
                id: 0, clientUUID: UUID(),
                sessionID: session.id, exerciseID: benchRowID,
                exerciseOrder: 0, setNumber: n,
                setType: .working,
                weightKg: w, reps: reps,
                durationSecs: nil, distanceM: nil,
                rpe: 8.0, completedAt: Date(),
                notes: nil, updatedAt: Date()
            ))
        }

        try await sessions.finish(id: session.clientUUID)

        let after = try await sessions.get(id: session.clientUUID)
        XCTAssertEqual(after?.status, .completed)
        XCTAssertNotNil(after?.finishedAt)

        let tops = try await sets.topSetPerSession(exerciseID: benchPressUUID, limit: 12)
        XCTAssertEqual(tops.count, 1, "completed session should produce one top set")
        let top = try XCTUnwrap(tops.first)
        XCTAssertEqual(top.weightKg, topWeight, accuracy: 0.001)
        XCTAssertEqual(top.reps, 5)

        let history = try await sets.historyByExercise(exerciseID: benchPressUUID, monthsBack: 12)
        XCTAssertEqual(history.count, 3)
    }

    // MARK: - Run end-to-end

    /// Create a run routine, start a session, append a run with a split,
    /// finish, then verify aggregates + split persisted.
    func testRunSessionEndToEnd() async throws {
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID,
            name: "Tempo Tuesday", type: .run,
            sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routines.create(routine, exerciseEntries: [], runEntries: [])
        let stored = try await routines.get(id: routineUUID)
        let routineRowID = stored!.id

        let templateRowID = try await rawScalarInt(
            "SELECT id FROM run_template WHERE client_uuid = '\(fiveByEightHundredUUID.uuidString.lowercased())';"
        )
        let runEntry = RoutineRun(
            id: 0, clientUUID: UUID(),
            routineID: routineRowID, runTemplateID: templateRowID, sortOrder: 0,
            notes: nil, updatedAt: now
        )
        try await routines.update(routine, exerciseEntries: [], runEntries: [runEntry])

        let session = try await sessions.start(routineID: routineUUID, type: .run)

        let runUUID = UUID()
        try await runs.append(SessionRun(
            id: 0, clientUUID: runUUID,
            sessionID: session.id, runTemplateID: templateRowID,
            runOrder: 0,
            actualDistanceKm: nil, durationSecs: nil,
            avgPaceSecs: nil, avgHR: nil, maxHR: nil,
            targetHRMin: 150, targetHRMax: 175,
            notes: nil, updatedAt: Date()
        ))

        try await runs.finish(
            id: runUUID,
            distanceKm: 8.4, durationSec: 2520,
            avgPaceSecPerKm: 300, avgHrBpm: 162
        )

        let runRowID = try await rawScalarInt(
            "SELECT id FROM session_run WHERE client_uuid = '\(runUUID.uuidString.lowercased())';"
        )
        try await runs.addSplit(SessionRunSplit(
            id: 0, sessionRunID: runRowID, sortOrder: 0, blockType: .work,
            distanceKm: 4.2, durationSecs: 1260, avgPaceSecs: 300, avgHR: 158
        ))

        try await sessions.finish(id: session.clientUUID)

        let fetched = try await runs.get(id: runUUID)
        let stored2 = try XCTUnwrap(fetched)
        XCTAssertEqual(try XCTUnwrap(stored2.actualDistanceKm), 8.4, accuracy: 0.001)
        XCTAssertEqual(stored2.durationSecs, 2520)
        XCTAssertEqual(stored2.avgPaceSecs, 300)
        XCTAssertEqual(stored2.avgHR, 162)

        let splits = try await runs.splits(sessionRunID: runUUID)
        XCTAssertEqual(splits.count, 1)
        XCTAssertEqual(splits.first?.blockType, .work)

        let stats = try await sessions.weekStats(weekStart: startOfThisWeek())
        XCTAssertGreaterThanOrEqual(stats.totalDistanceKm, 8.4)
    }

    // MARK: - Helpers

    private func startOfThisWeek() -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    private func rawScalarInt(_ sql: String) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, sql)
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }
}
