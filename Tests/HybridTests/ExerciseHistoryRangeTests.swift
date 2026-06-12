import XCTest
import SQLite3
@testable import Hybrid

/// Exercise history range selector — the chart loads ALL history (no count cap,
/// no month cutoff) so the user can scroll across older windows. These cover the
/// unbounded query paths (`limit: nil`, `monthsBack: nil`).
final class ExerciseHistoryRangeTests: XCTestCase {

    private var db: DatabaseManager!
    private var sessions: SessionRepository!
    private var sets: SessionSetRepository!
    private var exercises: ExerciseRepository!

    private let benchPressUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!

    override func setUp() async throws {
        try await super.setUp()
        db = try DatabaseManager(url: nil)
        sessions = SessionRepository(dbManager: db)
        sets = SessionSetRepository(dbManager: db)
        exercises = ExerciseRepository(dbManager: db)
    }

    override func tearDown() async throws {
        db = nil; sessions = nil; sets = nil; exercises = nil
        try await super.tearDown()
    }

    private func resolveExerciseRowID(uuid: UUID) async throws -> Int {
        guard let ex = try await exercises.get(id: uuid) else { throw DatabaseError.notFound }
        return ex.id
    }

    /// Creates a completed lift session with a single top set at `weight`.
    @discardableResult
    private func completedSession(weight: Double, exerciseRowID: Int) async throws -> Session {
        let s = try await sessions.start(routineID: nil, type: .lift)
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(), sessionID: s.id, exerciseID: exerciseRowID,
            exerciseOrder: 0, setNumber: 1, setType: .working,
            weightKg: weight, reps: 5, durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: nil, notes: nil, updatedAt: Date()
        ))
        try await sessions.finish(id: s.clientUUID)
        return s
    }

    /// Resolves a seeded TIME-metric exercise (id + uuid) for timed-history tests.
    private func anyTimeExercise() async throws -> (id: Int, uuid: UUID) {
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

    /// Creates a completed lift session holding one timed set per entry in `durations`.
    @discardableResult
    private func completedTimedSession(durations: [Int], exerciseRowID: Int) async throws -> Session {
        let s = try await sessions.start(routineID: nil, type: .lift)
        for (i, dur) in durations.enumerated() {
            try await sets.append(SessionSet(
                id: 0, clientUUID: UUID(), sessionID: s.id, exerciseID: exerciseRowID,
                exerciseOrder: 0, setNumber: i + 1, setType: .working,
                weightKg: nil, reps: nil, durationSecs: dur, distanceM: nil,
                rpe: nil, completedAt: nil, notes: nil, updatedAt: Date()
            ))
        }
        try await sessions.finish(id: s.clientUUID)
        return s
    }

    /// Backdates a session's started_at to `date` (started_at is stored as epoch secs).
    private func backdate(_ session: Session, to date: Date) async throws {
        let epoch = Int64(date.timeIntervalSince1970)
        try await db.read { handle in
            try execSQL(handle, "UPDATE session SET started_at = \(epoch) WHERE id = \(session.id);")
        }
    }

    /// limit: nil must drop the LIMIT clause and return every session's top set.
    func testTopSetPerSessionUnboundedReturnsAll() async throws {
        let rowID = try await resolveExerciseRowID(uuid: benchPressUUID)
        for w in [100.0, 110.0, 120.0] {
            try await completedSession(weight: w, exerciseRowID: rowID)
        }

        let capped = try await sets.topSetPerSession(exerciseID: benchPressUUID, limit: 2)
        XCTAssertEqual(capped.count, 2, "a non-nil limit must still cap")

        let all = try await sets.topSetPerSession(exerciseID: benchPressUUID, limit: nil)
        XCTAssertEqual(all.count, 3, "limit: nil must return every session's top set")
    }

    /// monthsBack: nil must drop the started_at cutoff and include ancient sessions.
    func testHistoryByExerciseUnboundedIncludesOldSessions() async throws {
        let rowID = try await resolveExerciseRowID(uuid: benchPressUUID)
        let recent = try await completedSession(weight: 100.0, exerciseRowID: rowID)
        let old = try await completedSession(weight: 90.0, exerciseRowID: rowID)
        _ = recent
        // Push one session well outside the 12-month window.
        try await backdate(old, to: Date().addingTimeInterval(-18 * 30 * 86_400))

        let bounded = try await sets.historyByExercise(exerciseID: benchPressUUID, monthsBack: 12)
        XCTAssertEqual(bounded.count, 1, "12-month cutoff must exclude the 18-month-old session")

        let unbounded = try await sets.historyByExercise(exerciseID: benchPressUUID, monthsBack: nil)
        XCTAssertEqual(unbounded.count, 2, "monthsBack: nil must include the old session")
    }

    /// topDurationPerSession returns one row per session (the session's max duration),
    /// newest first, dated on the session's started_at — the shared date source that
    /// keeps the timed history chart in step with the weighted one.
    func testTopDurationPerSessionMaxPerSessionDatedOnStartedAt() async throws {
        let ex = try await anyTimeExercise()

        let old = try await completedTimedSession(durations: [30, 60, 45], exerciseRowID: ex.id)
        _ = try await completedTimedSession(durations: [90, 20], exerciseRowID: ex.id)

        // Make the first session strictly older so ordering is deterministic.
        let oldDate = Date().addingTimeInterval(-10 * 86_400)
        try await backdate(old, to: oldDate)

        let all = try await sets.topDurationPerSession(exerciseID: ex.uuid, limit: nil)
        XCTAssertEqual(all.map(\.durationSecs), [90, 60],
            "newest first; each row is the session's max duration")
        XCTAssertEqual(all[1].sessionDate.timeIntervalSince1970, oldDate.timeIntervalSince1970,
            accuracy: 1, "row date must be the session's started_at, not a set timestamp")

        let capped = try await sets.topDurationPerSession(exerciseID: ex.uuid, limit: 1)
        XCTAssertEqual(capped.count, 1, "a non-nil limit must still cap")
    }
}
