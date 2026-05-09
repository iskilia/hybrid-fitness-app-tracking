# Database Schema

Platform: SQLite · iOS 17 · Local-only · 10 MB ceiling

V1 scope per PRD. Structural choices made with V2 hooks in mind: cloud sync, hybrid analytics (interference / volume per muscle / zone-time), wearable ingest, mixed sessions.

---

## V2-readiness conventions

Applied to every mutable user-data table:

- **`client_uuid TEXT NOT NULL UNIQUE`** — stable cross-device identifier. App generates `Foundation.UUID()` on insert. Autoincrement `id` stays as local PK for FK speed; UUID is the sync key.
- **`updated_at INTEGER NOT NULL`** — Unix epoch seconds. Bumped on every write. Required for last-write-wins or CRDT merge.
- **`deleted_at INTEGER`** — soft delete. NULL = live. Tombstone enables replicated delete.

Read paths must filter `deleted_at IS NULL` unless restoring.

---

## Tables

### schema_meta

Migration tracking. Single row.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY CHECK (id = 1) | |
| version | INTEGER | NOT NULL | Monotonic. Bump on every migration. |
| applied_at | INTEGER | NOT NULL | |

---

### user_profile

Single row.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY CHECK (id = 1) | |
| client_uuid | TEXT | NOT NULL UNIQUE | |
| name | TEXT | NOT NULL DEFAULT '' | |
| weight_unit | TEXT | NOT NULL DEFAULT 'KG' CHECK (weight_unit IN ('KG','LB')) | |
| distance_unit | TEXT | NOT NULL DEFAULT 'KM' CHECK (distance_unit IN ('KM','MI')) | |
| body_weight_kg | REAL | | Latest known. Snapshot copied to session at start. |
| created_at | INTEGER | NOT NULL | |
| updated_at | INTEGER | NOT NULL | |

---

### muscle

Canonical muscle-group lookup. Seeded from base library.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| code | TEXT | NOT NULL UNIQUE | CHEST, TRICEPS, QUADS, GLUTES, LATS, POSTERIOR_CHAIN, etc. |
| display_name | TEXT | NOT NULL | "Chest", "Triceps" |
| group_name | TEXT | NOT NULL | UPPER \| LOWER \| CORE \| FULL_BODY |

---

### equipment

Canonical equipment lookup.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| code | TEXT | NOT NULL UNIQUE | BARBELL, DUMBBELL, BODYWEIGHT, CABLE, MACHINE, KETTLEBELL, BAND, SLED |
| display_name | TEXT | NOT NULL | |

---

### exercise

Base library and custom exercises unified.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| client_uuid | TEXT | NOT NULL UNIQUE | |
| name | TEXT | NOT NULL | |
| abbreviation | TEXT | NOT NULL | 3–4 chars badge ("BNC","OHP") |
| equipment_id | INTEGER | NOT NULL REFERENCES equipment(id) | |
| metric_type | TEXT | NOT NULL DEFAULT 'REPS' CHECK (metric_type IN ('REPS','TIME','DISTANCE','REPS_BODYWEIGHT')) | Drives which session_set fields are valid. Hybrid-friendly: planks=TIME, sled push=DISTANCE, pull-up=REPS_BODYWEIGHT. |
| is_custom | INTEGER | NOT NULL DEFAULT 0 | |
| notes | TEXT | | |
| form_link | TEXT | | URL |
| created_at | INTEGER | NOT NULL | |
| updated_at | INTEGER | NOT NULL | |
| deleted_at | INTEGER | | |

---

### exercise_muscle

Many-to-many. Replaces comma-separated TEXT.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| exercise_id | INTEGER | NOT NULL REFERENCES exercise(id) ON DELETE CASCADE | |
| muscle_id | INTEGER | NOT NULL REFERENCES muscle(id) | |
| role | TEXT | NOT NULL DEFAULT 'PRIMARY' CHECK (role IN ('PRIMARY','SECONDARY')) | V2 volume-per-muscle weighting. |
| PRIMARY KEY | (exercise_id, muscle_id) | | |

---

### run_template

Run library + custom run types.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| client_uuid | TEXT | NOT NULL UNIQUE | |
| name | TEXT | NOT NULL | |
| run_type | TEXT | NOT NULL | STEADY \| THRESHOLD \| ENDURANCE \| INTERVALS \| FARTLEK \| RECOVERY |
| target_total_distance_km | REAL | | Includes WU/CD. |
| target_work_distance_km | REAL | | Work-only (e.g. 4.0 KM in 5×800m). Distinct from total per screenshot 6. |
| target_pace_secs_min | INTEGER | | seconds/km lower bound |
| target_pace_secs_max | INTEGER | | seconds/km upper bound |
| hr_zone_min | INTEGER | | 1–5. Z3-4 in screenshot 4. |
| hr_zone_max | INTEGER | | |
| hr_bpm_min | INTEGER | | |
| hr_bpm_max | INTEGER | | |
| is_custom | INTEGER | NOT NULL DEFAULT 0 | |
| created_at | INTEGER | NOT NULL | |
| updated_at | INTEGER | NOT NULL | |
| deleted_at | INTEGER | | |

---

### run_interval_block

Structured interval blocks for a run template. PRD entity made first-class.

Replaces freeform `interval_description`. Display string ("2k WU · 5k T · 1k CD") computed by joining ordered blocks.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| run_template_id | INTEGER | NOT NULL REFERENCES run_template(id) ON DELETE CASCADE | |
| sort_order | INTEGER | NOT NULL | |
| block_type | TEXT | NOT NULL CHECK (block_type IN ('WARMUP','WORK','RECOVERY','REST','COOLDOWN','TEMPO')) | |
| repeat_count | INTEGER | NOT NULL DEFAULT 1 | e.g. 5 for 5×800m |
| distance_km | REAL | | One of distance_km / duration_secs required. |
| duration_secs | INTEGER | | |
| target_pace_secs | INTEGER | | |
| hr_zone | INTEGER | | 1–5 |
| notes | TEXT | | |

---

### routine

Max 10 enforced at app layer.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| client_uuid | TEXT | NOT NULL UNIQUE | |
| name | TEXT | NOT NULL | |
| type | TEXT | NOT NULL CHECK (type IN ('LIFT','RUN','MIXED')) | MIXED reserved for V2; V1 ignores. |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | |
| created_at | INTEGER | NOT NULL | |
| updated_at | INTEGER | NOT NULL | |
| deleted_at | INTEGER | | |

---

### routine_exercise

Exercises in a LIFT (or MIXED) routine.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| client_uuid | TEXT | NOT NULL UNIQUE | |
| routine_id | INTEGER | NOT NULL REFERENCES routine(id) ON DELETE CASCADE | |
| exercise_id | INTEGER | NOT NULL REFERENCES exercise(id) | |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | |
| target_sets | INTEGER | | |
| target_rep_min | INTEGER | | |
| target_rep_max | INTEGER | | |
| target_rpe | REAL | | Optional planned RPE. |
| notes | TEXT | | |
| updated_at | INTEGER | NOT NULL | |

---

### routine_run

Runs in a RUN (or MIXED) routine.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| client_uuid | TEXT | NOT NULL UNIQUE | |
| routine_id | INTEGER | NOT NULL REFERENCES routine(id) ON DELETE CASCADE | |
| run_template_id | INTEGER | NOT NULL REFERENCES run_template(id) | |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | |
| notes | TEXT | | |
| updated_at | INTEGER | NOT NULL | |

---

### tag

Canonical session tags. PRD-flagged for V2 interference analysis.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| code | TEXT | NOT NULL UNIQUE | "heavy_lower", "tempo", "intervals", "deload" |
| display_name | TEXT | NOT NULL | |
| created_at | INTEGER | NOT NULL | |

---

### session

One row per workout. Status-aware.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| client_uuid | TEXT | NOT NULL UNIQUE | |
| routine_id | INTEGER | REFERENCES routine(id) ON DELETE SET NULL | Nullable — ad-hoc sessions allowed. |
| type | TEXT | NOT NULL CHECK (type IN ('LIFT','RUN','MIXED')) | |
| status | TEXT | NOT NULL DEFAULT 'IN_PROGRESS' CHECK (status IN ('IN_PROGRESS','COMPLETED','ABANDONED')) | |
| started_at | INTEGER | NOT NULL | |
| finished_at | INTEGER | | |
| body_weight_kg | REAL | | Snapshot at session start. Required for bodyweight-exercise progression. |
| notes | TEXT | | |
| updated_at | INTEGER | NOT NULL | |
| deleted_at | INTEGER | | |

---

### session_tag

Many-to-many.

| Column | Type | Constraints |
|--------|------|-------------|
| session_id | INTEGER | NOT NULL REFERENCES session(id) ON DELETE CASCADE |
| tag_id | INTEGER | NOT NULL REFERENCES tag(id) |
| PRIMARY KEY | (session_id, tag_id) | |

---

### session_set

One row per logged set. Hybrid-friendly via metric_type on the linked exercise.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| client_uuid | TEXT | NOT NULL UNIQUE | |
| session_id | INTEGER | NOT NULL REFERENCES session(id) ON DELETE CASCADE | |
| exercise_id | INTEGER | NOT NULL REFERENCES exercise(id) | |
| exercise_order | INTEGER | NOT NULL | Position of exercise within session. |
| set_number | INTEGER | NOT NULL | Position within exercise. |
| set_type | TEXT | NOT NULL DEFAULT 'WORKING' CHECK (set_type IN ('WARMUP','WORKING','DROPSET','AMRAP','FAILURE')) | |
| weight_kg | REAL | | NULL when not applicable (TIME/DISTANCE). |
| reps | INTEGER | | NULL when metric_type=TIME/DISTANCE. |
| duration_secs | INTEGER | | For TIME exercises (planks, holds). |
| distance_m | REAL | | For DISTANCE exercises (carries, sled). |
| rpe | REAL | | 1–10 |
| completed_at | INTEGER | | Timestamp of set completion. V2 rest-time analysis. |
| notes | TEXT | | |
| updated_at | INTEGER | NOT NULL | |

---

### session_run

One row per run logged within a session.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| client_uuid | TEXT | NOT NULL UNIQUE | |
| session_id | INTEGER | NOT NULL REFERENCES session(id) ON DELETE CASCADE | |
| run_template_id | INTEGER | REFERENCES run_template(id) ON DELETE SET NULL | |
| run_order | INTEGER | NOT NULL DEFAULT 0 | |
| actual_distance_km | REAL | | |
| duration_secs | INTEGER | | |
| avg_pace_secs | INTEGER | | |
| avg_hr | INTEGER | | |
| max_hr | INTEGER | | |
| target_hr_min | INTEGER | | Snapshot of target at start. Survives template edits. |
| target_hr_max | INTEGER | | |
| notes | TEXT | | |
| updated_at | INTEGER | NOT NULL | |

---

### session_run_split

Per-block actual splits for a logged run. NULL/absent in V1 manual entry; populated by V2 wearable ingest.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | INTEGER | PRIMARY KEY | |
| session_run_id | INTEGER | NOT NULL REFERENCES session_run(id) ON DELETE CASCADE | |
| sort_order | INTEGER | NOT NULL | |
| block_type | TEXT | | Mirrors run_interval_block.block_type. |
| distance_km | REAL | | |
| duration_secs | INTEGER | | |
| avg_pace_secs | INTEGER | | |
| avg_hr | INTEGER | | |

---

## Indices

```sql
CREATE INDEX idx_session_set_session       ON session_set(session_id);
CREATE INDEX idx_session_set_exercise_time ON session_set(exercise_id, session_id);
CREATE INDEX idx_session_started           ON session(started_at) WHERE deleted_at IS NULL;
CREATE INDEX idx_session_status            ON session(status);
CREATE INDEX idx_routine_exercise_routine  ON routine_exercise(routine_id);
CREATE INDEX idx_routine_run_routine       ON routine_run(routine_id);
CREATE INDEX idx_session_run_session       ON session_run(session_id);
CREATE INDEX idx_run_interval_block_tpl    ON run_interval_block(run_template_id);
CREATE INDEX idx_exercise_muscle_muscle    ON exercise_muscle(muscle_id);
CREATE INDEX idx_session_tag_tag           ON session_tag(tag_id);

-- Sync indices (V2 cloud)
CREATE INDEX idx_session_updated           ON session(updated_at);
CREATE INDEX idx_session_set_updated       ON session_set(updated_at);
CREATE INDEX idx_exercise_updated          ON exercise(updated_at);
CREATE INDEX idx_routine_updated           ON routine(updated_at);
```

---

## DDL

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE schema_meta (
    id         INTEGER PRIMARY KEY CHECK (id = 1),
    version    INTEGER NOT NULL,
    applied_at INTEGER NOT NULL
);

CREATE TABLE user_profile (
    id             INTEGER PRIMARY KEY CHECK (id = 1),
    client_uuid    TEXT NOT NULL UNIQUE,
    name           TEXT NOT NULL DEFAULT '',
    weight_unit    TEXT NOT NULL DEFAULT 'KG' CHECK (weight_unit IN ('KG','LB')),
    distance_unit  TEXT NOT NULL DEFAULT 'KM' CHECK (distance_unit IN ('KM','MI')),
    body_weight_kg REAL,
    created_at     INTEGER NOT NULL,
    updated_at     INTEGER NOT NULL
);

CREATE TABLE muscle (
    id           INTEGER PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    group_name   TEXT NOT NULL
);

CREATE TABLE equipment (
    id           INTEGER PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL
);

CREATE TABLE exercise (
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

CREATE TABLE exercise_muscle (
    exercise_id INTEGER NOT NULL REFERENCES exercise(id) ON DELETE CASCADE,
    muscle_id   INTEGER NOT NULL REFERENCES muscle(id),
    role        TEXT NOT NULL DEFAULT 'PRIMARY' CHECK (role IN ('PRIMARY','SECONDARY')),
    PRIMARY KEY (exercise_id, muscle_id)
);

CREATE TABLE run_template (
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

CREATE TABLE run_interval_block (
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

CREATE TABLE routine (
    id          INTEGER PRIMARY KEY,
    client_uuid TEXT NOT NULL UNIQUE,
    name        TEXT NOT NULL,
    type        TEXT NOT NULL CHECK (type IN ('LIFT','RUN','MIXED')),
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER
);

CREATE TABLE routine_exercise (
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

CREATE TABLE routine_run (
    id              INTEGER PRIMARY KEY,
    client_uuid     TEXT NOT NULL UNIQUE,
    routine_id      INTEGER NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
    run_template_id INTEGER NOT NULL REFERENCES run_template(id),
    sort_order      INTEGER NOT NULL DEFAULT 0,
    notes           TEXT,
    updated_at      INTEGER NOT NULL
);

CREATE TABLE tag (
    id           INTEGER PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    created_at   INTEGER NOT NULL
);

CREATE TABLE session (
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

CREATE TABLE session_tag (
    session_id INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
    tag_id     INTEGER NOT NULL REFERENCES tag(id),
    PRIMARY KEY (session_id, tag_id)
);

CREATE TABLE session_set (
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

CREATE TABLE session_run (
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

CREATE TABLE session_run_split (
    id               INTEGER PRIMARY KEY,
    session_run_id   INTEGER NOT NULL REFERENCES session_run(id) ON DELETE CASCADE,
    sort_order       INTEGER NOT NULL,
    block_type       TEXT,
    distance_km      REAL,
    duration_secs    INTEGER,
    avg_pace_secs    INTEGER,
    avg_hr           INTEGER
);

CREATE INDEX idx_session_set_session       ON session_set(session_id);
CREATE INDEX idx_session_set_exercise_time ON session_set(exercise_id, session_id);
CREATE INDEX idx_session_started           ON session(started_at) WHERE deleted_at IS NULL;
CREATE INDEX idx_session_status            ON session(status);
CREATE INDEX idx_routine_exercise_routine  ON routine_exercise(routine_id);
CREATE INDEX idx_routine_run_routine       ON routine_run(routine_id);
CREATE INDEX idx_session_run_session       ON session_run(session_id);
CREATE INDEX idx_run_interval_block_tpl    ON run_interval_block(run_template_id);
CREATE INDEX idx_exercise_muscle_muscle    ON exercise_muscle(muscle_id);
CREATE INDEX idx_session_tag_tag           ON session_tag(tag_id);

CREATE INDEX idx_session_updated           ON session(updated_at);
CREATE INDEX idx_session_set_updated       ON session_set(updated_at);
CREATE INDEX idx_exercise_updated          ON exercise(updated_at);
CREATE INDEX idx_routine_updated           ON routine(updated_at);
```

---

## V2 hooks summary

| V2 capability | What this schema provides |
|---------------|---------------------------|
| Cloud sync | `client_uuid`, `updated_at`, `deleted_at` on all mutable tables; `updated_at` indices |
| Hybrid interference analytics | Structured `session_tag`, `exercise_muscle`, `tag`, `muscle` joins |
| Volume per muscle group | `exercise_muscle.role` weighting |
| Mixed sessions | `session.type='MIXED'`; `routine.type='MIXED'`; `run_order` and `exercise_order` co-exist |
| Wearable ingest / GPS | `session_run_split` table; `target_hr_*` snapshots on session_run |
| Hybrid exercises (carries, planks, sled) | `exercise.metric_type` + nullable `weight_kg`/`reps`/`duration_secs`/`distance_m` on session_set |
| Bodyweight progression | `session.body_weight_kg` snapshot + `metric_type='REPS_BODYWEIGHT'` |
| Rest-time analysis | `session_set.completed_at` |
| Custom equipment | `equipment` lookup table |
| Migrations | `schema_meta.version` |
| Unit conversion | `user_profile.weight_unit` / `distance_unit` (storage stays canonical kg/km) |

---

## Storage budget

10 MB ceiling. Sync columns add ~50 bytes/row (UUID + 2× INTEGER timestamps).

| Table | Bytes/row | 5-yr power user (~750 sessions) |
|-------|-----------|----------------------------------|
| session | ~120 | 90 KB |
| session_set | ~140 | 750 × 25 sets = ~2.6 MB |
| session_run | ~140 | 200 runs ≈ 28 KB |
| session_run_split | ~80 | sparse V1; ~50 KB V2 |
| exercise + muscle joins | — | <50 KB total |

5-yr projection ≈ 3 MB. Within budget with V2 sync overhead included.
