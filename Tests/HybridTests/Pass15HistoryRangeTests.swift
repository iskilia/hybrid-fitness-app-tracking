import XCTest
import SQLite3
@testable import Hybrid

/// Exercise history range selector — the chart loads ALL history (no count cap,
/// no month cutoff) so the user can scroll across older windows. These cover the
/// unbounded query paths (`limit: nil`, `monthsBack: nil`).
final class Pass15HistoryRangeTests: XCTestCase {

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
}
