import SQLite3
import Foundation

// MARK: - RunTemplateRepository

struct RunTemplateRepository {
    let dbManager: DatabaseManager

    // MARK: - List

    func listAll() async throws -> [RunTemplate] {
        try await dbManager.read { db in
            try fetchTemplates(db, extraWhere: nil)
        }
    }

    func listBase() async throws -> [RunTemplate] {
        try await dbManager.read { db in
            try fetchTemplates(db, extraWhere: "is_custom = 0")
        }
    }

    func listCustom() async throws -> [RunTemplate] {
        try await dbManager.read { db in
            try fetchTemplates(db, extraWhere: "is_custom = 1")
        }
    }

    // MARK: - Get by UUID

    func get(id: UUID) async throws -> RunTemplate? {
        try await dbManager.read { db in
            let sql = templateSelectSQL() + " WHERE client_uuid = ? AND deleted_at IS NULL;"
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindUUID(stmt, 1, id)
            guard try step(stmt) else { return nil }
            return try templateFromStmt(stmt)
        }
    }

    // MARK: - Intervals

    func intervals(for templateID: UUID) async throws -> [RunIntervalBlock] {
        try await dbManager.read { db in
            // Resolve integer ID
            let idStmt = try prepare(db, "SELECT id FROM run_template WHERE client_uuid = ?;")
            defer { finalize(idStmt) }
            bindUUID(idStmt, 1, templateID)
            guard try step(idStmt), let rowID = columnInt(idStmt, 0) else { return [] }

            let sql = """
                SELECT id, run_template_id, sort_order, block_type, repeat_count,
                       distance_km, duration_secs, target_pace_secs, hr_zone, notes
                FROM run_interval_block
                WHERE run_template_id = ?
                ORDER BY sort_order ASC;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, rowID)
            var result: [RunIntervalBlock] = []
            while try step(stmt) {
                result.append(try blockFromStmt(stmt))
            }
            return result
        }
    }

    // MARK: - Create

    func create(_ template: RunTemplate, blocks: [RunIntervalBlock]) async throws {
        try await dbManager.transaction { db in
            try insertTemplate(db, template)
            let rowID = Int(sqlite3_last_insert_rowid(db))
            for block in blocks { try insertBlock(db, block, templateRowID: rowID) }
        }
    }

    // MARK: - Update

    func update(_ template: RunTemplate, blocks: [RunIntervalBlock]) async throws {
        try await dbManager.transaction { db in
            let sql = """
                UPDATE run_template
                SET name = ?, run_type = ?,
                    target_total_distance_km = ?, target_work_distance_km = ?,
                    target_pace_secs_min = ?, target_pace_secs_max = ?,
                    hr_zone_min = ?, hr_zone_max = ?,
                    hr_bpm_min = ?, hr_bpm_max = ?,
                    updated_at = ?
                WHERE client_uuid = ?;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindText(stmt, 1, template.name)
            bindText(stmt, 2, template.runType.rawValue)
            bindDouble(stmt, 3, template.targetTotalDistanceKm)
            bindDouble(stmt, 4, template.targetWorkDistanceKm)
            bindInt(stmt, 5, template.targetPaceSecsMin)
            bindInt(stmt, 6, template.targetPaceSecsMax)
            bindInt(stmt, 7, template.hrZoneMin)
            bindInt(stmt, 8, template.hrZoneMax)
            bindInt(stmt, 9, template.hrBpmMin)
            bindInt(stmt, 10, template.hrBpmMax)
            bindDate(stmt, 11, template.updatedAt)
            bindUUID(stmt, 12, template.clientUUID)
            _ = try step(stmt)

            // Resolve integer PK
            let rowID = template.id

            // Replace blocks (CASCADE would handle this, but be explicit)
            let delStmt = try prepare(db, "DELETE FROM run_interval_block WHERE run_template_id = ?;")
            defer { finalize(delStmt) }
            bindInt(delStmt, 1, rowID)
            _ = try step(delStmt)

            for block in blocks { try insertBlock(db, block, templateRowID: rowID) }
        }
    }

    // MARK: - Soft-delete

    func softDelete(id: UUID) async throws {
        try await dbManager.transaction { db in
            let sql = "UPDATE run_template SET deleted_at = ?, updated_at = ? WHERE client_uuid = ?;"
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

    private func templateSelectSQL() -> String {
        """
        SELECT id, client_uuid, name, run_type,
               target_total_distance_km, target_work_distance_km,
               target_pace_secs_min, target_pace_secs_max,
               hr_zone_min, hr_zone_max, hr_bpm_min, hr_bpm_max,
               is_custom, created_at, updated_at, deleted_at
        FROM run_template
        """
    }

    private func fetchTemplates(_ db: OpaquePointer, extraWhere: String?) throws -> [RunTemplate] {
        var sql = templateSelectSQL() + " WHERE deleted_at IS NULL"
        if let extra = extraWhere {
            sql += " AND \(extra)"
        }
        sql += " ORDER BY name ASC;"
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        var result: [RunTemplate] = []
        while try step(stmt) {
            result.append(try templateFromStmt(stmt))
        }
        return result
    }

    private func templateFromStmt(_ stmt: OpaquePointer) throws -> RunTemplate {
        guard
            let uuidStr = columnText(stmt, 1),
            let uuid = UUID(uuidString: uuidStr),
            let name = columnText(stmt, 2),
            let runTypeStr = columnText(stmt, 3),
            let runType = RunType(rawValue: runTypeStr),
            let createdAt = columnDate(stmt, 13),
            let updatedAt = columnDate(stmt, 14)
        else {
            throw DatabaseError.stepFailed("run_template row mapping failed")
        }
        return RunTemplate(
            id: Int(sqlite3_column_int64(stmt, 0)),
            clientUUID: uuid,
            name: name,
            runType: runType,
            targetTotalDistanceKm: columnDouble(stmt, 4),
            targetWorkDistanceKm: columnDouble(stmt, 5),
            targetPaceSecsMin: columnInt(stmt, 6),
            targetPaceSecsMax: columnInt(stmt, 7),
            hrZoneMin: columnInt(stmt, 8),
            hrZoneMax: columnInt(stmt, 9),
            hrBpmMin: columnInt(stmt, 10),
            hrBpmMax: columnInt(stmt, 11),
            isCustom: columnBool(stmt, 12),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: columnDate(stmt, 15)
        )
    }

    private func insertTemplate(_ db: OpaquePointer, _ t: RunTemplate) throws {
        let sql = """
            INSERT INTO run_template
                (client_uuid, name, run_type,
                 target_total_distance_km, target_work_distance_km,
                 target_pace_secs_min, target_pace_secs_max,
                 hr_zone_min, hr_zone_max, hr_bpm_min, hr_bpm_max,
                 is_custom, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        bindUUID(stmt, 1, t.clientUUID)
        bindText(stmt, 2, t.name)
        bindText(stmt, 3, t.runType.rawValue)
        bindDouble(stmt, 4, t.targetTotalDistanceKm)
        bindDouble(stmt, 5, t.targetWorkDistanceKm)
        bindInt(stmt, 6, t.targetPaceSecsMin)
        bindInt(stmt, 7, t.targetPaceSecsMax)
        bindInt(stmt, 8, t.hrZoneMin)
        bindInt(stmt, 9, t.hrZoneMax)
        bindInt(stmt, 10, t.hrBpmMin)
        bindInt(stmt, 11, t.hrBpmMax)
        bindBool(stmt, 12, t.isCustom)
        bindDate(stmt, 13, t.createdAt)
        bindDate(stmt, 14, t.updatedAt)
        _ = try step(stmt)
    }

    private func blockFromStmt(_ stmt: OpaquePointer) throws -> RunIntervalBlock {
        guard
            let blockTypeStr = columnText(stmt, 3),
            let blockType = IntervalBlockType(rawValue: blockTypeStr)
        else {
            throw DatabaseError.stepFailed("run_interval_block row mapping failed")
        }
        return RunIntervalBlock(
            id: Int(sqlite3_column_int64(stmt, 0)),
            runTemplateID: columnInt(stmt, 1) ?? 0,
            sortOrder: columnInt(stmt, 2) ?? 0,
            blockType: blockType,
            repeatCount: columnInt(stmt, 4) ?? 1,
            distanceKm: columnDouble(stmt, 5),
            durationSecs: columnInt(stmt, 6),
            targetPaceSecs: columnInt(stmt, 7),
            hrZone: columnInt(stmt, 8),
            notes: columnText(stmt, 9)
        )
    }

    private func insertBlock(_ db: OpaquePointer, _ b: RunIntervalBlock, templateRowID: Int) throws {
        let sql = """
            INSERT INTO run_interval_block
                (run_template_id, sort_order, block_type, repeat_count,
                 distance_km, duration_secs, target_pace_secs, hr_zone, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        bindInt(stmt, 1, templateRowID)
        bindInt(stmt, 2, b.sortOrder)
        bindText(stmt, 3, b.blockType.rawValue)
        bindInt(stmt, 4, b.repeatCount)
        bindDouble(stmt, 5, b.distanceKm)
        bindInt(stmt, 6, b.durationSecs)
        bindInt(stmt, 7, b.targetPaceSecs)
        bindInt(stmt, 8, b.hrZone)
        bindText(stmt, 9, b.notes)
        _ = try step(stmt)
    }
}
