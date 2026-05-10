import SQLite3
import Foundation

// MARK: - Date serialization
// Dates are stored as INTEGER (Unix epoch seconds) to match the schema DDL.
// All timestamp columns in the schema are declared INTEGER NOT NULL / INTEGER.

// MARK: - Prepare

func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
        let msg = String(cString: sqlite3_errmsg(db))
        throw DatabaseError.prepareFailed(msg)
    }
    return s
}

// MARK: - Bind helpers

func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ value: String?) {
    if let v = value {
        sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, nil)
    } else {
        sqlite3_bind_null(stmt, idx)
    }
}

func bindInt(_ stmt: OpaquePointer, _ idx: Int32, _ value: Int?) {
    if let v = value {
        sqlite3_bind_int64(stmt, idx, Int64(v))
    } else {
        sqlite3_bind_null(stmt, idx)
    }
}

func bindDouble(_ stmt: OpaquePointer, _ idx: Int32, _ value: Double?) {
    if let v = value {
        sqlite3_bind_double(stmt, idx, v)
    } else {
        sqlite3_bind_null(stmt, idx)
    }
}

func bindBool(_ stmt: OpaquePointer, _ idx: Int32, _ value: Bool) {
    sqlite3_bind_int64(stmt, idx, value ? 1 : 0)
}

/// Stores UUID as TEXT in the standard hyphenated lowercase format.
func bindUUID(_ stmt: OpaquePointer, _ idx: Int32, _ value: UUID) {
    bindText(stmt, idx, value.uuidString.lowercased())
}

/// Stores Date as INTEGER (Unix epoch seconds).
func bindDate(_ stmt: OpaquePointer, _ idx: Int32, _ value: Date?) {
    if let v = value {
        sqlite3_bind_int64(stmt, idx, Int64(v.timeIntervalSince1970))
    } else {
        sqlite3_bind_null(stmt, idx)
    }
}

// MARK: - Column readers

func columnText(_ stmt: OpaquePointer, _ col: Int32) -> String? {
    guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
    guard let ptr = sqlite3_column_text(stmt, col) else { return nil }
    return String(cString: ptr)
}

func columnInt(_ stmt: OpaquePointer, _ col: Int32) -> Int? {
    guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
    return Int(sqlite3_column_int64(stmt, col))
}

func columnDouble(_ stmt: OpaquePointer, _ col: Int32) -> Double? {
    guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
    return sqlite3_column_double(stmt, col)
}

func columnBool(_ stmt: OpaquePointer, _ col: Int32) -> Bool {
    sqlite3_column_int64(stmt, col) != 0
}

/// Reads a UUID stored as TEXT (hyphenated, case-insensitive).
func columnUUID(_ stmt: OpaquePointer, _ col: Int32) -> UUID? {
    guard let text = columnText(stmt, col) else { return nil }
    return UUID(uuidString: text)
}

/// Reads a Date stored as INTEGER (Unix epoch seconds).
func columnDate(_ stmt: OpaquePointer, _ col: Int32) -> Date? {
    guard let epoch = columnInt(stmt, col) else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(epoch))
}

// MARK: - Step

/// Returns true when a row is available, false when done, throws on error.
func step(_ stmt: OpaquePointer) throws -> Bool {
    let rc = sqlite3_step(stmt)
    switch rc {
    case SQLITE_ROW:  return true
    case SQLITE_DONE: return false
    default:
        let msg = String(cString: sqlite3_errmsg(sqlite3_db_handle(stmt)))
        throw DatabaseError.stepFailed(msg)
    }
}

// MARK: - Finalize (deferred-friendly)

func finalize(_ stmt: OpaquePointer?) {
    sqlite3_finalize(stmt)
}

// MARK: - Execute raw SQL (no bind parameters)

func execSQL(_ db: OpaquePointer, _ sql: String) throws {
    var err: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &err)
    if rc != SQLITE_OK {
        let msg = err.map { String(cString: $0) } ?? "unknown"
        sqlite3_free(err)
        throw DatabaseError.stepFailed(msg)
    }
}
