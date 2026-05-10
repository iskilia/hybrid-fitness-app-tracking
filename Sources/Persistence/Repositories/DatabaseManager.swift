import SQLite3
import Foundation

// MARK: - DatabaseManager

public actor DatabaseManager {

    // nonisolated(unsafe) is required because OpaquePointer is not Sendable, and
    // deinit in an actor is nonisolated in Swift 6. The actor's serial executor
    // ensures no concurrent access while alive; deinit runs after all references drop.
    private nonisolated(unsafe) var db: OpaquePointer?

    // MARK: - Init / deinit

    /// Opens the SQLite database at `url` (pass `nil` for `:memory:`).
    public init(url: URL?) throws {
        let path = url?.path ?? ":memory:"
        var ptr: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &ptr, flags, nil) == SQLITE_OK, let opened = ptr else {
            let msg = ptr.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close_v2(ptr)
            throw DatabaseError.openFailed(msg)
        }
        self.db = opened
        try migrate(opened)
        try seedIfEmpty(opened)
    }

    deinit {
        sqlite3_close_v2(db)
    }

    // MARK: - Raw handle (callers stay on the actor)

    public func handle() -> OpaquePointer {
        // Guaranteed non-nil after successful init.
        db!  // swiftlint:disable:this force_unwrapping
    }

    // MARK: - Read helper

    /// Runs `work` on the actor-isolated DB pointer. Use for reads.
    public func read<T: Sendable>(_ work: @Sendable (OpaquePointer) throws -> T) throws -> T {
        try work(handle())
    }

    // MARK: - Transaction helper

    /// Wraps `work` in BEGIN / COMMIT; rolls back on throw.
    public func transaction<T: Sendable>(_ work: @Sendable (OpaquePointer) throws -> T) throws -> T {
        let ptr = handle()
        try execSQL(ptr, "BEGIN;")
        do {
            let result = try work(ptr)
            try execSQL(ptr, "COMMIT;")
            return result
        } catch {
            try? execSQL(ptr, "ROLLBACK;")
            throw error
        }
    }
}
