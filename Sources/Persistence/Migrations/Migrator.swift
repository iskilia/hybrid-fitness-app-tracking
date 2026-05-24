import SQLite3
import Foundation

// MARK: - Error

public enum MigrationError: Error {
    case queryFailed(String)
    case migrationFailed(version: Int, underlying: Error)
}

// MARK: - Public entry point

public func migrate(_ db: OpaquePointer) throws {
    let currentVersion = try readSchemaVersion(db)

    let migrations: [(version: Int, apply: (OpaquePointer) throws -> Void)] = [
        (version: 1, apply: { db in
            try applySchema(db)
            try setSchemaVersion(db, version: 1)
        }),
        (version: 2, apply: { db in
            try applyV2(db)
            try setSchemaVersion(db, version: 2)
        }),
        (version: 3, apply: { db in
            try applyV3(db)
            try setSchemaVersion(db, version: 3)
        }),
        // Append V4, V5, … here as new tuples.
    ]

    for migration in migrations where migration.version > currentVersion {
        do {
            try migration.apply(db)
        } catch {
            throw MigrationError.migrationFailed(version: migration.version, underlying: error)
        }
    }
}

// MARK: - Version helpers

private func readSchemaVersion(_ db: OpaquePointer) throws -> Int {
    // If schema_meta doesn't exist yet, return 0.
    let tableCheck = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='schema_meta';"
    guard let tableCount = try querySingleInt(db, sql: tableCheck) else {
        return 0
    }
    guard tableCount > 0 else { return 0 }

    // Table exists — read the single row.
    let versionQuery = "SELECT version FROM schema_meta WHERE id = 1;"
    guard let version = try querySingleInt(db, sql: versionQuery) else {
        return 0
    }
    return version
}

private func setSchemaVersion(_ db: OpaquePointer, version: Int) throws {
    let now = Int(Date().timeIntervalSince1970)
    let sql = """
        INSERT INTO schema_meta (id, version, applied_at)
        VALUES (1, \(version), \(now))
        ON CONFLICT(id) DO UPDATE SET version = \(version), applied_at = \(now);
        """
    try exec(db: db, sql: sql)
}

// MARK: - V2 migration body

private func applyV2(_ db: OpaquePointer) throws {
    try exec(db: db, sql: "ALTER TABLE routine_exercise ADD COLUMN target_duration_secs_min INTEGER;")
    try exec(db: db, sql: "ALTER TABLE routine_exercise ADD COLUMN target_duration_secs_max INTEGER;")
    try exec(db: db, sql: """
        CREATE INDEX IF NOT EXISTS idx_session_routine_finished
            ON session(routine_id, finished_at DESC);
        """)
}

// MARK: - V3 migration body

private func applyV3(_ db: OpaquePointer) throws {
    try exec(db: db, sql: """
        CREATE TABLE IF NOT EXISTS routine_exercise_set (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_uuid TEXT NOT NULL UNIQUE,
            routine_exercise_id INTEGER NOT NULL REFERENCES routine_exercise(id) ON DELETE CASCADE,
            set_number INTEGER NOT NULL,
            set_type TEXT NOT NULL CHECK (set_type IN ('WARMUP','WORKING','BACKOFF')),
            target_weight_kg REAL,
            target_reps_min INTEGER,
            target_reps_max INTEGER,
            target_duration_secs_min INTEGER,
            target_duration_secs_max INTEGER,
            notes TEXT,
            updated_at INTEGER NOT NULL,
            UNIQUE(routine_exercise_id, set_number)
        );
        """)
    try exec(db: db, sql: """
        CREATE INDEX IF NOT EXISTS idx_res_routine_exercise
            ON routine_exercise_set(routine_exercise_id, set_number);
        """)

    // Backfill: one WORKING row per existing routine_exercise, copying the
    // V2 single-range columns into the per-set row so the UI has something
    // to render after the bump.
    try backfillV3Sets(db)
}

private func backfillV3Sets(_ db: OpaquePointer) throws {
    let selectSQL = """
        SELECT id, target_sets,
               target_rep_min, target_rep_max,
               target_duration_secs_min, target_duration_secs_max
        FROM routine_exercise;
        """
    var rows: [(reID: Int, sets: Int, repMin: Int?, repMax: Int?, durMin: Int?, durMax: Int?)] = []
    do {
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw MigrationError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(stmt, 0))
            let sets = max(1, Int(sqlite3_column_int(stmt, 1)))
            let repMin: Int? = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 2))
            let repMax: Int? = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 3))
            let durMin: Int? = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 4))
            let durMax: Int? = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 5))
            rows.append((id, sets, repMin, repMax, durMin, durMax))
        }
    }

    let now = Int(Date().timeIntervalSince1970)
    let insertSQL = """
        INSERT INTO routine_exercise_set
            (client_uuid, routine_exercise_id, set_number, set_type,
             target_weight_kg, target_reps_min, target_reps_max,
             target_duration_secs_min, target_duration_secs_max,
             notes, updated_at)
        VALUES (?, ?, ?, 'WORKING', NULL, ?, ?, ?, ?, NULL, ?);
        """
    for row in rows {
        for setNumber in 1...row.sets {
            var stmt: OpaquePointer? = nil
            guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
                throw MigrationError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            bindUUID(stmt!, 1, UUID())
            bindInt(stmt!, 2, row.reID)
            bindInt(stmt!, 3, setNumber)
            bindInt(stmt!, 4, row.repMin)
            bindInt(stmt!, 5, row.repMax)
            bindInt(stmt!, 6, row.durMin)
            bindInt(stmt!, 7, row.durMax)
            bindInt(stmt!, 8, now)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw MigrationError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
}

private func querySingleInt(_ db: OpaquePointer, sql: String) throws -> Int? {
    var stmt: OpaquePointer? = nil
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        let msg = String(cString: sqlite3_errmsg(db))
        throw MigrationError.queryFailed(msg)
    }
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
    return Int(sqlite3_column_int(stmt, 0))
}
