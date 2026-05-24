import SQLite3
import Foundation

// MARK: - Public entry point

public func seedIfEmpty(_ db: OpaquePointer) throws {
    guard try tableIsEmpty(db, table: "equipment"),
          try tableIsEmpty(db, table: "muscle"),
          try tableIsEmpty(db, table: "tag"),
          try tableIsEmpty(db, table: "exercise"),
          try tableIsEmpty(db, table: "run_template") else {
        return
    }

    try exec(db: db, sql: "BEGIN;")
    do {
        try insertEquipment(db)
        try insertMuscles(db)
        try insertTags(db)
        try insertExercises(db)
        try insertRunTemplates(db)
        try exec(db: db, sql: "COMMIT;")
    } catch {
        try? exec(db: db, sql: "ROLLBACK;")
        throw error
    }
}

// MARK: - Equipment
// Codes per SCHEMA.md: BARBELL, DUMBBELL, BODYWEIGHT, CABLE, MACHINE, KETTLEBELL, BAND, SLED

private func insertEquipment(_ db: OpaquePointer) throws {
    let rows: [(id: Int, code: String, display: String)] = [
        (1, "BARBELL",    "Barbell"),
        (2, "DUMBBELL",   "Dumbbell"),
        (3, "BODYWEIGHT", "Bodyweight"),
        (4, "CABLE",      "Cable"),
        (5, "MACHINE",    "Machine"),
        (6, "KETTLEBELL", "Kettlebell"),
        (7, "BAND",       "Band"),
        (8, "SLED",       "Sled"),
        (9, "PULLUP_BAR", "Pull-up Bar"),
    ]
    for r in rows {
        try exec(db: db, sql: """
            INSERT INTO equipment (id, code, display_name) VALUES (\(r.id), '\(r.code)', '\(r.display)');
            """)
    }
}

// MARK: - Muscles
// Per screenshot 05 chips and SCHEMA.md column notes.
// group_name values: UPPER | LOWER | CORE | FULL_BODY

private func insertMuscles(_ db: OpaquePointer) throws {
    let rows: [(id: Int, code: String, display: String, group: String)] = [
        (1,  "CHEST",           "Chest",           "UPPER"),
        (2,  "BACK",            "Back",            "UPPER"),
        (3,  "LATS",            "Lats",            "UPPER"),
        (4,  "SHOULDERS",       "Shoulders",       "UPPER"),
        (5,  "BICEPS",          "Biceps",          "UPPER"),
        (6,  "TRICEPS",         "Triceps",         "UPPER"),
        (7,  "QUADS",           "Quads",           "LOWER"),
        (8,  "HAMSTRINGS",      "Hamstrings",      "LOWER"),
        (9,  "GLUTES",          "Glutes",          "LOWER"),
        (10, "CALVES",          "Calves",          "LOWER"),
        (11, "CORE",            "Core",            "CORE"),
        (12, "POSTERIOR_CHAIN", "Posterior Chain", "FULL_BODY"),
        (13, "UPPER_CHEST",     "Upper Chest",     "UPPER"),
        (14, "OBLIQUES",        "Obliques",        "CORE"),
        (15, "FOREARMS",        "Forearms",        "UPPER"),
        (16, "HIP_FLEXORS",     "Hip Flexors",     "CORE"),
    ]
    for r in rows {
        try exec(db: db, sql: """
            INSERT INTO muscle (id, code, display_name, group_name) VALUES (\(r.id), '\(r.code)', '\(r.display)', '\(r.group)');
            """)
    }
}

// MARK: - Tags

private func insertTags(_ db: OpaquePointer) throws {
    let now = Int(Date().timeIntervalSince1970)
    let rows: [(id: Int, code: String, display: String)] = [
        (1, "push",        "Push"),
        (2, "pull",        "Pull"),
        (3, "legs",        "Legs"),
        (4, "upper",       "Upper"),
        (5, "lower",       "Lower"),
        (6, "heavy_lower", "Heavy Lower"),
        (7, "tempo",       "Tempo"),
        (8, "intervals",   "Intervals"),
        (9, "deload",      "Deload"),
    ]
    for r in rows {
        try exec(db: db, sql: """
            INSERT INTO tag (id, code, display_name, created_at) VALUES (\(r.id), '\(r.code)', '\(r.display)', \(now));
            """)
    }
}

// MARK: - Exercises

// Deterministic UUID namespace for exercises: 00000000-0000-0000-0001-<12-digit padded id>
private func exerciseUUID(_ id: Int) -> String {
    String(format: "00000000-0000-0000-0001-%012d", id)
}

private struct ExerciseSeed {
    let id: Int
    let name: String
    let abbr: String
    let equipmentID: Int
    let metricType: String       // REPS | TIME | DISTANCE | REPS_BODYWEIGHT
    let primaryMuscles: [Int]    // muscle IDs
    let secondaryMuscles: [Int]
    var notes: String? = nil
}

private func insertExercises(_ db: OpaquePointer) throws {
    let now = Int(Date().timeIntervalSince1970)

    let exercises: [ExerciseSeed] = [
        // ID 1 — Bench Press (screenshot: BNC, BARBELL · CHEST · TRICEPS)
        ExerciseSeed(id: 1,  name: "Bench Press",           abbr: "BNC", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [1],       secondaryMuscles: [6, 4]),
        // ID 2 — Back Squat (screenshot: SQT, BARBELL · QUADS · GLUTES)
        ExerciseSeed(id: 2,  name: "Back Squat",            abbr: "SQT", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [7],       secondaryMuscles: [9, 8]),
        // ID 3 — Deadlift (screenshot: DLT, BARBELL · POSTERIOR CHAIN)
        ExerciseSeed(id: 3,  name: "Deadlift",              abbr: "DLT", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [12],      secondaryMuscles: [8, 9, 2]),
        // ID 4 — Overhead Press (screenshot: OHP, BARBELL · SHOULDERS · TRICEPS)
        ExerciseSeed(id: 4,  name: "Overhead Press",        abbr: "OHP", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [4],       secondaryMuscles: [6]),
        // ID 5 — Bent-over Row (screenshot: ROW, BARBELL · BACK · BICEPS)
        ExerciseSeed(id: 5,  name: "Bent-over Row",         abbr: "ROW", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [2],       secondaryMuscles: [5, 3]),
        // ID 6 — Pull-up (screenshot: PUL, BODYWEIGHT · LATS · BICEPS)
        ExerciseSeed(id: 6,  name: "Pull-up",               abbr: "PUL", equipmentID: 3,
                     metricType: "REPS_BODYWEIGHT", primaryMuscles: [3],      secondaryMuscles: [5]),
        // ID 7 — Romanian Deadlift (screenshot: DLT / use RDL per task spec, BARBELL · HAMSTRINGS · GLUTES)
        ExerciseSeed(id: 7,  name: "Romanian Deadlift",     abbr: "RDL", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [8],       secondaryMuscles: [9, 12]),
        // ID 8 — Incline DB Press (screenshot: BNC, DUMBBELL · UPPER CHEST)
        ExerciseSeed(id: 8,  name: "Incline DB Press",      abbr: "IDB", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [13],      secondaryMuscles: [1, 6]),
        // ID 9 — Front Squat
        ExerciseSeed(id: 9,  name: "Front Squat",           abbr: "FSQ", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [7],       secondaryMuscles: [9]),
        // ID 10 — Lat Pulldown
        ExerciseSeed(id: 10, name: "Lat Pulldown",          abbr: "LPD", equipmentID: 4,
                     metricType: "REPS",           primaryMuscles: [3],       secondaryMuscles: [5]),
        // ID 11 — Cable Row
        ExerciseSeed(id: 11, name: "Cable Row",             abbr: "CRW", equipmentID: 4,
                     metricType: "REPS",           primaryMuscles: [2],       secondaryMuscles: [5]),
        // ID 12 — Leg Press
        ExerciseSeed(id: 12, name: "Leg Press",             abbr: "LGP", equipmentID: 5,
                     metricType: "REPS",           primaryMuscles: [7],       secondaryMuscles: [9]),
        // ID 13 — Leg Curl
        ExerciseSeed(id: 13, name: "Leg Curl",              abbr: "LGC", equipmentID: 5,
                     metricType: "REPS",           primaryMuscles: [8],       secondaryMuscles: []),
        // ID 14 — Leg Extension
        ExerciseSeed(id: 14, name: "Leg Extension",         abbr: "LGE", equipmentID: 5,
                     metricType: "REPS",           primaryMuscles: [7],       secondaryMuscles: []),
        // ID 15 — Calf Raise
        ExerciseSeed(id: 15, name: "Calf Raise",            abbr: "CLF", equipmentID: 5,
                     metricType: "REPS",           primaryMuscles: [10],      secondaryMuscles: []),
        // ID 16 — DB Curl
        ExerciseSeed(id: 16, name: "DB Curl",               abbr: "DBC", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [5],       secondaryMuscles: []),
        // ID 17 — Tricep Pushdown
        ExerciseSeed(id: 17, name: "Tricep Pushdown",       abbr: "TPD", equipmentID: 4,
                     metricType: "REPS",           primaryMuscles: [6],       secondaryMuscles: []),
        // ID 18 — Hammer Curl
        ExerciseSeed(id: 18, name: "Hammer Curl",           abbr: "HMC", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [5],       secondaryMuscles: []),
        // ID 19 — Skullcrusher
        ExerciseSeed(id: 19, name: "Skullcrusher",          abbr: "SKL", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [6],       secondaryMuscles: []),
        // ID 20 — Lateral Raise
        ExerciseSeed(id: 20, name: "Lateral Raise",         abbr: "LAT", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [4],       secondaryMuscles: []),
        // ID 21 — Face Pull
        ExerciseSeed(id: 21, name: "Face Pull",             abbr: "FPL", equipmentID: 4,
                     metricType: "REPS",           primaryMuscles: [4],       secondaryMuscles: [2]),
        // ID 22 — Hip Thrust
        ExerciseSeed(id: 22, name: "Hip Thrust",            abbr: "HPT", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [9],       secondaryMuscles: [8]),
        // ID 23 — Bulgarian Split Squat
        ExerciseSeed(id: 23, name: "Bulgarian Split Squat", abbr: "BSS", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [7],       secondaryMuscles: [9]),
        // ID 24 — Goblet Squat
        ExerciseSeed(id: 24, name: "Goblet Squat",          abbr: "GBS", equipmentID: 6,
                     metricType: "REPS",           primaryMuscles: [7],       secondaryMuscles: [9, 11]),
        // ID 25 — DB Bench
        ExerciseSeed(id: 25, name: "DB Bench",              abbr: "DBB", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [1],       secondaryMuscles: [6, 4]),
        // ID 26 — Push-up
        ExerciseSeed(id: 26, name: "Push-up",               abbr: "PSH", equipmentID: 3,
                     metricType: "REPS_BODYWEIGHT", primaryMuscles: [1],      secondaryMuscles: [6, 4]),
        // ID 27 — Dip
        ExerciseSeed(id: 27, name: "Dip",                   abbr: "DIP", equipmentID: 3,
                     metricType: "REPS_BODYWEIGHT", primaryMuscles: [6, 1],   secondaryMuscles: [4]),
        // ID 28 — Chin-up
        ExerciseSeed(id: 28, name: "Chin-up",               abbr: "CHN", equipmentID: 3,
                     metricType: "REPS_BODYWEIGHT", primaryMuscles: [5, 3],   secondaryMuscles: [2]),
        // ID 29 — Plank
        ExerciseSeed(id: 29, name: "Plank",                 abbr: "PLK", equipmentID: 3,
                     metricType: "TIME",            primaryMuscles: [11],     secondaryMuscles: []),
        // ID 30 — Russian Twist
        ExerciseSeed(id: 30, name: "Russian Twist",         abbr: "RST", equipmentID: 3,
                     metricType: "REPS",            primaryMuscles: [11],     secondaryMuscles: []),
        // ID 31 — Wall Sit (TIME · BODYWEIGHT · QUADS · GLUTES)
        ExerciseSeed(id: 31, name: "Wall Sit",              abbr: "WS",  equipmentID: 3,
                     metricType: "TIME",             primaryMuscles: [7],      secondaryMuscles: [9]),
        // ID 32 — Side Plank (TIME · BODYWEIGHT · OBLIQUES · CORE)
        ExerciseSeed(id: 32, name: "Side Plank",            abbr: "SPL", equipmentID: 3,
                     metricType: "TIME",             primaryMuscles: [14],     secondaryMuscles: [11],
                     notes: "Log left and right sides separately if desired."),
        // ID 33 — Dead Hang (TIME · PULLUP BAR · FOREARMS · LATS)
        ExerciseSeed(id: 33, name: "Dead Hang",             abbr: "DH",  equipmentID: 9,
                     metricType: "TIME",             primaryMuscles: [15],     secondaryMuscles: [3]),
        // ID 34 — L-Sit (TIME · BODYWEIGHT · CORE · HIP FLEXORS)
        ExerciseSeed(id: 34, name: "L-Sit",                 abbr: "LS",  equipmentID: 3,
                     metricType: "TIME",             primaryMuscles: [11],     secondaryMuscles: [16]),
    ]

    for ex in exercises {
        let uuid = exerciseUUID(ex.id)
        let notesValue = ex.notes.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "NULL"
        let sql = """
            INSERT INTO exercise (id, client_uuid, name, abbreviation, equipment_id, metric_type, is_custom, notes, created_at, updated_at)
            VALUES (\(ex.id), '\(uuid)', '\(ex.name.replacingOccurrences(of: "'", with: "''"))', '\(ex.abbr)', \(ex.equipmentID), '\(ex.metricType)', 0, \(notesValue), \(now), \(now));
            """
        try exec(db: db, sql: sql)

        for muscleID in ex.primaryMuscles {
            try exec(db: db, sql: """
                INSERT INTO exercise_muscle (exercise_id, muscle_id, role) VALUES (\(ex.id), \(muscleID), 'PRIMARY');
                """)
        }
        for muscleID in ex.secondaryMuscles {
            try exec(db: db, sql: """
                INSERT INTO exercise_muscle (exercise_id, muscle_id, role) VALUES (\(ex.id), \(muscleID), 'SECONDARY');
                """)
        }
    }
}

// MARK: - Run Templates

// Deterministic UUID namespace for run templates: 00000000-0000-0000-0002-<12-digit padded id>
private func runTemplateUUID(_ id: Int) -> String {
    String(format: "00000000-0000-0000-0002-%012d", id)
}

// pace helpers: converts "M:SS /KM" to secs/km integer
private func pace(min: Int, sec: Int) -> Int { min * 60 + sec }

private func insertRunTemplates(_ db: OpaquePointer) throws {
    let now = Int(Date().timeIntervalSince1970)

    // Screenshot 06 canonical values:
    // Easy Run:   STEADY     · 6.0 KM  · 5:40 /KM · 128–142 BPM
    // Tempo Run:  THRESHOLD  · 8.0 KM  · 4:35 /KM · 156–168 BPM
    // Long Run:   ENDURANCE  · 16.0 KM · 5:50 /KM · 130–145 BPM
    // 5×800m:     INTERVALS  · 4.0 KM WORK · 3:30 /KM · 170–182 BPM
    // Fartlek 30: FARTLEK    (partial, below screenshot)
    // Recovery:   RECOVERY   (not shown fully — reasonable defaults applied)

    struct RunTemplateSeed {
        let id: Int
        let name: String
        let runType: String
        let totalKm: Double?
        let workKm: Double?
        let paceMin: Int?   // secs/km lower
        let paceMax: Int?   // secs/km upper
        let hrZoneMin: Int?
        let hrZoneMax: Int?
        let hrBpmMin: Int?
        let hrBpmMax: Int?
    }

    let templates: [RunTemplateSeed] = [
        // ID 1 — Easy Run
        RunTemplateSeed(id: 1, name: "Easy Run",   runType: "STEADY",
                        totalKm: 6.0,  workKm: nil,
                        paceMin: pace(min: 5, sec: 20), paceMax: pace(min: 5, sec: 40),
                        hrZoneMin: 2, hrZoneMax: 3, hrBpmMin: 128, hrBpmMax: 142),
        // ID 2 — Tempo Run
        RunTemplateSeed(id: 2, name: "Tempo Run",  runType: "THRESHOLD",
                        totalKm: 8.0,  workKm: nil,
                        paceMin: pace(min: 4, sec: 35), paceMax: pace(min: 4, sec: 50),
                        hrZoneMin: 4, hrZoneMax: 4, hrBpmMin: 156, hrBpmMax: 168),
        // ID 3 — Long Run
        RunTemplateSeed(id: 3, name: "Long Run",   runType: "ENDURANCE",
                        totalKm: 16.0, workKm: nil,
                        paceMin: pace(min: 5, sec: 50), paceMax: pace(min: 6, sec: 10),
                        hrZoneMin: 2, hrZoneMax: 3, hrBpmMin: 130, hrBpmMax: 145),
        // ID 4 — 5×800m (screenshot: 4.0 KM WORK · 3:30 /KM · 170–182 BPM)
        RunTemplateSeed(id: 4, name: "5×800m",     runType: "INTERVALS",
                        totalKm: 6.0,  workKm: 4.0,
                        paceMin: pace(min: 3, sec: 30), paceMax: pace(min: 3, sec: 45),
                        hrZoneMin: 5, hrZoneMax: 5, hrBpmMin: 170, hrBpmMax: 182),
        // ID 5 — Fartlek 30
        RunTemplateSeed(id: 5, name: "Fartlek 30", runType: "FARTLEK",
                        totalKm: 8.0,  workKm: nil,
                        paceMin: pace(min: 4, sec: 30), paceMax: pace(min: 5, sec: 30),
                        hrZoneMin: 3, hrZoneMax: 5, hrBpmMin: 140, hrBpmMax: 175),
        // ID 6 — Recovery
        RunTemplateSeed(id: 6, name: "Recovery",   runType: "RECOVERY",
                        totalKm: 4.0,  workKm: nil,
                        paceMin: pace(min: 6, sec: 0), paceMax: pace(min: 6, sec: 30),
                        hrZoneMin: 1, hrZoneMax: 2, hrBpmMin: 110, hrBpmMax: 128),
    ]

    for t in templates {
        let uuid = runTemplateUUID(t.id)

        func sqlNullable<T>(_ v: T?) -> String {
            guard let v else { return "NULL" }
            return "\(v)"
        }

        let sql = """
            INSERT INTO run_template (
                id, client_uuid, name, run_type,
                target_total_distance_km, target_work_distance_km,
                target_pace_secs_min, target_pace_secs_max,
                hr_zone_min, hr_zone_max,
                hr_bpm_min, hr_bpm_max,
                is_custom, created_at, updated_at
            ) VALUES (
                \(t.id), '\(uuid)', '\(t.name)', '\(t.runType)',
                \(sqlNullable(t.totalKm)), \(sqlNullable(t.workKm)),
                \(sqlNullable(t.paceMin)), \(sqlNullable(t.paceMax)),
                \(sqlNullable(t.hrZoneMin)), \(sqlNullable(t.hrZoneMax)),
                \(sqlNullable(t.hrBpmMin)), \(sqlNullable(t.hrBpmMax)),
                0, \(now), \(now)
            );
            """
        try exec(db: db, sql: sql)
    }

    // Interval blocks for 5×800m (template ID 4)
    // Blocks: 1km WU · 5×800m WORK w/ 200m REST · 1km CD
    try insertIntervalBlocks(db, templateID: 4)

    // Interval blocks for Fartlek 30 (template ID 5)
    // Blocks: WU · alternating fast/easy bursts · CD
    try insertFartlekBlocks(db, templateID: 5)
}

private func insertIntervalBlocks(_ db: OpaquePointer, templateID: Int) throws {
    // 5×800m structure: 1km WU → 5× (800m WORK + 200m REST) → 1km CD
    // Flattened into ordered blocks; repeat_count on WORK block captures the ×5.
    let blocks: [(sort: Int, type: String, repeat_count: Int, distKm: Double?, durSecs: Int?, pace: Int?, zone: Int?)] = [
        (1, "WARMUP",   1, 1.0,  nil, pace(min: 5, sec: 30), 2),
        (2, "WORK",     5, 0.8,  nil, pace(min: 3, sec: 30), 5),
        (3, "RECOVERY", 5, 0.2,  nil, pace(min: 6, sec: 0),  1),
        (4, "COOLDOWN", 1, 1.0,  nil, pace(min: 5, sec: 30), 2),
    ]
    for b in blocks {
        let distVal = b.distKm.map { "\($0)" } ?? "NULL"
        let durVal  = b.durSecs.map { "\($0)" } ?? "NULL"
        let paceVal = b.pace.map { "\($0)" } ?? "NULL"
        let zoneVal = b.zone.map { "\($0)" } ?? "NULL"
        try exec(db: db, sql: """
            INSERT INTO run_interval_block (run_template_id, sort_order, block_type, repeat_count, distance_km, duration_secs, target_pace_secs, hr_zone)
            VALUES (\(templateID), \(b.sort), '\(b.type)', \(b.repeat_count), \(distVal), \(durVal), \(paceVal), \(zoneVal));
            """)
    }
}

private func insertFartlekBlocks(_ db: OpaquePointer, templateID: Int) throws {
    // Fartlek 30 — 30-minute fartlek: 2min WU → 6× (3min WORK + 2min RECOVERY) → 2min CD
    let blocks: [(sort: Int, type: String, repeat_count: Int, distKm: Double?, durSecs: Int?, pace: Int?, zone: Int?)] = [
        (1, "WARMUP",   1, nil, 120,  pace(min: 5, sec: 30), 2),
        (2, "WORK",     6, nil, 180,  pace(min: 4, sec: 0),  4),
        (3, "RECOVERY", 6, nil, 120,  pace(min: 5, sec: 30), 2),
        (4, "COOLDOWN", 1, nil, 120,  pace(min: 5, sec: 30), 2),
    ]
    for b in blocks {
        let distVal = b.distKm.map { "\($0)" } ?? "NULL"
        let durVal  = b.durSecs.map { "\($0)" } ?? "NULL"
        let paceVal = b.pace.map { "\($0)" } ?? "NULL"
        let zoneVal = b.zone.map { "\($0)" } ?? "NULL"
        try exec(db: db, sql: """
            INSERT INTO run_interval_block (run_template_id, sort_order, block_type, repeat_count, distance_km, duration_secs, target_pace_secs, hr_zone)
            VALUES (\(templateID), \(b.sort), '\(b.type)', \(b.repeat_count), \(distVal), \(durVal), \(paceVal), \(zoneVal));
            """)
    }
}

// MARK: - Helpers

private func tableIsEmpty(_ db: OpaquePointer, table: String) throws -> Bool {
    var stmt: OpaquePointer? = nil
    let sql = "SELECT COUNT(*) FROM \(table);"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        let msg = String(cString: sqlite3_errmsg(db))
        throw SchemaError.execFailed(statement: sql, message: msg)
    }
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_step(stmt) == SQLITE_ROW else { return true }
    return sqlite3_column_int(stmt, 0) == 0
}
