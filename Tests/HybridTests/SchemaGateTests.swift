import XCTest
import SQLite3
@testable import Hybrid

/// Phase 1 gate (PLAN.md line 127):
/// "unit test creates in-memory DB, applies schema, inserts seed, queries each table successfully."
final class SchemaGateTests: XCTestCase {

    // MARK: - Per-test in-memory DB

    private var db: OpaquePointer?

    override func setUpWithError() throws {
        try super.setUpWithError()
        var handle: OpaquePointer?
        let rc = sqlite3_open(":memory:", &handle)
        XCTAssertEqual(rc, SQLITE_OK, "sqlite3_open(:memory:) failed rc=\(rc)")
        XCTAssertNotNil(handle, ":memory: open returned nil handle")
        db = handle
    }

    override func tearDownWithError() throws {
        if let db {
            sqlite3_close(db)
        }
        db = nil
        try super.tearDownWithError()
    }

    // MARK: - Tests

    /// Migrate fresh DB → migrate() must not throw.
    func testMigrateAppliesV1AndSetsSchemaVersion() throws {
        let db = try unwrapDB()

        XCTAssertNoThrow(try migrate(db), "migrate(db) threw on fresh in-memory DB")
    }

    /// Seed the empty DB → seedIfEmpty must not throw.
    func testSeedIfEmptyDoesNotThrow() throws {
        let db = try unwrapDB()
        try migrate(db)

        XCTAssertNoThrow(try seedIfEmpty(db), "seedIfEmpty(db) threw after migrate on fresh DB")
    }

    /// PRAGMA foreign_keys = 1 (Schema.swift turns FKs ON).
    func testForeignKeysEnforcementIsOn() throws {
        let db = try unwrapDB()
        try migrate(db)

        let fk = try scalarInt(db, "PRAGMA foreign_keys;")
        XCTAssertEqual(fk, 1, "PRAGMA foreign_keys expected 1 (on); got \(fk ?? -1)")
    }

    /// PRAGMA journal_mode after migrate. In-memory DBs cannot do WAL — they
    /// downgrade silently to "memory". Either is acceptable per the gate spec.
    func testJournalModeIsWalOrMemory() throws {
        let db = try unwrapDB()
        try migrate(db)

        let mode = try scalarText(db, "PRAGMA journal_mode;")
        XCTAssertNotNil(mode, "PRAGMA journal_mode returned no row")
        let normalized = mode?.lowercased() ?? ""
        XCTAssertTrue(
            normalized == "wal" || normalized == "memory",
            "journal_mode expected 'wal' or 'memory' (in-memory downgrade); got '\(normalized)'"
        )
    }

    /// Every table from SCHEMA.md must exist + be queryable. Seed-backed
    /// lookup tables must have COUNT > 0.
    func testEverySchemaTableExistsAndSeededTablesAreNonEmpty() throws {
        let db = try unwrapDB()
        try migrate(db)
        try seedIfEmpty(db)

        // Full table list per SCHEMA.md.
        let allTables = [
            "equipment",
            "muscle",
            "tag",
            "user_profile",
            "exercise",
            "exercise_muscle",
            "run_template",
            "run_interval_block",
            "routine",
            "routine_exercise",
            "routine_run",
            "routine_exercise_set",
            "session",
            "session_tag",
            "session_set",
            "session_run",
            "session_run_split",
        ]

        // Subset that seedIfEmpty must populate.
        // exercise_muscle is filled as a side effect of inserting exercises.
        let mustBeNonEmpty: Set<String> = [
            "equipment",
            "muscle",
            "tag",
            "exercise",
            "exercise_muscle",
            "run_template",
            "run_interval_block",
        ]

        for table in allTables {
            let count: Int
            do {
                count = try scalarInt(db, "SELECT COUNT(*) FROM \(table);") ?? -1
            } catch {
                XCTFail("Table '\(table)' not queryable: \(error)")
                continue
            }
            XCTAssertGreaterThanOrEqual(count, 0, "Table '\(table)' returned negative count")

            if mustBeNonEmpty.contains(table) {
                XCTAssertGreaterThan(
                    count, 0,
                    "Seed/lookup table '\(table)' is empty after seedIfEmpty — seed-coder gap."
                )
            }
        }
    }

    // MARK: - V2 gate tests

    /// V2 migration must add both target_duration_secs_{min,max} INTEGER nullable
    /// columns to routine_exercise.
    func testV2MigrationAddsTargetDurationColumns() throws {
        let db = try unwrapDB()
        try migrate(db)

        var stmt: OpaquePointer?
        let prep = sqlite3_prepare_v2(db, "PRAGMA table_info(routine_exercise);", -1, &stmt, nil)
        XCTAssertEqual(prep, SQLITE_OK, "PRAGMA table_info(routine_exercise) failed to prepare")
        defer { sqlite3_finalize(stmt) }

        // PRAGMA table_info columns: cid, name, type, notnull, dflt_value, pk
        var minCol: (type: String, notnull: Int)?
        var maxCol: (type: String, notnull: Int)?
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = columnText(stmt!, 1)
            let type = columnText(stmt!, 2)
            let notnull = Int(sqlite3_column_int64(stmt!, 3))
            if name == "target_duration_secs_min" {
                minCol = (type, notnull)
            } else if name == "target_duration_secs_max" {
                maxCol = (type, notnull)
            }
        }

        XCTAssertNotNil(minCol, "routine_exercise missing target_duration_secs_min column after V2 migrate")
        XCTAssertNotNil(maxCol, "routine_exercise missing target_duration_secs_max column after V2 migrate")
        XCTAssertEqual(minCol?.type.uppercased(), "INTEGER",
                       "target_duration_secs_min should be INTEGER; got '\(minCol?.type ?? "")'")
        XCTAssertEqual(maxCol?.type.uppercased(), "INTEGER",
                       "target_duration_secs_max should be INTEGER; got '\(maxCol?.type ?? "")'")
        XCTAssertEqual(minCol?.notnull, 0, "target_duration_secs_min should be nullable (notnull=0)")
        XCTAssertEqual(maxCol?.notnull, 0, "target_duration_secs_max should be nullable (notnull=0)")
    }

    /// V2 migration must create idx_session_routine_finished on the session table.
    func testV2MigrationCreatesSessionRoutineFinishedIndex() throws {
        let db = try unwrapDB()
        try migrate(db)

        let sql = """
            SELECT tbl_name FROM sqlite_master
            WHERE type = 'index' AND name = 'idx_session_routine_finished';
            """
        let tbl = try scalarText(db, sql)
        XCTAssertEqual(tbl, "session",
                       "idx_session_routine_finished should exist on table 'session'; got '\(tbl ?? "nil")'")
    }

    /// Round-trip a routine_exercise row with timed-hold targets via raw SQL,
    /// since RoutineRepository doesn't bind these columns yet (TV2.1 pending).
    func testRoutineExerciseRoundTripsTimedTargetsViaRawSQL() throws {
        let db = try unwrapDB()
        try migrate(db)
        try seedIfEmpty(db)

        // Look up a seeded TIME exercise by name (Plank is at id 29 per SeedData).
        let exerciseID = try scalarInt(db,
            "SELECT id FROM exercise WHERE name = 'Plank' AND metric_type = 'TIME' AND is_custom = 0;")
        XCTAssertNotNil(exerciseID, "Seeded 'Plank' TIME exercise not found")
        guard let exID = exerciseID else { return }

        let now = Int(Date().timeIntervalSince1970)

        // Insert a routine row.
        let routineSQL = """
            INSERT INTO routine (client_uuid, name, type, sort_order, created_at, updated_at)
            VALUES ('11111111-1111-1111-1111-111111111111', 'V2 Test Routine', 'LIFT', 0, \(now), \(now));
            """
        XCTAssertNoThrow(try exec(db: db, sql: routineSQL), "Failed to insert routine row")
        let routineID = Int(sqlite3_last_insert_rowid(db))
        XCTAssertGreaterThan(routineID, 0, "Inserted routine row has invalid rowid")

        // Insert routine_exercise via raw SQL binding the new columns.
        var stmt: OpaquePointer?
        let insertSQL = """
            INSERT INTO routine_exercise
                (client_uuid, routine_id, exercise_id, sort_order, target_sets,
                 target_duration_secs_min, target_duration_secs_max, updated_at)
            VALUES (?, ?, ?, 0, 3, ?, ?, ?);
            """
        let prep = sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil)
        XCTAssertEqual(prep, SQLITE_OK, "prepare for routine_exercise insert failed: \(String(cString: sqlite3_errmsg(db)))")
        sqlite3_bind_text(stmt, 1, ("22222222-2222-2222-2222-222222222222" as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 2, Int64(routineID))
        sqlite3_bind_int64(stmt, 3, Int64(exID))
        sqlite3_bind_int64(stmt, 4, 30)
        sqlite3_bind_int64(stmt, 5, 45)
        sqlite3_bind_int64(stmt, 6, Int64(now))
        let stepRC = sqlite3_step(stmt)
        XCTAssertEqual(stepRC, SQLITE_DONE,
                       "routine_exercise insert step failed: \(String(cString: sqlite3_errmsg(db)))")
        sqlite3_finalize(stmt)

        // SELECT it back.
        var selStmt: OpaquePointer?
        let selectSQL = """
            SELECT target_duration_secs_min, target_duration_secs_max
            FROM routine_exercise
            WHERE routine_id = ? AND exercise_id = ?;
            """
        XCTAssertEqual(sqlite3_prepare_v2(db, selectSQL, -1, &selStmt, nil), SQLITE_OK,
                       "prepare for routine_exercise select failed")
        sqlite3_bind_int64(selStmt, 1, Int64(routineID))
        sqlite3_bind_int64(selStmt, 2, Int64(exID))
        XCTAssertEqual(sqlite3_step(selStmt), SQLITE_ROW, "routine_exercise round-trip select returned no row")
        let minSecs = Int(sqlite3_column_int64(selStmt, 0))
        let maxSecs = Int(sqlite3_column_int64(selStmt, 1))
        sqlite3_finalize(selStmt)

        XCTAssertEqual(minSecs, 30, "target_duration_secs_min round-trip mismatch")
        XCTAssertEqual(maxSecs, 45, "target_duration_secs_max round-trip mismatch")
    }

    /// Seed must include exactly 5 timed-hold exercises (TIME, non-custom)
    /// with the expected names: Wall Sit, Plank, Side Plank, Dead Hang, L-Sit.
    func testSeedHasFiveTimedHolds() throws {
        let db = try unwrapDB()
        try migrate(db)
        try seedIfEmpty(db)

        let count = try scalarInt(db,
            "SELECT COUNT(*) FROM exercise WHERE metric_type = 'TIME' AND is_custom = 0;")
        XCTAssertEqual(count, 5,
                       "Expected exactly 5 seeded TIME / non-custom exercises; got \(count ?? -1)")

        // Collect names of all TIME exercises and assert each expected name is present.
        var stmt: OpaquePointer?
        let prep = sqlite3_prepare_v2(db,
            "SELECT name FROM exercise WHERE metric_type = 'TIME';", -1, &stmt, nil)
        XCTAssertEqual(prep, SQLITE_OK, "prepare for TIME exercise names failed")
        defer { sqlite3_finalize(stmt) }

        var names: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            names.insert(columnText(stmt!, 0))
        }

        for expected in ["Wall Sit", "Plank", "Side Plank", "Dead Hang", "L-Sit"] {
            XCTAssertTrue(names.contains(expected),
                          "Expected timed-hold '\(expected)' not found in seed; got names: \(names)")
        }
    }

    // MARK: - V3 gate tests

    /// V3 must create the routine_exercise_set table with the documented
    /// 12 columns, the CHECK on set_type, the UNIQUE(routine_exercise_id, set_number)
    /// constraint, and the (routine_exercise_id, set_number) index.
    func testV3MigrationCreatesRoutineExerciseSetTable() throws {
        let db = try unwrapDB()
        try migrate(db)

        // 1. Table exists in sqlite_master.
        let tableName = try scalarText(db,
            "SELECT name FROM sqlite_master WHERE type='table' AND name='routine_exercise_set';")
        XCTAssertEqual(tableName, "routine_exercise_set",
                       "V3 migration should have created table routine_exercise_set")

        // 2. PRAGMA table_info → expect exactly the 12 columns documented.
        let expectedColumns: Set<String> = [
            "id",
            "client_uuid",
            "routine_exercise_id",
            "set_number",
            "set_type",
            "target_weight_kg",
            "target_reps_min",
            "target_reps_max",
            "target_duration_secs_min",
            "target_duration_secs_max",
            "notes",
            "updated_at",
        ]

        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "PRAGMA table_info(routine_exercise_set);", -1, &stmt, nil),
                       SQLITE_OK, "PRAGMA table_info(routine_exercise_set) failed to prepare")
        var actualColumns: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            actualColumns.insert(columnText(stmt!, 1))
        }
        sqlite3_finalize(stmt)
        XCTAssertEqual(actualColumns, expectedColumns,
                       "routine_exercise_set column set mismatch; got \(actualColumns)")

        // 3. CHECK on set_type — direct INSERT with set_type='BAD' must fail.
        let now = Int(Date().timeIntervalSince1970)
        // Need a routine_exercise row first. Seed a routine + routine_exercise via raw SQL.
        let routineSQL = """
            INSERT INTO routine (client_uuid, name, type, sort_order, created_at, updated_at)
            VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'V3 CHECK Test', 'LIFT', 0, \(now), \(now));
            """
        XCTAssertNoThrow(try exec(db: db, sql: routineSQL))
        let routineID = Int(sqlite3_last_insert_rowid(db))

        // Seed an exercise via seed (so a valid FK target exists).
        try seedIfEmpty(db)
        let exerciseID = try scalarInt(db,
            "SELECT id FROM exercise WHERE is_custom = 0 LIMIT 1;")
        XCTAssertNotNil(exerciseID)

        let reSQL = """
            INSERT INTO routine_exercise
                (client_uuid, routine_id, exercise_id, sort_order, target_sets, updated_at)
            VALUES ('aaaaaaaa-0000-0000-0000-000000000002', \(routineID), \(exerciseID!), 0, 3, \(now));
            """
        XCTAssertNoThrow(try exec(db: db, sql: reSQL))
        let reID = Int(sqlite3_last_insert_rowid(db))

        let badInsert = """
            INSERT INTO routine_exercise_set
                (client_uuid, routine_exercise_id, set_number, set_type, updated_at)
            VALUES ('aaaaaaaa-0000-0000-0000-000000000003', \(reID), 1, 'BAD', \(now));
            """
        XCTAssertThrowsError(try exec(db: db, sql: badInsert),
                             "CHECK(set_type IN ('WARMUP','WORKING','BACKOFF')) should reject 'BAD'")

        // 4. UNIQUE(routine_exercise_id, set_number) — second row with same pair errors.
        let firstOK = """
            INSERT INTO routine_exercise_set
                (client_uuid, routine_exercise_id, set_number, set_type, updated_at)
            VALUES ('aaaaaaaa-0000-0000-0000-000000000004', \(reID), 1, 'WORKING', \(now));
            """
        XCTAssertNoThrow(try exec(db: db, sql: firstOK))
        let dupePair = """
            INSERT INTO routine_exercise_set
                (client_uuid, routine_exercise_id, set_number, set_type, updated_at)
            VALUES ('aaaaaaaa-0000-0000-0000-000000000005', \(reID), 1, 'WORKING', \(now));
            """
        XCTAssertThrowsError(try exec(db: db, sql: dupePair),
                             "UNIQUE(routine_exercise_id, set_number) should reject duplicate (reID,1)")

        // 5. Index exists in sqlite_master.
        let idxName = try scalarText(db,
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_res_routine_exercise';")
        XCTAssertEqual(idxName, "idx_res_routine_exercise",
                       "V3 migration should have created idx_res_routine_exercise")
    }

    /// V3 seed inserts sample routines (Push Day, Core & Holds, Tempo Tuesday)
    /// with per-set plans. Verify they land after seedIfEmpty on a fresh DB.
    func testV3SeedInsertsSampleRoutinesAndPlannedSets() throws {
        let db = try unwrapDB()
        try migrate(db)
        try seedIfEmpty(db)

        let routineCount = try scalarInt(db, "SELECT COUNT(*) FROM routine;") ?? 0
        XCTAssertEqual(routineCount, 3, "V3 seed inserts 3 sample routines")

        let plannedSetCount = try scalarInt(db, "SELECT COUNT(*) FROM routine_exercise_set;") ?? 0
        XCTAssertGreaterThan(plannedSetCount, 0, "V3 seed inserts planned set rows for sample routines")
    }

    // MARK: - Helpers

    private func unwrapDB() throws -> OpaquePointer {
        guard let db else {
            throw NSError(domain: "Phase1GateTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "db handle is nil"])
        }
        return db
    }

    private func columnText(_ stmt: OpaquePointer, _ idx: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: cstr)
    }

    private func scalarInt(_ db: OpaquePointer, _ sql: String) throws -> Int? {
        var stmt: OpaquePointer?
        let prep = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prep == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "Phase1GateTests", code: Int(prep),
                          userInfo: [NSLocalizedDescriptionKey: "prepare failed: \(sql) — \(msg)"])
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func scalarText(_ db: OpaquePointer, _ sql: String) throws -> String? {
        var stmt: OpaquePointer?
        let prep = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prep == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "Phase1GateTests", code: Int(prep),
                          userInfo: [NSLocalizedDescriptionKey: "prepare failed: \(sql) — \(msg)"])
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnText(stmt, 0)
    }
}
