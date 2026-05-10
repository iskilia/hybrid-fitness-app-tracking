import SQLite3
import Foundation

// MARK: - Error

public enum SchemaError: Error {
    case execFailed(statement: String, message: String)
}

// MARK: - Public entry point

public func applySchema(_ db: OpaquePointer) throws {
    let statements: [String] = [
        "PRAGMA foreign_keys = ON;",
        "PRAGMA journal_mode = WAL;",

        // schema_meta
        """
        CREATE TABLE IF NOT EXISTS schema_meta (
            id         INTEGER PRIMARY KEY CHECK (id = 1),
            version    INTEGER NOT NULL,
            applied_at INTEGER NOT NULL
        );
        """,

        // user_profile
        """
        CREATE TABLE IF NOT EXISTS user_profile (
            id             INTEGER PRIMARY KEY CHECK (id = 1),
            client_uuid    TEXT NOT NULL UNIQUE,
            name           TEXT NOT NULL DEFAULT '',
            weight_unit    TEXT NOT NULL DEFAULT 'KG' CHECK (weight_unit IN ('KG','LB')),
            distance_unit  TEXT NOT NULL DEFAULT 'KM' CHECK (distance_unit IN ('KM','MI')),
            body_weight_kg REAL,
            created_at     INTEGER NOT NULL,
            updated_at     INTEGER NOT NULL
        );
        """,

        // muscle
        """
        CREATE TABLE IF NOT EXISTS muscle (
            id           INTEGER PRIMARY KEY,
            code         TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            group_name   TEXT NOT NULL
        );
        """,

        // equipment
        """
        CREATE TABLE IF NOT EXISTS equipment (
            id           INTEGER PRIMARY KEY,
            code         TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL
        );
        """,

        // exercise
        """
        CREATE TABLE IF NOT EXISTS exercise (
            id           INTEGER PRIMARY KEY,
            client_uuid  TEXT NOT NULL UNIQUE,
            name         TEXT NOT NULL,
            abbreviation TEXT NOT NULL,
            equipment_id INTEGER NOT NULL REFERENCES equipment(id),
            metric_type  TEXT NOT NULL DEFAULT 'REPS'
                             CHECK (metric_type IN ('REPS','TIME','DISTANCE','REPS_BODYWEIGHT')),
            is_custom    INTEGER NOT NULL DEFAULT 0,
            notes        TEXT,
            form_link    TEXT,
            created_at   INTEGER NOT NULL,
            updated_at   INTEGER NOT NULL,
            deleted_at   INTEGER
        );
        """,

        // exercise_muscle
        """
        CREATE TABLE IF NOT EXISTS exercise_muscle (
            exercise_id INTEGER NOT NULL REFERENCES exercise(id) ON DELETE CASCADE,
            muscle_id   INTEGER NOT NULL REFERENCES muscle(id),
            role        TEXT NOT NULL DEFAULT 'PRIMARY' CHECK (role IN ('PRIMARY','SECONDARY')),
            PRIMARY KEY (exercise_id, muscle_id)
        );
        """,

        // run_template
        """
        CREATE TABLE IF NOT EXISTS run_template (
            id                       INTEGER PRIMARY KEY,
            client_uuid              TEXT NOT NULL UNIQUE,
            name                     TEXT NOT NULL,
            run_type                 TEXT NOT NULL,
            target_total_distance_km REAL,
            target_work_distance_km  REAL,
            target_pace_secs_min     INTEGER,
            target_pace_secs_max     INTEGER,
            hr_zone_min              INTEGER,
            hr_zone_max              INTEGER,
            hr_bpm_min               INTEGER,
            hr_bpm_max               INTEGER,
            is_custom                INTEGER NOT NULL DEFAULT 0,
            created_at               INTEGER NOT NULL,
            updated_at               INTEGER NOT NULL,
            deleted_at               INTEGER
        );
        """,

        // run_interval_block
        """
        CREATE TABLE IF NOT EXISTS run_interval_block (
            id               INTEGER PRIMARY KEY,
            run_template_id  INTEGER NOT NULL REFERENCES run_template(id) ON DELETE CASCADE,
            sort_order       INTEGER NOT NULL,
            block_type       TEXT NOT NULL
                                 CHECK (block_type IN ('WARMUP','WORK','RECOVERY','REST','COOLDOWN','TEMPO')),
            repeat_count     INTEGER NOT NULL DEFAULT 1,
            distance_km      REAL,
            duration_secs    INTEGER,
            target_pace_secs INTEGER,
            hr_zone          INTEGER,
            notes            TEXT
        );
        """,

        // routine
        """
        CREATE TABLE IF NOT EXISTS routine (
            id          INTEGER PRIMARY KEY,
            client_uuid TEXT NOT NULL UNIQUE,
            name        TEXT NOT NULL,
            type        TEXT NOT NULL CHECK (type IN ('LIFT','RUN','MIXED')),
            sort_order  INTEGER NOT NULL DEFAULT 0,
            created_at  INTEGER NOT NULL,
            updated_at  INTEGER NOT NULL,
            deleted_at  INTEGER
        );
        """,

        // routine_exercise
        """
        CREATE TABLE IF NOT EXISTS routine_exercise (
            id             INTEGER PRIMARY KEY,
            client_uuid    TEXT NOT NULL UNIQUE,
            routine_id     INTEGER NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
            exercise_id    INTEGER NOT NULL REFERENCES exercise(id),
            sort_order     INTEGER NOT NULL DEFAULT 0,
            target_sets    INTEGER,
            target_rep_min INTEGER,
            target_rep_max INTEGER,
            target_rpe     REAL,
            notes          TEXT,
            updated_at     INTEGER NOT NULL
        );
        """,

        // routine_run
        """
        CREATE TABLE IF NOT EXISTS routine_run (
            id              INTEGER PRIMARY KEY,
            client_uuid     TEXT NOT NULL UNIQUE,
            routine_id      INTEGER NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
            run_template_id INTEGER NOT NULL REFERENCES run_template(id),
            sort_order      INTEGER NOT NULL DEFAULT 0,
            notes           TEXT,
            updated_at      INTEGER NOT NULL
        );
        """,

        // tag
        """
        CREATE TABLE IF NOT EXISTS tag (
            id           INTEGER PRIMARY KEY,
            code         TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            created_at   INTEGER NOT NULL
        );
        """,

        // session
        """
        CREATE TABLE IF NOT EXISTS session (
            id             INTEGER PRIMARY KEY,
            client_uuid    TEXT NOT NULL UNIQUE,
            routine_id     INTEGER REFERENCES routine(id) ON DELETE SET NULL,
            type           TEXT NOT NULL CHECK (type IN ('LIFT','RUN','MIXED')),
            status         TEXT NOT NULL DEFAULT 'IN_PROGRESS'
                               CHECK (status IN ('IN_PROGRESS','COMPLETED','ABANDONED')),
            started_at     INTEGER NOT NULL,
            finished_at    INTEGER,
            body_weight_kg REAL,
            notes          TEXT,
            updated_at     INTEGER NOT NULL,
            deleted_at     INTEGER
        );
        """,

        // session_tag
        """
        CREATE TABLE IF NOT EXISTS session_tag (
            session_id INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
            tag_id     INTEGER NOT NULL REFERENCES tag(id),
            PRIMARY KEY (session_id, tag_id)
        );
        """,

        // session_set
        """
        CREATE TABLE IF NOT EXISTS session_set (
            id             INTEGER PRIMARY KEY,
            client_uuid    TEXT NOT NULL UNIQUE,
            session_id     INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
            exercise_id    INTEGER NOT NULL REFERENCES exercise(id),
            exercise_order INTEGER NOT NULL,
            set_number     INTEGER NOT NULL,
            set_type       TEXT NOT NULL DEFAULT 'WORKING'
                               CHECK (set_type IN ('WARMUP','WORKING','DROPSET','AMRAP','FAILURE')),
            weight_kg      REAL,
            reps           INTEGER,
            duration_secs  INTEGER,
            distance_m     REAL,
            rpe            REAL,
            completed_at   INTEGER,
            notes          TEXT,
            updated_at     INTEGER NOT NULL
        );
        """,

        // session_run
        """
        CREATE TABLE IF NOT EXISTS session_run (
            id                 INTEGER PRIMARY KEY,
            client_uuid        TEXT NOT NULL UNIQUE,
            session_id         INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
            run_template_id    INTEGER REFERENCES run_template(id) ON DELETE SET NULL,
            run_order          INTEGER NOT NULL DEFAULT 0,
            actual_distance_km REAL,
            duration_secs      INTEGER,
            avg_pace_secs      INTEGER,
            avg_hr             INTEGER,
            max_hr             INTEGER,
            target_hr_min      INTEGER,
            target_hr_max      INTEGER,
            notes              TEXT,
            updated_at         INTEGER NOT NULL
        );
        """,

        // session_run_split
        """
        CREATE TABLE IF NOT EXISTS session_run_split (
            id               INTEGER PRIMARY KEY,
            session_run_id   INTEGER NOT NULL REFERENCES session_run(id) ON DELETE CASCADE,
            sort_order       INTEGER NOT NULL,
            block_type       TEXT,
            distance_km      REAL,
            duration_secs    INTEGER,
            avg_pace_secs    INTEGER,
            avg_hr           INTEGER
        );
        """,

        // Indices
        "CREATE INDEX IF NOT EXISTS idx_session_set_session       ON session_set(session_id);",
        "CREATE INDEX IF NOT EXISTS idx_session_set_exercise_time ON session_set(exercise_id, session_id);",
        "CREATE INDEX IF NOT EXISTS idx_session_started           ON session(started_at) WHERE deleted_at IS NULL;",
        "CREATE INDEX IF NOT EXISTS idx_session_status            ON session(status);",
        "CREATE INDEX IF NOT EXISTS idx_routine_exercise_routine  ON routine_exercise(routine_id);",
        "CREATE INDEX IF NOT EXISTS idx_routine_run_routine       ON routine_run(routine_id);",
        "CREATE INDEX IF NOT EXISTS idx_session_run_session       ON session_run(session_id);",
        "CREATE INDEX IF NOT EXISTS idx_run_interval_block_tpl    ON run_interval_block(run_template_id);",
        "CREATE INDEX IF NOT EXISTS idx_exercise_muscle_muscle    ON exercise_muscle(muscle_id);",
        "CREATE INDEX IF NOT EXISTS idx_session_tag_tag           ON session_tag(tag_id);",
        "CREATE INDEX IF NOT EXISTS idx_session_updated           ON session(updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_session_set_updated       ON session_set(updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_exercise_updated          ON exercise(updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_routine_updated           ON routine(updated_at);",
    ]

    for sql in statements {
        try exec(db: db, sql: sql)
    }
}

// MARK: - Internal helper

func exec(db: OpaquePointer, sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>? = nil
    let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
    if rc != SQLITE_OK {
        let msg = errorMessage.map { String(cString: $0) } ?? "unknown error"
        sqlite3_free(errorMessage)
        throw SchemaError.execFailed(statement: sql, message: msg)
    }
}
