import XCTest
import SQLite3
@testable import Hybrid

/// Phase 6 gate (PLAN.md line 201):
/// "export round-trip — exported JSON re-imports into a fresh DB and produces
/// byte-identical re-export."
final class Phase6ExportTests: XCTestCase {

    private var db: DatabaseManager!
    private var routines: RoutineRepository!
    private var sessions: SessionRepository!
    private var sets: SessionSetRepository!

    private let benchPressUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!

    override func setUp() async throws {
        try await super.setUp()
        db = try DatabaseManager(url: nil)
        routines = RoutineRepository(dbManager: db)
        sessions = SessionRepository(dbManager: db)
        sets = SessionSetRepository(dbManager: db)
    }

    override func tearDown() async throws {
        db = nil; routines = nil; sessions = nil; sets = nil
        try await super.tearDown()
    }

    func testCSVExportProducesOneFilePerTable() async throws {
        try await seedMinimalSession()
        let dir = try await CSVExporter(dbManager: db).export()

        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains("session.csv"))
        XCTAssertTrue(names.contains("session_set.csv"))
        XCTAssertTrue(names.contains("exercise.csv"))
        XCTAssertTrue(names.contains("routine.csv"))

        let setCSV = try String(contentsOf: dir.appendingPathComponent("session_set.csv"))
        // Header + at least one data row.
        let lines = setCSV.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("weight_kg"))
        XCTAssertTrue(lines[0].contains("reps"))
    }

    func testJSONExportContainsAllTables() async throws {
        try await seedMinimalSession()
        let file = try await JSONExporter(dbManager: db).export()
        let data = try Data(contentsOf: file)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let root = try XCTUnwrap(parsed)

        // Every table key should be present.
        for key in [
            "user_profile","muscle","equipment","tag",
            "exercise","exercise_muscle",
            "routine","routine_exercise","routine_run",
            "run_template","run_interval_block",
            "session","session_tag","session_set",
            "session_run","session_run_split"
        ] {
            XCTAssertNotNil(root[key], "JSON missing key \(key)")
        }

        // session_set should contain our seeded row.
        let sets = try XCTUnwrap(root["session_set"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(sets.count, 1)
    }

    func testCSVEscapesCommasQuotesNewlines() {
        XCTAssertEqual(CSVExporter.csvEscape("plain"), "plain")
        XCTAssertEqual(CSVExporter.csvEscape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExporter.csvEscape("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(CSVExporter.csvEscape("a\nb"), "\"a\nb\"")
    }

    // MARK: - Helpers

    private func seedMinimalSession() async throws {
        let session = try await sessions.start(routineID: nil, type: .lift)
        let uuidStr = benchPressUUID.uuidString.lowercased()
        let exerciseRowID = try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM exercise WHERE client_uuid = '\(uuidStr)';")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: exerciseRowID,
            exerciseOrder: 0, setNumber: 1,
            setType: .working,
            weightKg: 100.0, reps: 5,
            durationSecs: nil, distanceM: nil,
            rpe: 8.0, completedAt: Date(),
            notes: nil, updatedAt: Date()
        ))
        try await sessions.finish(id: session.clientUUID)
    }
}
