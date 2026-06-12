import Foundation
import Observation

// MARK: - ExerciseLibraryViewModel

@Observable
@MainActor
final class ExerciseLibraryViewModel {
    var exercises: [Exercise] = []
    var allEquipment: [Equipment] = []
    var allMuscles: [Muscle] = []

    /// Per-exercise lookup maps loaded with the full list.
    var equipmentByExerciseID: [Int: Equipment] = [:]
    var musclesByExerciseID: [Int: [Muscle]] = [:]

    var searchQuery: String = ""
    var selectedEquipmentCode: String? = nil
    var selectedMuscleGroup: String? = nil

    private let exerciseRepo: ExerciseRepository

    init(dbManager: DatabaseManager) {
        self.exerciseRepo = ExerciseRepository(dbManager: dbManager)
    }

    func load() async {
        do {
            async let fetchedExercises = exerciseRepo.listAll()
            async let fetchedEquipment = exerciseRepo.listAllEquipment()
            async let fetchedMuscles = exerciseRepo.listAllMuscles()

            let (exList, eqList, muList) = try await (fetchedExercises, fetchedEquipment, fetchedMuscles)
            self.exercises = exList
            self.allEquipment = eqList
            self.allMuscles = muList

            // Build equipment map from exercise.equipmentID
            let eqByID = Dictionary(uniqueKeysWithValues: eqList.map { ($0.id, $0) })
            self.equipmentByExerciseID = Dictionary(
                uniqueKeysWithValues: exList.compactMap { ex -> (Int, Equipment)? in
                    guard let eq = eqByID[ex.equipmentID] else { return nil }
                    return (ex.id, eq)
                }
            )
        } catch {
            // Silently fail — view shows empty state
        }
    }

    /// Permanently deletes a custom exercise and all its associated data, then reloads.
    func delete(_ exercise: Exercise) async {
        do {
            try await exerciseRepo.hardDelete(id: exercise.clientUUID)
            musclesByExerciseID[exercise.id] = nil
            await load()
        } catch {
            // Silently fail — list stays unchanged
        }
    }

    /// Loads muscle associations for a batch of exercises (called lazily or on demand).
    func loadMuscles(for exercise: Exercise) async {
        guard musclesByExerciseID[exercise.id] == nil else { return }
        do {
            let pairs = try await exerciseRepo.musclesFor(exerciseID: exercise.clientUUID)
            musclesByExerciseID[exercise.id] = pairs.map { $0.0 }
        } catch {}
    }

    // MARK: - Distinct muscle groups (for filter chips)

    var distinctMuscleGroups: [String] {
        let groups = allMuscles.map { $0.groupName }
        var seen = Set<String>()
        return groups.filter { seen.insert($0).inserted }
    }

    // MARK: - Equipment codes (for filter chips)

    var distinctEquipmentCodes: [String] {
        let codes = allEquipment.map { $0.code }
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    // MARK: - Filtered list

    var filteredExercises: [Exercise] {
        exercises.filter { exercise in
            let matchesSearch: Bool
            if searchQuery.isEmpty {
                matchesSearch = true
            } else {
                let q = searchQuery.lowercased()
                matchesSearch = exercise.name.lowercased().contains(q)
                    || exercise.abbreviation.lowercased().contains(q)
            }

            let matchesEquipment: Bool
            if let code = selectedEquipmentCode {
                matchesEquipment = equipmentByExerciseID[exercise.id]?.code == code
            } else {
                matchesEquipment = true
            }

            let matchesMuscleGroup: Bool
            if let group = selectedMuscleGroup {
                let muscles = musclesByExerciseID[exercise.id] ?? []
                matchesMuscleGroup = muscles.contains { $0.groupName == group }
            } else {
                matchesMuscleGroup = true
            }

            return matchesSearch && matchesEquipment && matchesMuscleGroup
        }
    }
}
