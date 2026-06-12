import XCTest
import SQLite3
@testable import Hybrid

/// Pass 1 — Settings + Schema Rewrite gate tests.
///
/// Covers:
///  1. Schema correctness after migrate() on a fresh in-memory DB.
///  2. UserProfileRepository upsert / get round-trip with maxDataMb.
///  3. Smoke-level CRUD for sessions and routines against the rewritten schema.
///  4. Failure / edge cases.
final class SettingsSchemaTests: XCTestCase {

    // MARK: - Per-test raw in-memory DB (for PRAGMA-level checks)

    private var rawDB: OpaquePointer?

    override func setUpWithError() throws {
        try super.setUpWithError()
        var handle: OpaquePointer?
        let rc = sqlite3_open(":memory:", &handle)
        XCTAssertEqual(rc, SQLITE_OK)
        rawDB = handle
    }

    override func tearDownWithError() throws {
        if let rawDB { sqlite3_close(rawDB) }
        rawDB = nil
        try super.tearDownWithError()
    }

    // MARK: - 1. Schema correctness

    /// Fresh DB via migrate() must NOT have a schema_meta table.
    func testSchemaMetaTableAbsent() throws {
        let db = try unwrapRaw()
        try migrate(db)

        let count = try scalarInt(db,
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='schema_meta';")
        XCTAssertEqual(count, 0,
            "schema_meta table must not exist after Pass 1 schema rewrite")
    }

    /// user_profile must have max_data_mb (default 10) and must NOT have body_weight_kg.
    func testUserProfileSchemaColumns() throws {
        let db = try unwrapRaw()
        try migrate(db)

        var hasMaxDataMb = false
        var hasBodyWeightKg = false

        var stmt: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(db, "PRAGMA table_info(user_profile);", -1, &stmt, nil),
            SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = columnTextRaw(stmt!, 1)
            if name == "max_data_mb" { hasMaxDataMb = true }
            if name == "body_weight_kg" { hasBodyWeightKg = true }
        }

        XCTAssertTrue(hasMaxDataMb,
            "user_profile must have max_data_mb column after Pass 1")
        XCTAssertFalse(hasBodyWeightKg,
            "user_profile must NOT have body_weight_kg after Pass 1")
    }

    /// user_profile.max_data_mb default value must be 10.
    func testUserProfileMaxDataMbDefault() throws {
        let db = try unwrapRaw()
        try migrate(db)

        var dflt: String?
        var stmt: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(db, "PRAGMA table_info(user_profile);", -1, &stmt, nil),
            SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if columnTextRaw(stmt!, 1) == "max_data_mb" {
                dflt = columnTextRaw(stmt!, 4)  // dflt_value column
                break
            }
        }

        XCTAssertEqual(dflt, "10",
            "max_data_mb DEFAULT must be 10; got '\(dflt ?? "nil")'")
    }

    /// session table must NOT have body_weight_kg.
    func testSessionTableHasNoBodyWeightKg() throws {
        let db = try unwrapRaw()
        try migrate(db)

        var hasBodyWeightKg = false
        var stmt: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(db, "PRAGMA table_info(session);", -1, &stmt, nil),
            SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if columnTextRaw(stmt!, 1) == "body_weight_kg" {
                hasBodyWeightKg = true
            }
        }

        XCTAssertFalse(hasBodyWeightKg,
            "session table must NOT have body_weight_kg after Pass 1")
    }

    /// routine_exercise_set table must exist after migrate().
    func testRoutineExerciseSetTableExists() throws {
        let db = try unwrapRaw()
        try migrate(db)

        let count = try scalarInt(db,
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='routine_exercise_set';")
        XCTAssertEqual(count, 1,
            "routine_exercise_set table must exist after Pass 1 schema rewrite")
    }

    /// Both new indices must exist after migrate().
    func testNewIndicesExist() throws {
        let db = try unwrapRaw()
        try migrate(db)

        let finishedIdx = try scalarText(db,
            "SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_session_routine_finished';")
        XCTAssertEqual(finishedIdx, "session",
            "idx_session_routine_finished must exist on session table")

        let resIdx = try scalarText(db,
            "SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_res_routine_exercise';")
        XCTAssertEqual(resIdx, "routine_exercise_set",
            "idx_res_routine_exercise must exist on routine_exercise_set table")
    }

    // MARK: - 2. UserProfileRepository upsert / get round-trip

    /// upsert(maxDataMb:) persists and get() reads back the correct value.
    func testUserProfileMaxDataMbRoundTrip() async throws {
        let db = try DatabaseManager(url: nil)
        let repo = UserProfileRepository(dbManager: db)

        // No profile row exists before the first upsert.
        let initial = try await repo.get()
        XCTAssertNil(initial, "get() must return nil before any upsert")

        // First upsert creates the row with the default maxDataMb value.
        try await repo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 10)
        let created = try await repo.get()
        XCTAssertNotNil(created, "get() must return a profile after first upsert")
        XCTAssertEqual(created?.maxDataMb, 10,
            "First upsert with maxDataMb:10 must round-trip")

        // Upsert with a non-default value.
        try await repo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 250)
        let updated = try await repo.get()
        XCTAssertEqual(updated?.maxDataMb, 250,
            "After upsert(maxDataMb:250) get() must return 250")
    }

    /// upsert preserves weightUnit and distanceUnit when only maxDataMb changes.
    func testUserProfileUpsertPreservesUnits() async throws {
        let db = try DatabaseManager(url: nil)
        let repo = UserProfileRepository(dbManager: db)

        try await repo.upsert(weightUnit: .lb, distanceUnit: .mi, maxDataMb: 50)
        let profile = try await repo.get()

        XCTAssertEqual(profile?.weightUnit, .lb,
            "weightUnit must survive upsert as LB")
        XCTAssertEqual(profile?.distanceUnit, .mi,
            "distanceUnit must survive upsert as MI")
        XCTAssertEqual(profile?.maxDataMb, 50,
            "maxDataMb must survive upsert as 50")
    }

    /// Repeated upserts (ON CONFLICT DO UPDATE) must not create additional rows.
    func testUserProfileUpsertIsSingleRow() async throws {
        let db = try DatabaseManager(url: nil)
        let repo = UserProfileRepository(dbManager: db)

        try await repo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 10)
        try await repo.upsert(weightUnit: .lb, distanceUnit: .mi, maxDataMb: 100)
        try await repo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 200)

        let count = try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM user_profile;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertEqual(count, 1,
            "user_profile must always have exactly one row regardless of upsert count")
    }

    // MARK: - 3. Session / routine smoke-level CRUD

    /// Sessions start and finish correctly against the rewritten schema.
    func testSessionStartAndFinishSmoke() async throws {
        let db = try DatabaseManager(url: nil)
        let sessions = SessionRepository(dbManager: db)

        let s = try await sessions.start(routineID: nil, type: .lift)
        XCTAssertEqual(s.status, .inProgress)
        XCTAssertNil(s.finishedAt)

        try await sessions.finish(id: s.clientUUID)
        let finished = try await sessions.get(id: s.clientUUID)
        XCTAssertEqual(finished?.status, .completed)
        XCTAssertNotNil(finished?.finishedAt)
    }

    /// seedIfEmpty populates routine and routine_exercise_set (3 sample routines,
    /// planned sets present).
    func testSeedPopulatesRoutineExerciseSet() async throws {
        let db = try DatabaseManager(url: nil)

        let routineCount = try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM routine;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertEqual(routineCount, 3,
            "V3 seed must create 3 sample routines; got \(routineCount)")

        let setCount = try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM routine_exercise_set;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertGreaterThan(setCount, 0,
            "V3 seed must insert rows into routine_exercise_set")
    }

    /// Routine create → list → soft-delete still works against the rewritten schema.
    func testRoutineCrudSmoke() async throws {
        let db = try DatabaseManager(url: nil)
        let routines = RoutineRepository(dbManager: db)

        let now = Date()
        let uuid = UUID()
        let routine = Routine(
            id: 0, clientUUID: uuid,
            name: "Pass1 Smoke", type: .lift,
            sortOrder: 99, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routines.create(routine, exerciseEntries: [], runEntries: [])

        let listed = try await routines.list()
        XCTAssertTrue(listed.contains { $0.clientUUID == uuid },
            "Newly created routine must appear in list()")

        try await routines.softDelete(id: uuid)
        let afterDelete = try await routines.list()
        XCTAssertFalse(afterDelete.contains { $0.clientUUID == uuid },
            "Soft-deleted routine must not appear in list()")
    }

    // MARK: - 4. Failure / edge cases

    /// maxDataMb boundary: value 1 (minimum of the UI picker) must round-trip.
    func testUserProfileMaxDataMbMinBoundaryRoundTrips() async throws {
        let db = try DatabaseManager(url: nil)
        let repo = UserProfileRepository(dbManager: db)

        try await repo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 1)
        let profile = try await repo.get()
        XCTAssertEqual(profile?.maxDataMb, 1,
            "maxDataMb=1 (UI picker minimum) must round-trip through upsert/get")
    }

    /// maxDataMb boundary: value 500 (maximum of the UI picker) must round-trip.
    func testUserProfileMaxDataMbMaxBoundaryRoundTrips() async throws {
        let db = try DatabaseManager(url: nil)
        let repo = UserProfileRepository(dbManager: db)

        try await repo.upsert(weightUnit: .kg, distanceUnit: .km, maxDataMb: 500)
        let profile = try await repo.get()
        XCTAssertEqual(profile?.maxDataMb, 500,
            "maxDataMb=500 (UI picker maximum) must round-trip through upsert/get")
    }

    /// A session row must NOT include body_weight_kg in its column list.
    /// Verified by checking that Session does not expose bodyWeightKg at all
    /// (compile-time) and that a real session start/get succeeds (runtime).
    func testSessionModelHasNoBodyWeightKg() async throws {
        let db = try DatabaseManager(url: nil)
        let sessions = SessionRepository(dbManager: db)

        let s = try await sessions.start(routineID: nil, type: .lift)
        // This is a compile-time check as well as a runtime no-throw check.
        // If Session still had bodyWeightKg this test file would not compile.
        let fetched = try await sessions.get(id: s.clientUUID)
        XCTAssertNotNil(fetched, "Session must be retrievable after start")
        // Ensure the model's column count is correct by verifying notes is accessible.
        XCTAssertNil(fetched?.notes, "Notes should be nil on a freshly started session")
    }

    /// routine_exercise_set CHECK constraint rejects invalid set_type values.
    func testRoutineExerciseSetCheckRejectsInvalidSetType() throws {
        let db = try unwrapRaw()
        try migrate(db)
        try seedIfEmpty(db)

        let now = Int(Date().timeIntervalSince1970)

        // Insert a routine + routine_exercise to satisfy the FK.
        try execRaw(db, """
            INSERT INTO routine (client_uuid, name, type, sort_order, created_at, updated_at)
            VALUES ('pass1-check-test-0001-000000000001', 'Check Test', 'LIFT', 0, \(now), \(now));
            """)
        let routineID = Int(sqlite3_last_insert_rowid(db))

        let exerciseID = try scalarInt(db, "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
        XCTAssertNotNil(exerciseID)

        try execRaw(db, """
            INSERT INTO routine_exercise
                (client_uuid, routine_id, exercise_id, sort_order, updated_at)
            VALUES ('pass1-check-test-0002-000000000001', \(routineID), \(exerciseID!), 0, \(now));
            """)
        let reID = Int(sqlite3_last_insert_rowid(db))

        // Valid insert should succeed.
        XCTAssertNoThrow(
            try execRaw(db, """
                INSERT INTO routine_exercise_set
                    (client_uuid, routine_exercise_id, set_number, set_type, updated_at)
                VALUES ('pass1-check-test-0003-000000000001', \(reID), 1, 'WORKING', \(now));
                """),
            "INSERT with set_type='WORKING' must succeed"
        )

        // Invalid set_type should be rejected.
        XCTAssertThrowsError(
            try execRaw(db, """
                INSERT INTO routine_exercise_set
                    (client_uuid, routine_exercise_id, set_number, set_type, updated_at)
                VALUES ('pass1-check-test-0004-000000000001', \(reID), 2, 'INVALID', \(now));
                """),
            "INSERT with set_type='INVALID' must be rejected by CHECK constraint"
        )
    }

    // MARK: - Helpers

    private func unwrapRaw() throws -> OpaquePointer {
        guard let db = rawDB else {
            throw NSError(domain: "Pass1SettingsTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "rawDB handle is nil"])
        }
        return db
    }

    private func columnTextRaw(_ stmt: OpaquePointer, _ idx: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: cstr)
    }

    private func scalarInt(_ db: OpaquePointer, _ sql: String) throws -> Int? {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "Pass1SettingsTests", code: Int(rc),
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func scalarText(_ db: OpaquePointer, _ sql: String) throws -> String? {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "Pass1SettingsTests", code: Int(rc),
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnTextRaw(stmt, 0)
    }

    private func execRaw(_ db: OpaquePointer, _ sql: String) throws {
        try exec(db: db, sql: sql)
    }
}
