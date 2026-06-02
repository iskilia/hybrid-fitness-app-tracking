import Foundation
import Observation
import SQLite3

// MARK: - MuscleSelection

struct MuscleSelection: Identifiable {
    let muscle: Muscle
    var isSelected: Bool
    var role: MuscleRole

    var id: Int { muscle.id }
}

// MARK: - CustomExerciseEditorViewModel

@Observable
@MainActor
final class CustomExerciseEditorViewModel {
    var name: String = ""
    var abbreviation: String = ""
    var selectedEquipmentID: Int? = nil
    var muscleSelections: [MuscleSelection] = []
    var notes: String = ""
    var formLink: String = ""
    var metricType: MetricType = .reps

    var allEquipment: [Equipment] = []
    var isSaving = false
    var isMetricTypeLocked = false
    var errorMessage: String?
    var didSave = false

    var showEvictionConfirm = false
    var showImpossibleAlert = false
    private var pendingInsert: (@Sendable (OpaquePointer) throws -> Void)?

    /// Non-nil when editing an existing exercise (integer row ID).
    private let editingExerciseID: Int?
    private let exerciseRepo: ExerciseRepository
    private let dbManager: DatabaseManager
    private let storageGuard: StorageGuard
    private var maxDataMb: Int = 10

    init(dbManager: DatabaseManager, editingExerciseID: Int? = nil) {
        self.editingExerciseID = editingExerciseID
        self.exerciseRepo = ExerciseRepository(dbManager: dbManager)
        self.dbManager = dbManager
        self.storageGuard = StorageGuard(dbManager: dbManager)
    }

    func load() async {
        do {
            async let equipment = exerciseRepo.listAllEquipment()
            async let muscles = exerciseRepo.listAllMuscles()
            let (eq, mu) = try await (equipment, muscles)
            self.allEquipment = eq
            self.selectedEquipmentID = eq.first?.id
            self.muscleSelections = mu.map { MuscleSelection(muscle: $0, isSelected: false, role: .primary) }

            if let exerciseID = editingExerciseID {
                self.isMetricTypeLocked = try await exerciseRepo.metricTypeLocked(exerciseID: exerciseID)
            }

            if let p = try await UserProfileRepository(dbManager: dbManager).get() { maxDataMb = p.maxDataMb }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedEquipmentID != nil
    }

    func save() async {
        guard isValid else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let now = Date()
            let exercise = Exercise(
                id: editingExerciseID ?? 0,
                clientUUID: UUID(),
                name: name.trimmingCharacters(in: .whitespaces),
                abbreviation: String(abbreviation.prefix(4)).uppercased(),
                equipmentID: selectedEquipmentID ?? 0,
                metricType: metricType,
                isCustom: true,
                notes: notes.isEmpty ? nil : notes,
                formLink: formLink.isEmpty ? nil : formLink,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
            // Encode muscle IDs as UUIDs using last-segment hex convention
            let musclePairs: [(UUID, MuscleRole)] = muscleSelections
                .filter { $0.isSelected }
                .map { sel in
                    let muscleUUID = encodeMuscleID(sel.muscle.id)
                    return (muscleUUID, sel.role)
                }
            if editingExerciseID != nil {
                try await exerciseRepo.update(exercise, muscles: musclePairs)
                didSave = true
                return
            }
            let repo = exerciseRepo
            let insert: @Sendable (OpaquePointer) throws -> Void = { db in
                try repo.insertExerciseWork(db, exercise, muscles: musclePairs)
            }
            let probe = try await storageGuard.probe(insert: insert, maxDataMb: maxDataMb)
            switch probe {
            case .fits:
                try await exerciseRepo.create(exercise, muscles: musclePairs)
                didSave = true
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
            case .fitted:     didSave = true
            case .impossible: showImpossibleAlert = true
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func cancelEviction() {
        pendingInsert = nil
        didSave = true   // Cancel = persist nothing, dismiss the editor
    }

    /// Encodes integer muscle ID as a UUID with the ID in the last 12 hex digits.
    /// Format: "00000000-0000-0000-0000-<paddedHexID>"
    private func encodeMuscleID(_ id: Int) -> UUID {
        let hexID = String(format: "%012x", id)
        let uuidString = "00000000-0000-0000-0000-\(hexID)"
        return UUID(uuidString: uuidString) ?? UUID()
    }
}
