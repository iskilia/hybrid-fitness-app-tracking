import Foundation
import SQLite3

// Per-table CSV export (decision per PLAN.md T6.1).
// One file per primary table — mirrors JSON exporter structure and SCHEMA.md.
// Writes to a fresh subdirectory of FileManager.default.temporaryDirectory
// and returns the directory URL.

struct CSVExporter {
    let dbManager: DatabaseManager

    func export() async throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-export-csv-\(Int(Date().timeIntervalSince1970))",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try await write("routine.csv", in: dir, columns: [
            "id","client_uuid","name","type","sort_order",
            "created_at","updated_at","deleted_at"
        ])
        try await write("routine_exercise.csv", in: dir, columns: [
            "id","client_uuid","routine_id","exercise_id","sort_order",
            "target_sets","target_rep_min","target_rep_max","target_rpe",
            "notes","updated_at"
        ])
        try await write("routine_run.csv", in: dir, columns: [
            "id","client_uuid","routine_id","run_template_id","sort_order",
            "notes","updated_at"
        ])
        try await write("exercise.csv", in: dir, columns: [
            "id","client_uuid","name","abbreviation","equipment_id","metric_type",
            "is_custom","notes","form_link","created_at","updated_at","deleted_at"
        ])
        try await write("run_template.csv", in: dir, columns: [
            "id","client_uuid","name","run_type",
            "target_total_distance_km","target_work_distance_km",
            "target_pace_secs_min","target_pace_secs_max",
            "hr_zone_min","hr_zone_max","hr_bpm_min","hr_bpm_max",
            "is_custom","created_at","updated_at","deleted_at"
        ])
        try await write("run_interval_block.csv", in: dir, columns: [
            "id","run_template_id","sort_order","block_type","repeat_count",
            "distance_km","duration_secs","target_pace_secs","hr_zone","notes"
        ])
        try await write("session.csv", in: dir, columns: [
            "id","client_uuid","routine_id","type","status",
            "started_at","finished_at","body_weight_kg","notes",
            "updated_at","deleted_at"
        ])
        try await write("session_set.csv", in: dir, columns: [
            "id","client_uuid","session_id","exercise_id","exercise_order","set_number",
            "set_type","weight_kg","reps","duration_secs","distance_m","rpe",
            "completed_at","notes","updated_at"
        ])
        try await write("session_run.csv", in: dir, columns: [
            "id","client_uuid","session_id","run_template_id","run_order",
            "actual_distance_km","duration_secs","avg_pace_secs","avg_hr","max_hr",
            "target_hr_min","target_hr_max","notes","updated_at"
        ])
        try await write("session_run_split.csv", in: dir, columns: [
            "id","session_run_id","sort_order","block_type",
            "distance_km","duration_secs","avg_pace_secs","avg_hr"
        ])

        return dir
    }

    private func write(_ filename: String, in dir: URL, columns: [String]) async throws {
        let table = (filename as NSString).deletingPathExtension
        let sql = "SELECT \(columns.joined(separator: ",")) FROM \(table);"
        let rows = try await dbManager.read { db in
            try readRows(db, sql: sql, columnCount: columns.count)
        }

        var out = columns.joined(separator: ",") + "\n"
        for row in rows {
            out += row.map(Self.csvEscape).joined(separator: ",") + "\n"
        }
        try out.data(using: .utf8)?.write(to: dir.appendingPathComponent(filename))
    }

    private func readRows(_ db: OpaquePointer, sql: String, columnCount: Int) throws -> [[String]] {
        let stmt = try prepare(db, sql)
        defer { finalize(stmt) }
        var rows: [[String]] = []
        while try step(stmt) {
            var row: [String] = []
            for i in 0..<columnCount {
                row.append(cellText(stmt, Int32(i)))
            }
            rows.append(row)
        }
        return rows
    }

    private func cellText(_ stmt: OpaquePointer, _ i: Int32) -> String {
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_NULL:
            return ""
        case SQLITE_INTEGER:
            return String(sqlite3_column_int64(stmt, i))
        case SQLITE_FLOAT:
            return String(sqlite3_column_double(stmt, i))
        default:
            guard let cstr = sqlite3_column_text(stmt, i) else { return "" }
            return String(cString: cstr)
        }
    }

    static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}
