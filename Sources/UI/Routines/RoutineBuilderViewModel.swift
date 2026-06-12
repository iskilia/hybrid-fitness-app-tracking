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

    init(exercise: Exercise) {
        self.exercise = exercise
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

    private let routineRepo: RoutineRepository
    private let storageGuard: StorageGuard
    private let profileRepo: UserProfileRepository
    let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
        self.routineRepo = RoutineRepository(dbManager: dbManager)
        self.storageGuard = StorageGuard(dbManager: dbManager)
        self.profileRepo = UserProfileRepository(dbManager: dbManager)
    }

    func load() async {
        if let p = try? await profileRepo.get() { maxDataMb = p.maxDataMb }
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
            RoutineExercise(
                id: 0,
                clientUUID: UUID(),
                routineID: 0,
                exerciseID: entry.exercise.id,
                sortOrder: index + 1,
                targetSets: entry.targetSets,
                targetRepMin: entry.targetRepMin,
                targetRepMax: entry.targetRepMax,
                targetRPE: nil,
                targetDurationSecsMin: nil,
                targetDurationSecsMax: nil,
                notes: nil,
                updatedAt: now
            )
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
        } catch let dbErr as DatabaseError {
            if case .conflict(let msg) = dbErr {
                errorMessage = msg
            } else {
                errorMessage = dbErr.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
        } catch { errorMessage = error.localizedDescription }
    }

    func cancelEviction() {
        pendingInsert = nil
        didCancel = true
    }
}
