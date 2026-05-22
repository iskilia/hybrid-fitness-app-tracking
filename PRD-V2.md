Below is the **V2 PRD-style outline**, layered on top of V1 (`PRD.md`). V2 adds three things: timed-hold exercises, a pre-session "last execution" recall card, and an LLM-readable data-access surface. The privacy-first, offline-first, local-SQLite stance from V1 is retained.

## Product framing

V2 remains a privacy-first hybrid training log for athletes who run and lift in the same week. The core promise is unchanged: clean, structured, on-device training history that makes interference easier to reason about later. **[V2]** V2 expands "lifting" to cover the full strength-work surface area an athlete actually uses — including isometric holds — so that wall sits, planks, and dead hangs sit in the same timeline as squats and tempo runs. **[V2]** V2 also acknowledges that athletes increasingly route their own data through LLM agents for analysis and plan generation, and treats that as a first-class outbound use case rather than a workaround.

## Problem statement

Current apps fragment the training picture by modality, and within the lifting modality they fragment further by exercise type. Strength apps log reps × load well, but treat timed isometrics as a second-class citizen — users resort to entering "45" in a reps field, breaking analytics. They also rarely surface "what did I hit last time on this exact routine" at the moment the athlete is about to start, even though that is the highest-value information a logger can render. Finally, even apps that nominally export data do so to ephemeral or proprietary locations, making it hostile to LLM consumption. **[V2]** V2 solves all three: every set is logged in its native unit (reps, load, or seconds); the routine detail screen shows the last execution before the athlete taps Start; and the full DB is auto-mirrored as a documented JSON file at a stable, user-visible filesystem path.

## Target user

Unchanged from V1. Primary user is a self-directed hybrid athlete. **[V2]** Secondary user expansion:
- Athletes coming back from injury whose programs lean heavily on isometric tolerance work (Achilles, patellar tendon rehab) — a population the V1 reps-only model excludes.
- Athletes who use LLM agents (Claude, ChatGPT, custom MCP setups) to analyse their training and want a clean, stable on-device data source they can point those tools at.

## V2 scope

### In scope
- Everything in V1.
- **[V2]** Timed-hold exercises: any exercise whose metric type is `TIME` is treated as a hold. Sets are logged with duration in seconds instead of reps.
- **[V2]** Routine planner supports a target duration per set for timed exercises (`target_duration_secs_min` / `target_duration_secs_max` on `routine_exercise`).
- **[V2]** Base exercise library seeds five timed holds: wall sit, plank, side plank (L/R as one exercise with notes), dead hang, L-sit.
- **[V2]** 12-month history view for timed exercises plots seconds-per-set instead of load.
- **[V2]** CSV/JSON export emits `duration_secs` on every set row.
- **[V2]** Pre-session "Last execution" summary card on every routine detail screen, showing the most recent completed session of that routine.
- **[V2]** LLM data-access surface: the app's `Documents` directory is exposed via the Files app, and a stable `hybrid-latest.json` snapshot is auto-written to that directory whenever a session is finished or a routine/exercise is edited.

### Out of scope
- Countdown timer / live UI during the hold. V2 ships manual logging only, consistent with the V1 manual-logging ethos. A timer is a V3 candidate.
- Mixed-unit exercises (e.g. weighted plank logging both `weight_kg` and `duration_secs`). V2 keeps one unit per exercise.
- Tempo prescriptions for traditional lifts (e.g. "3-1-3 squat"). Separate problem from timed holds.
- Auto-detecting "this exercise should be timed" from name string. Metric type is set explicitly at exercise creation.
- Pre-session trend charts or sparklines per exercise. V2 ships a single summary card; richer at-a-glance comparison is a V3 candidate.
- Cloud sync of the JSON snapshot (e.g. automatic iCloud upload). The snapshot lives in the local Documents directory; the user moves it elsewhere if they choose. V1's privacy-first stance is retained.
- Write-back from LLM agents (e.g. an external tool inserting a session). V2 LLM access is read-only.
- App Intents / Shortcuts surface. Deferred to V3 once the JSON snapshot shape is proven stable.
- Everything already out-of-scope in V1 (social feed, cloud sync, AI recovery scoring, automatic training-plan generation, wearable integration, audio coaching, live GPS).

## Core flows

1. Build or edit a routine.
2. Add lifting exercises from the base library **[V2: now including timed holds]** or create a custom exercise **[V2: with an explicit metric-type selector — reps, reps + load, or time]**.
3. **[V2]** For a timed-hold exercise in a routine, set target sets and a target duration range (e.g. 3 × 30–45s).
4. **[V2]** Open the routine detail screen. Above the "Start session" button, see a "Last execution" card: date, total duration, per-exercise top set rendered in each exercise's native unit. One tap opens the full prior session for reference. If there is no prior session, the card shows an empty state.
5. Start a workout or run session from that routine.
6. Log sets. **[V2]** For timed-hold sets, enter seconds (single field) and optionally RPE. Reps and load fields are hidden for these sets.
7. Finish the session and persist it locally. **[V2]** On finish, the JSON snapshot at `Documents/hybrid-latest.json` is rewritten atomically.
8. Open an exercise to view 12-month performance trends. **[V2]** Trend axis switches based on metric type: load for reps-based, seconds for timed.
9. Export all data as CSV or JSON.
10. **[V2]** Optionally open the Files app, navigate to the app's Documents folder, and pass `hybrid-latest.json` or `Hybrid.sqlite` to any LLM tool or analysis script.

## Data model

V1 entities unchanged. **[V2]** Changes:

- `routine_exercise`: add `target_duration_secs_min` and `target_duration_secs_max` (both nullable integers). Nullable so reps-based routine items are unaffected. Single-value target = both fields equal.
- `session_set.duration_secs`: already present in V1 schema (currently always null on lift rows); V2 populates it for timed-hold sets.
- `exercise.metric_type`: already supports `TIME` in V1; no schema change.
- `session.routine_id`: already present in V1 (foreign key, `ON DELETE SET NULL`); powers the previous-execution lookup. No schema change.
- New composite index on `session(routine_id, finished_at DESC)` to keep the "last execution" lookup O(log n) on large histories.
- Seed migration inserts five timed holds into the base library (`is_custom = 0`, `metric_type = 'TIME'`).

**[V2]** Validation rule (app-layer, not DB constraint): for an `exercise` with `metric_type = TIME`, a `session_set` must have `duration_secs` non-null and `reps` null; for `metric_type IN (REPS, REPS_BODYWEIGHT)`, `reps` must be non-null and `duration_secs` null. Metric type is immutable after the first session set is logged against that exercise.

## Previous-execution recall

**[V2]** Every routine detail screen surfaces a "Last execution" summary card above the Start button.

Card content:
- Header: "Last time — {relative date, e.g. '3 days ago'}".
- Total session duration.
- Per exercise, in the original routine order: exercise name + best set rendered in its native unit ("315 lb × 5 @ RPE 8" for reps-based; "45s @ RPE 7" for timed).
- Tap target: opens the full prior session detail screen.
- Empty state when no prior session exists: "First time on this routine — no comparison yet."

The card is read-only. Exercises that were in the prior session but are no longer in today's routine are still shown, visually muted, with a "removed from routine" tag. New exercises in today's routine that have no prior data are omitted from the card.

### Run-lane addendum

**[V2.1]** The same card surfaces on run routine detail screens, but the per-item shape changes. A run routine references one or more `routine_run` slots (each pointing at a `run_template`), and each slot in the prior session produced exactly one `session_run` row plus its `session_run_split` rows.

Card content for the run lane, in original `routine_run.sort_order`:

- Slot label: the underlying `run_template.name`.
- Best-effort summary line, in this order of preference:
  1. **Distance-based templates** (`run_type` of `LONG`, `EASY`, `STEADY`, `RACE`): `"{actual_distance_km, 2dp} km · {duration_secs → hh:mm:ss} · {avg_pace_secs → m'ss"/km}"`. Heart-rate suffix `· avg {avg_hr} bpm` when present.
  2. **Interval / structured templates** (`run_type` of `INTERVAL`, `TEMPO`, `FARTLEK`): `"{repeat_count} × {block summary} · {duration_secs → hh:mm:ss}"` where block summary is taken from `IntervalDescription` for the dominant block, plus `avg_pace_secs` for that block.
  3. **Missing data fallback**: when the prior `session_run` row has neither pace nor HR (e.g. user finished early without GPS), render `"{duration_secs → hh:mm:ss} · pace not recorded"`.
- Removed-from-routine slots follow the same muted-with-tag rule as the lift lane.

`session_run_split` rows are not surfaced in the card itself — the tap target opens the full session detail screen where splits already live (V1 surface).

The query path mirrors the lift lane: `SessionRepository.lastCompletedSession(forRoutineID:)` returns the session; for each `routine_run` slot a new repo method (`SessionRunRepository.bestRunForSlot(sessionID:templateID:)`) returns the matching `session_run` row, formatted by a shared run-lane formatter.

Empty state copy is identical to the lift lane ("First time on this routine — no comparison yet").

## LLM data access

**[V2]** Two layers, both opt-in via existing iOS surfaces. No new permission prompts, no network traffic.

1. **Files-app visibility.** The app's `Info.plist` is updated to set `UIFileSharingEnabled = YES` and `LSSupportsOpeningDocumentsInPlace = YES`. After this change, `Hybrid.sqlite` and any exported files in `Documents/` are reachable from the Files app on iPhone and iPad, and via Finder on macOS. LLM agents that can read from the filesystem (Claude Desktop with file access, ChatGPT with file uploads, custom MCP filesystem servers) can be pointed at these files directly.

2. **Auto-written JSON snapshot.** A new component writes `Documents/hybrid-latest.json` containing the full DB contents — same shape as the existing JSON export, but at a stable, never-purged path. The snapshot is rewritten on:
   - Session finish.
   - Routine create / edit / delete.
   - Custom exercise create / edit.
   - Settings → "Refresh LLM snapshot" tap (manual trigger).

   Writes are atomic (temp file + rename), debounced to 250 ms, and dispatched off the main thread. The file is human-readable JSON (pretty-printed, stable key order) so that an LLM diffing two snapshots over time gets clean diffs.

   The JSON document includes a top-level `schema_version` field (starts at `"2.0"`) so future consumers can detect breaking shape changes.

   A short companion file `Documents/hybrid-schema.md` is written once on first launch (and regenerated when `schema_version` bumps) describing the JSON shape, unit conventions (kg for load, seconds for duration, metres for distance), and how to interpret `metric_type`. This is the "README for the LLM" — the snapshot's documentation.

Settings exposes an "Auto-update LLM snapshot" toggle (default ON). When OFF, the auto-write hooks become no-ops; only the manual "Refresh LLM snapshot" button writes. A footer note in Settings reminds the user that their training data is visible in the Files app, so the privacy implication is explicit.

## UX principles

Unchanged from V1: sparse, fast, explicit. **[V2]** Additions:
- The active session SetRow renders different input fields based on the exercise's metric type. An athlete never sees a reps field on a wall sit or a seconds field on a back squat. This conditional rendering is the entire UX surface of timed holds.
- The "Last execution" card renders asynchronously with a skeleton placeholder during load. The routine detail screen never blocks on history queries.

## Success metrics

V1 metrics retained. **[V2]** Add:
- Share of logged sets that are timed (proxy for whether the timed-hold feature gets adopted).
- Share of users with ≥1 timed-hold session per week (proxy for whether it serves hybrid programs).
- Custom exercise creation rate for `metric_type = TIME` (proxy for whether the seed library is sufficient).
- Tap-through rate on the "Last execution" card → full session detail (proxy for whether pre-session recall is actually used).
- "Refresh LLM snapshot" manual tap count and `hybrid-latest.json` mtime delta over a 7-day window (proxy for whether the LLM snapshot is being consumed externally).

## Risks and fixes

- **Risk:** Users mis-set metric type when creating a custom exercise and end up with a wall sit recorded in reps. **Fix:** Default metric type to "reps + load" but force an explicit choice; show a one-line example for each option.
- **Risk:** History view becomes confusing when an exercise's metric type is changed retroactively. **Fix:** Metric type is immutable after the first session set is logged against that exercise. Enforced in the repo layer.
- **Risk:** Export consumers that expected `duration_secs` to always be null on lift rows break. **Fix:** The column existed in V1 — it was just always null. V2 populates it. Document in the schema-doc file.
- **Risk:** "Last execution" card stalls the routine detail screen on devices with thousands of historical sessions. **Fix:** Composite index on `session(routine_id, finished_at DESC)`; card renders asynchronously with a skeleton placeholder.
- **Risk:** "Last execution" shows a session whose routine has since been edited, causing a mismatch between today's plan and yesterday's card. **Fix:** Card shows exactly what was logged in the prior session. Removed-from-routine exercises remain in the card, muted with a tag. New exercises in today's routine are omitted from the card.
- **Risk:** Auto-writing `hybrid-latest.json` on every session finish becomes expensive as the DB grows. **Fix:** Debounce 250 ms, off-main dispatch. For DBs over a configurable size threshold (default 10 MB) the snapshot writer falls back to manifest-only mode and prompts the user to use the regular CSV/JSON export.
- **Risk:** Files-app exposure surprises a privacy-conscious user by making `Hybrid.sqlite` visible. **Fix:** Settings footer states the visibility explicitly. Auto-snapshot is user-togglable.
- **Risk:** An LLM consuming `hybrid-latest.json` parses an inconsistent mid-write state. **Fix:** Atomic write via temp-file + rename. Readers always see a complete prior version or the complete new version, never partial.

## Verification

**[V2]** 15-step manual pass that gates the V2 → main merge. The canonical checklist with sign-off block lives in `VERIFICATION-V2.md` at the repo root; the steps below are the spec the checklist instantiates.

### Timed-hold flows (7 steps)

1. Clean install launches the app, seeded routines load without crash.
2. A seeded routine that contains Plank displays a duration range (e.g. `30–45s`) on the Plank row instead of a rep range.
3. Custom-exercise editor can create an exercise with `metric_type = TIME`; it persists into the exercise library.
4. The metric-type picker on a brand-new custom exercise is editable; round-tripping through "Reps + Weight" persists across reopen.
5. Active session for a routine containing Plank renders a single "Seconds" SetRow field (no KG / Reps fields); two sets at different durations both persist and finish cleanly.
6. After a set has been logged against a Time custom exercise, reopening that exercise's editor shows the metric-type picker locked with hint copy ("Locked — already used in completed sets").
7. Exercise history view for a Time exercise plots `duration_secs` on the Y axis (legend "TOP-SET SECS") and renders session list rows as `{n}s`.

### Previous-execution recall (3 steps)

8. After completing one session of a lift routine, the routine detail screen renders `LastExecutionCard` above the Start button with relative time, total duration mm:ss, and per-exercise top sets formatted per metric type.
9. A never-completed routine shows the empty state copy.
10. Editing a completed routine to remove one exercise and add another causes the card on reopen to show the removed exercise muted with a "removed" tag while omitting the newly-added one.

### LLM access (5 steps)

11. Files app → On My iPhone → Hybrid exposes `Hybrid.sqlite`, `hybrid-latest.json`, and `hybrid-schema.md`.
12. `hybrid-schema.md` opens to content that contains `schema_version: 2.0`, the Envelope section, and the metric_type semantics table.
13. Finishing a session causes `hybrid-latest.json` mtime to advance; the file parses to an object whose top-level keys are `schema_version: "2.0"` and `data: { ... }`.
14. With "Auto-update LLM snapshot" toggled OFF, finishing another session leaves `hybrid-latest.json` mtime unchanged.
15. Tapping "Refresh LLM snapshot now" in Settings updates `hybrid-latest.json` mtime regardless of the toggle.

### Sign-off

The tester records device / OS, date, pass/fail per step, and any regressions in the sign-off block of `VERIFICATION-V2.md`. A clean pass is required before tagging `v0.2` on the merge commit.
