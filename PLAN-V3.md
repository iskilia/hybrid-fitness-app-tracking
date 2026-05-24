# V3 — Screenshot parity + verification unblock

## Context

V2 shipped DB-level changes (timed-hold columns, composite index, snapshot
infrastructure, Settings toggles) and lift-side recall card. The user ran
`VERIFICATION-V2.md` and only step 1 passed; the remaining 14 steps failed.
Root causes:

- **No seeded routines.** Seed populates exercises + run templates only —
  zero `routine` / `routine_exercise` rows. Steps 2 (Plank in a routine),
  5–10 (active session, recall card) cannot be reached without first
  building a routine through a UI that does not exist.
- **No routine planner editor.** Users have no in-app way to create a
  routine. CustomExerciseEditor only edits the exercise *catalogue*.
- **Per-set plans not rendered.** Screenshots
  (`routine-lift.png`, `routine-holds-empty.png`, `create-exercise.png`)
  show one pill chip per planned set (`W · 48kg × 6-8`, `1 · 45-60S`,
  `2 · 65kg × 6-8`). Current schema stores a single rep/duration range per
  `routine_exercise`, and the detail view renders one consolidated label.
- **Active session UI gaps.** `workout-lift.png` / `workout-holds.png`
  show a REST countdown + progress bar, a warmup "W" row, planned values
  shown beside the input fields, and an exercise notes blob. None of
  these are implemented.
- **No standalone Library surface.** Run templates are reachable only
  inside the "add run to a routine" flow; the user expected to browse the
  6 seeded templates from a top-level Library destination.

Scope decisions (set with the user before drafting):
- Full screenshot parity.
- V3 schema migration adding `routine_exercise_set` (per-set plans).
- Standalone Library tab with Lift + Run sub-tabs.

Outcome: when V3 ships, `VERIFICATION-V2.md` passes end to end on a
clean install, and the captured screenshots align with the rendered app.

---

## Branch + schema baseline

Branch off `feature/v2` once it is merged (or off `main` if the V2 merge
lands first). Branch name `feature/v3`. Bump `schema_version` to `3`,
mirroring the V2 pattern (`Migrator.swift` adds a `(version: 3, apply:
applyV3)` tuple, `SchemaDoc.schemaVersion` becomes `"3.0"`).

The plan file itself lives at `PLAN-V3.md` in the repo root once
execution starts; this scratchpad becomes obsolete after that.

---

## Phase W1 — `routine_exercise_set` schema + repo

**Schema (`Sources/Persistence/Schema.swift`).** Append a new table:

```
CREATE TABLE routine_exercise_set (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    client_uuid TEXT NOT NULL UNIQUE,
    routine_exercise_id INTEGER NOT NULL REFERENCES routine_exercise(id) ON DELETE CASCADE,
    set_number INTEGER NOT NULL,
    set_type TEXT NOT NULL CHECK (set_type IN ('WARMUP','WORKING','BACKOFF')),
    target_weight_kg REAL,
    target_reps_min INTEGER,
    target_reps_max INTEGER,
    target_duration_secs_min INTEGER,
    target_duration_secs_max INTEGER,
    notes TEXT,
    updated_at INTEGER NOT NULL,
    UNIQUE(routine_exercise_id, set_number)
);
CREATE INDEX idx_res_routine_exercise ON routine_exercise_set(routine_exercise_id, set_number);
```

**Migration (`Sources/Persistence/Migrations/Migrator.swift`).** New
`applyV3` runs the CREATE TABLE + CREATE INDEX, plus a one-time
backfill: for every existing `routine_exercise` row, insert one or more
`routine_exercise_set` rows derived from the V2 columns
(`target_sets` count, `target_rep_min/max`, `target_duration_secs_min/max`).
Type `WARMUP` for the first set when `target_sets > 1` is up to product;
default all backfilled rows to `WORKING`.

**Model (`Sources/Domain/Models/Routine.swift`).** Add a
`RoutineExerciseSet: Codable, Identifiable, Sendable` value type with
fields mirroring the columns. Add `targetSets: [RoutineExerciseSet]` on
`RoutineExercise` as a populated-by-repo field.

**Repo (`Sources/Persistence/Repositories/RoutineRepository.swift`).**
Add CRUD around the new table:

- `listSets(routineExerciseID: Int) async throws -> [RoutineExerciseSet]`
- `replaceSets(routineExerciseID: Int, sets: [RoutineExerciseSet]) async throws`
  (transactional delete + re-insert; simplest contract for the editor)
- `appendSet(_ set: RoutineExerciseSet) async throws`
- `updateSet(_ set: RoutineExerciseSet) async throws`
- `removeSet(id: UUID) async throws`

`listExercises(routineID:)` should populate each `RoutineExercise.targetSets`
in one batched query so the detail view does not N+1.

`SnapshotHook.notifyChange()` fires after every mutation.

---

## Phase W2 — Seed data + sample routines

**File:** `Sources/Persistence/Seed/SeedData.swift`.

Add three seeded routines (insert into `routine` + `routine_exercise` +
`routine_exercise_set`):

1. **Push Day** (`type=LIFT`, 3 exercises × per-set plans matching the
   `routine-lift.png` screenshot):
   - Bench Press — 4 sets (`W·40kg×6-8`, `2·65kg×6-8`, `3·70kg×5-7`, `4·72.5kg×4-6`)
   - Overhead Press — 3 sets (`1·40kg×6-8`, `2·45kg×5-7`, `3·50kg×4-6`)
   - Incline DB Press — 3 sets (`1·24kg×8-12`, `2·26kg×8-10`, `3·28kg×6-10`)
2. **Core & Holds** (`type=LIFT`, 4 exercises × time-based per-set plans
   matching `routine-holds-empty.png`):
   - Plank — 3 sets × 45–60s
   - Side Plank — 3 sets × 30–45s
   - Dead Hang — 3 sets × 30–45s
   - Wall Sit — 3 sets × 45–60s
3. **Tempo Tuesday** (`type=RUN`, 1 `routine_run` slot pointing at the
   seeded Tempo Run template):
   - Tempo Run × 1

Subtitle counts use the relationship between the seeded
`routine_exercise.exercise_id` and the exercise's `metric_type` — hold
count = number of routine_exercise rows whose exercise is `.time`.

Seed runs only when `routine` is empty (`tableIsEmpty(db, table: "routine")`
guard, mirroring the existing exercise/run-template seeding pattern).

---

## Phase W3 — Routine detail per-set pill rendering

**Lift (`Sources/UI/Lift/LiftRoutineDetailView.swift`).** Replace the
single `repRangeLabel` with a `setPillStack` view that wraps a row of
`SetPill` chips, one per `routineExercise.targetSets` entry, in order.

`SetPill` (new, in `Sources/UI/Shared/SetPill.swift`) renders:

- Leading label: `W` for `set_type == .warmup`, `set.set_number` otherwise.
- Body: branched on the parent `exercise.metricType`:
  - `.repsWeighted` → `{weight}kg × {min}-{max}` (single value when
    `min == max`; `min+` when only min set).
  - `.reps`, `.repsBodyweight` → `× {min}-{max}`.
  - `.time` → `{min}-{max}s` (or single value when equal).
- Trailing pencil tap area (push to W5 editor).

**Run (`Sources/UI/Run/RunRoutineDetailView.swift`).** Existing
`RunRow` already approximates the screenshot; verify and patch the
interval description label ("2k WU · 5k T · 1k CD") via
`IntervalDescription` if it diverges.

**Subtitle calculation** lives in `LiftRoutineDetailViewModel` (and
mirrored in `HomeViewModel.subtitleText`): exercise count + hold count
(`exercise.metricType == .time` rows), formatted as
`"{n} EXERCISES · {h} HOLD{s}"`. Hold suffix elided when zero.

---

## Phase W4 — Active session UI

Files: `Sources/UI/Lift/LiftActiveSessionView.swift`,
`ExerciseCardView.swift`, `SetRow.swift`, `LiftActiveSessionViewModel.swift`.

1. **Planned hint per set.** `SetRow` accepts a `planned: RoutineExerciseSet?`.
   When present, the row renders the planned weight + rep/duration range
   as inline text in the empty TextField placeholder slot and as a small
   muted label below the input. Pattern matches the `60` value visible
   next to the input field in `workout-lift.png`.
2. **Warmup "W" label.** Replace the numeric set index with `W` when the
   row's `planned?.setType == .warmup`.
3. **REST timer.** New shared component `Sources/UI/Shared/RestTimerBar.swift`
   (clock icon + countdown text + horizontal progress bar). Driven by an
   `@Observable` `RestTimerState` on the `ExerciseCardState` — starts on
   set ✓, ticks every 250 ms via `Task`, completes silently. Default rest
   60 s; pulled from `RoutineExerciseSet.notes` parsing or a future column
   if time permits, otherwise hard-coded for now.
4. **Exercise notes blob.** Display `routine_exercise.notes` (existing
   field) above the set table in an italic card matching the
   `workout-holds.png` rendering.

Touchpoints in `LiftActiveSessionViewModel.load()` — extend
`ExerciseCardState` to hold `[RoutineExerciseSet]` and bind to row
construction so each `SetRowState` gets its `planned` companion.

---

## Phase W5 — Routine planner editor

New files:
- `Sources/UI/Lift/RoutinePlanEditorView.swift`
- `Sources/UI/Lift/RoutinePlanEditorViewModel.swift`

Surface: pushed from a "+" / pencil button on routine detail. Edits a
single `routine_exercise` at a time (one screen per exercise). Reuses
`SetPill` from W3 for read-only render, adds an editable form sheet for
each pill: set number, type (warmup/working/backoff), weight, rep range
or duration range (branched on exercise.metricType), notes.

Buttons: `Add set` (appends with sensible defaults from prior set),
`Remove` (per pill), `Save` (calls `RoutineRepository.replaceSets`).

Reorder via SwiftUI `.onMove` on the editor list; persist via
re-numbering `set_number` in `replaceSets`.

A second new screen `RoutineCreationView` (also under
`Sources/UI/Lift/`) handles the "+" on `RoutinesView`: pick a name,
type, pick exercises from existing `ExerciseLibraryView`, then drill
into per-exercise `RoutinePlanEditorView` for set planning. This is the
piece the manual verification needs in order to even reach step 2 on a
clean install if the seed data ever fails to load.

---

## Phase W6 — Standalone Library tab

New top-level destination beside Today / Routines / Settings. Files:

- `Sources/UI/Library/LibraryView.swift` — host with two segmented
  sub-tabs (Lift / Run).
- `Sources/UI/Library/LibraryLiftSection.swift` — reuses
  `ExerciseLibraryView` content; lists all exercises (custom + seeded)
  with metric_type badge.
- `Sources/UI/Library/LibraryRunSection.swift` — lists the 6 seeded
  run templates + any user-created ones, reusing `RunRow` for the cells.

Router (`Sources/UI/Router.swift`) gets a `.library` case; the root
`HybridApp` tab structure adds the destination between Routines and
Settings. Templates are read-only here; tap-to-detail pushes to a
read-only `RunTemplateDetailView` (new, minimal — render the same
content as `RunRow` plus the interval list).

Pbxproj: 4 new files × 2 entries (build + ref) + 2 group + 2 source.
Orchestrator pre-wires stubs before dispatching the ui-coder.

---

## Phase W7 — Snapshot + export updates

Files: `Sources/Export/JSONExporter.swift`, `CSVExporter.swift`,
`Sources/Export/SchemaDoc.swift`.

- Add `routine_exercise_set` (with all column names) to both exporter
  payload arrays.
- `SchemaDoc.schemaVersion` bumps to `"3.0"`; markdown body documents
  the new table, set_type semantics, and the relationship to
  `routine_exercise.target_sets` (now a denormalised count that
  `replaceSets` keeps in sync).
- `SnapshotWriter` does not change; envelope is still
  `{"schema_version": "3.0", "data": {...}}` once `SchemaDoc.schemaVersion`
  flips.

---

## Phase W8 — Tests + verification

Test files in `Tests/HybridTests/`:

- Append to `Phase1GateTests.swift`: V3 migration adds the table + index;
  backfill produces ≥1 set per pre-existing routine_exercise; schema_meta
  version is 3.
- Append to `Phase2RepositoryTests.swift`: replaceSets is transactional
  and atomic; listExercises populates targetSets; set_type CHECK
  constraint rejects bad values; cascade delete from routine_exercise
  drops the sets.
- Append to `Phase6ExportTests.swift`: JSON + CSV round-trip the new
  table; SchemaDoc 3.0 contains the new table section.
- New file `Phase8UITests.swift` (XCUITest, optional) snapshots Today,
  Routines, Routine detail (Lift), Routine detail (Holds), Active lift,
  Library Lift, Library Run — compares against the on-disk screenshots
  via pixel-difference threshold. Skip if the project doesn't already
  carry a snapshot-test dependency; we can defer this to a follow-up.

`VERIFICATION-V2.md` is renamed to `VERIFICATION-V3.md` and rewritten:

- 7 timed-hold steps stay; step 2 now lands on the seeded **Core &
  Holds** routine.
- 3 previous-execution steps stay; step 8 lands on the seeded **Push
  Day** routine after completing one session of it.
- 5 LLM-access steps stay; mtime checks now also pass because the
  routine flow can actually finish a session.
- New steps (extending to 20–22 total): per-set pill rendering on a lift
  routine; per-set pill rendering on Core & Holds; REST timer ticks
  between sets; warmup row displays "W"; routine planner editor lets you
  add/edit/remove a set; Library tab lists 6 run templates including
  Tempo Run.

---

## Critical files to modify (representative)

- `Sources/Persistence/Schema.swift`, `Migrator.swift`, `SeedData.swift`
- `Sources/Domain/Models/Routine.swift`
- `Sources/Persistence/Repositories/RoutineRepository.swift`
- `Sources/UI/Lift/LiftRoutineDetailView.swift` and `*ViewModel.swift`
- `Sources/UI/Lift/ExerciseCardView.swift`, `SetRow.swift`,
  `LiftActiveSessionViewModel.swift`
- `Sources/UI/Lift/RoutinePlanEditorView.swift` (new),
  `RoutinePlanEditorViewModel.swift` (new),
  `RoutineCreationView.swift` (new)
- `Sources/UI/Library/LibraryView.swift` (new) + 2 sub-section files
- `Sources/UI/Shared/SetPill.swift` (new), `RestTimerBar.swift` (new)
- `Sources/Export/JSONExporter.swift`, `CSVExporter.swift`,
  `SchemaDoc.swift`
- `Hybrid.xcodeproj/project.pbxproj` — new files pre-wired by
  orchestrator (4 entries per file: PBXBuildFile, PBXFileReference,
  group child, Sources phase)
- `VERIFICATION-V3.md` (rename + extend from V2)

## Reused existing components

- `LastExecutionCard` — unchanged; per-set pills don't affect it.
- `SnapshotHook` / `SnapshotWriter` — unchanged; just consumes the
  bumped schema version from `SchemaDoc`.
- `IntervalDescription` — keep for the run library row rendering.
- `ExerciseLibraryView` content — wrap inside the new Library lift
  sub-tab rather than rebuild.
- `RunRow` — reused inside the new Library run sub-tab.

## Verification

End-to-end:

1. `xcodebuild test -scheme Hybrid -project Hybrid.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17'`
   → full suite green (target ≥ 60 tests once W8 lands).
2. Clean install on iPhone 17 sim: launch, see Today populated with 3
   seeded routines and week stats; tap Core & Holds, confirm
   `1 · 45-60S` pills render; START the session, confirm seconds-only
   SetRow + REST bar + W row.
3. Walk the full `VERIFICATION-V3.md` checklist; every step green.
4. Open Files app → On My iPhone → Hybrid; `hybrid-latest.json` parses
   to `schema_version: "3.0"` with the `routine_exercise_set` key under
   `data`.
5. Tag `v0.3` on the merge commit once VERIFICATION-V3.md is signed off.
