import SQLite3
import Foundation

// MARK: - SessionSetRepository

struct SessionSetRepository {
    let dbManager: DatabaseManager

    // MARK: - Append

    func append(_ set: SessionSet) async throws {
        try await dbManager.transaction { db in
            try insertSet(db, set)
        }
    }

    // MARK: - Update

    func update(_ set: SessionSet) async throws {
        try await dbManager.transaction { db in
            let sql = """
                UPDATE session_set
                SET exercise_order = ?, set_number = ?, set_type = ?,
                    weight_kg = ?, reps = ?, duration_secs = ?,
                    distance_m = ?, rpe = ?, completed_at = ?,
                    notes = ?, updated_at = ?
                WHERE client_uuid = ?;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, set.exerciseOrder)
            bindInt(stmt, 2, set.setNumber)
            bindText(stmt, 3, set.setType.rawValue)
            bindDouble(stmt, 4, set.weightKg)
            bindInt(stmt, 5, set.reps)
            bindInt(stmt, 6, set.durationSecs)
            bindDouble(stmt, 7, set.distanceM)
            bindDouble(stmt, 8, set.rpe)
            bindDate(stmt, 9, set.completedAt)
            bindText(stmt, 10, set.notes)
            bindDate(stmt, 11, set.updatedAt)
            bindUUID(stmt, 12, set.clientUUID)
            _ = try step(stmt)
        }
    }

    // MARK: - Delete

    func delete(id: UUID) async throws {
        try await dbManager.transaction { db in
            let stmt = try prepare(db, "DELETE FROM session_set WHERE client_uuid = ?;")
            defer { finalize(stmt) }
            bindUUID(stmt, 1, id)
            _ = try step(stmt)
        }
    }

    // MARK: - List by session + exercise

    func list(sessionID: UUID, exerciseID: UUID) async throws -> [SessionSet] {
        try await dbManager.read { db in
            // Resolve integer IDs
            let sessionRowID = try resolveSessionID(db, uuid: sessionID)
            let exerciseRowID = try resolveExerciseID(db, uuid: exerciseID)

            let sql = setSelectSQL() + """
                 WHERE ss.session_id = ? AND ss.exercise_id = ?
                 ORDER BY ss.set_number ASC;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, sessionRowID)
            bindInt(stmt, 2, exerciseRowID)
            var result: [SessionSet] = []
            while try step(stmt) {
                result.append(try setFromStmt(stmt))
            }
            return result
        }
    }

    // MARK: - History by exercise (last N months across completed sessions)

    func historyByExercise(exerciseID: UUID, monthsBack: Int = 12) async throws -> [SessionSet] {
        try await dbManager.read { db in
            let exerciseRowID = try resolveExerciseID(db, uuid: exerciseID)
            let cutoff = Calendar.current.date(byAdding: .month, value: -monthsBack, to: Date()) ?? Date()

            let sql = setSelectSQL() + """
                 JOIN session s ON s.id = ss.session_id
                 WHERE ss.exercise_id = ?
                   AND s.status = 'COMPLETED'
                   AND s.deleted_at IS NULL
                   AND s.started_at >= ?
                 ORDER BY s.started_at DESC, ss.set_number ASC;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, exerciseRowID)
            bindDate(stmt, 2, cutoff)
            var result: [SessionSet] = []
            while try step(stmt) {
                result.append(try setFromStmt(stmt))
            }
            return result
        }
    }

    // MARK: - Top set per session

    func topSetPerSession(exerciseID: UUID, limit: Int = 12) async throws -> [(sessionDate: Date, weightKg: Double, reps: Int)] {
        try await dbManager.read { db in
            let exerciseRowID = try resolveExerciseID(db, uuid: exerciseID)

            // For each completed session that has this exercise, pick the set with max weight_kg.
            // Tie-break by reps DESC so the heaviest + most reps row wins.
            let sql = """
                SELECT s.started_at, ss.weight_kg, ss.reps
                FROM session_set ss
                JOIN session s ON s.id = ss.session_id
                WHERE ss.exercise_id = ?
                  AND s.status = 'COMPLETED'
                  AND s.deleted_at IS NULL
                  AND ss.weight_kg IS NOT NULL
                  AND ss.reps IS NOT NULL
                  AND ss.weight_kg = (
                      SELECT MAX(ss2.weight_kg)
                      FROM session_set ss2
                      WHERE ss2.session_id = ss.session_id
                        AND ss2.exercise_id = ss.exercise_id
                        AND ss2.weight_kg IS NOT NULL
                  )
                GROUP BY ss.session_id
                ORDER BY s.started_at DESC
                LIMIT ?;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, exerciseRowID)
            bindInt(stmt, 2, limit)
            var result: [(sessionDate: Date, weightKg: Double, reps: Int)] = []
            while try step(stmt) {
                guard
                    let date = columnDate(stmt, 0),
                    let weight = columnDouble(stmt, 1),
                    let reps = columnInt(stmt, 2)
                else { continue }
                result.append((sessionDate: date, weightKg: weight, reps: reps))
            }
            return result
        }
    }

    // MARK: - Private helpers

    private func setSelectSQL() -> String {
        """
        SELECT ss.id, ss.client_uuid, ss.session_id, ss.exercise_id,
               ss.exercise_order, ss.set_number, ss.set_type,
               ss.weight_kg, ss.reps, ss.duration_secs, ss.distance_m,
               ss.rpe, ss.completed_at, ss.notes, ss.updated_at
        FROM session_set ss
        """
    }

    private func setFromStmt(_ stmt: OpaquePointer) throws -> SessionSet {
        guard
            let uuidStr = columnText(stmt, 1),
            let uuid = UUID(uuidString: uuidStr),
            let setTypeStr = columnText(stmt, 6),
            let setType = SetType(rawValue: setTypeStr),
            let updatedAt = columnDate(stmt, 14)
        else {
            throw DatabaseError.stepFailed("session_set row mapping failed")
        }
        return SessionSet(
            id: Int(sqlite3_column_int64(stmt, 0)),
            clientUUID: uuid,
            sessionID: columnInt(stmt, 2) ?? 0,
            exerciseID: columnInt(stmt, 3) ?? 0,
            exerciseOrder: columnInt(stmt, 4) ?? 0,
            setNumber: columnInt(stmt, 5) ?? 0,
            setType: setType,
            weightKg: columnDouble(stmt, 7),
            reps: columnInt(stmt, 8),
            durationSecs: columnInt(stmt, 9),
            distanceM: columnDouble(stmt, 10),
            rpe: columnDouble(stmt, 11),
            completedAt: columnDate(stmt, 12),
            notes: columnText(stmt, 13),
            updatedAt: updatedAt
        )
    }

    private func insertSet(_ db: OpaquePointer, _ s: SessionSet) throws {
        let sql = """
            INSERT INTO session_set
                (client_uuid, session_id, exercise_id, exercise_order,
                 set_number, set_type, weight_kg, reps, duration_secs,
                 distance_m, rpe, completed_at, notes, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        bindUUID(stmt, 1, s.clientUUID)
        bindInt(stmt, 2, s.sessionID)
        bindInt(stmt, 3, s.exerciseID)
        bindInt(stmt, 4, s.exerciseOrder)
        bindInt(stmt, 5, s.setNumber)
        bindText(stmt, 6, s.setType.rawValue)
        bindDouble(stmt, 7, s.weightKg)
        bindInt(stmt, 8, s.reps)
        bindInt(stmt, 9, s.durationSecs)
        bindDouble(stmt, 10, s.distanceM)
        bindDouble(stmt, 11, s.rpe)
        bindDate(stmt, 12, s.completedAt)
        bindText(stmt, 13, s.notes)
        bindDate(stmt, 14, s.updatedAt)
        _ = try step(stmt)
    }

    private func resolveSessionID(_ db: OpaquePointer, uuid: UUID) throws -> Int {
        let stmt = try prepare(db, "SELECT id FROM session WHERE client_uuid = ?;")
        defer { finalize(stmt) }
        bindUUID(stmt, 1, uuid)
        guard try step(stmt), let id = columnInt(stmt, 0) else {
            throw DatabaseError.notFound
        }
        return id
    }

    private func resolveExerciseID(_ db: OpaquePointer, uuid: UUID) throws -> Int {
        let stmt = try prepare(db, "SELECT id FROM exercise WHERE client_uuid = ?;")
        defer { finalize(stmt) }
        bindUUID(stmt, 1, uuid)
        guard try step(stmt), let id = columnInt(stmt, 0) else {
            throw DatabaseError.notFound
        }
        return id
    }
}
