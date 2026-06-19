import Foundation
import Observation
import SQLite3

// MARK: - ExerciseEntry

@Observable
@MainActor
final class ExerciseEntry: Identifiable {
    // Own identity (not exercise.clientUUID) so the same exercise can be added twice.
    let id = UUID()
    let exercise: Exercise
    var targetSets: Int?
    var targetRepMin: Int?
    var targetRepMax: Int?
    var notes: String

    init(exercise: Exercise,
         targetSets: Int? = nil,
         targetRepMin: Int? = nil,
         targetRepMax: Int? = nil,
         notes: String = "") {
        self.exercise = exercise
        self.targetSets = targetSets
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.notes = notes
    }
}

// MARK: - RoutineBuilderViewModel

@Observable
@MainActor
final class RoutineBuilderViewModel {
    var name: String = ""
    var entries: [ExerciseEntry] = []
    var runEntries: [RunTemplate] = []
    var errorMessage: String?
    var didCreate = false
    var didCancel = false
    var showEvictionConfirm = false
    var showImpossibleAlert = false
    private var pendingInsert: (@Sendable (OpaquePointer) throws -> Void)?
    private var maxDataMb: Int = 10

    /// When set, `create()` updates this existing routine instead of inserting a new one.
    private let editRoutineID: UUID?
    private var editingRoutine: Routine?

    private let routineRepo: RoutineRepository
    private let exerciseRepo: ExerciseRepository
    private let storageGuard: StorageGuard
    private let profileRepo: UserProfileRepository
    let dbManager: DatabaseManager

    init(dbManager: DatabaseManager, editRoutineID: UUID? = nil) {
        self.dbManager = dbManager
        self.editRoutineID = editRoutineID
        self.routineRepo = RoutineRepository(dbManager: dbManager)
        self.exerciseRepo = ExerciseRepository(dbManager: dbManager)
        self.storageGuard = StorageGuard(dbManager: dbManager)
        self.profileRepo = UserProfileRepository(dbManager: dbManager)
    }

    var isEditing: Bool { editRoutineID != nil }

    func load() async {
        if let p = try? await profileRepo.get() { maxDataMb = p.maxDataMb }
        if let editRoutineID { await loadExisting(editRoutineID) }
    }

    /// Prefills name, exercise entries (with targets + notes) and run entries from a saved routine.
    private func loadExisting(_ id: UUID) async {
        do {
            guard let routine = try await routineRepo.get(id: id) else { return }
            editingRoutine = routine
            name = routine.name

            let routineExercises = try await routineRepo.listExercises(routineID: id)
            let exerciseByID = Dictionary(uniqueKeysWithValues: try await exerciseRepo.listAll().map { ($0.id, $0) })
            entries = routineExercises.compactMap { re in
                guard let exercise = exerciseByID[re.exerciseID] else { return nil }
                return ExerciseEntry(
                    exercise: exercise,
                    targetSets: re.targetSets,
                    targetRepMin: re.targetRepMin,
                    targetRepMax: re.targetRepMax,
                    notes: re.notes ?? ""
                )
            }

            let runRows = try await routineRepo.runs(routineIntID: routine.id)
            let templatesByID = Dictionary(uniqueKeysWithValues:
                try await RunTemplateRepository(dbManager: dbManager).listAll().map { ($0.id, $0) })
            runEntries = runRows.compactMap { templatesByID[$0.runTemplateID] }
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// Drag-reorder for the exercise list (feature: reorder when ≥2 exercises).
    /// Moves the dragged entry to the dropped-on entry's position.
    func moveEntry(fromID: UUID, toID: UUID) {
        guard fromID != toID,
              let from = entries.firstIndex(where: { $0.id == fromID }),
              let to = entries.firstIndex(where: { $0.id == toID })
        else { return }
        let item = entries.remove(at: from)
        let insertIndex = to > from ? to - 1 : to
        entries.insert(item, at: insertIndex)
    }

    func add(_ exercise: Exercise) {
        entries.append(ExerciseEntry(exercise: exercise))
    }

    func remove(_ entry: ExerciseEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func addRun(_ template: RunTemplate) {
        runEntries.append(template)
    }

    func removeRun(_ template: RunTemplate) {
        runEntries.removeAll { $0.id == template.id }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !(entries.isEmpty && runEntries.isEmpty)
    }

    var derivedType: WorkoutType {
        if entries.isEmpty { return .run }
        if runEntries.isEmpty { return .lift }
        return .mixed
    }

    func create() async {
        guard isValid else { return }
        let now = Date()

        if let editing = editingRoutine {
            await update(editing, now: now)
            return
        }

        let routine = Routine(
            id: 0,
            clientUUID: UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: derivedType,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        let exerciseEntries: [RoutineExercise] = entries.enumerated().map { index, entry in
            routineExercise(from: entry, routineID: 0, sortOrder: index + 1, now: now)
        }
        let runRows: [RoutineRun] = runEntries.enumerated().map { index, template in
            RoutineRun(
                id: 0,
                clientUUID: UUID(),
                routineID: 0,
                runTemplateID: template.id,
                sortOrder: index + 1,
                notes: nil,
                updatedAt: now
            )
        }

        let repo = routineRepo
        let insert: @Sendable (OpaquePointer) throws -> Void = { db in
            try repo.insertRoutineWork(db, routine, exerciseEntries: exerciseEntries, runEntries: runRows)
        }

        do {
            let probe = try await storageGuard.probe(insert: insert, maxDataMb: maxDataMb)
            switch probe {
            case .fits:
                try await routineRepo.create(routine, exerciseEntries: exerciseEntries, runEntries: runRows)
                didCreate = true
            case .needsEviction:
                pendingInsert = insert
                showEvictionConfirm = true
            }
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// Edit path: replaces the routine's name/type and all child rows in one transaction.
    /// No storage probe — `update` swaps rows in place, so the size delta is negligible and
    /// the 10-routine cap doesn't apply (no new routine is added).
    private func update(_ editing: Routine, now: Date) async {
        let routine = Routine(
            id: editing.id,
            clientUUID: editing.clientUUID,
            name: name.trimmingCharacters(in: .whitespaces),
            type: derivedType,
            sortOrder: editing.sortOrder,
            createdAt: editing.createdAt,
            updatedAt: now,
            deletedAt: editing.deletedAt
        )
        let exerciseEntries: [RoutineExercise] = entries.enumerated().map { index, entry in
            routineExercise(from: entry, routineID: editing.id, sortOrder: index + 1, now: now)
        }
        let runRows: [RoutineRun] = runEntries.enumerated().map { index, template in
            RoutineRun(
                id: 0,
                clientUUID: UUID(),
                routineID: editing.id,
                runTemplateID: template.id,
                sortOrder: index + 1,
                notes: nil,
                updatedAt: now
            )
        }
        do {
            try await routineRepo.update(routine, exerciseEntries: exerciseEntries, runEntries: runRows)
            didCreate = true
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// Builds a `RoutineExercise` from a builder entry. Blank notes persist as `nil`.
    private func routineExercise(from entry: ExerciseEntry, routineID: Int, sortOrder: Int, now: Date) -> RoutineExercise {
        let trimmedNotes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return RoutineExercise(
            id: 0,
            clientUUID: UUID(),
            routineID: routineID,
            exerciseID: entry.exercise.id,
            sortOrder: sortOrder,
            targetSets: entry.targetSets,
            targetRepMin: entry.targetRepMin,
            targetRepMax: entry.targetRepMax,
            targetRPE: nil,
            targetDurationSecsMin: nil,
            targetDurationSecsMax: nil,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            updatedAt: now
        )
    }

    func confirmEviction() async {
        guard let insert = pendingInsert else { return }
        pendingInsert = nil
        do {
            let outcome = try await storageGuard.commitWithEviction(insert: insert, maxDataMb: maxDataMb)
            switch outcome {
            case .fitted:     didCreate = true
            case .impossible: showImpossibleAlert = true
            }
        } catch { errorMessage = error.userMessage }
    }

    func cancelEviction() {
        pendingInsert = nil
        didCancel = true
    }
}
