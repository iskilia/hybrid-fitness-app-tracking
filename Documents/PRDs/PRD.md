Below is a tighter **V1 PRD-style outline** based on your idea, with the scope trimmed to something shippable and testable. The architecture choice of local-only SQLite and manual logging is sensible for an offline-first app, and your lifting/running split matches what existing products already do well separately, which helps clarify your wedge. [innovationm](https://www.innovationm.com/blog/react-native-offline-first-architecture-sqlite-local-database-guide/)

## Product framing

V1 should be positioned as a privacy-first hybrid training log for athletes who run and lift in the same week. The core promise is not automation; it is clean, structured, on-device training history that makes interference easier to reason about later. That is a stronger and more defensible V1 than promising recovery intelligence before you have enough trustworthy data. [sqliteforum](https://www.sqliteforum.com/p/building-offline-first-applications)

## Problem statement

Current apps fragment the training picture by modality. Strength apps excel at lifting logs and previous-set visibility, while run platforms excel at pace and HR zones, but neither gives hybrid athletes a unified, offline, local-history workflow. V1 should solve that by making the timeline the product: every lift and run sits in one data model, one history view, and one exportable database. [hevyapp](https://www.hevyapp.com/features/custom-exercises/)

## Target user

The primary user is a self-directed hybrid athlete who already knows what they want to do each week. This user values repeatability, privacy, and fast logging more than social features or AI coaching. Secondary users include coaches or advanced lifters/runners who want a clean manual baseline before adopting more automated tooling later. [support.myprocoach](https://support.myprocoach.net/hc/en-us/articles/360019174032-How-to-Update-Your-Run-Thresholds-in-TrainingPeaks)

## V1 scope

### In scope
- Local-only storage using SQLite.
- Up to 10 routines.
- Custom lifting exercise creation with name, notes, and a form-check link.
- Base exercise library for common lifts.
- Run templates for tempo, long run, and intervals.
- Exercise-level history views for the last 12 months.
- CSV and JSON export.
- Offline session logging, routine creation, and history browsing.

### Out of scope
- Social feed, likes, comments, or leaderboards.
- Cloud sync.
- AI recovery scoring.
- Automatic training plan generation.
- Wearable integration.
- Audio coaching or live GPS tracking.

That boundary is important because offline-first systems work best when the local schema is stable and the sync problem is postponed, not hidden. [linkedin](https://www.linkedin.com/pulse/offline-first-mobile-apps-best-practices-sync-local-storage-cardoso-sxe6f)

## Core flows

1. Build or edit a routine.
2. Add lifting exercises from the base library or create a custom exercise.
3. Start a workout or run session from that routine.
4. Log sets, reps, load, RPE, pace, HR, and interval structure.
5. Finish the session and persist it locally.
6. Open an exercise to view 12-month performance trends.
7. Export all data as CSV or JSON.

That flow keeps the app centered on logging integrity instead of feature sprawl. Hevy’s custom exercise and previous-workout patterns are good proof that users value this kind of frictionless historical context. [hevyapp](https://www.hevyapp.com/features/track-exercises/)

## Data model

At minimum, you need these entities:
- User profile.
- Routine.
- Routine item.
- Exercise.
- Custom exercise.
- Session.
- Session set.
- Run template.
- Run interval block.
- Export job.

For hybrid analytics later, the schema should also preserve session tags like “heavy lower,” “tempo,” and “intervals,” because those labels will matter when you eventually analyze interference. SQLite is a good fit here because the app’s first job is reliable local persistence, not multi-device conflict resolution. [innovationm](https://www.innovationm.com/blog/react-native-offline-first-architecture-sqlite-local-database-guide/)

## UX principles

The UI should be sparse, fast, and explicit. Every screen should answer one question: what am I doing, what did I do last time, or what should I log now. Avoid the temptation to add discovery feeds, badges, streaks, or AI prompts in V1, because those features compete with the athlete’s focus and make the product feel less like a tool. [linkedin](https://www.linkedin.com/pulse/offline-first-mobile-apps-best-practices-sync-local-storage-cardoso-sxe6f)

## Success metrics

Track V1 with behavior metrics rather than vanity metrics:
- 3+ multi-modal sessions per week over 90 days.
- Percentage of workouts created from templates.
- Percentage of users reaching the 10-routine ceiling.
- Export usage rate.
- 12-month history view engagement.

These are good because they measure whether the app is actually helping athletes build repeatable training behavior, not just whether they installed it. For hybrid training, consistency is more meaningful than social engagement. [sqliteforum](https://www.sqliteforum.com/p/building-offline-first-applications)

## Risks and fixes

The biggest risk is over-designing the hybrid intelligence layer before you have enough clean data. Another risk is making custom exercise creation too verbose, which could slow down logging and reduce retention. A third risk is confusing “privacy-first” with “no backup strategy,” so you should plan local export and restore early to protect users from device loss. [innovationm](https://www.innovationm.com/blog/react-native-offline-first-architecture-sqlite-local-database-guide/)

