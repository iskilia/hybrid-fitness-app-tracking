import XCTest
import SQLite3
@testable import Hybrid

/// PR B review follow-up — focused coverage for the centralized SetRowPersistence mapping
/// (reps vs time vs distance, km vs mi → metres, empty-row skip).
@MainActor
final class Pass10SetRowPersistenceTests: XCTestCase {

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass10-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    private func exercise(metricType raw: String, _ db: DatabaseManager) async throws -> Exercise {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, """
                SELECT id, client_uuid, name, abbreviation, equipment_id, metric_type,
                       is_custom, notes, form_link, created_at, updated_at, deleted_at
                FROM exercise WHERE metric_type = ? AND is_custom = 0 LIMIT 1;
                """)
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindText(stmt, 1, raw)
            guard try Hybrid.step(stmt),
                  let uuidStr = Hybrid.columnText(stmt, 1),
                  let uuid = UUID(uuidString: uuidStr),
                  let name = Hybrid.columnText(stmt, 2),
                  let abbr = Hybrid.columnText(stmt, 3),
                  let metricRaw = Hybrid.columnText(stmt, 5),
                  let metric = MetricType(rawValue: metricRaw),
                  let createdAt = Hybrid.columnDate(stmt, 9),
                  let updatedAt = Hybrid.columnDate(stmt, 10)
            else { throw DatabaseError.notFound }
            return Exercise(
                id: Int(sqlite3_column_int64(stmt, 0)),
                clientUUID: uuid, name: name, abbreviation: abbr,
                equipmentID: Int(sqlite3_column_int64(stmt, 4)),
                metricType: metric,
                isCustom: sqlite3_column_int(stmt, 6) != 0,
                notes: Hybrid.columnText(stmt, 7),
                formLink: Hybrid.columnText(stmt, 8),
                createdAt: createdAt, updatedAt: updatedAt,
                deletedAt: Hybrid.columnDate(stmt, 11)
            )
        }
    }

    private func column(_ db: DatabaseManager, sessionID: Int, exerciseID: Int, _ col: String) async throws -> Double? {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle,
                "SELECT \(col) FROM session_set WHERE session_id = ? AND exercise_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, sessionID)
            Hybrid.bindInt(stmt, 2, exerciseID)
            guard try Hybrid.step(stmt) else { return nil }
            return sqlite3_column_type(stmt, 0) != SQLITE_NULL ? sqlite3_column_double(stmt, 0) : nil
        }
    }

    private func rowCount(_ db: DatabaseManager, sessionID: Int, exerciseID: Int) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle,
                "SELECT COUNT(*) FROM session_set WHERE session_id = ? AND exercise_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, sessionID)
            Hybrid.bindInt(stmt, 2, exerciseID)
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    func testRepsMapping() async throws {
        let db = try makeTempDB()
        let session = try await SessionRepository(dbManager: db).start(routineID: nil, type: .lift)
        let ex = try await exercise(metricType: "REPS", db)
        let row = SetRowState()
        row.weightText = "60"; row.repsText = "5"
        try await SetRowPersistence.persist(row, exercise: ex, sessionRowID: session.id,
            exerciseOrder: 1, setNumber: 1, distanceUnit: .km, repo: SessionSetRepository(dbManager: db))

        let w = try await column(db, sessionID: session.id, exerciseID: ex.id, "weight_kg")
        let reps = try await column(db, sessionID: session.id, exerciseID: ex.id, "reps")
        XCTAssertEqual(w ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(reps ?? 0, 5, accuracy: 0.001)
    }

    func testTimeMapping() async throws {
        let db = try makeTempDB()
        let session = try await SessionRepository(dbManager: db).start(routineID: nil, type: .lift)
        let ex = try await exercise(metricType: "TIME", db)
        let row = SetRowState()
        row.durationSecsText = "45"
        try await SetRowPersistence.persist(row, exercise: ex, sessionRowID: session.id,
            exerciseOrder: 1, setNumber: 1, distanceUnit: .km, repo: SessionSetRepository(dbManager: db))

        let d = try await column(db, sessionID: session.id, exerciseID: ex.id, "duration_secs")
        XCTAssertEqual(d ?? 0, 45, accuracy: 0.001)
    }

    func testDistanceMileConversion() async throws {
        let db = try makeTempDB()
        let session = try await SessionRepository(dbManager: db).start(routineID: nil, type: .lift)
        let ex = try await exercise(metricType: "DISTANCE", db)
        let row = SetRowState()
        row.distanceText = "1"
        try await SetRowPersistence.persist(row, exercise: ex, sessionRowID: session.id,
            exerciseOrder: 1, setNumber: 1, distanceUnit: .mi, repo: SessionSetRepository(dbManager: db))

        let m = try await column(db, sessionID: session.id, exerciseID: ex.id, "distance_m")
        XCTAssertEqual(m ?? 0, 1609.344, accuracy: 0.001, "1 mi must persist as 1609.344 m")
    }

    func testDistanceKmConversion() async throws {
        let db = try makeTempDB()
        let session = try await SessionRepository(dbManager: db).start(routineID: nil, type: .lift)
        let ex = try await exercise(metricType: "DISTANCE", db)
        let row = SetRowState()
        row.distanceText = "2"
        try await SetRowPersistence.persist(row, exercise: ex, sessionRowID: session.id,
            exerciseOrder: 1, setNumber: 1, distanceUnit: .km, repo: SessionSetRepository(dbManager: db))

        let m = try await column(db, sessionID: session.id, exerciseID: ex.id, "distance_m")
        XCTAssertEqual(m ?? 0, 2000, accuracy: 0.001, "2 km must persist as 2000 m")
    }

    /// Second persist of the same row must UPDATE (not duplicate-insert) and refresh
    /// the cached `persistedSet` snapshot.
    func testUpdateRefreshesSnapshotAndDoesNotDuplicate() async throws {
        let db = try makeTempDB()
        let session = try await SessionRepository(dbManager: db).start(routineID: nil, type: .lift)
        let ex = try await exercise(metricType: "REPS", db)
        let repo = SessionSetRepository(dbManager: db)
        let row = SetRowState()

        row.weightText = "60"; row.repsText = "5"
        try await SetRowPersistence.persist(row, exercise: ex, sessionRowID: session.id,
            exerciseOrder: 1, setNumber: 1, distanceUnit: .km, repo: repo)
        XCTAssertEqual(row.persistedSet?.weightKg ?? 0, 60, accuracy: 0.001)

        row.weightText = "70"
        try await SetRowPersistence.persist(row, exercise: ex, sessionRowID: session.id,
            exerciseOrder: 1, setNumber: 1, distanceUnit: .km, repo: repo)

        let count = try await rowCount(db, sessionID: session.id, exerciseID: ex.id)
        XCTAssertEqual(count, 1, "second persist must update, not insert a duplicate")
        let w = try await column(db, sessionID: session.id, exerciseID: ex.id, "weight_kg")
        XCTAssertEqual(w ?? 0, 70, accuracy: 0.001)
        XCTAssertEqual(row.persistedSet?.weightKg ?? 0, 70, accuracy: 0.001,
            "cached snapshot must reflect the update")
    }

    func testEmptyRowSkipped() async throws {
        let db = try makeTempDB()
        let session = try await SessionRepository(dbManager: db).start(routineID: nil, type: .lift)
        let ex = try await exercise(metricType: "REPS", db)
        let row = SetRowState()  // all blank
        try await SetRowPersistence.persist(row, exercise: ex, sessionRowID: session.id,
            exerciseOrder: 1, setNumber: 1, distanceUnit: .km, repo: SessionSetRepository(dbManager: db))

        let count = try await rowCount(db, sessionID: session.id, exerciseID: ex.id)
        XCTAssertEqual(count, 0, "fully-empty row must not be persisted")
    }
}
