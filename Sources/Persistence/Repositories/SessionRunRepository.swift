import SQLite3
import Foundation

// MARK: - SessionRunRepository

struct SessionRunRepository {
    let dbManager: DatabaseManager

    // MARK: - Append

    func append(_ run: SessionRun) async throws {
        try await dbManager.transaction { db in
            try insertRun(db, run)
        }
    }

    // MARK: - Finish (update actual results)

    func finish(
        id: UUID,
        distanceKm: Double?,
        durationSec: Int,
        avgPaceSecPerKm: Int?,
        avgHrBpm: Int?
    ) async throws {
        try await dbManager.transaction { db in
            let sql = """
                UPDATE session_run
                SET actual_distance_km = ?, duration_secs = ?,
                    avg_pace_secs = ?, avg_hr = ?, updated_at = ?
                WHERE client_uuid = ?;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindDouble(stmt, 1, distanceKm)
            bindInt(stmt, 2, durationSec)
            bindInt(stmt, 3, avgPaceSecPerKm)
            bindInt(stmt, 4, avgHrBpm)
            bindDate(stmt, 5, Date())
            bindUUID(stmt, 6, id)
            _ = try step(stmt)
        }
    }

    // MARK: - Add split

    func addSplit(_ split: SessionRunSplit) async throws {
        try await dbManager.transaction { db in
            try insertSplit(db, split)
        }
    }

    // MARK: - Splits for a run (ordered by sort_order)

    func splits(sessionRunID: UUID) async throws -> [SessionRunSplit] {
        try await dbManager.read { db in
            // Resolve integer ID
            let idStmt = try prepare(db, "SELECT id FROM session_run WHERE client_uuid = ?;")
            defer { finalize(idStmt) }
            bindUUID(idStmt, 1, sessionRunID)
            guard try step(idStmt), let rowID = columnInt(idStmt, 0) else { return [] }

            let sql = """
                SELECT id, session_run_id, sort_order, block_type,
                       distance_km, duration_secs, avg_pace_secs, avg_hr
                FROM session_run_split
                WHERE session_run_id = ?
                ORDER BY sort_order ASC;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, rowID)
            var result: [SessionRunSplit] = []
            while try step(stmt) {
                result.append(try splitFromStmt(stmt))
            }
            return result
        }
    }

    // MARK: - Fetch by client UUID

    func get(id: UUID) async throws -> SessionRun? {
        try await dbManager.read { db in
            let sql = """
                SELECT id, client_uuid, session_id, run_template_id, run_order,
                       actual_distance_km, duration_secs, avg_pace_secs, avg_hr, max_hr,
                       target_hr_min, target_hr_max, notes, updated_at
                FROM session_run WHERE client_uuid = ?;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindUUID(stmt, 1, id)
            guard try step(stmt),
                  let uuidStr = columnText(stmt, 1),
                  let uuid = UUID(uuidString: uuidStr),
                  let updatedAt = columnDate(stmt, 13)
            else { return nil }
            return SessionRun(
                id: Int(sqlite3_column_int64(stmt, 0)),
                clientUUID: uuid,
                sessionID: columnInt(stmt, 2) ?? 0,
                runTemplateID: columnInt(stmt, 3),
                runOrder: columnInt(stmt, 4) ?? 0,
                actualDistanceKm: columnDouble(stmt, 5),
                durationSecs: columnInt(stmt, 6),
                avgPaceSecs: columnInt(stmt, 7),
                avgHR: columnInt(stmt, 8),
                maxHR: columnInt(stmt, 9),
                targetHRMin: columnInt(stmt, 10),
                targetHRMax: columnInt(stmt, 11),
                notes: columnText(stmt, 12),
                updatedAt: updatedAt
            )
        }
    }

    // MARK: - Best run for a slot (TV5.2b)

    /// Returns the `session_run` row recorded for the given session + template
    /// slot. Each session yields at most one `session_run` per template slot;
    /// when multiple are present (defensive) the highest `run_order` wins.
    func bestRunForSlot(sessionID: Int, templateID: Int) async throws -> SessionRun? {
        try await dbManager.read { db in
            let sql = """
                SELECT id, client_uuid, session_id, run_template_id, run_order,
                       actual_distance_km, duration_secs, avg_pace_secs, avg_hr, max_hr,
                       target_hr_min, target_hr_max, notes, updated_at
                FROM session_run
                WHERE session_id = ? AND run_template_id = ?
                ORDER BY run_order DESC
                LIMIT 1;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, sessionID)
            bindInt(stmt, 2, templateID)
            guard try step(stmt),
                  let uuidStr = columnText(stmt, 1),
                  let uuid = UUID(uuidString: uuidStr),
                  let updatedAt = columnDate(stmt, 13)
            else { return nil }
            return SessionRun(
                id: Int(sqlite3_column_int64(stmt, 0)),
                clientUUID: uuid,
                sessionID: columnInt(stmt, 2) ?? 0,
                runTemplateID: columnInt(stmt, 3),
                runOrder: columnInt(stmt, 4) ?? 0,
                actualDistanceKm: columnDouble(stmt, 5),
                durationSecs: columnInt(stmt, 6),
                avgPaceSecs: columnInt(stmt, 7),
                avgHR: columnInt(stmt, 8),
                maxHR: columnInt(stmt, 9),
                targetHRMin: columnInt(stmt, 10),
                targetHRMax: columnInt(stmt, 11),
                notes: columnText(stmt, 12),
                updatedAt: updatedAt
            )
        }
    }

    // MARK: - Run-template IDs recorded in a session

    /// All `run_template_id`s that have a `session_run` row for this session
    /// (one per slot run; may repeat if a template appears more than once).
    /// Order/duplicates aren't load-bearing — the sole caller wraps this in a
    /// `Set` for removed-slot detection.
    func templateIDs(forSession sessionID: Int) async throws -> [Int] {
        try await dbManager.read { db in
            let stmt = try prepare(db, "SELECT run_template_id FROM session_run WHERE session_id = ?;")
            defer { finalize(stmt) }
            bindInt(stmt, 1, sessionID)
            var ids: [Int] = []
            while try step(stmt) {
                if let tid = columnInt(stmt, 0) { ids.append(tid) }
            }
            return ids
        }
    }

    // MARK: - Delete

    func delete(id: UUID) async throws {
        try await dbManager.transaction { db in
            let stmt = try prepare(db, "DELETE FROM session_run WHERE client_uuid = ?;")
            defer { finalize(stmt) }
            bindUUID(stmt, 1, id)
            _ = try step(stmt)
        }
    }

    // MARK: - Private helpers

    private func insertRun(_ db: OpaquePointer, _ r: SessionRun) throws {
        let sql = """
            INSERT INTO session_run
                (client_uuid, session_id, run_template_id, run_order,
                 actual_distance_km, duration_secs, avg_pace_secs, avg_hr, max_hr,
                 target_hr_min, target_hr_max, notes, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        bindUUID(stmt, 1, r.clientUUID)
        bindInt(stmt, 2, r.sessionID)
        bindInt(stmt, 3, r.runTemplateID)
        bindInt(stmt, 4, r.runOrder)
        bindDouble(stmt, 5, r.actualDistanceKm)
        bindInt(stmt, 6, r.durationSecs)
        bindInt(stmt, 7, r.avgPaceSecs)
        bindInt(stmt, 8, r.avgHR)
        bindInt(stmt, 9, r.maxHR)
        bindInt(stmt, 10, r.targetHRMin)
        bindInt(stmt, 11, r.targetHRMax)
        bindText(stmt, 12, r.notes)
        bindDate(stmt, 13, r.updatedAt)
        _ = try step(stmt)
    }

    private func insertSplit(_ db: OpaquePointer, _ s: SessionRunSplit) throws {
        let sql = """
            INSERT INTO session_run_split
                (session_run_id, sort_order, block_type,
                 distance_km, duration_secs, avg_pace_secs, avg_hr)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        bindInt(stmt, 1, s.sessionRunID)
        bindInt(stmt, 2, s.sortOrder)
        bindText(stmt, 3, s.blockType?.rawValue)
        bindDouble(stmt, 4, s.distanceKm)
        bindInt(stmt, 5, s.durationSecs)
        bindInt(stmt, 6, s.avgPaceSecs)
        bindInt(stmt, 7, s.avgHR)
        _ = try step(stmt)
    }

    private func splitFromStmt(_ stmt: OpaquePointer) throws -> SessionRunSplit {
        let blockType: IntervalBlockType?
        if let str = columnText(stmt, 3) {
            blockType = IntervalBlockType(rawValue: str)
        } else {
            blockType = nil
        }
        return SessionRunSplit(
            id: Int(sqlite3_column_int64(stmt, 0)),
            sessionRunID: columnInt(stmt, 1) ?? 0,
            sortOrder: columnInt(stmt, 2) ?? 0,
            blockType: blockType,
            distanceKm: columnDouble(stmt, 4),
            durationSecs: columnInt(stmt, 5),
            avgPaceSecs: columnInt(stmt, 6),
            avgHR: columnInt(stmt, 7)
        )
    }
}
