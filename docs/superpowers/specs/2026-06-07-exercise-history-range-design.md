# Exercise History Range Selector — Design

**Date:** 2026-06-07
**Status:** Approved

## Goal

On an exercise's history screen, let the user choose how much past data the chart
spans: 1 week, 1 month, 1 quarter, 1 year, 2 years. The chart shows the selected
window and scrolls horizontally to reveal older windows of the same width.

## Decisions

- **Range = visible window width.** The selection sets the chart's visible time
  domain; the user pans horizontally to see earlier periods. (E.g. with 1W
  selected, scrolling left reveals the week before, then the week before that.)
- **Load all history once.** The view fetches every completed session's top set
  for the exercise. Window and scroll position are pure view state — no re-query
  on scroll. Single-user data volume makes this trivial.
- **Default range: 1 Week.** Not persisted — resets to 1W on every open.
- **Anchor to newest data.** The initial/visible window's right edge sits at the
  most recent session (not `Date()`), so the default 1W view is never empty when
  the last workout predates the window.
- **Session list below the chart is unchanged** — full history, newest first,
  independent of the selected range.

## Implementation

### Range type (Lift UI layer)

```swift
enum HistoryRange: String, CaseIterable, Identifiable {
    case week, month, quarter, year, twoYears
    var id: String { rawValue }
    var label: String        // "1W", "1M", "1Q", "1Y", "2Y"
    var visibleDuration: TimeInterval   // days * 86_400 → 7, 30, 91, 365, 730
}
```

### Data layer (`SessionSetRepository`)

- `topSetPerSession(exerciseID:limit:)` — `limit: Int? = 12`; when `nil`, omit the
  `LIMIT` clause.
- `historyByExercise(exerciseID:monthsBack:)` — `monthsBack: Int? = 12`; when
  `nil`, omit the `started_at >= ?` cutoff.
- Both built by conditionally appending the fixed clause — no user input in SQL.
- All existing callers keep their current arguments; behavior unchanged.

### ViewModel (`ExerciseHistoryViewModel`)

- `load()` passes `nil` for both bounds → `topSets` holds full chronological
  history. Remove the `.suffix(12)` on the time-exercise path.

### View (`ExerciseHistoryView`)

- `@State private var range: HistoryRange = .week` (no persistence).
- Segmented `Picker` (W/M/Q/Y/2Y) above the chart.
- Chart:
  ```swift
  .chartScrollableAxes(.horizontal)
  .chartXVisibleDomain(length: range.visibleDuration)
  .chartScrollPosition(x: $scrollX)
  ```
- Scroll position anchored so the newest data point is at the right edge;
  re-anchored when `range` changes or data loads.
- Chart header: replace "LAST 12 SESSIONS" with the selected range label.

## Tests

- Repo: `topSetPerSession(limit: nil)` / `historyByExercise(monthsBack: nil)`
  return sessions older than the previous bounds (insert old + recent, assert
  both present).
- Existing bounded-argument tests stay green (defaults unchanged).
