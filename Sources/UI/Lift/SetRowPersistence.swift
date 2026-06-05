import Foundation

/// Shared mapping from an editable `SetRowState` to a persisted `SessionSet`.
///
/// Lives in the UI layer (not `SessionSetRepository`) on purpose: `SetRowState` is
/// view-model state, so keeping the parse here means the repository stays
/// `SessionSet`-only and no UI type leaks into persistence.
@MainActor
enum SetRowPersistence {

    /// Inserts or updates `row` for `exercise`. Fully-empty rows are skipped.
    /// `setNumber` is the row's 1-based position within its block.
    /// Throws if the underlying write fails so callers can surface the error
    /// (rather than silently dropping the set).
    static func persist(
        _ row: SetRowState,
        exercise: Exercise,
        sessionRowID: Int,
        exerciseOrder: Int,
        setNumber: Int,
        distanceUnit: DistanceUnit,
        repo: SessionSetRepository
    ) async throws {
        let isTime     = exercise.metricType == .time
        let isDistance = exercise.metricType == .distance

        // Skip fully-empty rows
        if isTime, row.durationSecsText.isEmpty { return }
        if isDistance, row.distanceText.isEmpty { return }
        if !isTime && !isDistance, row.weightText.isEmpty && row.repsText.isEmpty { return }

        let now = Date()
        let rpe = Double(row.rpeText)
        let weightKg:     Double? = (isTime || isDistance) ? nil : Double(row.weightText)
        let reps:         Int?    = (isTime || isDistance) ? nil : Int(row.repsText)
        let durationSecs: Int?    = isTime ? Int(row.durationSecsText) : nil
        let distanceM:    Double? = isDistance
            ? Double(row.distanceText).map { distanceUnit == .km ? $0 * 1000.0 : $0 * 1609.344 }
            : nil

        if let existing = row.persistedSet {
            let updated = SessionSet(
                id: existing.id,
                clientUUID: existing.clientUUID,
                sessionID: existing.sessionID,
                exerciseID: existing.exerciseID,
                exerciseOrder: exerciseOrder,
                setNumber: setNumber,
                setType: existing.setType,
                weightKg: weightKg,
                reps: reps,
                durationSecs: durationSecs,
                distanceM: distanceM,
                rpe: rpe,
                completedAt: row.isCompleted ? now : existing.completedAt,
                notes: nil,
                updatedAt: now
            )
            try await repo.update(updated)
            // Keep the cached snapshot current (e.g. completedAt) for the next edit.
            row.persistedSet = updated
        } else {
            let newSet = SessionSet(
                id: 0,
                clientUUID: row.id,
                sessionID: sessionRowID,
                exerciseID: exercise.id,
                exerciseOrder: exerciseOrder,
                setNumber: setNumber,
                setType: .working,
                weightKg: weightKg,
                reps: reps,
                durationSecs: durationSecs,
                distanceM: distanceM,
                rpe: rpe,
                completedAt: row.isCompleted ? now : nil,
                notes: nil,
                updatedAt: now
            )
            try await repo.append(newSet)
            row.persistedSet = newSet
        }
    }
}
