import Foundation

// TV3.2 — Static schema documentation for hybrid-latest.json.

public enum SchemaDoc {

    public static let schemaVersion = "2.0"

    public static let markdown: String = """
    # hybrid-latest.json — Schema Reference

    **schema_version**: `2.0`

    This file is the canonical LLM-readable snapshot of a user's Hybrid training
    data. It is written atomically to the app's Documents directory whenever the
    data changes. Consumers should check `schema_version` before parsing; a
    version bump indicates a structural change.

    ---

    ## Envelope

    ```
    {
      "schema_version": "2.0",   // always the first sorted key
      "data": { ... }            // table dump (see Tables below)
    }
    ```

    If the database exceeds the size threshold, the file switches to manifest mode:

    ```
    {
      "schema_version": "2.0",
      "mode": "manifest",
      "db_size_bytes": <integer>,
      "generated_at": "<ISO 8601>",
      "message": "..."
    }
    ```

    ---

    ## Unit Conventions

    | Field               | Unit    |
    |---------------------|---------|
    | `weight_kg`         | kg      |
    | `duration_secs`     | seconds |
    | `distance_m`        | metres  |
    | `distance_km`       | km      |
    | `body_weight_kg`    | kg      |
    | `target_pace_secs`  | seconds per km |

    ---

    ## metric_type Semantics

    Each `exercise` row carries a `metric_type` that governs how `session_set`
    rows are populated:

    | metric_type        | `reps` | `weight_kg` | `duration_secs` | `distance_m` |
    |--------------------|--------|-------------|-----------------|--------------|
    | `REPS`             | set    | null        | null            | null         |
    | `REPS_BODYWEIGHT`  | set    | null        | null            | null         |
    | `REPS_WEIGHTED`    | set    | set         | null            | null         |
    | `TIME`             | null   | null        | set             | null         |
    | `DISTANCE`         | null   | null        | null            | set          |

    For `TIME` exercises (timed holds such as Plank, Wall Sit, Dead Hang):
    - `session_set.reps` is always null.
    - `session_set.duration_secs` is always populated.
    - `routine_exercise.target_duration_secs_min` / `target_duration_secs_max`
      hold the planned hold range in seconds; both are null for reps-based items.

    ---

    ## Atomic-Write Guarantee

    The file is written to a `.tmp` staging path and promoted via
    `FileManager.replaceItemAt(_:withItemAt:)`. Readers will never observe a
    partial-write state — the file is either the previous complete version or
    the new complete version.

    ---

    ## Tables

    `data` contains one key per SQLite table. Each value is an array of row
    objects. All nullable columns may be `null` in JSON. Soft-deleted rows are
    included (check `deleted_at`).

    Key tables for training data:
    - `routine` / `routine_exercise` / `routine_run` — programme structure.
    - `session` / `session_set` / `session_run` — completed work.
    - `exercise` — exercise catalogue with `metric_type`.
    """

    /// Writes `markdown` to `documentsURL/hybrid-schema.md` atomically.
    public static func write(to documentsURL: URL) throws {
        let dest = documentsURL.appendingPathComponent("hybrid-schema.md")
        try markdown.write(to: dest, atomically: true, encoding: .utf8)
    }
}
