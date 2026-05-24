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
        // Append V3, V4, … here as new tuples.
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
