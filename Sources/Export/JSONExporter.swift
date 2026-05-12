import Foundation
import SQLite3

// JSON export per PLAN.md T6.2 — mirrors SCHEMA.md table structure.
// Top-level keys = table names. Values = arrays of row objects keyed by column.
// Single file written to a fresh subdirectory of the temp dir.

struct JSONExporter {
    let dbManager: DatabaseManager

    func export() async throws -> URL {
        let payload: [(String, [String])] = [
            ("user_profile", ["id","client_uuid","name","weight_unit","distance_unit",
                              "body_weight_kg","created_at","updated_at"]),
            ("muscle", ["id","code","display_name","group_name"]),
            ("equipment", ["id","code","display_name"]),
            ("tag", ["id","code","display_name"]),
            ("exercise", ["id","client_uuid","name","abbreviation","equipment_id","metric_type",
                          "is_custom","notes","form_link","created_at","updated_at","deleted_at"]),
            ("exercise_muscle", ["exercise_id","muscle_id","role"]),
            ("routine", ["id","client_uuid","name","type","sort_order",
                         "created_at","updated_at","deleted_at"]),
            ("routine_exercise", ["id","client_uuid","routine_id","exercise_id","sort_order",
                                  "target_sets","target_rep_min","target_rep_max","target_rpe",
                                  "notes","updated_at"]),
            ("routine_run", ["id","client_uuid","routine_id","run_template_id","sort_order",
                             "notes","updated_at"]),
            ("run_template", ["id","client_uuid","name","run_type",
                              "target_total_distance_km","target_work_distance_km",
                              "target_pace_secs_min","target_pace_secs_max",
                              "hr_zone_min","hr_zone_max","hr_bpm_min","hr_bpm_max",
                              "is_custom","created_at","updated_at","deleted_at"]),
            ("run_interval_block", ["id","run_template_id","sort_order","block_type","repeat_count",
                                    "distance_km","duration_secs","target_pace_secs",
                                    "hr_zone","notes"]),
            ("session", ["id","client_uuid","routine_id","type","status",
                         "started_at","finished_at","body_weight_kg","notes",
                         "updated_at","deleted_at"]),
            ("session_tag", ["session_id","tag_id"]),
            ("session_set", ["id","client_uuid","session_id","exercise_id","exercise_order","set_number",
                             "set_type","weight_kg","reps","duration_secs","distance_m","rpe",
                             "completed_at","notes","updated_at"]),
            ("session_run", ["id","client_uuid","session_id","run_template_id","run_order",
                             "actual_distance_km","duration_secs","avg_pace_secs","avg_hr","max_hr",
                             "target_hr_min","target_hr_max","notes","updated_at"]),
            ("session_run_split", ["id","session_run_id","sort_order","block_type",
                                   "distance_km","duration_secs","avg_pace_secs","avg_hr"]),
        ]

        var root: [String: [[String: JSONValue]]] = [:]
        for (table, cols) in payload {
            root[table] = try await readTable(table: table, columns: cols)
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-export-json-\(Int(Date().timeIntervalSince1970))",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let file = dir.appendingPathComponent("hybrid-export.json")
        let data = try Self.encode(root)
        try data.write(to: file)
        return file
    }

    private func readTable(table: String, columns: [String]) async throws -> [[String: JSONValue]] {
        let sql = "SELECT \(columns.joined(separator: ",")) FROM \(table);"
        return try await dbManager.read { db in
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            var rows: [[String: JSONValue]] = []
            while try step(stmt) {
                var row: [String: JSONValue] = [:]
                for (i, col) in columns.enumerated() {
                    row[col] = cellValue(stmt, Int32(i))
                }
                rows.append(row)
            }
            return rows
        }
    }

    private func cellValue(_ stmt: OpaquePointer, _ i: Int32) -> JSONValue {
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_NULL:
            return .null
        case SQLITE_INTEGER:
            return .int(sqlite3_column_int64(stmt, i))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(stmt, i))
        default:
            guard let cstr = sqlite3_column_text(stmt, i) else { return .null }
            return .string(String(cString: cstr))
        }
    }

    static func encode(_ root: [String: [[String: JSONValue]]]) throws -> Data {
        let dict = root.mapValues { rows in
            rows.map { $0.mapValues(\.any) }
        }
        return try JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
        )
    }
}

enum JSONValue: Sendable {
    case null
    case int(Int64)
    case double(Double)
    case string(String)

    var any: Any {
        switch self {
        case .null: return NSNull()
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        }
    }
}
