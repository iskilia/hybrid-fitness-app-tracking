import SQLite3
import Foundation

// MARK: - WeekStats

struct WeekStats: Sendable {
    let sessionCount: Int
    let totalTonnageKg: Double   // sum(weight_kg * reps) across all session_set rows in window
    let totalDistanceKm: Double  // sum(session_run.actual_distance_km) in window
}

// MARK: - SessionRepository

struct SessionRepository {
    let dbManager: DatabaseManager

    // MARK: - Start

    func start(routineID: UUID?, type: WorkoutType) async throws -> Session {
        try await dbManager.transaction { db in
            let now = Date()
            let clientUUID = UUID()

            // Resolve routineID to integer if provided
            var routineRowID: Int?
            if let rID = routineID {
                let stmt = try prepare(db, "SELECT id FROM routine WHERE client_uuid = ?;")
                defer { finalize(stmt) }
                bindUUID(stmt, 1, rID)
                if try step(stmt) { routineRowID = columnInt(stmt, 0) }
            }

            let sql = """
                INSERT INTO session
                    (client_uuid, routine_id, type, status, started_at, updated_at)
                VALUES (?, ?, ?, 'IN_PROGRESS', ?, ?);
                """
            let insertStmt = try prepare(db, sql)
            defer { finalize(insertStmt) }
            bindUUID(insertStmt, 1, clientUUID)
            bindInt(insertStmt, 2, routineRowID)
            bindText(insertStmt, 3, type.rawValue)
            bindDate(insertStmt, 4, now)
            bindDate(insertStmt, 5, now)
            _ = try step(insertStmt)

            let rowID = Int(sqlite3_last_insert_rowid(db))
            return Session(
                id: rowID,
                clientUUID: clientUUID,
                routineID: routineRowID,
                type: type,
                status: .inProgress,
                startedAt: now,
                finishedAt: nil,
                bodyWeightKg: nil,
                notes: nil,
                updatedAt: now,
                deletedAt: nil
            )
        }
    }

    // MARK: - Finish

    func finish(id: UUID) async throws {
        try await dbManager.transaction { db in
            let now = Date()
            let sql = """
                UPDATE session
                SET status = 'COMPLETED', finished_at = ?, updated_at = ?
                WHERE client_uuid = ?;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindDate(stmt, 1, now)
            bindDate(stmt, 2, now)
            bindUUID(stmt, 3, id)
            _ = try step(stmt)
        }
    }

    // MARK: - Abandon

    func abandon(id: UUID) async throws {
        try await dbManager.transaction { db in
            let now = Date()
            let sql = """
                UPDATE session
                SET status = 'ABANDONED', finished_at = ?, updated_at = ?
                WHERE client_uuid = ?;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindDate(stmt, 1, now)
            bindDate(stmt, 2, now)
            bindUUID(stmt, 3, id)
            _ = try step(stmt)
        }
    }

    // MARK: - Get by UUID

    func get(id: UUID) async throws -> Session? {
        try await dbManager.read { db in
            let sql = sessionSelectSQL() + " WHERE s.client_uuid = ? AND s.deleted_at IS NULL;"
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindUUID(stmt, 1, id)
            guard try step(stmt) else { return nil }
            return try sessionFromStmt(stmt)
        }
    }

    // MARK: - List by date range

    func list(from: Date, to: Date) async throws -> [Session] {
        try await dbManager.read { db in
            let sql = sessionSelectSQL() + """
                 WHERE s.deleted_at IS NULL
                   AND s.started_at >= ? AND s.started_at <= ?
                 ORDER BY s.started_at DESC;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindDate(stmt, 1, from)
            bindDate(stmt, 2, to)
            var result: [Session] = []
            while try step(stmt) {
                result.append(try sessionFromStmt(stmt))
            }
            return result
        }
    }

    // MARK: - Last completed session for a routine

    func lastCompletedSession(forRoutineID routineID: Int) async throws -> Session? {
        try await dbManager.read { db in
            let sql = sessionSelectSQL() + """
                 WHERE s.routine_id = ?
                   AND s.status = 'COMPLETED'
                   AND s.deleted_at IS NULL
                 ORDER BY s.finished_at DESC
                 LIMIT 1;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, routineID)
            guard try step(stmt) else { return nil }
            return try sessionFromStmt(stmt)
        }
    }

    // MARK: - Week stats

    func weekStats(weekStart: Date) async throws -> WeekStats {
        try await dbManager.read { db in
            let weekEnd = weekStart.addingTimeInterval(7 * 24 * 60 * 60)
            let startEpoch = Int(weekStart.timeIntervalSince1970)
            let endEpoch = Int(weekEnd.timeIntervalSince1970)

            // Session count in window
            let countSQL = """
                SELECT COUNT(*) FROM session
                WHERE deleted_at IS NULL
                  AND started_at >= ? AND started_at < ?;
                """
            let countStmt = try prepare(db, countSQL)
            defer { finalize(countStmt) }
            bindInt(countStmt, 1, startEpoch)
            bindInt(countStmt, 2, endEpoch)
            _ = try step(countStmt)
            let sessionCount = Int(sqlite3_column_int64(countStmt, 0))

            // Total tonnage: sum(weight_kg * reps) for sets in completed sessions in window
            let tonnageSQL = """
                SELECT COALESCE(SUM(ss.weight_kg * ss.reps), 0.0)
                FROM session_set ss
                JOIN session s ON s.id = ss.session_id
                WHERE s.deleted_at IS NULL
                  AND s.started_at >= ? AND s.started_at < ?
                  AND ss.weight_kg IS NOT NULL AND ss.reps IS NOT NULL;
                """
            let tonnageStmt = try prepare(db, tonnageSQL)
            defer { finalize(tonnageStmt) }
            bindInt(tonnageStmt, 1, startEpoch)
            bindInt(tonnageStmt, 2, endEpoch)
            _ = try step(tonnageStmt)
            let totalTonnage = sqlite3_column_double(tonnageStmt, 0)

            // Total distance: sum(actual_distance_km) for runs in window
            let distSQL = """
                SELECT COALESCE(SUM(sr.actual_distance_km), 0.0)
                FROM session_run sr
                JOIN session s ON s.id = sr.session_id
                WHERE s.deleted_at IS NULL
                  AND s.started_at >= ? AND s.started_at < ?
                  AND sr.actual_distance_km IS NOT NULL;
                """
            let distStmt = try prepare(db, distSQL)
            defer { finalize(distStmt) }
            bindInt(distStmt, 1, startEpoch)
            bindInt(distStmt, 2, endEpoch)
            _ = try step(distStmt)
            let totalDistance = sqlite3_column_double(distStmt, 0)

            return WeekStats(
                sessionCount: sessionCount,
                totalTonnageKg: totalTonnage,
                totalDistanceKm: totalDistance
            )
        }
    }

    // MARK: - Private helpers

    private func sessionSelectSQL() -> String {
        """
        SELECT s.id, s.client_uuid, s.routine_id, s.type, s.status,
               s.started_at, s.finished_at, s.body_weight_kg, s.notes,
               s.updated_at, s.deleted_at
        FROM session s
        """
    }

    private func sessionFromStmt(_ stmt: OpaquePointer) throws -> Session {
        guard
            let uuidStr = columnText(stmt, 1),
            let uuid = UUID(uuidString: uuidStr),
            let typeStr = columnText(stmt, 3),
            let type = WorkoutType(rawValue: typeStr),
            let statusStr = columnText(stmt, 4),
            let status = SessionStatus(rawValue: statusStr),
            let startedAt = columnDate(stmt, 5),
            let updatedAt = columnDate(stmt, 9)
        else {
            throw DatabaseError.stepFailed("session row mapping failed")
        }
        return Session(
            id: Int(sqlite3_column_int64(stmt, 0)),
            clientUUID: uuid,
            routineID: columnInt(stmt, 2),
            type: type,
            status: status,
            startedAt: startedAt,
            finishedAt: columnDate(stmt, 6),
            bodyWeightKg: columnDouble(stmt, 7),
            notes: columnText(stmt, 8),
            updatedAt: updatedAt,
            deletedAt: columnDate(stmt, 10)
        )
    }
}
