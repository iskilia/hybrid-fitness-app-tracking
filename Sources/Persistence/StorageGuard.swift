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

    /// Returns (page_count − freelist_count) × page_size.
    /// Operates on an already-open handle; opens NO transaction.
    func logicalSizeBytes(_ db: OpaquePointer) throws -> Int64 {
        let s1 = try prepare(db, "PRAGMA page_count;")
        defer { finalize(s1) }
        _ = try step(s1)
        let pageCount = Int(sqlite3_column_int64(s1, 0))

        let s2 = try prepare(db, "PRAGMA freelist_count;")
        defer { finalize(s2) }
        _ = try step(s2)
        let freelistCount = Int(sqlite3_column_int64(s2, 0))

        let s3 = try prepare(db, "PRAGMA page_size;")
        defer { finalize(s3) }
        _ = try step(s3)
        let pageSize = Int(sqlite3_column_int64(s3, 0))

        return Int64(pageCount - freelistCount) * Int64(pageSize)
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
