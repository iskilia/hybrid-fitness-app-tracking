# Implementation Plan — Hybrid V0.1

iOS 17 · Swift 6 · SwiftUI · MVVM (`@Observable`) · SQLite · SPM

Source of truth: `PRD.md`, `SCHEMA.md`, `screenshots/`.

---

## Agent Roster

Create the following agents in `.claude/agents/` (or via `/agents`). Each is single-responsibility. The Orchestrator is the only agent the user talks to directly; it dispatches Coders.

### 1. `orchestrator` (1 instance)

**Role.** Plan owner. Reads `PLAN.md`, dispatches Coders, gates phase transitions, runs verification, updates task status in this file. Never writes feature code itself.

**Responsibilities:**
- Maintain task state in `## Task Board` below (mark `[ ]` → `[~]` → `[x]`).
- Enforce dependency order — never dispatch a task whose deps aren't `[x]`.
- Fan out parallel tasks via simultaneous Coder dispatches.
- Run `xcodebuild` / `swift test` after each phase.
- Block on any failed acceptance criterion. Re-dispatch with diagnostics.
- Coordinate merges between Coder branches/worktrees.
- Surface ambiguities back to user; never invent product behavior.

**Tools.** All. Skill: `superpowers:executing-plans`, `superpowers:dispatching-parallel-agents`, `superpowers:verification-before-completion`.

---

### 2. `db-coder` (1 instance)

**Role.** SQLite schema, migrations, seed data, raw DB connection.

**Owns:** `Sources/Persistence/Schema/*`, `Sources/Persistence/Migrations/*`, `Sources/Persistence/Seed/*`.

**Tools.** Read, Write, Edit, Bash. No UI files.

---

### 3. `repo-coder` (1 instance)

**Role.** Repository / DAO layer over raw SQLite. Typed queries, transactions, mapping rows ↔ Swift structs.

**Owns:** `Sources/Persistence/Repositories/*`. Depends on db-coder output.

**Tools.** Read, Write, Edit, Bash.

---

### 4. `models-coder` (1 instance)

**Role.** Swift value types and `@Observable` view-models. Pure domain — no UI, no SQL.

**Owns:** `Sources/Domain/Models/*`, `Sources/Domain/ViewModels/*`.

---

### 5. `ui-shared-coder` (1 instance)

**Role.** Cross-cutting UI: navigation router, design tokens (colors, fonts, spacing), reusable components (`BadgeView`, `ExerciseRow`, `RunRow`, `MetricChip`), home dashboard, routines list.

**Owns:** `Sources/UI/Shared/*`, `Sources/UI/Navigation/*`, `Sources/UI/Home/*`, `Sources/UI/Routines/*`.

---

### 6. `ui-lift-coder` (1 instance)

**Role.** Lift-specific screens: lift routine detail, lift session active, exercise picker, exercise history view, custom-exercise editor.

**Owns:** `Sources/UI/Lift/*`.

---

### 7. `ui-run-coder` (1 instance)

**Role.** Run-specific screens: run routine detail, run session active, run-template picker, custom-run-template editor, interval block editor.

**Owns:** `Sources/UI/Run/*`.

---

### 8. `export-coder` (1 instance)

**Role.** CSV + JSON export. Settings screen footer ("412 SESSIONS · 8.4 MB · EXPORT").

**Owns:** `Sources/Export/*`, `Sources/UI/Settings/*`.

---

### 9. `test-coder` (1 instance)

**Role.** XCTest unit + integration tests. Runs after each phase. Reports pass/fail to orchestrator.

**Owns:** `Tests/*`. Read access everywhere.

---

## Dispatch Legend

- **`[P]`** — Parallel-safe within its phase. Orchestrator dispatches simultaneously with siblings.
- **`[S]`** — Sequential / blocking. Must complete before next item in same phase starts.
- **`deps:`** — Task IDs that must be `[x]` before this task is dispatchable.

---

## Task Board

### Phase 0 — Bootstrap (orchestrator runs solo)

- [x] **T0.1** [S] Create Xcode project `Hybrid` (iOS 17 minimum, SwiftUI lifecycle, Swift 6 strict concurrency). Folder layout: `Sources/{Persistence,Domain,UI,Export}/`, `Tests/`. Add SQLite as `import SQLite3`. — *orchestrator*
- [x] **T0.2** [S] Commit baseline. Tag `v0.0-bootstrap`. — *orchestrator*

**Gate:** project builds. `xcodebuild build` exits 0.

---

### Phase 1 — Foundation (parallel fan-out)

All Phase 1 tasks dispatchable simultaneously after T0.2.

- [x] **T1.1** [P] DDL implementation. Translate `SCHEMA.md` DDL block into `Sources/Persistence/Schema/Schema.swift`. Function `applySchema(_ db: OpaquePointer)` runs `CREATE TABLE`/`CREATE INDEX` statements idempotently. Enable `PRAGMA foreign_keys = ON`, `PRAGMA journal_mode = WAL`. — *db-coder* — deps: T0.2
- [x] **T1.2** [P] Migration runner. `Sources/Persistence/Migrations/Migrator.swift` reads `schema_meta.version`, applies migrations in order. V1 baseline = version 1. — *db-coder* — deps: T0.2
- [x] **T1.3** [P] Seed data. `Sources/Persistence/Seed/SeedData.swift` populates `equipment`, `muscle`, `tag` lookups + ~30 base exercises (Bench Press, Back Squat, Deadlift, OHP, Bent-over Row, Pull-up, RDL, Incline DB Press, …) + ~6 base run templates (Easy Run, Tempo Run, Long Run, 5×800m, Fartlek 30, Recovery). Reference screenshots 5–6 for canonical names + abbreviations. — *db-coder* — deps: T0.2
- [x] **T1.4** [P] Domain model structs. Swift `struct` per table in `SCHEMA.md`. `Codable` conformance. UUID generation helper. — *models-coder* — deps: T0.2
- [x] **T1.5** [P] Design-token module: `Sources/UI/Shared/DesignSystem/{Colors,Typography,Spacing}.swift`. Match screenshot palette (cream background, accent orange `START`, charcoal text, badge oranges). — *ui-shared-coder* — deps: T0.2

**Gate:** unit test creates in-memory DB, applies schema, inserts seed, queries each table successfully. — *test-coder*

---

### Phase 2 — Persistence layer

All Phase 2 tasks dispatchable after Phase 1 gate passes.

- [x] **T2.1** [P] `DatabaseManager` actor wrapping `OpaquePointer`. Connection lifecycle, transaction helper. — *repo-coder* — deps: T1.1, T1.4
- [x] **T2.2** [P] `RoutineRepository` — CRUD + 10-routine cap enforcement. — *repo-coder* — deps: T2.1
- [x] **T2.3** [P] `ExerciseRepository` — base + custom list, by-id, search by name. Joins `exercise_muscle`+`muscle`+`equipment`. — *repo-coder* — deps: T2.1
- [x] **T2.4** [P] `RunTemplateRepository` — base + custom list, intervals join. — *repo-coder* — deps: T2.1
- [x] **T2.5** [P] `SessionRepository` — start session, finish session, abandon, list by date range, week stats (count + tonnage + km). — *repo-coder* — deps: T2.1
- [x] **T2.6** [P] `SessionSetRepository` — append set, update set, delete, history-by-exercise (last 12 months), top-set-per-session (last 12). — *repo-coder* — deps: T2.1
- [x] **T2.7** [P] `SessionRunRepository` — append run, finish run, splits CRUD. — *repo-coder* — deps: T2.1

**Gate:** integration tests cover repo round-trip for each entity. CASCADE deletes verified. — *test-coder*

---

### Phase 3 — Navigation + Home

Sequential to Phase 2.

- [x] **T3.1** [S] `Router` `@Observable` with type-safe `Route` enum (`.home, .routines, .routineDetail(id), .session(id), .exerciseLibrary, .runTypes, .exerciseHistory(id), .settings`). `NavigationStack(path:)` wired in `RootView`. — *ui-shared-coder* — deps: T2.1
- [x] **T3.2** [P] Home screen (`screenshots/01-hybrid.png`). Greeting, week metrics (sessions / volume / distance), routine cards with `START`. — *ui-shared-coder* — deps: T3.1, T2.5, T2.2
- [x] **T3.3** [P] Routines screen (`screenshots/02-hybrid.png`). List, badge, last-performed, exercise/run count, `+` to create, `4 ACTIVE · MAX 10` counter. — *ui-shared-coder* — deps: T3.1, T2.2

**Gate:** SwiftUI preview renders Home + Routines with seeded data. **Screenshot parity:** side-by-side compare against `screenshots/01-hybrid.png` (Home) and `screenshots/02-hybrid.png` (Routines). Layout, copy, badge colors, counters must match. Diff noted in PR; orchestrator blocks on mismatch.

---

### Phase 4 — Routine detail + builders (parallel: lift / run lanes)

Two independent lanes after Phase 3 gate.

#### Lift lane

- [x] **T4.L1** [P] Lift routine detail (`screenshots/03-hybrid.png`). Shows exercise rows with last-session weight × routine rep range. — *ui-lift-coder* — deps: T3.1, T2.2, T2.3, T2.6
- [x] **T4.L2** [P] Exercise library picker (`screenshots/05-hybrid.png`). Search, equipment filter, muscle chips. — *ui-lift-coder* — deps: T3.1, T2.3
- [x] **T4.L3** [P] Custom exercise editor. Name, abbrev, equipment, muscles, notes, form_link, `metric_type`. — *ui-lift-coder* — deps: T2.3

#### Run lane

- [x] **T4.R1** [P] Run routine detail (`screenshots/04-hybrid.png`). Run rows with type, distance, pace, BPM range, interval description (composed from `run_interval_block`). — *ui-run-coder* — deps: T3.1, T2.2, T2.4
- [x] **T4.R2** [P] Run-types picker (`screenshots/06-hybrid.png`). Search, type filter. — *ui-run-coder* — deps: T3.1, T2.4
- [x] **T4.R3** [P] Custom run-template editor + interval block editor. — *ui-run-coder* — deps: T2.4

**Gate:** preview renders both detail screens. Picker insert flow round-trips through repo. **Screenshot parity:** compare against `screenshots/03-hybrid.png` (lift detail), `screenshots/04-hybrid.png` (run detail), `screenshots/05-hybrid.png` (exercise picker), `screenshots/06-hybrid.png` (run-types picker). Verify row composition, filter chips, search bar, abbreviations.

---

### Phase 5 — Active sessions (parallel lanes)

#### Lift lane

- [ ] **T5.L1** [P] Active lift session view. Per-exercise card, set rows (W / 1 / 2 / 3 …), weight + reps + RPE input, "previous" hint from last session. Auto-creates `session` row on entry, persists each set on commit. Pause / finish / abandon. — *ui-lift-coder* — deps: T4.L1, T2.5, T2.6
- [ ] **T5.L2** [P] Exercise history screen (`screenshots/09-hybrid.png`). Top-set chart (last 12 sessions), session list. — *ui-lift-coder* — deps: T2.6

#### Run lane

- [ ] **T5.R1** [P] Active run session view (`screenshots/08-hybrid.png`). Timer, distance, pace, HR vs target. Manual entry path (V1) + structured slot for V2 wearable feed. — *ui-run-coder* — deps: T4.R1, T2.5, T2.7
- [ ] **T5.R2** [P] Post-run summary + persist `session_run` (+ optional `session_run_split` rows). — *ui-run-coder* — deps: T5.R1

**Gate:** end-to-end test: create routine → start → log sets/run → finish → appears in history with correct aggregates. **Screenshot parity:** compare active lift session, `screenshots/08-hybrid.png` (active run), `screenshots/09-hybrid.png` (exercise history). Verify timer layout, set-row format (W / 1 / 2 / 3), HR-vs-target chip, top-set chart axes.

---

### Phase 6 — Export + Settings

- [ ] **T6.1** [P] CSV exporter. One file per table OR a flat denormalized session-set CSV. Decision recorded in code comment + this PLAN. — *export-coder* — deps: Phase 5 gate
- [ ] **T6.2** [P] JSON exporter. Mirrors `SCHEMA.md` table structure. — *export-coder* — deps: Phase 5 gate
- [ ] **T6.3** [P] Settings screen (`screenshots/10-hybrid.png`). DB size readout, session count, `EXPORT` buttons, units toggle (kg/lb, km/mi), bodyweight input. — *export-coder* — deps: T6.1, T6.2, T2.5

**Gate:** export round-trip — exported JSON re-imports into a fresh DB and produces byte-identical re-export. **Screenshot parity:** compare Settings against `screenshots/10-hybrid.png`. Verify footer format (`412 SESSIONS · 8.4 MB · EXPORT`), units toggle, bodyweight input.

---

### Phase 7 — Polish + Verification

- [ ] **T7.1** [S] Full XCTest suite green. — *test-coder* — deps: all prior
- [ ] **T7.2** [S] Screenshot verification pass. For every file in `screenshots/*.png`: launch sim at iPhone 15 Pro, navigate to matching screen with seeded data, capture sim screenshot, side-by-side diff against reference. Checklist below; each item must be `[x]` before T7.4. Mismatches re-dispatched to owning UI coder. — *orchestrator* — deps: T7.1
- [ ] **T7.3** [S] DB size sanity: seed 500 fake sessions, confirm < 10 MB. — *test-coder*
- [ ] **T7.4** [S] Tag `v0.1`. — *orchestrator* — deps: T7.2, T7.3

#### Screenshot verification checklist (T7.2)

For each row: capture sim screenshot, attach to PR, mark `[x]` when parity confirmed.

- [ ] `01-hybrid.png` — Home (greeting, week metrics, routine cards, START button) — *ui-shared-coder*
- [ ] `02-hybrid.png` — Routines list (badge, last-performed, counts, `4 ACTIVE · MAX 10`) — *ui-shared-coder*
- [ ] `03-hybrid.png` — Lift routine detail (last-session weight × rep range) — *ui-lift-coder*
- [ ] `04-hybrid.png` — Run routine detail (type, distance, pace, BPM, interval desc) — *ui-run-coder*
- [ ] `05-hybrid.png` — Exercise library picker (search, equipment filter, muscle chips) — *ui-lift-coder*
- [ ] `06-hybrid.png` — Run-types picker (search, type filter) — *ui-run-coder*
- [ ] `07-hybrid.png` — assign to owning lane on first read — *orchestrator*
- [ ] `08-hybrid.png` — Active run session (timer, distance, pace, HR vs target) — *ui-run-coder*
- [ ] `09-hybrid.png` — Exercise history (top-set chart, session list) — *ui-lift-coder*
- [ ] `10-hybrid.png` — Settings (DB size readout, EXPORT, units toggle, bodyweight) — *export-coder*

Verification rubric per screen: layout structure, color palette, typography weights/sizes, copy strings exact, iconography, badge/chip colors, numeric format (e.g. `8.4 MB`, `4 ACTIVE · MAX 10`). Pixel-perfect not required; semantic + visual parity is.

---

## Parallelism Matrix

| Phase | Parallel agents in flight |
|-------|---------------------------|
| 0 | orchestrator |
| 1 | db-coder, models-coder, ui-shared-coder (3-way) |
| 2 | repo-coder (single agent, multiple parallel tasks) |
| 3 | ui-shared-coder (T3.2, T3.3 parallel after T3.1) |
| 4 | ui-lift-coder + ui-run-coder (independent lanes, 6 tasks parallel) |
| 5 | ui-lift-coder + ui-run-coder (independent lanes, 4 tasks parallel) |
| 6 | export-coder |
| 7 | test-coder + orchestrator |

Peak concurrency: Phase 4 with 6 simultaneous Coder tasks.

---

## Dependency DAG (text form)

```
T0.1 → T0.2
              ├─ T1.1 ─┐
              ├─ T1.2 ─┤
T0.2 ────────┼─ T1.3 ─┼──→ T2.1 ─┬─ T2.2 ─┐
              ├─ T1.4 ─┤          ├─ T2.3 ─┤
              └─ T1.5 ─┘          ├─ T2.4 ─┼──→ T3.1 ─┬─ T3.2
                                  ├─ T2.5 ─┤          └─ T3.3
                                  ├─ T2.6 ─┤
                                  └─ T2.7 ─┘
                                                         │
                          ┌──────────────────────────────┤
                          ↓                              ↓
                   (Lift lane)                     (Run lane)
                  T4.L1 → T5.L1                  T4.R1 → T5.R1 → T5.R2
                  T4.L2                          T4.R2
                  T4.L3                          T4.R3
                  T5.L2 (parallel to T5.L1)
                          │                              │
                          └──────────┬───────────────────┘
                                     ↓
                              T6.1, T6.2 → T6.3
                                     ↓
                          T7.1 → T7.2 → T7.3 → T7.4
```

---

## Orchestrator Workflow

For each phase:

1. Read this file. Identify all tasks where `[ ]` and every `deps:` is `[x]`.
2. Group by parallel-safety. Dispatch `[P]` siblings in a single multi-Agent message.
3. On Coder completion: verify acceptance, mark `[x]`, commit.
4. On Coder failure: re-dispatch the same agent with the failure diagnostics, NOT a fresh agent (preserves context).
5. At phase gate: dispatch `test-coder`. Block until green.
6. Surface to user: phase summary, next phase plan, any spec ambiguity discovered.
