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

    var isEditing: Bool { editingExerciseID != nil }
    private var pendingInsert: (@Sendable (OpaquePointer) throws -> Void)?

    /// Non-nil when editing an existing exercise (integer row ID).
    private let editingExerciseID: Int?
    /// Identity of the exercise being edited, preserved so update() targets the same row.
    private var editingClientUUID: UUID?
    private var editingCreatedAt: Date?
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
                try await prefill(exerciseID: exerciseID)
            }

            if let p = try await UserProfileRepository(dbManager: dbManager).get() { maxDataMb = p.maxDataMb }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Populates the form with the existing exercise's values when editing.
    private func prefill(exerciseID: Int) async throws {
        guard let exercise = try await exerciseRepo.get(rowID: exerciseID) else { return }
        name = exercise.name
        abbreviation = exercise.abbreviation
        selectedEquipmentID = exercise.equipmentID
        metricType = exercise.metricType
        notes = exercise.notes ?? ""
        formLink = exercise.formLink ?? ""
        editingClientUUID = exercise.clientUUID
        editingCreatedAt = exercise.createdAt

        let existing = try await exerciseRepo.musclesFor(exerciseID: exercise.clientUUID)
        let roleByMuscleID = Dictionary(uniqueKeysWithValues: existing.map { ($0.0.id, $0.1) })
        muscleSelections = muscleSelections.map { sel in
            var sel = sel
            if let role = roleByMuscleID[sel.muscle.id] {
                sel.isSelected = true
                sel.role = role
            }
            return sel
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedEquipmentID != nil
    }

    func save() async {
        guard isValid else { return }
        // Only http/https form links may be stored; anything else (javascript:,
        // file:, data:, …) would become a code-execution vector the moment the
        // link is rendered as tappable.
        let trimmedLink = formLink.trimmingCharacters(in: .whitespaces)
        if !trimmedLink.isEmpty {
            guard let scheme = URL(string: trimmedLink)?.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                errorMessage = "Form link must be an http or https URL."
                return
            }
        }
        let formLinkValue = trimmedLink.isEmpty ? nil : trimmedLink
        isSaving = true
        defer { isSaving = false }
        do {
            let now = Date()
            let exercise = Exercise(
                id: editingExerciseID ?? 0,
                clientUUID: editingClientUUID ?? UUID(),
                name: name.trimmingCharacters(in: .whitespaces),
                abbreviation: String(abbreviation.prefix(4)).uppercased(),
                equipmentID: selectedEquipmentID ?? 0,
                metricType: metricType,
                isCustom: true,
                notes: notes.isEmpty ? nil : notes,
                formLink: formLinkValue,
                createdAt: editingCreatedAt ?? now,
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
        } catch {
            errorMessage = error.userMessage
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
