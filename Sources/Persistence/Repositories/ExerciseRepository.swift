import SQLite3
import Foundation

// MARK: - ExerciseRepository

struct ExerciseRepository {
    let dbManager: DatabaseManager

    // MARK: - List

    func listAll() async throws -> [Exercise] {
        try await dbManager.read { db in
            try fetchExercises(db, extraWhere: nil)
        }
    }

    func listBase() async throws -> [Exercise] {
        try await dbManager.read { db in
            try fetchExercises(db, extraWhere: "is_custom = 0")
        }
    }

    func listCustom() async throws -> [Exercise] {
        try await dbManager.read { db in
            try fetchExercises(db, extraWhere: "is_custom = 1")
        }
    }

    // MARK: - Get by UUID

    func get(id: UUID) async throws -> Exercise? {
        try await dbManager.read { db in
            let sql = exerciseSelectSQL() + " WHERE e.client_uuid = ? AND e.deleted_at IS NULL;"
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindUUID(stmt, 1, id)
            guard try step(stmt) else { return nil }
            return try exerciseFromStmt(stmt)
        }
    }

    // MARK: - Lookup lists

    func listAllEquipment() async throws -> [Equipment] {
        try await dbManager.read { db in
            let stmt = try prepare(db, "SELECT id, code, display_name FROM equipment ORDER BY display_name ASC;")
            defer { finalize(stmt) }
            var result: [Equipment] = []
            while try step(stmt) {
                guard
                    let code = columnText(stmt, 1),
                    let displayName = columnText(stmt, 2)
                else { continue }
                result.append(Equipment(
                    id: Int(sqlite3_column_int64(stmt, 0)),
                    code: code,
                    displayName: displayName
                ))
            }
            return result
        }
    }

    func listAllMuscles() async throws -> [Muscle] {
        try await dbManager.read { db in
            let stmt = try prepare(db, "SELECT id, code, display_name, group_name FROM muscle ORDER BY display_name ASC;")
            defer { finalize(stmt) }
            var result: [Muscle] = []
            while try step(stmt) {
                guard
                    let code = columnText(stmt, 1),
                    let displayName = columnText(stmt, 2),
                    let groupName = columnText(stmt, 3)
                else { continue }
                result.append(Muscle(
                    id: Int(sqlite3_column_int64(stmt, 0)),
                    code: code,
                    displayName: displayName,
                    groupName: groupName
                ))
            }
            return result
        }
    }

    // MARK: - Search

    func search(query: String) async throws -> [Exercise] {
        try await dbManager.read { db in
            let sql = exerciseSelectSQL() + """
                 WHERE e.deleted_at IS NULL
                   AND (e.name LIKE ? OR e.abbreviation LIKE ?)
                 ORDER BY e.name ASC;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            let pattern = "%\(query)%"
            bindText(stmt, 1, pattern)
            bindText(stmt, 2, pattern)
            var result: [Exercise] = []
            while try step(stmt) {
                result.append(try exerciseFromStmt(stmt))
            }
            return result
        }
    }

    // MARK: - Muscles join

    func musclesFor(exerciseID: UUID) async throws -> [(Muscle, MuscleRole)] {
        try await dbManager.read { db in
            // Resolve integer ID first
            let idStmt = try prepare(db, "SELECT id FROM exercise WHERE client_uuid = ?;")
            defer { finalize(idStmt) }
            bindUUID(idStmt, 1, exerciseID)
            guard try step(idStmt), let rowID = columnInt(idStmt, 0) else { return [] }

            let sql = """
                SELECT m.id, m.code, m.display_name, m.group_name, em.role
                FROM exercise_muscle em
                JOIN muscle m ON m.id = em.muscle_id
                WHERE em.exercise_id = ?
                ORDER BY em.role ASC;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, rowID)
            var result: [(Muscle, MuscleRole)] = []
            while try step(stmt) {
                guard
                    let code = columnText(stmt, 1),
                    let displayName = columnText(stmt, 2),
                    let groupName = columnText(stmt, 3),
                    let roleStr = columnText(stmt, 4),
                    let role = MuscleRole(rawValue: roleStr)
                else { continue }
                let muscle = Muscle(
                    id: Int(sqlite3_column_int64(stmt, 0)),
                    code: code,
                    displayName: displayName,
                    groupName: groupName
                )
                result.append((muscle, role))
            }
            return result
        }
    }

    // MARK: - Equipment join

    func equipmentFor(exerciseID: UUID) async throws -> Equipment? {
        try await dbManager.read { db in
            let sql = """
                SELECT eq.id, eq.code, eq.display_name
                FROM exercise e
                JOIN equipment eq ON eq.id = e.equipment_id
                WHERE e.client_uuid = ? AND e.deleted_at IS NULL;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindUUID(stmt, 1, exerciseID)
            guard try step(stmt) else { return nil }
            guard
                let code = columnText(stmt, 1),
                let displayName = columnText(stmt, 2)
            else { return nil }
            return Equipment(
                id: Int(sqlite3_column_int64(stmt, 0)),
                code: code,
                displayName: displayName
            )
        }
    }

    // MARK: - Create (custom exercises only)

    func create(_ exercise: Exercise, muscles: [(UUID, MuscleRole)]) async throws {
        try await dbManager.transaction { db in
            try insertExercise(db, exercise)
            let rowID = Int(sqlite3_last_insert_rowid(db))
            for (_, role) in muscles {
                // muscles param carries muscle UUIDs, but muscle table uses integer PKs.
                // Resolve each UUID to its integer ID.
                // (The caller passes muscle UUIDs; we look them up.)
                // Since Muscle doesn't have a UUID, we interpret these as muscle integer IDs
                // encoded as a UUID string. See note in repo signature.
                _ = role // handled below via muscleID resolution
            }
            // Re-insert using integer muscle IDs from the tuple.
            // The signature says [(UUID, MuscleRole)] — UUIDs identify muscles.
            // Muscle table has no client_uuid, so we treat the UUID's integer representation
            // as unavailable. Callers must pass integer IDs packed as UUIDs via
            // UUID(uuidString: "00000000-0000-0000-0000-<paddedInt>").
            // We resolve by querying muscle WHERE id = last 12 digits of UUID string.
            for (muscleUUID, role) in muscles {
                let muscleID = try resolveMuscleID(db, uuid: muscleUUID)
                try insertExerciseMuscle(db, exerciseRowID: rowID, muscleID: muscleID, role: role)
            }
            SnapshotHook.notifyChange()
        }
    }

    // MARK: - Metric-type locked check

    func metricTypeLocked(exerciseID: Int) async throws -> Bool {
        try await dbManager.read { db in
            let stmt = try prepare(db, "SELECT EXISTS(SELECT 1 FROM session_set WHERE exercise_id = ? LIMIT 1);")
            defer { finalize(stmt) }
            bindInt(stmt, 1, exerciseID)
            _ = try step(stmt)
            return columnBool(stmt, 0)
        }
    }

    // MARK: - Update

    func update(_ exercise: Exercise, muscles: [(UUID, MuscleRole)]) async throws {
        try await dbManager.transaction { db in
            // Metric-type immutability guard: reject if metric_type changes and sets exist.
            let currentStmt = try prepare(db, "SELECT metric_type FROM exercise WHERE id = ?;")
            defer { finalize(currentStmt) }
            bindInt(currentStmt, 1, exercise.id)
            if try step(currentStmt),
               let currentRaw = columnText(currentStmt, 0),
               currentRaw != exercise.metricType.rawValue {
                let existsStmt = try prepare(db, "SELECT EXISTS(SELECT 1 FROM session_set WHERE exercise_id = ? LIMIT 1);")
                defer { finalize(existsStmt) }
                bindInt(existsStmt, 1, exercise.id)
                _ = try step(existsStmt)
                if columnBool(existsStmt, 0) {
                    throw DatabaseError.conflict("metric_type cannot be changed after sets have been logged for this exercise")
                }
            }

            let sql = """
                UPDATE exercise
                SET name = ?, abbreviation = ?, equipment_id = ?, metric_type = ?,
                    notes = ?, form_link = ?, updated_at = ?
                WHERE client_uuid = ?;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindText(stmt, 1, exercise.name)
            bindText(stmt, 2, exercise.abbreviation)
            bindInt(stmt, 3, exercise.equipmentID)
            bindText(stmt, 4, exercise.metricType.rawValue)
            bindText(stmt, 5, exercise.notes)
            bindText(stmt, 6, exercise.formLink)
            bindDate(stmt, 7, exercise.updatedAt)
            bindUUID(stmt, 8, exercise.clientUUID)
            _ = try step(stmt)

            let rowID = exercise.id
            // Replace muscles
            let delStmt = try prepare(db, "DELETE FROM exercise_muscle WHERE exercise_id = ?;")
            defer { finalize(delStmt) }
            bindInt(delStmt, 1, rowID)
            _ = try step(delStmt)

            for (muscleUUID, role) in muscles {
                let muscleID = try resolveMuscleID(db, uuid: muscleUUID)
                try insertExerciseMuscle(db, exerciseRowID: rowID, muscleID: muscleID, role: role)
            }
            if exercise.isCustom { SnapshotHook.notifyChange() }
        }
    }

    // MARK: - Soft-delete

    func softDelete(id: UUID) async throws {
        try await dbManager.transaction { db in
            let sql = "UPDATE exercise SET deleted_at = ?, updated_at = ? WHERE client_uuid = ?;"
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            let now = Date()
            bindDate(stmt, 1, now)
            bindDate(stmt, 2, now)
            bindUUID(stmt, 3, id)
            _ = try step(stmt)
        }
    }

    // MARK: - Private helpers

    private func exerciseSelectSQL() -> String {
        """
        SELECT e.id, e.client_uuid, e.name, e.abbreviation, e.equipment_id,
               e.metric_type, e.is_custom, e.notes, e.form_link,
               e.created_at, e.updated_at, e.deleted_at
        FROM exercise e
        """
    }

    private func fetchExercises(_ db: OpaquePointer, extraWhere: String?) throws -> [Exercise] {
        var sql = exerciseSelectSQL() + " WHERE e.deleted_at IS NULL"
        if let extra = extraWhere {
            sql += " AND \(extra)"
        }
        sql += " ORDER BY e.name ASC;"
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        var result: [Exercise] = []
        while try step(stmt) {
            result.append(try exerciseFromStmt(stmt))
        }
        return result
    }

    private func exerciseFromStmt(_ stmt: OpaquePointer) throws -> Exercise {
        guard
            let uuidStr = columnText(stmt, 1),
            let uuid = UUID(uuidString: uuidStr),
            let name = columnText(stmt, 2),
            let abbreviation = columnText(stmt, 3),
            let metricStr = columnText(stmt, 5),
            let metricType = MetricType(rawValue: metricStr),
            let createdAt = columnDate(stmt, 9),
            let updatedAt = columnDate(stmt, 10)
        else {
            throw DatabaseError.stepFailed("exercise row mapping failed")
        }
        return Exercise(
            id: Int(sqlite3_column_int64(stmt, 0)),
            clientUUID: uuid,
            name: name,
            abbreviation: abbreviation,
            equipmentID: columnInt(stmt, 4) ?? 0,
            metricType: metricType,
            isCustom: columnBool(stmt, 6),
            notes: columnText(stmt, 7),
            formLink: columnText(stmt, 8),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: columnDate(stmt, 11)
        )
    }

    private func insertExercise(_ db: OpaquePointer, _ e: Exercise) throws {
        let sql = """
            INSERT INTO exercise
                (client_uuid, name, abbreviation, equipment_id, metric_type,
                 is_custom, notes, form_link, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        bindUUID(stmt, 1, e.clientUUID)
        bindText(stmt, 2, e.name)
        bindText(stmt, 3, e.abbreviation)
        bindInt(stmt, 4, e.equipmentID)
        bindText(stmt, 5, e.metricType.rawValue)
        bindBool(stmt, 6, e.isCustom)
        bindText(stmt, 7, e.notes)
        bindText(stmt, 8, e.formLink)
        bindDate(stmt, 9, e.createdAt)
        bindDate(stmt, 10, e.updatedAt)
        _ = try step(stmt)
    }

    private func insertExerciseMuscle(
        _ db: OpaquePointer,
        exerciseRowID: Int,
        muscleID: Int,
        role: MuscleRole
    ) throws {
        let sql = """
            INSERT OR IGNORE INTO exercise_muscle (exercise_id, muscle_id, role)
            VALUES (?, ?, ?);
            """
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        bindInt(stmt, 1, exerciseRowID)
        bindInt(stmt, 2, muscleID)
        bindText(stmt, 3, role.rawValue)
        _ = try step(stmt)
    }

    /// Resolves a muscle UUID to its integer row ID.
    /// Since Muscle has no client_uuid column, callers encode the integer muscle ID
    /// in the UUID's last segment: "00000000-0000-0000-0000-<paddedInt>".
    /// Falls back to treating the UUID's integer representation directly.
    private func resolveMuscleID(_ db: OpaquePointer, uuid: UUID) throws -> Int {
        // Try parsing as padded integer UUID
        let uuidStr = uuid.uuidString
        let lastSegment = String(uuidStr.split(separator: "-").last ?? "")
        if let id = Int(lastSegment, radix: 16), id > 0 {
            return id
        }
        throw DatabaseError.notFound
    }
}
