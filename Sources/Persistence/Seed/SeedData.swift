import SQLite3
import Foundation

// MARK: - Public entry point

public func seedIfEmpty(_ db: OpaquePointer) throws {
    let needsCatalog =
        try tableIsEmpty(db, table: "equipment")
        && (try tableIsEmpty(db, table: "muscle"))
        && (try tableIsEmpty(db, table: "tag"))
        && (try tableIsEmpty(db, table: "exercise"))
        && (try tableIsEmpty(db, table: "run_template"))

    // Routines depend on the V3 routine_exercise_set table. If V3 hasn't run
    // yet (e.g. an in-flight migration test), skip routine seeding.
    let routineTableReady = try tableExists(db, table: "routine_exercise_set")
    let needsRoutines: Bool
    if routineTableReady {
        needsRoutines = try tableIsEmpty(db, table: "routine")
    } else {
        needsRoutines = false
    }

    guard needsCatalog || needsRoutines else { return }

    try exec(db: db, sql: "BEGIN;")
    do {
        if needsCatalog {
            try insertEquipment(db)
            try insertMuscles(db)
            try insertTags(db)
            try insertExercises(db)
            try insertRunTemplates(db)
        }
        if needsRoutines {
            try insertSeedRoutines(db)
        }
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

enum SeedMuscle: Int {
    case chest = 1, back = 2, lats = 3, shoulders = 4, biceps = 5, triceps = 6
    case quads = 7, hamstrings = 8, glutes = 9, calves = 10
    case core = 11, posteriorChain = 12, upperChest = 13
    case obliques = 14, forearms = 15, hipFlexors = 16
}

private struct ExerciseSeed {
    let id: Int
    let name: String
    let abbr: String
    let equipmentID: Int
    let metricType: String       // REPS | TIME | DISTANCE | REPS_BODYWEIGHT
    let primaryMuscles: [SeedMuscle]
    let secondaryMuscles: [SeedMuscle]
    var notes: String? = nil
}

private func insertExercises(_ db: OpaquePointer) throws {
    let now = Int(Date().timeIntervalSince1970)

    let exercises: [ExerciseSeed] = [
        // ID 1 — Bench Press (screenshot: BNC, BARBELL · CHEST · TRICEPS)
        ExerciseSeed(id: 1,  name: "Bench Press",           abbr: "BNC", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [.chest],       secondaryMuscles: [.triceps, .shoulders]),
        // ID 2 — Back Squat (screenshot: SQT, BARBELL · QUADS · GLUTES)
        ExerciseSeed(id: 2,  name: "Back Squat",            abbr: "SQT", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [.quads],       secondaryMuscles: [.glutes, .hamstrings]),
        // ID 3 — Deadlift (screenshot: DLT, BARBELL · POSTERIOR CHAIN)
        ExerciseSeed(id: 3,  name: "Deadlift",              abbr: "DLT", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [.posteriorChain],      secondaryMuscles: [.hamstrings, .glutes, .back]),
        // ID 4 — Overhead Press (screenshot: OHP, BARBELL · SHOULDERS · TRICEPS)
        ExerciseSeed(id: 4,  name: "Overhead Press",        abbr: "OHP", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [.shoulders],       secondaryMuscles: [.triceps]),
        // ID 5 — Bent-over Row (screenshot: ROW, BARBELL · BACK · BICEPS)
        ExerciseSeed(id: 5,  name: "Bent-over Row",         abbr: "ROW", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [.back],       secondaryMuscles: [.biceps, .lats]),
        // ID 6 — Pull-up (screenshot: PUL, BODYWEIGHT · LATS · BICEPS)
        ExerciseSeed(id: 6,  name: "Pull-up",               abbr: "PUL", equipmentID: 3,
                     metricType: "REPS_BODYWEIGHT", primaryMuscles: [.lats],      secondaryMuscles: [.biceps]),
        // ID 7 — Romanian Deadlift (screenshot: DLT / use RDL per task spec, BARBELL · HAMSTRINGS · GLUTES)
        ExerciseSeed(id: 7,  name: "Romanian Deadlift",     abbr: "RDL", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [.hamstrings],       secondaryMuscles: [.glutes, .posteriorChain]),
        // ID 8 — Incline DB Press (screenshot: BNC, DUMBBELL · UPPER CHEST)
        ExerciseSeed(id: 8,  name: "Incline DB Press",      abbr: "IDB", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [.upperChest],      secondaryMuscles: [.chest, .triceps]),
        // ID 9 — Front Squat
        ExerciseSeed(id: 9,  name: "Front Squat",           abbr: "FSQ", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [.quads],       secondaryMuscles: [.glutes]),
        // ID 10 — Lat Pulldown
        ExerciseSeed(id: 10, name: "Lat Pulldown",          abbr: "LPD", equipmentID: 4,
                     metricType: "REPS",           primaryMuscles: [.lats],       secondaryMuscles: [.biceps]),
        // ID 11 — Cable Row
        ExerciseSeed(id: 11, name: "Cable Row",             abbr: "CRW", equipmentID: 4,
                     metricType: "REPS",           primaryMuscles: [.back],       secondaryMuscles: [.biceps]),
        // ID 12 — Leg Press
        ExerciseSeed(id: 12, name: "Leg Press",             abbr: "LGP", equipmentID: 5,
                     metricType: "REPS",           primaryMuscles: [.quads],       secondaryMuscles: [.glutes]),
        // ID 13 — Leg Curl
        ExerciseSeed(id: 13, name: "Leg Curl",              abbr: "LGC", equipmentID: 5,
                     metricType: "REPS",           primaryMuscles: [.hamstrings],       secondaryMuscles: []),
        // ID 14 — Leg Extension
        ExerciseSeed(id: 14, name: "Leg Extension",         abbr: "LGE", equipmentID: 5,
                     metricType: "REPS",           primaryMuscles: [.quads],       secondaryMuscles: []),
        // ID 15 — Calf Raise
        ExerciseSeed(id: 15, name: "Calf Raise",            abbr: "CLF", equipmentID: 5,
                     metricType: "REPS",           primaryMuscles: [.calves],      secondaryMuscles: []),
        // ID 16 — DB Curl
        ExerciseSeed(id: 16, name: "DB Curl",               abbr: "DBC", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [.biceps],       secondaryMuscles: []),
        // ID 17 — Tricep Pushdown
        ExerciseSeed(id: 17, name: "Tricep Pushdown",       abbr: "TPD", equipmentID: 4,
                     metricType: "REPS",           primaryMuscles: [.triceps],       secondaryMuscles: []),
        // ID 18 — Hammer Curl
        ExerciseSeed(id: 18, name: "Hammer Curl",           abbr: "HMC", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [.biceps],       secondaryMuscles: []),
        // ID 19 — Skullcrusher
        ExerciseSeed(id: 19, name: "Skullcrusher",          abbr: "SKL", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [.triceps],       secondaryMuscles: []),
        // ID 20 — Lateral Raise
        ExerciseSeed(id: 20, name: "Lateral Raise",         abbr: "LAT", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [.shoulders],       secondaryMuscles: []),
        // ID 21 — Face Pull
        ExerciseSeed(id: 21, name: "Face Pull",             abbr: "FPL", equipmentID: 4,
                     metricType: "REPS",           primaryMuscles: [.shoulders],       secondaryMuscles: [.back]),
        // ID 22 — Hip Thrust
        ExerciseSeed(id: 22, name: "Hip Thrust",            abbr: "HPT", equipmentID: 1,
                     metricType: "REPS",           primaryMuscles: [.glutes],       secondaryMuscles: [.hamstrings]),
        // ID 23 — Bulgarian Split Squat
        ExerciseSeed(id: 23, name: "Bulgarian Split Squat", abbr: "BSS", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [.quads],       secondaryMuscles: [.glutes]),
        // ID 24 — Goblet Squat
        ExerciseSeed(id: 24, name: "Goblet Squat",          abbr: "GBS", equipmentID: 6,
                     metricType: "REPS",           primaryMuscles: [.quads],       secondaryMuscles: [.glutes, .core]),
        // ID 25 — DB Bench
        ExerciseSeed(id: 25, name: "DB Bench",              abbr: "DBB", equipmentID: 2,
                     metricType: "REPS",           primaryMuscles: [.chest],       secondaryMuscles: [.triceps, .shoulders]),
        // ID 26 — Push-up
        ExerciseSeed(id: 26, name: "Push-up",               abbr: "PSH", equipmentID: 3,
                     metricType: "REPS_BODYWEIGHT", primaryMuscles: [.chest],      secondaryMuscles: [.triceps, .shoulders]),
        // ID 27 — Dip
        ExerciseSeed(id: 27, name: "Dip",                   abbr: "DIP", equipmentID: 3,
                     metricType: "REPS_BODYWEIGHT", primaryMuscles: [.triceps, .chest],   secondaryMuscles: [.shoulders]),
        // ID 28 — Chin-up
        ExerciseSeed(id: 28, name: "Chin-up",               abbr: "CHN", equipmentID: 3,
                     metricType: "REPS_BODYWEIGHT", primaryMuscles: [.biceps, .lats],   secondaryMuscles: [.back]),
        // ID 29 — Plank
        ExerciseSeed(id: 29, name: "Plank",                 abbr: "PLK", equipmentID: 3,
                     metricType: "TIME",            primaryMuscles: [.core],     secondaryMuscles: []),
        // ID 30 — Russian Twist
        ExerciseSeed(id: 30, name: "Russian Twist",         abbr: "RST", equipmentID: 3,
                     metricType: "REPS",            primaryMuscles: [.core],     secondaryMuscles: []),
        // ID 31 — Wall Sit (TIME · BODYWEIGHT · QUADS · GLUTES)
        ExerciseSeed(id: 31, name: "Wall Sit",              abbr: "WS",  equipmentID: 3,
                     metricType: "TIME",             primaryMuscles: [.quads],      secondaryMuscles: [.glutes]),
        // ID 32 — Side Plank (TIME · BODYWEIGHT · OBLIQUES · CORE)
        ExerciseSeed(id: 32, name: "Side Plank",            abbr: "SPL", equipmentID: 3,
                     metricType: "TIME",             primaryMuscles: [.obliques],     secondaryMuscles: [.core],
                     notes: "Log left and right sides separately if desired."),
        // ID 33 — Dead Hang (TIME · PULLUP BAR · FOREARMS · LATS)
        ExerciseSeed(id: 33, name: "Dead Hang",             abbr: "DH",  equipmentID: 9,
                     metricType: "TIME",             primaryMuscles: [.forearms],     secondaryMuscles: [.lats]),
        // ID 34 — L-Sit (TIME · BODYWEIGHT · CORE · HIP FLEXORS)
        ExerciseSeed(id: 34, name: "L-Sit",                 abbr: "LS",  equipmentID: 3,
                     metricType: "TIME",             primaryMuscles: [.core],     secondaryMuscles: [.hipFlexors]),
        // ID 35 — Run (DISTANCE · BODYWEIGHT · QUADS · HAMSTRINGS · GLUTES · CALVES)
        ExerciseSeed(id: 35, name: "Run",                   abbr: "RUN", equipmentID: 3,
                     metricType: "DISTANCE",         primaryMuscles: [.quads],      secondaryMuscles: [.hamstrings, .glutes, .calves]),
    ]

    for ex in exercises {
        let uuid = exerciseUUID(ex.id)
        let notesValue = ex.notes.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "NULL"
        let sql = """
            INSERT INTO exercise (id, client_uuid, name, abbreviation, equipment_id, metric_type, is_custom, notes, created_at, updated_at)
            VALUES (\(ex.id), '\(uuid)', '\(ex.name.replacingOccurrences(of: "'", with: "''"))', '\(ex.abbr)', \(ex.equipmentID), '\(ex.metricType)', 0, \(notesValue), \(now), \(now));
            """
        try exec(db: db, sql: sql)

        for muscle in ex.primaryMuscles {
            try exec(db: db, sql: """
                INSERT INTO exercise_muscle (exercise_id, muscle_id, role) VALUES (\(ex.id), \(muscle.rawValue), 'PRIMARY');
                """)
        }
        for muscle in ex.secondaryMuscles {
            try exec(db: db, sql: """
                INSERT INTO exercise_muscle (exercise_id, muscle_id, role) VALUES (\(ex.id), \(muscle.rawValue), 'SECONDARY');
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

// MARK: - Routines (V3)
//
// Three seeded sample routines so the home + routine list screens are
// populated on first launch. IDs are chosen to avoid colliding with
// user-created routines (these are inserted before any user action).

private struct PlannedSet {
    let setType: String                  // 'WARMUP' | 'WORKING' | 'BACKOFF'
    let weightKg: Double?
    let repsMin: Int?
    let repsMax: Int?
    let durationSecsMin: Int?
    let durationSecsMax: Int?
}

private struct RoutineExerciseSeed {
    let id: Int                          // routine_exercise.id
    let exerciseID: Int                  // FK exercise.id
    let sortOrder: Int
    let notes: String?
    let plannedSets: [PlannedSet]
}

private struct RoutineRunSeed {
    let id: Int                          // routine_run.id
    let runTemplateID: Int               // FK run_template.id
    let sortOrder: Int
}

private struct RoutineSeed {
    let id: Int
    let name: String
    let type: String                     // 'LIFT' | 'RUN' | 'MIXED'
    let sortOrder: Int
    let exercises: [RoutineExerciseSeed]
    let runs: [RoutineRunSeed]
}

private func insertSeedRoutines(_ db: OpaquePointer) throws {
    let now = Int(Date().timeIntervalSince1970)

    let pushDay = RoutineSeed(
        id: 1, name: "Push Day", type: "LIFT", sortOrder: 1,
        exercises: [
            RoutineExerciseSeed(id: 1, exerciseID: 1, sortOrder: 1, notes: nil, plannedSets: [
                PlannedSet(setType: "WARMUP",  weightKg: 40,   repsMin: 6, repsMax: 8, durationSecsMin: nil, durationSecsMax: nil),
                PlannedSet(setType: "WORKING", weightKg: 65,   repsMin: 6, repsMax: 8, durationSecsMin: nil, durationSecsMax: nil),
                PlannedSet(setType: "WORKING", weightKg: 70,   repsMin: 5, repsMax: 7, durationSecsMin: nil, durationSecsMax: nil),
                PlannedSet(setType: "WORKING", weightKg: 72.5, repsMin: 4, repsMax: 6, durationSecsMin: nil, durationSecsMax: nil),
            ]),
            RoutineExerciseSeed(id: 2, exerciseID: 4, sortOrder: 2, notes: nil, plannedSets: [
                PlannedSet(setType: "WORKING", weightKg: 40, repsMin: 6, repsMax: 8, durationSecsMin: nil, durationSecsMax: nil),
                PlannedSet(setType: "WORKING", weightKg: 45, repsMin: 5, repsMax: 7, durationSecsMin: nil, durationSecsMax: nil),
                PlannedSet(setType: "WORKING", weightKg: 50, repsMin: 4, repsMax: 6, durationSecsMin: nil, durationSecsMax: nil),
            ]),
            RoutineExerciseSeed(id: 3, exerciseID: 8, sortOrder: 3, notes: nil, plannedSets: [
                PlannedSet(setType: "WORKING", weightKg: 24, repsMin: 8, repsMax: 12, durationSecsMin: nil, durationSecsMax: nil),
                PlannedSet(setType: "WORKING", weightKg: 26, repsMin: 8, repsMax: 10, durationSecsMin: nil, durationSecsMax: nil),
                PlannedSet(setType: "WORKING", weightKg: 28, repsMin: 6, repsMax: 10, durationSecsMin: nil, durationSecsMax: nil),
            ]),
        ],
        runs: []
    )

    let coreHolds = RoutineSeed(
        id: 2, name: "Core & Holds", type: "LIFT", sortOrder: 2,
        exercises: [
            RoutineExerciseSeed(id: 4, exerciseID: 29, sortOrder: 1, notes: nil, plannedSets: [
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 45, durationSecsMax: 60),
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 45, durationSecsMax: 60),
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 45, durationSecsMax: 60),
            ]),
            RoutineExerciseSeed(id: 5, exerciseID: 32, sortOrder: 2, notes: nil, plannedSets: [
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 30, durationSecsMax: 45),
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 30, durationSecsMax: 45),
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 30, durationSecsMax: 45),
            ]),
            RoutineExerciseSeed(id: 6, exerciseID: 33, sortOrder: 3, notes: nil, plannedSets: [
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 30, durationSecsMax: 45),
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 30, durationSecsMax: 45),
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 30, durationSecsMax: 45),
            ]),
            RoutineExerciseSeed(id: 7, exerciseID: 31, sortOrder: 4, notes: nil, plannedSets: [
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 45, durationSecsMax: 60),
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 45, durationSecsMax: 60),
                PlannedSet(setType: "WORKING", weightKg: nil, repsMin: nil, repsMax: nil, durationSecsMin: 45, durationSecsMax: 60),
            ]),
        ],
        runs: []
    )

    let tempoTuesday = RoutineSeed(
        id: 3, name: "Tempo Tuesday", type: "RUN", sortOrder: 3,
        exercises: [],
        runs: [
            RoutineRunSeed(id: 1, runTemplateID: 2, sortOrder: 1),
        ]
    )

    for routine in [pushDay, coreHolds, tempoTuesday] {
        try insertRoutine(db, routine, now: now)
    }
}

private func insertRoutine(_ db: OpaquePointer, _ r: RoutineSeed, now: Int) throws {
    let routineUUID = UUID().uuidString.lowercased()
    let routineSQL = """
        INSERT INTO routine
            (id, client_uuid, name, type, sort_order, created_at, updated_at, deleted_at)
        VALUES
            (\(r.id), '\(routineUUID)', '\(r.name)', '\(r.type)', \(r.sortOrder), \(now), \(now), NULL);
        """
    try exec(db: db, sql: routineSQL)

    for re in r.exercises {
        let reUUID = UUID().uuidString.lowercased()
        let targetSets = re.plannedSets.count
        // Derive single-range V2 columns from planned set list so legacy
        // consumers (V1/V2 readers) still see usable data. Use the working-set
        // ranges if available; fall back to nil.
        let workingSet = re.plannedSets.first(where: { $0.setType == "WORKING" }) ?? re.plannedSets[0]
        let reSQL = """
            INSERT INTO routine_exercise
                (id, client_uuid, routine_id, exercise_id, sort_order,
                 target_sets, target_rep_min, target_rep_max, target_rpe,
                 target_duration_secs_min, target_duration_secs_max,
                 notes, updated_at)
            VALUES
                (\(re.id), '\(reUUID)', \(r.id), \(re.exerciseID), \(re.sortOrder),
                 \(targetSets), \(intOrNull(workingSet.repsMin)), \(intOrNull(workingSet.repsMax)), NULL,
                 \(intOrNull(workingSet.durationSecsMin)), \(intOrNull(workingSet.durationSecsMax)),
                 \(textOrNull(re.notes)), \(now));
            """
        try exec(db: db, sql: reSQL)

        for (i, p) in re.plannedSets.enumerated() {
            let setUUID = UUID().uuidString.lowercased()
            let setSQL = """
                INSERT INTO routine_exercise_set
                    (client_uuid, routine_exercise_id, set_number, set_type,
                     target_weight_kg, target_reps_min, target_reps_max,
                     target_duration_secs_min, target_duration_secs_max,
                     notes, updated_at)
                VALUES
                    ('\(setUUID)', \(re.id), \(i + 1), '\(p.setType)',
                     \(doubleOrNull(p.weightKg)),
                     \(intOrNull(p.repsMin)), \(intOrNull(p.repsMax)),
                     \(intOrNull(p.durationSecsMin)), \(intOrNull(p.durationSecsMax)),
                     NULL, \(now));
                """
            try exec(db: db, sql: setSQL)
        }
    }

    for run in r.runs {
        let runUUID = UUID().uuidString.lowercased()
        let runSQL = """
            INSERT INTO routine_run
                (id, client_uuid, routine_id, run_template_id, sort_order, notes, updated_at)
            VALUES
                (\(run.id), '\(runUUID)', \(r.id), \(run.runTemplateID), \(run.sortOrder), NULL, \(now));
            """
        try exec(db: db, sql: runSQL)
    }
}

private func intOrNull(_ v: Int?) -> String { v.map { String($0) } ?? "NULL" }
private func doubleOrNull(_ v: Double?) -> String { v.map { String($0) } ?? "NULL" }
private func textOrNull(_ v: String?) -> String { v.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "NULL" }

// MARK: - Helpers

private func tableExists(_ db: OpaquePointer, table: String) throws -> Bool {
    var stmt: OpaquePointer? = nil
    let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name = ?;"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        let msg = String(cString: sqlite3_errmsg(db))
        throw SchemaError.execFailed(statement: sql, message: msg)
    }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_text(stmt, 1, (table as NSString).utf8String, -1, nil)
    return sqlite3_step(stmt) == SQLITE_ROW
}

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
