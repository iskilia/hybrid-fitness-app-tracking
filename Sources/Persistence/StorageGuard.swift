import SQLite3
import Foundation

// MARK: - Result + error types

enum ProbeResult: Sendable, Equatable {
    case fits
    case needsEviction(overBy: Int64)
}

enum EvictionOutcome: Sendable, Equatable {
    case fitted        // committed; data now within limit
    case impossible    // nothing (more) evictable but still over; rolled back / no-op
}

enum StorageGuardError: Error { case impossible }

// MARK: - StorageGuard

struct StorageGuard {
    let dbManager: DatabaseManager

    // MARK: - Logical size

    /// Reads a single-row, single-integer PRAGMA on an already-open handle.
    private func pragmaInt64(_ db: OpaquePointer, _ pragma: String) throws -> Int64 {
        let stmt = try prepare(db, pragma)
        defer { finalize(stmt) }
        _ = try step(stmt)
        return sqlite3_column_int64(stmt, 0)   // sqlite3_int64 → Int64, no truncation
    }

    /// Returns (page_count − freelist_count) × page_size.
    /// Operates on an already-open handle; opens NO transaction.
    /// All arithmetic is Int64 end-to-end so the result is exact regardless of the
    /// platform word size (no Int/Int32 intermediate to overflow on a large DB).
    func logicalSizeBytes(_ db: OpaquePointer) throws -> Int64 {
        let pageCount     = try pragmaInt64(db, "PRAGMA page_count;")
        let freelistCount = try pragmaInt64(db, "PRAGMA freelist_count;")
        let pageSize      = try pragmaInt64(db, "PRAGMA page_size;")
        return (pageCount - freelistCount) * pageSize
    }

    // MARK: - Limit

    func limitBytes(maxDataMb: Int) -> Int64 { Int64(maxDataMb) * 1024 * 1024 }

    // MARK: - Over-limit convenience

    func isOverLimit(maxDataMb: Int) async throws -> Bool {
        try await dbManager.read { db in
            try logicalSizeBytes(db) > limitBytes(maxDataMb: maxDataMb)
        }
    }

    // MARK: - Probe (rolls back; persists nothing)

    func probe(insert: @Sendable (OpaquePointer) throws -> Void,
               maxDataMb: Int) async throws -> ProbeResult {
        try await dbManager.transactionRollingBack { db in
            try insert(db)
            let size = try logicalSizeBytes(db)
            let limit = limitBytes(maxDataMb: maxDataMb)
            return size <= limit ? .fits : .needsEviction(overBy: size - limit)
        }
    }

    // MARK: - Commit with eviction

    func commitWithEviction(insert: @Sendable (OpaquePointer) throws -> Void,
                            maxDataMb: Int) async throws -> EvictionOutcome {
        do {
            let outcome = try await dbManager.transaction { db -> EvictionOutcome in
                try insert(db)
                let limit = limitBytes(maxDataMb: maxDataMb)
                while try logicalSizeBytes(db) > limit {
                    guard try evictOldestSession(db) else { throw StorageGuardError.impossible }
                }
                return .fitted
            }
            try await dbManager.vacuum()
            return outcome
        } catch StorageGuardError.impossible {
            return .impossible
        }
    }

    // MARK: - Reconcile (data already persisted)

    func reconcile(maxDataMb: Int) async throws -> EvictionOutcome {
        guard try await isOverLimit(maxDataMb: maxDataMb) else { return .fitted }
        // Data is already persisted; the user confirmed deletion. Evict oldest→newest
        // best-effort and COMMIT what we removed — never roll back. If every evictable
        // session is gone and base tables still exceed the limit (only reachable at an
        // absurdly small limit), we stop: history is cleared, which is the desired outcome.
        try await dbManager.transaction { db in
            let limit = limitBytes(maxDataMb: maxDataMb)
            while try logicalSizeBytes(db) > limit {
                guard try evictOldestSession(db) else { break }
            }
        }
        try await dbManager.vacuum()
        return .fitted
    }

    // MARK: - Delete all history

    /// Deletes ALL session history (session + its child rows) in one transaction.
    /// Keeps routines, custom exercises, the catalog, and the user profile.
    func deleteAllHistory() async throws {
        try await dbManager.transaction { db in
            for sql in [
                "DELETE FROM session_run_split;",
                "DELETE FROM session_run;",
                "DELETE FROM session_set;",
                "DELETE FROM session_tag;",
                "DELETE FROM session;",
            ] {
                let stmt = try prepare(db, sql)
                defer { finalize(stmt) }
                _ = try step(stmt)
            }
        }
        try await dbManager.vacuum()
    }

    // MARK: - Private: evict oldest session

    /// Deletes the single oldest session + its child rows.
    /// Returns true if a session was deleted, false if no sessions remain.
    private func evictOldestSession(_ db: OpaquePointer) throws -> Bool {
        // Find the oldest session (including soft-deleted/abandoned)
        let findStmt = try prepare(db, "SELECT id FROM session ORDER BY started_at ASC, id ASC LIMIT 1;")
        defer { finalize(findStmt) }
        guard try step(findStmt) else { return false }
        let sid = Int(sqlite3_column_int64(findStmt, 0))

        // Delete deepest children first
        let splitStmt = try prepare(db, """
            DELETE FROM session_run_split
             WHERE session_run_id IN (SELECT id FROM session_run WHERE session_id = ?);
            """)
        defer { finalize(splitStmt) }
        bindInt(splitStmt, 1, sid)
        _ = try step(splitStmt)

        let runStmt = try prepare(db, "DELETE FROM session_run WHERE session_id = ?;")
        defer { finalize(runStmt) }
        bindInt(runStmt, 1, sid)
        _ = try step(runStmt)

        let setStmt = try prepare(db, "DELETE FROM session_set WHERE session_id = ?;")
        defer { finalize(setStmt) }
        bindInt(setStmt, 1, sid)
        _ = try step(setStmt)

        let tagStmt = try prepare(db, "DELETE FROM session_tag WHERE session_id = ?;")
        defer { finalize(tagStmt) }
        bindInt(tagStmt, 1, sid)
        _ = try step(tagStmt)

        let sessStmt = try prepare(db, "DELETE FROM session WHERE id = ?;")
        defer { finalize(sessStmt) }
        bindInt(sessStmt, 1, sid)
        _ = try step(sessStmt)

        return true
    }
}
