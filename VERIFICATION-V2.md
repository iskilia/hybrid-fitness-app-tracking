# V2 Manual Verification Checklist

TV7.3 — Manual verification pass for V2 (timed holds + previous-execution
recall + LLM access). Author runs this on a physical iPhone or simulator
running iOS 17+. The XCTest suite (52/52) covers automated behaviour; this
list covers user-visible flows the suite cannot reach.

Tick each step in the PR description before merging `feature/v2` → `main`.

## Timed-hold flows (7 steps)

1. [Y] Launch the app on a clean install (or after deleting and reinstalling).
       Open the routine list. Confirm seed routines load without crash.
2. [N] Open a routine that includes Plank. The Plank row trailing label reads
       a duration range (e.g. `30–45s`), not a rep range.
3. [N] Custom-exercise editor → create a new exercise with metric type
       "Time". Save. Confirm it lands in the exercise library.
4. [N] Edit that brand-new custom exercise. The metric-type picker is
       editable (not locked). Switch to "Reps + Weight"; save; reopen; the
       change persists.
5. [N] Start a session that includes Plank. SetRow shows a single "Seconds"
       field (no KG / Reps fields). Enter `35`; tap the checkmark; the set
       persists. Add a second set with `40`. Finish the session.
6. [N] After a set has been logged against the Time custom exercise from step
       3, open the custom-exercise editor again. The metric-type picker is
       now locked with hint copy "Locked — already used in completed sets."
7. [N] Exercise history view for Plank: chart Y axis shows seconds (legend
       "TOP-SET SECS"). Session list rows show `{n}s`, not `× n`.

## Previous-execution recall (3 steps)

8. [N] Complete one session of a lift routine. Return to that routine's
       detail screen. `LastExecutionCard` appears above the Start button
       with a relative time ("a few seconds ago" / "1 minute ago"), total
       duration mm:ss, and per-exercise top sets formatted per metric type.
9. [N] Open a routine that has never been completed. The card shows the
       empty state copy ("First time on this routine — no comparison yet").
10. [N] Edit the just-completed routine: remove one exercise that was logged
        in the prior session; add a new exercise. Reopen the routine detail.
        The removed exercise still appears in `LastExecutionCard` muted with
        the "removed" tag; the newly-added exercise is absent from the card.

## LLM access (5 steps)

11. [N] Files app → On My iPhone → Hybrid. Three files visible:
        `Hybrid.sqlite`, `hybrid-latest.json`, `hybrid-schema.md`.
12. [N] Open `hybrid-schema.md` from the Files app. Content includes
        `schema_version: 2.0`, the Envelope section, and the metric_type
        semantics table.
13. [N] Note the mtime of `hybrid-latest.json`. Finish a new session. Re-open
        Files; mtime is more recent than before. JSON opens to an object
        with `schema_version: "2.0"` and `data: { ... }`.
14. [N] Settings → toggle "Auto-update LLM snapshot" OFF. Finish another
        session. Re-check `hybrid-latest.json` mtime — unchanged.
15. [N] Settings → "Refresh LLM snapshot now" button. mtime updates.
        Toggle the auto-update back ON.

## Sign-off

- Tester:
- Device / OS:
- Date:
- All 15 steps green? (Y / N):
- Notes / regressions:
