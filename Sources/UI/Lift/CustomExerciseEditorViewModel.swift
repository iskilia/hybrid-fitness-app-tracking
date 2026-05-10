import Foundation
import Observation

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
    var errorMessage: String?
    var didSave = false

    private let exerciseRepo: ExerciseRepository

    init(dbManager: DatabaseManager) {
        self.exerciseRepo = ExerciseRepository(dbManager: dbManager)
    }

    func load() async {
        do {
            async let equipment = exerciseRepo.listAllEquipment()
            async let muscles = exerciseRepo.listAllMuscles()
            let (eq, mu) = try await (equipment, muscles)
            self.allEquipment = eq
            self.selectedEquipmentID = eq.first?.id
            self.muscleSelections = mu.map { MuscleSelection(muscle: $0, isSelected: false, role: .primary) }
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
                id: 0,
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
            try await exerciseRepo.create(exercise, muscles: musclePairs)
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Encodes integer muscle ID as a UUID with the ID in the last 12 hex digits.
    /// Format: "00000000-0000-0000-0000-<paddedHexID>"
    private func encodeMuscleID(_ id: Int) -> UUID {
        let hexID = String(format: "%012x", id)
        let uuidString = "00000000-0000-0000-0000-\(hexID)"
        return UUID(uuidString: uuidString) ?? UUID()
    }
}
