import Foundation
import Observation

// MARK: - LiftRoutineDetailEntry

struct LiftRoutineDetailEntry: Identifiable, Sendable {
    let id: Int   // RoutineExercise.id
    let routineExercise: RoutineExercise
    let exercise: Exercise
    let equipment: Equipment?
    let primaryMuscle: Muscle?
    let lastWeightKg: Double?
}

// MARK: - LiftRoutineDetailViewModel

@Observable
@MainActor
final class LiftRoutineDetailViewModel {
    var routine: Routine?
    var entries: [LiftRoutineDetailEntry] = []
    var isLoading = false
    var errorMessage: String?

    private let routineRepo: RoutineRepository
    private let exerciseRepo: ExerciseRepository
    private let sessionSetRepo: SessionSetRepository

    init(dbManager: DatabaseManager) {
        self.routineRepo = RoutineRepository(dbManager: dbManager)
        self.exerciseRepo = ExerciseRepository(dbManager: dbManager)
        self.sessionSetRepo = SessionSetRepository(dbManager: dbManager)
    }

    func load(routineID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await routineRepo.get(id: routineID)
            self.routine = r

            let routineExercises = try await routineRepo.listExercises(routineID: routineID)
            let allExercises = try await exerciseRepo.listAll()
            let exerciseByID = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })

            let allEquipment = try await exerciseRepo.listAllEquipment()
            let equipmentByID = Dictionary(uniqueKeysWithValues: allEquipment.map { ($0.id, $0) })

            var built: [LiftRoutineDetailEntry] = []
            for re in routineExercises {
                guard let exercise = exerciseByID[re.exerciseID] else { continue }
                let equipment = equipmentByID[exercise.equipmentID]

                // Load muscle data for this exercise via musclesFor
                let muscleRoles = try await exerciseRepo.musclesFor(exerciseID: exercise.clientUUID)
                let primaryMuscle = muscleRoles.first(where: { $0.1 == .primary })?.0
                    ?? muscleRoles.first?.0

                // Last session top set weight for this exercise
                let topSets = try await sessionSetRepo.topSetPerSession(exerciseID: exercise.clientUUID, limit: 1)
                let lastWeightKg = topSets.first?.weightKg

                built.append(LiftRoutineDetailEntry(
                    id: re.id,
                    routineExercise: re,
                    exercise: exercise,
                    equipment: equipment,
                    primaryMuscle: primaryMuscle,
                    lastWeightKg: lastWeightKg
                ))
            }
            self.entries = built
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
