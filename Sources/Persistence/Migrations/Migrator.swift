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
        // Append V2, V3, … here as new tuples.
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
