# Database Schema

Platform: SQLite · iOS 17 · Local-only · 10 MB ceiling

---

## Tables

### user_profile

Single row enforced by `CHECK (id = 1)`.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY CHECK (id = 1) | |
| name | TEXT | NOT NULL DEFAULT '' | |
| created_at | INTEGER | NOT NULL | Unix epoch seconds |

---

### exercise

Base library and custom exercises unified in one table.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| name | TEXT | NOT NULL | |
| abbreviation | TEXT | NOT NULL | 3–4 chars, e.g. "BNC", "OHP" |
| equipment | TEXT | NOT NULL | BARBELL \| DUMBBELL \| BODYWEIGHT \| CABLE \| MACHINE \| KETTLEBELL |
| muscles | TEXT | NOT NULL | Comma-separated: "CHEST,TRICEPS" |
| is_custom | INTEGER | NOT NULL DEFAULT 0 | 0 = base library, 1 = user-created |
| notes | TEXT | | |
| form_link | TEXT | | URL |
| created_at | INTEGER | NOT NULL | Unix epoch seconds |

---

### run_template

Base library and custom run types unified in one table.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| name | TEXT | NOT NULL | |
| run_type | TEXT | NOT NULL | STEADY \| THRESHOLD \| ENDURANCE \| INTERVALS \| FARTLEK |
| target_distance_km | REAL | | |
| target_pace_secs | INTEGER | | Seconds per km |
| hr_bpm_min | INTEGER | | |
| hr_bpm_max | INTEGER | | |
| interval_description | TEXT | | e.g. "2k WU · 5k T · 1k CD" |
| is_custom | INTEGER | NOT NULL DEFAULT 0 | 0 = base library, 1 = user-created |
| created_at | INTEGER | NOT NULL | Unix epoch seconds |

---

### routine

Max 10 routines enforced at the application layer.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| name | TEXT | NOT NULL | |
| type | TEXT | NOT NULL CHECK (type IN ('LIFT', 'RUN')) | |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | |
| created_at | INTEGER | NOT NULL | Unix epoch seconds |
| updated_at | INTEGER | NOT NULL | Unix epoch seconds |

---

### routine_exercise

Exercises belonging to a LIFT routine.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| routine_id | INTEGER | NOT NULL REFERENCES routine(id) ON DELETE CASCADE | |
| exercise_id | INTEGER | NOT NULL REFERENCES exercise(id) | |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | |
| target_sets | INTEGER | | |
| target_rep_min | INTEGER | | |
| target_rep_max | INTEGER | | |
| notes | TEXT | | |

---

### routine_run

Runs belonging to a RUN routine.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| routine_id | INTEGER | NOT NULL REFERENCES routine(id) ON DELETE CASCADE | |
| run_template_id | INTEGER | NOT NULL REFERENCES run_template(id) | |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | |
| notes | TEXT | | |

---

### session

One row per completed workout.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| routine_id | INTEGER | REFERENCES routine(id) ON DELETE SET NULL | Nullable — ad-hoc sessions allowed |
| type | TEXT | NOT NULL CHECK (type IN ('LIFT', 'RUN')) | |
| started_at | INTEGER | NOT NULL | Unix epoch seconds |
| finished_at | INTEGER | | Null until session ends |
| notes | TEXT | | |
| tags | TEXT | | JSON array: ["heavy lower","deload"] |

---

### session_set

One row per set logged in a LIFT session.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| session_id | INTEGER | NOT NULL REFERENCES session(id) ON DELETE CASCADE | |
| exercise_id | INTEGER | NOT NULL REFERENCES exercise(id) | |
| set_number | INTEGER | NOT NULL | |
| set_type | TEXT | NOT NULL DEFAULT 'WORKING' CHECK (set_type IN ('WARMUP','WORKING','DROPSET')) | |
| weight_kg | REAL | NOT NULL DEFAULT 0 | |
| reps | INTEGER | NOT NULL DEFAULT 0 | |
| rpe | REAL | | 1–10 scale |

---

### session_run

One row per run logged in a RUN session.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| session_id | INTEGER | NOT NULL REFERENCES session(id) ON DELETE CASCADE | |
| run_template_id | INTEGER | REFERENCES run_template(id) ON DELETE SET NULL | Nullable |
| actual_distance_km | REAL | | |
| duration_secs | INTEGER | | |
| avg_pace_secs | INTEGER | | Seconds per km |
| avg_hr | INTEGER | | |
| notes | TEXT | | |

---

## Indices

```sql
CREATE INDEX idx_session_set_session  ON session_set(session_id);
CREATE INDEX idx_session_set_exercise ON session_set(exercise_id);
CREATE INDEX idx_session_started      ON session(started_at);
CREATE INDEX idx_routine_exercise     ON routine_exercise(routine_id);
```

---

## DDL

```sql
CREATE TABLE user_profile (
    id         INTEGER PRIMARY KEY CHECK (id = 1),
    name       TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL
);

CREATE TABLE exercise (
    id           INTEGER PRIMARY KEY,
    name         TEXT NOT NULL,
    abbreviation TEXT NOT NULL,
    equipment    TEXT NOT NULL,
    muscles      TEXT NOT NULL,
    is_custom    INTEGER NOT NULL DEFAULT 0,
    notes        TEXT,
    form_link    TEXT,
    created_at   INTEGER NOT NULL
);

CREATE TABLE run_template (
    id                   INTEGER PRIMARY KEY,
    name                 TEXT NOT NULL,
    run_type             TEXT NOT NULL,
    target_distance_km   REAL,
    target_pace_secs     INTEGER,
    hr_bpm_min           INTEGER,
    hr_bpm_max           INTEGER,
    interval_description TEXT,
    is_custom            INTEGER NOT NULL DEFAULT 0,
    created_at           INTEGER NOT NULL
);

CREATE TABLE routine (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    type       TEXT NOT NULL CHECK (type IN ('LIFT', 'RUN')),
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE routine_exercise (
    id             INTEGER PRIMARY KEY,
    routine_id     INTEGER NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
    exercise_id    INTEGER NOT NULL REFERENCES exercise(id),
    sort_order     INTEGER NOT NULL DEFAULT 0,
    target_sets    INTEGER,
    target_rep_min INTEGER,
    target_rep_max INTEGER,
    notes          TEXT
);

CREATE TABLE routine_run (
    id              INTEGER PRIMARY KEY,
    routine_id      INTEGER NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
    run_template_id INTEGER NOT NULL REFERENCES run_template(id),
    sort_order      INTEGER NOT NULL DEFAULT 0,
    notes           TEXT
);

CREATE TABLE session (
    id          INTEGER PRIMARY KEY,
    routine_id  INTEGER REFERENCES routine(id) ON DELETE SET NULL,
    type        TEXT NOT NULL CHECK (type IN ('LIFT', 'RUN')),
    started_at  INTEGER NOT NULL,
    finished_at INTEGER,
    notes       TEXT,
    tags        TEXT
);

CREATE TABLE session_set (
    id          INTEGER PRIMARY KEY,
    session_id  INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
    exercise_id INTEGER NOT NULL REFERENCES exercise(id),
    set_number  INTEGER NOT NULL,
    set_type    TEXT NOT NULL DEFAULT 'WORKING'
                    CHECK (set_type IN ('WARMUP','WORKING','DROPSET')),
    weight_kg   REAL NOT NULL DEFAULT 0,
    reps        INTEGER NOT NULL DEFAULT 0,
    rpe         REAL
);

CREATE TABLE session_run (
    id                 INTEGER PRIMARY KEY,
    session_id         INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
    run_template_id    INTEGER REFERENCES run_template(id) ON DELETE SET NULL,
    actual_distance_km REAL,
    duration_secs      INTEGER,
    avg_pace_secs      INTEGER,
    avg_hr             INTEGER,
    notes              TEXT
);

CREATE INDEX idx_session_set_session  ON session_set(session_id);
CREATE INDEX idx_session_set_exercise ON session_set(exercise_id);
CREATE INDEX idx_session_started      ON session(started_at);
CREATE INDEX idx_routine_exercise     ON routine_exercise(routine_id);
```
