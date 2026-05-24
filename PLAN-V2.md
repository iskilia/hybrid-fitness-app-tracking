# Implementation Plan — Hybrid V0.2

iOS 17 · Swift 6 · SwiftUI · MVVM (`@Observable`) · SQLite · SPM

Source of truth: `PRD-V2.md`, `SCHEMA.md`, V1 `PLAN.md` (for agent roster + dispatch conventions).

V2 adds three themes on top of the V1 baseline:
1. **Timed-hold exercises** — sets logged in seconds for `metric_type = TIME` exercises.
2. **Previous-execution recall** — Last-Execution card on every routine detail screen.
3. **LLM data-access surface** — Files-app exposure + auto-written `Documents/hybrid-latest.json` snapshot + `hybrid-schema.md` companion.

V2 ships on a `feature/v2` branch off the current `main` tip (`98f9a0e Phase 7: full suite green + DB size sanity`). All V2 task IDs are V-prefixed (`TV0.1` … `TV7.4`) so they never collide with V1's `T0.1` … `T7.4` task IDs and the orchestrator can co-track V1's open items (`T7.2` screenshot pass, `T7.4` tag) alongside V2.

**V2-specific deviation from V1.** V1 used screenshot parity (ten `screenshots/*.png` references) as the primary visual gate. V2 introduces net-new UI surfaces (Last-Execution card, Settings additions, duration-variant SetRow) and modifies existing ones (routine planner, history-chart axis) without a canonical pixel reference. Each V2 phase gate uses SwiftUI previews + manual sim runs + XCTest. The 15-step manual verification list in `PRD-V2.md` is the human acceptance suite.

---

## Agent Roster

V2 reuses the V1 agent roster verbatim — no new agent types are introduced. See `PLAN.md` §"Agent Roster" for the full definition of each agent's role, owned files, and tools. V2 owners by name:

- `orchestrator` — plan owner, dispatcher, gatekeeper.
- `db-coder` — schema migration + seed.
- `repo-coder` — repository layer over SQLite.
- `models-coder` — Swift domain types + view-models.
- `ui-shared-coder` — cross-cutting UI (design tokens, Last-Execution card, Settings shell, `Info.plist`).
- `ui-lift-coder` — lift-specific screens (routine planner, active session, history).
- `ui-run-coder` — run-specific screens (routine detail for Last-Execution-card integration).
- `export-coder` — CSV/JSON exporters, `SnapshotWriter`, `SchemaDoc`, Settings export controls.
- `test-coder` — XCTest unit + integration tests.

---

## Dispatch Legend

- **`[P]`** — Parallel-safe within its phase. Orchestrator dispatches simultaneously with siblings.
- **`[S]`** — Sequential / blocking. Must complete before next item in same phase starts.
- **`deps:`** — Task IDs that must be `[x]` before this task is dispatchable. V2 tasks may depend on V1 tasks (assume all V1 `[x]` are met on the `feature/v2` branch base).

---

## Task Board

### Phase V0 — Bootstrap (orchestrator runs solo)

- [ ] **TV0.1** [S] Create `feature/v2` branch from `main` (`98f9a0e`). — *orchestrator*
- [ ] **TV0.2** [S] Bump `schema_meta.version` from 1 → 2 in `Sources/Persistence/Migrations/Migrator.swift`. Register a V1→V2 migration slot (empty body for now; populated by TV1.1). — *orchestrator* (or *db-coder*)

**Gate:** `xcodebuild build` exits 0 on the new branch. Existing V1 XCTest suite still green.

---

### Phase V1 — Foundation (parallel fan-out)

All Phase V1 tasks dispatchable simultaneously after TV0.2.

- [ ] **TV1.1** [P] Schema migration: add `target_duration_secs_min INTEGER NULL` and `target_duration_secs_max INTEGER NULL` to `routine_exercise`; add composite index `idx_session_routine_finished` on `session(routine_id, finished_at DESC)`. Wire into the V1→V2 migration slot from TV0.2. — *db-coder* — deps: TV0.2. Files: `Sources/Persistence/Schema/Schema.swift`, new file under `Sources/Persistence/Migrations/`.
- [ ] **TV1.2** [P] Seed five timed holds with `metric_type = 'TIME'`, `is_custom = 0`: Wall Sit, Plank, Side Plank (L/R via notes), Dead Hang, L-Sit. Wire muscle/equipment joins. — *db-coder* — deps: TV0.2. File: `Sources/Persistence/Seed/SeedData.swift`.
- [ ] **TV1.3** [P] Extend `RoutineExercise` struct with `targetDurationSecsMin: Int?` and `targetDurationSecsMax: Int?` + CodingKeys (`target_duration_secs_min` / `target_duration_secs_max`). — *models-coder* — deps: TV0.2. File: `Sources/Domain/Models/Routine.swift:37`.
- [ ] **TV1.4** [P] `Info.plist`: set `UIFileSharingEnabled = YES`, `LSSupportsOpeningDocumentsInPlace = YES`. — *ui-shared-coder* — deps: TV0.2. File: app `Info.plist`.
- [ ] **TV1.5** [P] Design token: add a "muted / removed" color + opacity rule for Last-Execution-card's removed-exercise rows. — *ui-shared-coder* — deps: TV0.2. File: `Sources/UI/Shared/DesignSystem/Colors.swift`.

**Gate:** XCTest applies the migration to an in-memory DB at schema version 1, advances to 2, inserts a routine with timed-hold targets, queries it back. Seed rows present and queryable. — *test-coder*

---

### Phase V2 — Persistence layer

All Phase V2 tasks dispatchable after Phase V1 gate passes.

- [ ] **TV2.1** [P] Extend `RoutineRepository.insertRoutineExercise` (private helper at `RoutineRepository.swift:162`) and the SELECT in `listExercises` (`:203`) to pass through `target_duration_secs_min` / `target_duration_secs_max`. No new file — `routine_exercise` CRUD already lives inside `RoutineRepository`. — *repo-coder* — deps: TV1.1, TV1.3. File: `Sources/Persistence/Repositories/RoutineRepository.swift`.
- [ ] **TV2.2** [P] `SessionRepository.lastCompletedSession(forRoutineID: Int) -> Session?`. SQL: `SELECT * FROM session WHERE routine_id = ? AND status = 'COMPLETED' AND deleted_at IS NULL ORDER BY finished_at DESC LIMIT 1`. Uses the literal `'COMPLETED'` to match the schema CHECK constraint (`Schema.swift:188-189`) and the actual write path (`SessionRepository.swift:71`). — *repo-coder* — deps: TV1.1. File: `Sources/Persistence/Repositories/SessionRepository.swift`.
- [ ] **TV2.3** [P] `ExerciseRepository`: metric-type immutability guard. Reject updates that change `metric_type` when ≥1 `session_set` references the exercise. — *repo-coder* — deps: TV1.1. File: `Sources/Persistence/Repositories/ExerciseRepository.swift`.
- [ ] **TV2.3a** [P] `ExerciseRepository.metricTypeLocked(exerciseID: Int) -> Bool`. UI read API so the custom-exercise editor (TV4.2) can render the metric-type field as locked pre-input rather than failing at save. Implementation: `SELECT EXISTS(SELECT 1 FROM session_set WHERE exercise_id = ? LIMIT 1)`. — *repo-coder* — deps: TV1.1. File: `Sources/Persistence/Repositories/ExerciseRepository.swift`.
- [ ] **TV2.4** [P] `SessionSetRepository`: app-layer validation. For `TIME` exercises: reject sets with null `duration_secs` or non-null `reps`. For reps-based: reject sets with null `reps` or non-null `duration_secs`. — *repo-coder* — deps: TV1.1. File: `Sources/Persistence/Repositories/SessionSetRepository.swift`.
- [ ] **TV2.5** [P] `SessionSetRepository.topSet(sessionID: Int, exerciseID: Int) -> SessionSet?`. Returns the top set *within one specific session* for a given exercise. Branches on the exercise's `metric_type`: for `TIME`, order by `duration_secs DESC`; for reps-based, order by `weight_kg DESC` then `reps DESC`. Distinct from the existing `topSetPerSession(exerciseID:limit:)` at `SessionSetRepository.swift:111`, which returns history across sessions and excludes TIME rows. Required by TV5.2/TV5.2a. — *repo-coder* — deps: TV1.1. File: `Sources/Persistence/Repositories/SessionSetRepository.swift`.

**Gate:** integration tests cover all six. Immutability guard rejects a real attempt; `metricTypeLocked` returns true after one set, false before. `lastCompletedSession` uses `'COMPLETED'` literal, ignores `IN_PROGRESS` and `ABANDONED`, returns nil for an unused routine. `topSet(sessionID:exerciseID:)` returns the heaviest set for a reps exercise and the longest hold for a TIME exercise. — *test-coder*

---

### Phase V3 — Snapshot infrastructure (parallel with V2 — independent)

Dispatchable after TV0.2; can proceed in parallel with Phase V2.

- [ ] **TV3.1** [P] New `Sources/Domain/Export/SnapshotWriter.swift`. Reuses `JSONExporter` serialisation. Writes `Documents/hybrid-latest.json` atomically (temp file + `FileManager.replaceItemAt`). Debounced 250 ms; off-main dispatch. Top-level `schema_version = "2.0"`. Pretty-printed, stable key order. Documents-dir resolution mirrors `HybridApp.swift:7`. — *export-coder* — deps: TV0.2.
- [ ] **TV3.2** [P] New `Sources/Domain/Export/SchemaDoc.swift`. Emits a static `hybrid-schema.md` string describing the JSON shape, unit conventions (kg / secs / m), and `metric_type` semantics including the timed-hold rule. — *export-coder* — deps: TV0.2.
- [ ] **TV3.3** [P] Size-threshold fallback: when DB > 10 MB (configurable), `SnapshotWriter` switches to manifest-only mode and exposes a flag the UI consumes to nudge the user toward the regular full export. — *export-coder* — deps: TV3.1.

**Gate:** XCTest invokes `SnapshotWriter.write()` against a temp Documents dir. Asserts: file exists, parses as JSON, has `schema_version: "2.0"`, contains every schema table. Concurrent calls debounce to one final write. — *test-coder*

---

### Phase V4 — Timed-hold UI (lift lane + export sanity)

Dispatchable after Phase V2 gate.

- [ ] **TV4.1** [P] Routine planner: when the selected exercise has `metricType == .time`, swap the rep-range fields for a duration-range field (min/max seconds). Persist via TV2.1. — *ui-lift-coder* — deps: TV2.1, TV1.3. File: routine-exercise editor under `Sources/UI/Lift/`.
- [ ] **TV4.2** [P] Custom-exercise editor: explicit metric-type selector (reps / reps+load / time) with a one-line example per option. Default reps+load. Renders the metric-type field as locked (read-only with hint copy) when `ExerciseRepository.metricTypeLocked(exerciseID:)` returns true, instead of relying on save-time failure. — *ui-lift-coder* — deps: TV2.3, TV2.3a. Files: `Sources/UI/Lift/CustomExerciseEditorView.swift`, `Sources/UI/Lift/CustomExerciseEditorViewModel.swift`.
- [ ] **TV4.3** [P] `SetRow` + `LiftActiveSessionViewModel`: branch on the exercise's metric type. For `.time`: render a single seconds field; persist `durationSecs`, leave `reps`/`weightKg` nil. For others: existing behaviour. Replace hardcoded `durationSecs: nil` at `LiftActiveSessionViewModel.swift:154` and `:173`. — *ui-lift-coder* — deps: TV2.4. Files: `Sources/UI/Lift/SetRow.swift` (lines 1–61), `Sources/UI/Lift/LiftActiveSessionViewModel.swift` (lines 9–26 for `SetRowState`, 134–184 for `persistSet`).
- [ ] **TV4.4** [P] Exercise history view: when the exercise's metric type is `.time`, plot `duration_secs` on the Y axis instead of estimated 1RM / load. — *ui-lift-coder* — deps: TV2.4.
- [ ] **TV4.5** [P] Exporter sanity: confirm CSV + JSON emit `duration_secs` on every set row. — *export-coder* — deps: TV1.1. Files: existing exporters under `Sources/Domain/Export/`.

**Gate:** sim run. Create routine with Plank (3 × 30–45s) and Hanging Leg Raise (3 × 8–12). Start session; confirm SetRows render correctly per metric type. Finish; history chart axis correct (seconds for Plank, load for HLR). CSV inspection: plank rows have `duration_secs` populated and `reps` empty; HLR rows are the inverse.

---

### Phase V5 — Previous-execution recall

Sequential spine: TV5.1 → TV5.2a → TV5.2b → (TV5.3 ‖ TV5.4). The card component (TV5.1) defines the `LastExecutionSummary` shape; lift VM (TV5.2a) ratifies it against a real query; run VM (TV5.2b) reuses it; only then do the two screens render in parallel.

- [ ] **TV5.1** [S] New shared component `Sources/UI/Shared/LastExecutionCard.swift`. Accepts a `LastExecutionSummary` value (date, totalDurationSecs, per-exercise top sets). Renders header ("Last time — {relative}"), total duration, per-exercise top sets in each exercise's native unit. Tap → session detail. Empty state ("First time on this routine — no comparison yet"). Muted "removed from routine" rows using TV1.5 token. Async skeleton placeholder for first 200 ms. — *ui-shared-coder* — deps: TV2.2, TV2.5, TV1.5.
- [ ] **TV5.2a** [S] `LiftRoutineDetailViewModel.loadLastExecution()`: calls `SessionRepository.lastCompletedSession(forRoutineID:)`, then `SessionSetRepository.topSet(sessionID:exerciseID:)` per exercise (uses TV2.5, not the historical `topSetPerSession`), composes `LastExecutionSummary`. Includes removed-from-routine exercises as muted rows by diffing the prior session's exercises against the current routine's exercise list. — *ui-lift-coder* — deps: TV5.1, TV2.2, TV2.5. File: `Sources/UI/Lift/LiftRoutineDetailViewModel.swift`.
- [ ] **TV5.2b** [S] `RunRoutineDetailViewModel.loadLastExecution()`: same shape as TV5.2a but for the run lane. Per-`routine_run` summary line shows the last session's distance / duration / pace for that run-template slot. Spec: see PRD-V2 §"Previous-execution recall" addendum (TODO — see Open Specs below); if the addendum is not written by phase entry, scope LastExecutionCard to lift + mixed only in V2 and defer pure-run lane to V2.1. — *ui-run-coder* — deps: TV5.1, TV5.2a, TV2.2. File: `Sources/UI/Run/RunRoutineDetailViewModel.swift`.
- [ ] **TV5.3** [P] Lift routine detail screen renders `LastExecutionCard` above the Start button. — *ui-lift-coder* — deps: TV5.1, TV5.2a. File: `Sources/UI/Lift/LiftRoutineDetailView.swift`.
- [ ] **TV5.4** [P] Run routine detail screen renders `LastExecutionCard` above the Start button. Gated on TV5.2b decision (full implementation vs V2.1 defer). — *ui-run-coder* — deps: TV5.1, TV5.2b. File: `Sources/UI/Run/RunRoutineDetailView.swift`.

**Gate:** sim run. Complete one session; return to its routine detail; card appears with relative time + total duration + per-exercise top sets. Open an untested routine; card shows empty state. Edit the routine to remove an exercise and add a new one; reopen; card still shows the removed exercise muted with the "removed" tag, and omits the new exercise.

---

### Phase V6 — Snapshot wiring + Settings

Dispatchable after Phase V3 gate (snapshot infra exists) and Phase V1 gate (Info.plist).

- [ ] **TV6.1** [P] Wire `SnapshotWriter.write()` into `SessionRepository.finish` (after commit), `RoutineRepository.create/update/delete`, `ExerciseRepository.create/update` (custom-exercise rows only). All calls fire-and-forget; debounce is internal to `SnapshotWriter`. — *repo-coder* + *export-coder* — deps: TV3.1, TV2.1. Files: the named repos plus a thin `SnapshotHook` indirection if cross-module wiring requires it.
- [ ] **TV6.2** [P] Settings: "Auto-update LLM snapshot" toggle (default ON; `UserDefaults` key `snapshot.auto_enabled`). When OFF, hook calls from TV6.1 are no-ops. — *export-coder* — deps: TV6.1.
- [ ] **TV6.3** [P] Settings: "Refresh LLM snapshot" manual button. Always writes regardless of the toggle. — *export-coder* — deps: TV6.1.
- [ ] **TV6.4** [P] Settings footer: one-line privacy note ("Your training data is visible in the Files app under On My iPhone → Hybrid. This is the only way LLM tools can read it."). — *export-coder* — deps: TV1.4.
- [ ] **TV6.5** [P] First-launch hook: write `Documents/hybrid-schema.md` if absent or stale (schema_version mismatch). — *export-coder* — deps: TV3.2.

**Gate:** sim run on a device or simulator with Files app. Confirm `Hybrid.sqlite`, `hybrid-latest.json`, `hybrid-schema.md` visible in On My iPhone → Hybrid. Finish a session; `hybrid-latest.json` mtime updates and contents include the new session. Toggle OFF; finish another session; mtime unchanged. Tap "Refresh LLM snapshot"; mtime updates.

---

### Phase V7 — Polish + Verification

- [ ] **TV7.1** [S] Full XCTest suite green. New cases (eleven, from `PRD-V2.md` test list):
    1. Timed-hold custom exercise create round-trips.
    2. Routine with mixed rep-based + time-based items round-trips.
    3. Session persistence routes seconds vs reps to the correct columns by metric type.
    4. Immutability guard rejects metric-type change after first set.
    5. Export round-trips a timed set.
    6. `lastCompletedSession(forRoutineID:)` returns the most recent `COMPLETED` session (matches the schema CHECK literal at `Schema.swift:188-189`), ignores `IN_PROGRESS` / `ABANDONED`.
    7. `lastCompletedSession` returns nil for a brand-new routine.
    8. `LastExecutionSummary` correctly mutes exercises that were in the prior session but no longer in the current routine.
    9. `SnapshotWriter.write()` produces a JSON file at the expected path with `schema_version = "2.0"` and is parseable.
    10. Concurrent calls to `SnapshotWriter.write()` debounce to a single final write.
    11. With "Auto-update LLM snapshot" OFF, session finish does not modify `hybrid-latest.json` mtime.
    
    — *test-coder* — deps: all prior phases.
- [ ] **TV7.2** [S] DB-size sanity rerun: composite index + two new columns + five seed rows must keep the 500-session fixture under 10 MB. Update `Phase7SizeTests` to assert this on the V2 schema. — *test-coder* — deps: TV7.1.
- [ ] **TV7.3** [S] Manual V2 verification pass (15 steps from `PRD-V2.md` §"Verification": 7 timed-hold steps, 3 previous-execution steps, 5 LLM-access steps). — *orchestrator* — deps: TV7.1.
- [ ] **TV7.4** [S] Tag `v0.2` on the merge commit. — *orchestrator* — deps: TV7.3.

---

## Parallelism Matrix

| Phase | Parallel agents in flight |
|-------|---------------------------|
| V0 | orchestrator |
| V1 | db-coder, models-coder, ui-shared-coder (3-way) |
| V2 | repo-coder (single agent, six parallel tasks: TV2.1–TV2.5 + TV2.3a) |
| V3 | export-coder (parallel with V2 — independent) |
| V4 | ui-lift-coder + export-coder |
| V5 | ui-shared-coder → ui-lift-coder → ui-run-coder → (ui-lift-coder ‖ ui-run-coder) |
| V6 | export-coder + repo-coder |
| V7 | test-coder + orchestrator |

Peak concurrency: Phase V4 with 5 simultaneous Coder tasks (TV4.1–TV4.5).
Cross-phase concurrency: Phases V2 and V3 can run fully in parallel (no shared deps).

---

## Dependency DAG (text form)

```
TV0.1 → TV0.2
              ├─ TV1.1 ─┐
              ├─ TV1.2 ─┤
TV0.2 ───────┼─ TV1.3 ─┼─→ TV2.1 ──→ TV4.1
              ├─ TV1.4 ─┤      
              └─ TV1.5 ─┘      
                                  TV2.2, TV2.5 ──→ TV5.1 ──→ TV5.2a ──→ TV5.2b ──→ TV5.3, TV5.4
                                  TV2.3, TV2.3a ──→ TV4.2
                                  TV2.4 ──→ TV4.3, TV4.4
                                  TV1.1 ──→ TV4.5

TV0.2 ─→ TV3.1, TV3.2 ─→ TV3.3
TV3.1, TV2.1 ─→ TV6.1 ─→ TV6.2, TV6.3
TV3.2 ─→ TV6.5
TV1.4 ─→ TV6.4

(all V4–V6 done) → TV7.1 → TV7.2, TV7.3 → TV7.4
```

---

## Orchestrator Workflow

For each phase:

1. Read this file. Identify all tasks where `[ ]` and every `deps:` is `[x]`.
2. Group by parallel-safety. Dispatch `[P]` siblings in a single multi-Agent message.
3. On Coder completion: verify acceptance, mark `[x]`, commit.
4. On Coder failure: re-dispatch the same agent with the failure diagnostics, not a fresh agent (preserves context).
5. At phase gate: dispatch `test-coder`. Block until green.
6. Surface to user: phase summary, next phase plan, any spec ambiguity discovered.

**V2-specific:**
- No screenshot-parity step in any gate. Replace with: SwiftUI preview review + sim run + new XCTest cases + the 15-step manual verification list at TV7.3.
- All commits land on `feature/v2`. Merge to `main` only after TV7.3 passes and TV7.4 tags `v0.2`.
- V1's open items (`T7.2` screenshot pass, `T7.4` tag `v0.1`) are orthogonal to V2 and can be addressed on `main` independently. The orchestrator should not block V2 on them.

---

## Open Specs (must close before the named phase enters)

- **Run-lane LastExecutionCard shape (blocks TV5.2b / TV5.4).** PRD-V2 §"Previous-execution recall" describes the card in terms of "per-exercise top set". Run routines hold `routine_run` entries (run-template references), not exercises. Decide before Phase V5 enters: (a) add a PRD-V2 addendum defining the run-lane card content (distance / duration / pace per `routine_run` slot, removed-run-template muting rules), or (b) scope LastExecutionCard to lift + mixed routines in V2 and defer pure-run lane to V2.1. The orchestrator must record the decision in this section before dispatching TV5.2b.
- **TV7.3 manual verification list (blocks Phase V7 gate).** PLAN-V2 references "15 steps from PRD-V2.md §Verification" (7 timed-hold + 3 previous-execution + 5 LLM-access). PRD-V2 as written ends at the Risks section with no Verification appendix. Before TV7.3 is dispatchable, either add the appendix to PRD-V2 or inline the checklist into TV7.3's task body.
