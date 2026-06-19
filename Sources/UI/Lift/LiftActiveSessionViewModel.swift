import Foundation
import Observation

// MARK: - SetRowState

/// Mutable in-progress state for a single set row.
@Observable
@MainActor
final class SetRowState: Identifiable {
    let id: UUID
    var weightText: String
    var repsText: String
    var rpeText: String
    var durationSecsText: String
    var distanceText: String
    var isCompleted: Bool

    /// The persisted SessionSet once written to DB (used for updates).
    var persistedSet: SessionSet?

    init(id: UUID = UUID(), weight: Double? = nil, reps: Int? = nil, rpe: Double? = nil, duration: Int? = nil, distance: Double? = nil, distanceUnit: DistanceUnit = .km, isCompleted: Bool = false) {
        self.id = id
        self.weightText = weight.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int($0))" : String(format: "%.1f", $0) } ?? ""
        self.repsText   = reps.map { "\($0)" } ?? ""
        self.rpeText    = rpe.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int($0))" : String(format: "%.1f", $0) } ?? ""
        self.durationSecsText = duration.map { "\($0)" } ?? ""
        self.distanceText = distance.map {
            let unitValue = distanceUnit == .km ? $0 / 1000.0 : $0 / 1609.344
            return unitValue.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(unitValue))" : String(format: "%.3f", unitValue)
        } ?? ""
        self.isCompleted = isCompleted
    }
}

// MARK: - ExerciseCardState

/// State for one exercise card inside an active session.
@Observable
@MainActor
final class ExerciseCardState: Identifiable {
    let id: UUID  // exercise.clientUUID
    let exercise: Exercise
    let routineExercise: RoutineExercise
    var rows: [SetRowState]
    var previousBest: String?  // e.g. "Previous: 90 KG × 5"

    init(exercise: Exercise, routineExercise: RoutineExercise, rows: [SetRowState] = [], previousBest: String? = nil) {
        self.id = exercise.clientUUID
        self.exercise = exercise
        self.routineExercise = routineExercise
        self.rows = rows
        self.previousBest = previousBest
    }
}

// MARK: - LiftActiveSessionViewModel

@Observable
@MainActor
final class LiftActiveSessionViewModel {
    var session: Session?
    var routine: Routine?
    var cards: [ExerciseCardState] = []
    var expandedCardID: UUID?
    var doneCardIDs: Set<UUID> = []
    var errorMessage: String?

    private let sessionID: UUID
    private let sessionRepo: SessionRepository
    private let sessionSetRepo: SessionSetRepository
    private let routineRepo: RoutineRepository
    private let exerciseRepo: ExerciseRepository
    private let storageGuard: StorageGuard
    private let profileRepo: UserProfileRepository
    var showStorageFullConfirm = false
    private var maxDataMb: Int = 10
    var distanceUnit: DistanceUnit = .km

    init(sessionID: UUID, dbManager: DatabaseManager) {
        self.sessionID = sessionID
        self.sessionRepo     = SessionRepository(dbManager: dbManager)
        self.sessionSetRepo  = SessionSetRepository(dbManager: dbManager)
        self.routineRepo     = RoutineRepository(dbManager: dbManager)
        self.exerciseRepo    = ExerciseRepository(dbManager: dbManager)
        self.storageGuard    = StorageGuard(dbManager: dbManager)
        self.profileRepo     = UserProfileRepository(dbManager: dbManager)
    }

    // MARK: - Load

    func load() async {
        do {
            if let p = try await profileRepo.get() {
                maxDataMb = p.maxDataMb
                distanceUnit = p.distanceUnit
            }

            let s = try await sessionRepo.get(id: sessionID)
            self.session = s

            guard let s else { return }

            if let routineRowID = s.routineID {
                // Fetch all routines and find by integer ID
                let allRoutines = try await routineRepo.list()
                self.routine = allRoutines.first(where: { $0.id == routineRowID })
            }

            guard let routine else { return }

            let routineExercises = try await routineRepo.listExercises(routineID: routine.clientUUID)
            let allExercises     = try await exerciseRepo.listAll()
            let exerciseByID     = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })

            var builtCards: [ExerciseCardState] = []
            for re in routineExercises {
                guard let exercise = exerciseByID[re.exerciseID] else { continue }
                builtCards.append(try await makeCard(exercise: exercise, routineExercise: re))
            }
            self.cards = builtCards
            expandedCardID = builtCards.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Builds an exercise card: computes the "previous best" hint and hydrates any
    /// already-persisted sets for this session+exercise (falling back to one empty row).
    /// Shared by `load()` and mid-session exercise swaps.
    private func makeCard(exercise: Exercise, routineExercise: RoutineExercise) async throws -> ExerciseCardState {
        let du = distanceUnit

        // Previous best
        let topSets = try await sessionSetRepo.topSetPerSession(exerciseID: exercise.clientUUID, limit: 1)
        var previousBest: String?
        if exercise.metricType == .time {
            // topSetPerSession filters on weight_kg IS NOT NULL, so returns nothing for .time;
            // use the session list to derive the best duration instead.
            let recentSets = try await sessionSetRepo.historyByExercise(exerciseID: exercise.clientUUID, monthsBack: 12)
            if let best = recentSets.compactMap({ $0.durationSecs }).max() {
                previousBest = "Previous: \(best)s"
            }
        } else if let top = topSets.first {
            let wStr = top.weightKg.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(top.weightKg)) KG" : String(format: "%.1f KG", top.weightKg)
            previousBest = "Previous: \(wStr) × \(top.reps)"
        }

        // Existing sets for this session + exercise
        let existingSets = try await sessionSetRepo.list(sessionID: sessionID, exerciseID: exercise.clientUUID)
        let rows: [SetRowState] = existingSets.map { ss in
            if exercise.metricType == .time {
                return SetRowState(id: ss.clientUUID, rpe: ss.rpe, duration: ss.durationSecs, isCompleted: ss.completedAt != nil)
            } else if exercise.metricType == .distance {
                return SetRowState(id: ss.clientUUID, rpe: ss.rpe, distance: ss.distanceM, distanceUnit: du, isCompleted: ss.completedAt != nil)
            } else {
                return SetRowState(id: ss.clientUUID, weight: ss.weightKg, reps: ss.reps, rpe: ss.rpe, isCompleted: ss.completedAt != nil)
            }
        }

        return ExerciseCardState(
            exercise: exercise,
            routineExercise: routineExercise,
            rows: rows.isEmpty ? [SetRowState()] : rows,
            previousBest: previousBest
        )
    }

    // MARK: - Mid-session edit (delete / swap exercise)

    /// Removes an exercise from the in-progress session and deletes its persisted sets.
    func deleteCard(_ card: ExerciseCardState) async {
        do {
            try await sessionSetRepo.deleteAll(sessionID: sessionID, exerciseID: card.exercise.clientUUID)
        } catch {
            errorMessage = "Couldn't remove exercise: \(error.userMessage)"
            return
        }
        cards.removeAll { $0.id == card.id }
        doneCardIDs.remove(card.id)
        if expandedCardID == card.id { expandedCardID = cards.first(where: { !doneCardIDs.contains($0.id) })?.id }
    }

    /// Swaps the exercise in `card` for `newExercise`, discarding the old exercise's
    /// logged sets. The replacement starts fresh at the same position.
    func swapExercise(in card: ExerciseCardState, to newExercise: Exercise) async {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        guard newExercise.clientUUID != card.exercise.clientUUID else { return }
        guard !cards.contains(where: { $0.exercise.clientUUID == newExercise.clientUUID }) else {
            errorMessage = "\(newExercise.name) is already in this session."
            return
        }
        do {
            try await sessionSetRepo.deleteAll(sessionID: sessionID, exerciseID: card.exercise.clientUUID)
            let transient = RoutineExercise(
                id: 0, clientUUID: UUID(), routineID: 0,
                exerciseID: newExercise.id, sortOrder: card.routineExercise.sortOrder,
                targetSets: nil, targetRepMin: nil, targetRepMax: nil,
                targetRPE: nil, targetDurationSecsMin: nil, targetDurationSecsMax: nil,
                notes: nil, updatedAt: Date()
            )
            let newCard = try await makeCard(exercise: newExercise, routineExercise: transient)
            doneCardIDs.remove(card.id)
            cards[index] = newCard
            if expandedCardID == card.id { expandedCardID = newCard.id }
        } catch {
            errorMessage = "Couldn't change exercise: \(error.userMessage)"
        }
    }

    // MARK: - Expand / Done state

    func toggleExpand(_ card: ExerciseCardState) {
        expandedCardID = (expandedCardID == card.id) ? nil : card.id
    }

    func advanceToNextCard(after card: ExerciseCardState) {
        guard let i = cards.firstIndex(where: { $0.id == card.id }) else { expandedCardID = nil; return }
        let next = cards[(i + 1)...].first(where: { !doneCardIDs.contains($0.id) })
        expandedCardID = next?.id
    }

    /// Persist all rows of this card (awaiting writes), mark its sets completed + the card done.
    func markCardDone(_ card: ExerciseCardState, exerciseOrder: Int) async {
        for row in card.rows { row.isCompleted = true }
        for row in card.rows { await persistRow(row, in: card, exerciseOrder: exerciseOrder) }
        doneCardIDs.insert(card.id)
        advanceToNextCard(after: card)
    }

    // MARK: - Add Set

    func addSet(to card: ExerciseCardState) {
        card.rows.append(SetRowState())
    }

    // MARK: - Persist Set

    func persistSet(_ row: SetRowState, in card: ExerciseCardState, exerciseOrder: Int) {
        Task { await persistRow(row, in: card, exerciseOrder: exerciseOrder) }
    }

    private func persistRow(_ row: SetRowState, in card: ExerciseCardState, exerciseOrder: Int) async {
        guard let s = session else { return }
        let setNumber = (card.rows.firstIndex(where: { $0.id == row.id }) ?? 0) + 1
        do {
            try await SetRowPersistence.persist(
                row,
                exercise: card.exercise,
                sessionRowID: s.id,
                exerciseOrder: exerciseOrder,
                setNumber: setNumber,
                distanceUnit: distanceUnit,
                repo: sessionSetRepo
            )
        } catch {
            errorMessage = "Couldn't save set: \(error.userMessage)"
        }
    }

    /// Persists every row that contains data, awaiting each write so rows land before FINISH.
    func persistAllRows() async {
        guard session != nil else { return }
        for (index, card) in cards.enumerated() {
            for row in card.rows {
                await persistRow(row, in: card, exerciseOrder: index + 1)
            }
        }
    }

    // MARK: - Finish / Abandon

    /// Returns true if the caller should pop to Home immediately;
    /// false if a storage-full confirmation is now showing (caller waits).
    func finishAndCheckStorage() async -> Bool {
        try? await sessionRepo.finish(id: sessionID)
        if let p = try? await profileRepo.get() { maxDataMb = p.maxDataMb }
        let over = (try? await storageGuard.isOverLimit(maxDataMb: maxDataMb)) ?? false
        if over { showStorageFullConfirm = true; return false }
        return true
    }

    /// Returns true if eviction succeeded (caller may pop to Home); false on failure,
    /// in which case `errorMessage` is set and the caller should keep the user here.
    func confirmStorageEviction() async -> Bool {
        do {
            _ = try await storageGuard.reconcile(maxDataMb: maxDataMb)
            return true
        } catch {
            errorMessage = "Couldn't free space: \(error.localizedDescription)"
            return false
        }
    }

    func abandon() async {
        try? await sessionRepo.abandon(id: sessionID)
    }
}
