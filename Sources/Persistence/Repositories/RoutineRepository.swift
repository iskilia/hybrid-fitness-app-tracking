import SQLite3
import Foundation

// MARK: - RoutineRepository

struct RoutineRepository {
    let dbManager: DatabaseManager

    // MARK: - List (active, ordered by sort_order then name)

    func list() async throws -> [Routine] {
        try await dbManager.read { db in
            let sql = """
                SELECT id, client_uuid, name, type, sort_order, created_at, updated_at, deleted_at
                FROM routine
                WHERE deleted_at IS NULL
                ORDER BY sort_order ASC, name ASC;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            var result: [Routine] = []
            while try step(stmt) {
                result.append(try routineFromStmt(stmt))
            }
            return result
        }
    }

    // MARK: - Get by ID

    func get(id: UUID) async throws -> Routine? {
        try await dbManager.read { db in
            let sql = """
                SELECT id, client_uuid, name, type, sort_order, created_at, updated_at, deleted_at
                FROM routine
                WHERE client_uuid = ?;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindUUID(stmt, 1, id)
            guard try step(stmt) else { return nil }
            return try routineFromStmt(stmt)
        }
    }

    // MARK: - Create (10-routine cap enforced)

    func create(_ routine: Routine, exerciseEntries: [RoutineExercise], runEntries: [RoutineRun]) async throws {
        try await dbManager.transaction { db in
            // Enforce 10-active cap
            let capStmt = try prepare(db, "SELECT COUNT(*) FROM routine WHERE deleted_at IS NULL;")
            defer { finalize(capStmt) }
            _ = try step(capStmt)
            let count = sqlite3_column_int(capStmt, 0)
            guard count < 10 else {
                throw DatabaseError.conflict("routine cap reached")
            }

            try insertRoutine(db, routine)
            for entry in exerciseEntries { try insertRoutineExercise(db, entry) }
            for entry in runEntries { try insertRoutineRun(db, entry) }
        }
    }

    // MARK: - Update (replace exercise + run entries)

    func update(_ routine: Routine, exerciseEntries: [RoutineExercise], runEntries: [RoutineRun]) async throws {
        try await dbManager.transaction { db in
            let updateSQL = """
                UPDATE routine
                SET name = ?, type = ?, sort_order = ?, updated_at = ?
                WHERE client_uuid = ?;
                """
            let stmt = try prepare(db, updateSQL)
            defer { finalize(stmt) }
            bindText(stmt, 1, routine.name)
            bindText(stmt, 2, routine.type.rawValue)
            bindInt(stmt, 3, routine.sortOrder)
            bindDate(stmt, 4, routine.updatedAt)
            bindUUID(stmt, 5, routine.clientUUID)
            _ = try step(stmt)

            // Resolve integer PK for the routine
            let routineRowID = try routineRowID(db, clientUUID: routine.clientUUID)

            // Replace exercise entries
            let delExSQL = "DELETE FROM routine_exercise WHERE routine_id = ?;"
            let delExStmt = try prepare(db, delExSQL)
            defer { finalize(delExStmt) }
            bindInt(delExStmt, 1, routineRowID)
            _ = try step(delExStmt)

            // Replace run entries
            let delRunSQL = "DELETE FROM routine_run WHERE routine_id = ?;"
            let delRunStmt = try prepare(db, delRunSQL)
            defer { finalize(delRunStmt) }
            bindInt(delRunStmt, 1, routineRowID)
            _ = try step(delRunStmt)

            for entry in exerciseEntries { try insertRoutineExercise(db, entry) }
            for entry in runEntries { try insertRoutineRun(db, entry) }
        }
    }

    // MARK: - Soft-delete

    func softDelete(id: UUID) async throws {
        try await dbManager.transaction { db in
            let sql = "UPDATE routine SET deleted_at = ?, updated_at = ? WHERE client_uuid = ?;"
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

    private func routineFromStmt(_ stmt: OpaquePointer) throws -> Routine {
        guard
            let uuidStr = columnText(stmt, 1),
            let uuid = UUID(uuidString: uuidStr),
            let name = columnText(stmt, 2),
            let typeStr = columnText(stmt, 3),
            let type = WorkoutType(rawValue: typeStr),
            let createdAt = columnDate(stmt, 5),
            let updatedAt = columnDate(stmt, 6)
        else {
            throw DatabaseError.stepFailed("routine row mapping failed")
        }
        return Routine(
            id: Int(sqlite3_column_int64(stmt, 0)),
            clientUUID: uuid,
            name: name,
            type: type,
            sortOrder: columnInt(stmt, 4) ?? 0,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: columnDate(stmt, 7)
        )
    }

    private func insertRoutine(_ db: OpaquePointer, _ r: Routine) throws {
        let sql = """
            INSERT INTO routine (client_uuid, name, type, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        bindUUID(stmt, 1, r.clientUUID)
        bindText(stmt, 2, r.name)
        bindText(stmt, 3, r.type.rawValue)
        bindInt(stmt, 4, r.sortOrder)
        bindDate(stmt, 5, r.createdAt)
        bindDate(stmt, 6, r.updatedAt)
        _ = try step(stmt)
    }

    private func insertRoutineExercise(_ db: OpaquePointer, _ e: RoutineExercise) throws {
        let sql = """
            INSERT INTO routine_exercise
                (client_uuid, routine_id, exercise_id, sort_order,
                 target_sets, target_rep_min, target_rep_max, target_rpe, notes, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        bindUUID(stmt, 1, e.clientUUID)
        bindInt(stmt, 2, e.routineID)
        bindInt(stmt, 3, e.exerciseID)
        bindInt(stmt, 4, e.sortOrder)
        bindInt(stmt, 5, e.targetSets)
        bindInt(stmt, 6, e.targetRepMin)
        bindInt(stmt, 7, e.targetRepMax)
        bindDouble(stmt, 8, e.targetRPE)
        bindText(stmt, 9, e.notes)
        bindDate(stmt, 10, e.updatedAt)
        _ = try step(stmt)
    }

    private func insertRoutineRun(_ db: OpaquePointer, _ r: RoutineRun) throws {
        let sql = """
            INSERT INTO routine_run
                (client_uuid, routine_id, run_template_id, sort_order, notes, updated_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        bindUUID(stmt, 1, r.clientUUID)
        bindInt(stmt, 2, r.routineID)
        bindInt(stmt, 3, r.runTemplateID)
        bindInt(stmt, 4, r.sortOrder)
        bindText(stmt, 5, r.notes)
        bindDate(stmt, 6, r.updatedAt)
        _ = try step(stmt)
    }

    // MARK: - List exercises for a routine (ordered by sort_order)

    func listExercises(routineID: UUID) async throws -> [RoutineExercise] {
        try await dbManager.read { db in
            let rowIDStmt = try prepare(db, "SELECT id FROM routine WHERE client_uuid = ?;")
            defer { finalize(rowIDStmt) }
            bindUUID(rowIDStmt, 1, routineID)
            guard try step(rowIDStmt), let rowID = columnInt(rowIDStmt, 0) else { return [] }

            let sql = """
                SELECT id, client_uuid, routine_id, exercise_id, sort_order,
                       target_sets, target_rep_min, target_rep_max, target_rpe, notes, updated_at
                FROM routine_exercise
                WHERE routine_id = ?
                ORDER BY sort_order ASC;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, rowID)
            var result: [RoutineExercise] = []
            while try step(stmt) {
                guard
                    let uuidStr = columnText(stmt, 1),
                    let uuid = UUID(uuidString: uuidStr),
                    let updatedAt = columnDate(stmt, 10)
                else { continue }
                result.append(RoutineExercise(
                    id: Int(sqlite3_column_int64(stmt, 0)),
                    clientUUID: uuid,
                    routineID: columnInt(stmt, 2) ?? 0,
                    exerciseID: columnInt(stmt, 3) ?? 0,
                    sortOrder: columnInt(stmt, 4) ?? 0,
                    targetSets: columnInt(stmt, 5),
                    targetRepMin: columnInt(stmt, 6),
                    targetRepMax: columnInt(stmt, 7),
                    targetRPE: columnDouble(stmt, 8),
                    targetDurationSecsMin: nil,
                    targetDurationSecsMax: nil,
                    notes: columnText(stmt, 9),
                    updatedAt: updatedAt
                ))
            }
            return result
        }
    }

    // MARK: - Summary (exercise + run counts for a routine)

    func summary(routineID: UUID) async throws -> (exerciseCount: Int, runCount: Int) {
        try await dbManager.read { db in
            let rowIDStmt = try prepare(db, "SELECT id FROM routine WHERE client_uuid = ?;")
            defer { finalize(rowIDStmt) }
            bindUUID(rowIDStmt, 1, routineID)
            guard try step(rowIDStmt), let rowID = columnInt(rowIDStmt, 0) else {
                return (0, 0)
            }

            let exStmt = try prepare(db, "SELECT COUNT(*) FROM routine_exercise WHERE routine_id = ?;")
            defer { finalize(exStmt) }
            bindInt(exStmt, 1, rowID)
            _ = try step(exStmt)
            let exerciseCount = Int(sqlite3_column_int64(exStmt, 0))

            let runStmt = try prepare(db, "SELECT COUNT(*) FROM routine_run WHERE routine_id = ?;")
            defer { finalize(runStmt) }
            bindInt(runStmt, 1, rowID)
            _ = try step(runStmt)
            let runCount = Int(sqlite3_column_int64(runStmt, 0))

            return (exerciseCount, runCount)
        }
    }

    // MARK: - Private helpers

    private func routineRowID(_ db: OpaquePointer, clientUUID: UUID) throws -> Int {
        let stmt = try prepare(db, "SELECT id FROM routine WHERE client_uuid = ?;")
        defer { finalize(stmt) }
        bindUUID(stmt, 1, clientUUID)
        guard try step(stmt), let id = columnInt(stmt, 0) else {
            throw DatabaseError.notFound
        }
        return id
    }
}
