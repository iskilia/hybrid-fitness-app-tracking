import SQLite3
import Foundation

// MARK: - DatabaseManager

public actor DatabaseManager {

    // nonisolated(unsafe) is required because OpaquePointer is not Sendable, and
    // deinit in an actor is nonisolated in Swift 6. The actor's serial executor
    // ensures no concurrent access while alive; deinit runs after all references drop.
    private nonisolated(unsafe) var db: OpaquePointer?

    // Exposed for SnapshotWriter (TV3.3) to read the SQLite file size without
    // going through the actor — it's a plain immutable value set at init.
    public nonisolated let dbFileURL: URL?

    // MARK: - Init / deinit

    /// Opens the SQLite database at `url` (pass `nil` for `:memory:`).
    public init(url: URL?) throws {
        self.dbFileURL = url
        let path = url?.path ?? ":memory:"
        var ptr: OpaquePointer?
        // NOFOLLOW: refuse to open through a symlink. PRIVATECACHE: no shared page cache.
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
                  | SQLITE_OPEN_NOFOLLOW | SQLITE_OPEN_PRIVATECACHE
        guard sqlite3_open_v2(path, &ptr, flags, nil) == SQLITE_OK, let opened = ptr else {
            let msg = ptr.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close_v2(ptr)
            throw DatabaseError.openFailed(msg)
        }
        self.db = opened
        Self.harden(opened)
        try migrate(opened)
        try seedIfEmpty(opened)
        if let url { Self.protect(url) }
    }

    // MARK: - Hardening (F3 — keep SQL inside this one file)

    /// Removes SQLite's only filesystem-reaching primitive so that no statement —
    /// even an injected one — can open or read another file inside the sandbox.
    private static func harden(_ db: OpaquePointer) {
        // Extension loading is already impossible: iOS's system SQLite is compiled
        // with SQLITE_OMIT_LOAD_EXTENSION, so load_extension() is not available.
        //
        // Deny ATTACH of any named file. VACUUM performs an internal attach with an
        // empty filename, which must stay allowed, so we only block non-empty names.
        sqlite3_set_authorizer(db, { _, action, arg3, _, _, _ in
            if action == SQLITE_ATTACH, let arg3, strlen(arg3) > 0 {
                return SQLITE_DENY
            }
            return SQLITE_OK
        }, nil)
    }

    // MARK: - Data protection (F1)

    /// Marks the DB file and its WAL siblings as protected so the bytes are
    /// encrypted at rest while the device is locked.
    private static func protect(_ url: URL) {
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: path
            )
        }
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

    /// Wraps `work` in BEGIN / ROLLBACK. ALWAYS rolls back — persists nothing.
    public func transactionRollingBack<T: Sendable>(
        _ work: @Sendable (OpaquePointer) throws -> T
    ) throws -> T {
        let ptr = handle()
        try execSQL(ptr, "BEGIN;")
        do {
            let result = try work(ptr)
            try execSQL(ptr, "ROLLBACK;")
            return result
        } catch {
            try? execSQL(ptr, "ROLLBACK;")
            throw error
        }
    }

    /// Runs VACUUM to reclaim freed pages. Must NOT be called inside a transaction.
    public func vacuum() throws {
        try execSQL(handle(), "VACUUM;")
    }
}
