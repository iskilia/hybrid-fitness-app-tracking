import XCTest
import SQLite3
@testable import Hybrid

/// Phase 1 gate (PLAN.md line 127):
/// "unit test creates in-memory DB, applies schema, inserts seed, queries each table successfully."
final class Phase1GateTests: XCTestCase {

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

    /// Migrate fresh DB → schema_meta.version must be 1.
    func testMigrateAppliesV1AndSetsSchemaVersion() throws {
        let db = try unwrapDB()

        XCTAssertNoThrow(try migrate(db), "migrate(db) threw on fresh in-memory DB")

        let version = try scalarInt(db, "SELECT version FROM schema_meta WHERE id = 1;")
        XCTAssertEqual(version, 1, "schema_meta.version should be 1 after baseline migration")
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
            "session",
            "session_tag",
            "session_set",
            "session_run",
            "session_run_split",
            "schema_meta",
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
            "schema_meta",
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
