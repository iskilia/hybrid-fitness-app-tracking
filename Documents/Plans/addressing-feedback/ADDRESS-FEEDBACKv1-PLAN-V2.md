Plan: Address simulator feedback (feedback.md)
  
 Context

 feedback.md captures bugs and product changes found while running the app in the macOS
 simulator, across four areas: session tracking, routines, settings, and a new
 cross-cutting data-size limit. This plan turns that feedback into concrete work and
 routes execution through the repo's four-stage pipeline agents:

 - planner (opus) → writes .pipeline/spec.md
 - coder (sonnet) → implements the spec, writes .pipeline/changes.md
 - tester (sonnet) → writes/runs tests, writes .pipeline/test-results.md
 - reviewer (opus) → git diff + verdict in .pipeline/review.md

 Each numbered Pass below is one full run of that pipeline. The planner reads only the
 spec, so each pass's spec must be self-contained. Run passes in order (1 → 4); Pass 3 is
 independent and may run any time.

 Decisions confirmed with the user

 - Data-limit UX: when an add action would exceed the limit, warn the user that
 historical data will be deleted, with Confirm / Cancel.
   - Cancel → do nothing, return to Home screen.
   - Confirm → perform the insert, then prune oldest → newest (sessions / exercise
 history first) until under the limit; reclaim space (VACUUM).
   - If it's impossible to fit even after pruning all evictable history → revert the
 insert and tell the user immediately the action is impossible so they can edit.
 - Bodyweight: remove all entry points and drop the DB columns.
 - "Run": add as a DISTANCE-metric exercise in the exercise library.

 ---
 Pass 1 — Settings overhaul + schema migration

 Goal: Strip clutter from Settings, remove bodyweight everywhere (incl. DB), add the
 data-limit setting, and remove the export/LLM-snapshot subsystem.

 Schema — rewrite, and rip out all migration code (Sources/Persistence/Schema/Schema.swift,
 Sources/Persistence/Migrations/Migrator.swift): the app is unreleased (no users), so
 collapse to a single canonical schema with no incremental-migration machinery:
 - Fold the final DDL into applySchema in Schema.swift: merge what V2 added
 (routine_exercise.target_duration_secs_min/_max columns + idx_session_routine_finished)
 and what V3 added (the routine_exercise_set table + idx_res_routine_exercise index)
 directly into the canonical CREATE TABLE/CREATE INDEX statements.
 - Remove the body_weight_kg column from the session and user_profile table defs.
 - Add max_data_mb INTEGER NOT NULL DEFAULT 10 to the user_profile table def.
 - Delete the migration scaffolding in Migrator.swift: the migrations array and
 version-stepping loop, applyV2, applyV3, backfillV3Sets, and the schema_meta
 version read/write helpers (and the schema_meta table itself if nothing else uses it).
 Reduce migrate(_:) to a single idempotent applySchema(db) (CREATE ... IF NOT EXISTS).
 - There is no upgrade path for stale local DBs — wipe the simulator's Hybrid.sqlite
 (delete the app from the simulator) so the schema is created fresh. Note in
 .pipeline/changes.md. Reviewer confirms no dangling refs to the removed symbols.

 Bodyweight removal (refs found in):
 - Models: Sources/Domain/Models/Session.swift (bodyWeightKg),
 Sources/Domain/Models/UserProfile.swift (bodyWeightKg).
 - Repos: SessionRepository.swift (insert/select column lists, Session(...) init),
 UserProfileRepository.swift (get()/upsert() signature — drop bodyWeightKg:).
 - Settings UI/VM: remove bodyweightSection (SettingsView.swift:77-96) and
 bodyWeightInput (SettingsViewModel.swift:10,33,43-47).
 - Sources/Export/* is being removed in this pass (below), so its bodyweight refs go too.

 Remove export + LLM-snapshot subsystem (explicit feedback: "remove the export
 functionality and refreshing the LLM Snapshot"):
 - Delete exportSection + llmSnapshotSection + the Files/LLM privacy footer note in
 SettingsView.swift (lines 98-183, 194-198); delete ShareSheet usage,
 shareURL/showShare/snapshotAutoEnabled/refreshState state.
 - Delete exportCSV()/exportJSON()/isExporting in SettingsViewModel.swift.
 - Remove Sources/Export/ entirely (CSVExporter, JSONExporter, SnapshotHook,
 SnapshotWriter, SchemaDoc) and every SnapshotHook.notifyChange() / forceWrite()
 call site in the repositories (Session/Routine/Exercise repos).
 - Remove configureSnapshotHook() + schema-doc write from HybridApp.swift:17,21-45.
 - planner should confirm no other live references remain; reviewer verifies orphan-free.

 Add "DATA LIMIT" Settings section (new section in SettingsView.swift, mirror the
 unitsSection card style):
 - A dropdown Picker (menu style) bound to viewModel.maxDataMb, with options in
 10 MB increments from 10 to 200 (stride(from: 10, through: 200, by: 10)), default
 10. No free-text entry — this removes the need for digit validation/clamping entirely.
 - Persist via UserProfileRepository (new maxDataMb field) on .onChange, reusing the
 existing .onChange → viewModel.save() pattern. Lowering the value also triggers the
 Pass 2 eviction flow (see Pass 2).
 - SettingsViewModel: add var maxDataMb: Int = 10, load it in load(), write it in
 save(); extend UserProfileRepository.upsert(...) and get() to carry it.

 Verify: build; open Settings — only Units + Data Limit remain; the limit is a 10–200 MB
 (step 10) dropdown defaulting to 10 and persists across app relaunch; grep -ri bodyweight Sources/
 returns nothing; Sources/Export/ is gone; Migrator.swift has no applyV2/applyV3/
 backfill/migrations array and the project still compiles and creates the DB fresh.

 ---
 Pass 2 — Storage-limit enforcement engine

 Goal: Enforce max_data_mb on every add action with the confirm-then-evict UX.

 Pre-calculate via a rolled-back transaction probe (chosen over commit-then-measure):
 validate the insert before persisting it, so the DB is never transiently over-limit.

 New service Sources/Persistence/StorageGuard.swift (struct taking DatabaseManager):
 - logicalSizeBytes(db) → (page_count − freelist_count) × page_size. Use
 page_count − freelist_count (not raw page_count) so freed pages don't inflate the
 measurement — this equals the post-VACUUM size. Read via PRAGMA statements.
 - limitBytes(profile) → maxDataMb * 1024 * 1024.
 - probe(insert:) -> ProbeResult → in one transaction: run the insert closure, read
 logicalSizeBytes, then ROLLBACK unconditionally. Returns .fits /
 .needsEviction(overBy:) without persisting anything. (Do not hold this transaction
 open across the user's Confirm dialog — probe and roll back first, then prompt.)
 - commitWithEviction(insert:) -> Outcome → on Confirm, in a real transaction: run the
 insert, then delete oldest sessions + child rows (session_set, session_run,
 session_run_split) oldest→newest until logicalSizeBytes ≤ limit, then COMMIT.
 Returns .fitted or .impossible (nothing left to evict but still over → ROLLBACK).
 Run VACUUM after commit (VACUUM cannot run inside a transaction) to shrink the file.

 Why probe-then-commit, not commit-then-measure: the probe is exact (real SQLite B-tree
 accounting, not a byte estimate) and atomic — an invalid insert is never persisted, so there
 is no transient over-limit window and no separate destructive cleanup pass. Caveat captured
 above: measure page_count − freelist_count and VACUUM only outside the transaction.

 There are two trigger shapes — the data is sometimes inserted atomically (probe applies)
 and sometimes already persisted by the time we check (reconcile applies):

 (A) Pre-insert probe — atomic single inserts: create routine, create custom exercise.
 1. Before the add, run probe(insert:).
 2. .fits → just do the insert.
 3. .needsEviction → confirmationDialog: "This will delete your oldest history. Continue?"
   - Cancel → do nothing, router.popToRoot() / return Home.
   - Confirm → commitWithEviction(insert:); on .impossible alert "Not enough space
 — edit your data first." (nothing was persisted).
 - Wire into: RoutineRepository.create(...) (the new builder from Pass 4 — sequence Pass 2
 before Pass 4) and ExerciseRepository.create(...) (CustomExerciseEditorView).

 (B) Post-hoc reconcile — data already in the DB: session finish, and limit decrease.
 A session's session_set/session_run rows are inserted live during the active session,
 so there is nothing to probe at finish — the data already exists. Reconcile instead:
 - reconcile(toLimit:) -> Outcome → if logicalSizeBytes ≤ limit, no-op; else delete oldest
 sessions + child rows oldest→newest until under (the just-finished session is newest, so
 it's preserved naturally), then VACUUM. .impossible only if a single un-evictable item
 still exceeds the limit.
 - Session finish — trigger on SessionRepository.finish(...), not start(...). In
 LiftActiveSessionViewModel.finish (and the Run equivalent): after finishing, if over limit
 → warn "Your storage limit is full. Finishing will delete your oldest history. Continue?"
   - Cancel → return to Home; the finished session stays but no eviction runs (it remains
 over limit until the next reconcile/decrease). (Confirm with planner: acceptable, or
 should Cancel instead leave the session IN_PROGRESS? Default: just return Home.)
   - Confirm → reconcile(toLimit:).
 - Limit decrease in Settings — on the Data Limit Picker change in SettingsView/VM:
   - Increase (new ≥ old) → save the new value, no warning, no eviction.
   - Decrease (new < old) → if current size already fits, save silently; else warn
 ("Lowering the limit will delete your oldest history. Continue?"):
       - Cancel → revert the picker to the previous value, persist nothing.
     - Confirm → save the new limit, then reconcile(toLimit:) — clearing the entire
 history if required to meet the limit.

 Verify: set limit to 1 MB with seeded data present; attempt each add → dialog appears;
 Cancel returns Home with nothing written and the DB byte-identical (probe rolled back);
 Confirm writes then evicts oldest sessions and logical size drops below limit; force
 impossible case (limit smaller than non-evictable data) → nothing persisted + alert. Tester
 writes unit tests for probe (.fits/.needsEviction) and commitWithEviction
 (.fitted/.impossible), asserting the probe leaves the DB unchanged.

 Pass 2 — post-review hardening (PR #4 feedback)

 Two follow-ups raised on PR #4 after the engine shipped to a branch:

 1. Surface reconcile failures instead of swallowing them. Today the session-finish and
 limit-decrease confirm paths do _ = try? await storageGuard.reconcile(...) and then
 popToRoot() / dismiss unconditionally — so if reconcile throws, the user is told
 nothing, lands Home, and the DB is silently still over limit. (The create-exercise path
 already handles this correctly via confirmEviction → errorMessage / .impossible
 alert; we're making the other two consistent.) Note both session VMs already declare
 errorMessage but no view ever presents it — that gap is fixed here too.
   - LiftActiveSessionViewModel.confirmStorageEviction() /
 RunActiveSessionViewModel.confirmStorageEviction() → return Bool
 (do { _ = try await reconcile } catch { errorMessage = "Couldn't free space: …"; return false }).
   - LiftActiveSessionView / RunActiveSessionView → Continue button pops only on
 true; add an error .alert bound to errorMessage (a String?→Bool binding) so
 a failure is shown and the user stays put.
   - SettingsViewModel.confirmLimitDecrease() → wrap reconcile in do/catch, store the
 message; SettingsView → add a matching error .alert. (The lowered limit is already
 persisted at this point; the alert tells the user cleanup failed so the DB may still be
 over limit.)
   - Concurrency (other PR comment): no code change. DatabaseManager is an actor on a
 single SQLITE_OPEN_FULLMUTEX handle, so every DB op is serialized — no races, no nested
 transactions. StorageGuard chains separate actor calls (check-then-act), but each step
 re-measures logical size inside its own transaction, so an interleaved write only makes a
 probe hint stale, never corrupts. Documented in the PR reply; nothing to fix.
 2. Keep the temp DEBUG test harness until Pass 4, then remove it. The #if DEBUG
 seed-buttons / small-limit-options / live-readout in SettingsView.swift +
 SettingsViewModel.swift (all tagged // TEMP PASS-2 TESTING) stay in so Pass 2 stays
 hand-testable through Pass 3/4. Add a // TODO(pass-4): remove … next to each tag now;
 Pass 4 deletes the harness (see Pass 4 checklist) — verify with
 grep -rn "TEMP PASS-2 TESTING" Sources/ returning nothing.

 Verify (hardening): force reconcile to throw (e.g. temporarily) → finishing an
 over-limit session / lowering the limit shows an error alert and does not pop as if it
 succeeded; the happy path is unchanged. Existing 81 tests stay green.

 ---
 Pass 3 — Session-tracking fixes

 Goal: Fix the two session bugs. Use systematic-debugging for bug #1.

 Bug #2 — abandoned sessions counted (confirmed root cause):
 - SessionRepository.weekStats() COUNT query (SessionRepository.swift:165-169) filters
 only deleted_at IS NULL + date window. Add AND status = 'COMPLETED' so abandoned
 and in-progress sessions don't count toward the Home "WEEK · sessions" chip.

 Bug #1 — sessions vanish after opening/closing Settings (root cause NOT yet pinned;
 static reading ruled out the obvious culprits — Settings performs no destructive DB writes,
 seeding is seedIfEmpty-guarded, and weekStats/bindDate use matching epoch-seconds, so
 the count reads consistently across loads):
 - Tester writes a failing reproduction first: start → finish a session → load Home
 (assert WEEK count = 1) → navigate to Settings and back → reload Home (assert count
 still 1). Drive HomeViewModel.load() directly against a real DatabaseManager.
 - Leads to investigate: HomeView's .task reload lifecycle on NavigationStack
 pop; HomeViewModel.load()'s silent catch that "leaves previous state on error"
 (a throw on the second load would freeze stale/zeroed state); week-window boundary
 (Calendar.current.firstWeekday) vs started_at.
 - Fix the reproduced cause; keep the regression test green.
 - If it cannot be reproduced or root-caused without running the live app (e.g. it only
 manifests through real SwiftUI navigation lifecycle that the test harness can't drive):
 stop the pipeline and hand off to the user. Write .pipeline/debug-bug1.md with:
 exact repro steps in the simulator (debug build), suggested breakpoints —
 HomeViewModel.load() entry + its catch (capture the thrown error), weekStats()
 return value, Calendar weekStart/firstWeekday — and what to record at each
 (count value, error, epoch bounds). Do not guess a fix.

 Verify: new tests pass; manually in simulator, the WEEK count survives a Settings
 round-trip and abandoned sessions never increment it. (If handed off, verification is the
 user's debug-session findings feeding a follow-up pipeline run.)

 ---
 Pass 4 — Routine creation flow + "Run" library exercise

 Goal: Make routine creation actually work, and add "Run".

 Root cause of routines #1 & #2 (one shared gap): the "+" in RoutinesView.swift:59
 pushes .routineDetail(UUID(), .lift) with a random UUID that is never persisted.
 LiftRoutineDetailView is the execute screen — its add-exercise sheet is a TODO no-op
 (LiftRoutineDetailView.swift:39) and its bottom button is START (starts a session on
 the nonexistent routine), not CREATE.

 Routine creation:
 - Introduce a create/builder mode (either a RoutineBuilderView or a mode: parameter on
 LiftRoutineDetailView). In create mode:
   - Wire ExerciseLibraryView(onSelect:) (currently { _ in }) to append the chosen
 exercise to an in-memory entries list that renders on screen in
 exerciseListSection.
   - Replace the bottom START button with CREATE: persist via
 RoutineRepository.create(routine:exerciseEntries:runEntries:) (already enforces the
 10-routine cap), then router.pop() back to the routines list (which reloads via its
 .task).
 - Existing routines keep the START (execute) button. Update RoutinesView "+" to open
 create mode instead of a throwaway detail.
 - This add path must call the Pass 2 StorageGuard before create(...).

 "Run" default exercise:
 - Add a Run exercise (metricType: "DISTANCE") to Sources/Persistence/Seed/SeedData.swift
 (currently 0 DISTANCE exercises). It then appears in ExerciseLibraryView.
 - Distance logging gap: confirm LiftActiveSessionView/-ViewModel and
 SessionSetRepository render and store a distance set for a DISTANCE exercise; if the
 set editor only handles reps/weight/time, add the distance input path so a logged "Run"
 is recordable. (Optionally surface Distance in the CustomExerciseEditorView metric
 picker, which today offers only Reps/Reps+Weight/Time — only if low-cost.)

 Remove the temp Pass-2 DEBUG harness (deferred from Pass 2 so the engine stayed
 hand-testable through Pass 3/4): delete every // TEMP PASS-2 TESTING block in
 SettingsView.swift (the debugSection, the [1, 2, 5] + … branch of limitOptions) and
 SettingsViewModel.swift (debugBusy/debugLogicalMB/debugRefreshLogical/debugSeed and
 the #if DEBUG call inside refreshFooter). The data-limit picker returns to its 10–200 MB
 (step 10) production range. Verify grep -rn "TEMP PASS-2 TESTING" Sources/ returns nothing.

 Verify: simulator — tap "+", add several exercises (they appear in the list), tap
 CREATE → returns to routines list showing the new routine with correct exercise count;
 START on it begins a session containing those exercises; "Run" is visible in the library

     Verify: simulator — tap "+", add several exercises (they appear in the list), tap
     CREATE → returns to routines list showing the new routine with correct exercise count;
     START on it begins a session containing those exercises; "Run" is visible in the library
     and a run set can be logged; the DEBUG storage section is gone from Settings.

     ---
     What "a pass" is, and how to run one

     A pass is one end-to-end trip through the four repo agents in .claude/agents/, scoped to
     one chunk of this plan. The agents hand work to each other through files in a .pipeline/
     folder at the repo root:

     planner  → writes .pipeline/spec.md        (files to touch, signatures, edge cases)
     coder    → FIRST creates a git branch off main, then implements,
                writes .pipeline/changes.md      (what changed, what to test)
     tester   → reads changes, writes+runs tests on that branch,
                writes .pipeline/test-results.md (pass/fail)
     reviewer → reads all + `git diff` on the branch,
                writes .pipeline/review.md        (SHIP / NEEDS WORK / BLOCK)

     One branch per pass. Before touching any code, the coder creates and checks out a fresh
     branch off main, named per pass: feature/pass-1-settings, feature/pass-2-storage-limit,
     feature/pass-3-session-tracking, feature/pass-4-routines-run. All of that pass's work,
     tests, and review happen on its branch; it merges to main only after a SHIP verdict and your
     sign-off. (The coder creates the branch but does not commit/push unless you ask.)

     How you (the user) run a pass: after this plan is approved, just tell me e.g.
     "execute Pass 1" (or "proceed to Pass 2"). I then drive the agents for you — I invoke the
     planner subagent with that pass's scope from this plan, wait for .pipeline/spec.md, then
     invoke coder, then tester, then reviewer, reading each .pipeline/*.md between stages
     and stopping to surface any OPEN QUESTIONS, test failures, or a NEEDS WORK / BLOCK verdict
     before continuing. You don't invoke the agents yourself — you approve the plan and tell me
     which pass to run; I orchestrate the four stages and report back at the gates. We do one pass
     at a time so you can review .pipeline/review.md before moving on.

     (Mechanically, these run via the Agent tool with subagent_type: planner | coder | tester | reviewer — the same agent names defined in .claude/agents/.)

     Pipeline execution notes

     - Do not skip to coding — the planner gates ambiguity via OPEN QUESTIONS.
     - Respect ordering: 1 → 2 → 4 (Pass 4's add paths depend on Pass 2's StorageGuard;
     everything depends on Pass 1's migration/limit field). Pass 3 is independent.
     - Keep changes surgical per the repo's CLAUDE.md: match existing repo/SQLite-helper
     patterns (prepare/step/bindDate/bindInt), @Observable + @MainActor VMs,
     NavigationStack routing via Router.
     - Final gate: each pass ends with the reviewer verdict (SHIP / NEEDS WORK / BLOCK) in
     .pipeline/review.md before human sign-off.
     1. Pass 1 settings+migration → verify: Settings clean, no bodyweight, limit persists
     2. Pass 2 storage engine     → verify: confirm/evict/impossible all behave
     3. Pass 3 session bugs       → verify: count survives Settings + abandoned excluded
     4. Pass 4 routines + Run     → verify: CREATE persists routine, Run loggable