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
    var runEntries: [(run: RoutineRun, template: RunTemplate, intervals: [RunIntervalBlock])] = []
    var isLoading = false
    var errorMessage: String?
    var lastExecutionSummary: LastExecutionSummary? = nil
    var isLoadingLastExecution: Bool = false

    private let routineRepo: RoutineRepository
    private let exerciseRepo: ExerciseRepository
    private let sessionSetRepo: SessionSetRepository
    private let sessionRepo: SessionRepository
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
        self.routineRepo = RoutineRepository(dbManager: dbManager)
        self.exerciseRepo = ExerciseRepository(dbManager: dbManager)
        self.sessionSetRepo = SessionSetRepository(dbManager: dbManager)
        self.sessionRepo = SessionRepository(dbManager: dbManager)
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

            // Load run entries for mixed routines
            if let routineInt = r?.id {
                let rawRuns = try await routineRepo.runs(routineIntID: routineInt)
                let templateRepo = RunTemplateRepository(dbManager: dbManager)
                let templatesByID = Dictionary(uniqueKeysWithValues: try await templateRepo.listAll().map { ($0.id, $0) })
                var builtRuns: [(run: RoutineRun, template: RunTemplate, intervals: [RunIntervalBlock])] = []
                for entry in rawRuns {
                    guard let tmpl = templatesByID[entry.runTemplateID] else { continue }
                    let blocks = try await templateRepo.intervals(for: tmpl.clientUUID)
                    builtRuns.append((run: entry, template: tmpl, intervals: blocks))
                }
                self.runEntries = builtRuns
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - TV5.2a: Load last execution summary

    func loadLastExecution(routineID: UUID) async {
        isLoadingLastExecution = true
        defer { isLoadingLastExecution = false }
        do {
            // Resolve routine (use already-loaded value if available)
            let r: Routine
            if let loaded = routine {
                r = loaded
            } else {
                guard let fetched = try await routineRepo.get(id: routineID) else {
                    lastExecutionSummary = nil
                    return
                }
                r = fetched
            }

            guard let session = try await sessionRepo.lastCompletedSession(forRoutineID: r.id) else {
                lastExecutionSummary = nil
                return
            }

            let finishedAt = session.finishedAt!
            let totalDurationSecs = Int(finishedAt.timeIntervalSince(session.startedAt))

            // Build the set of exercise integer IDs in the current routine
            let currentExercises = entries.map { $0.exercise }
            let currentExerciseIDs = Set(currentExercises.map { $0.id })

            // Build TopSetLine for each exercise in the current routine
            var lines: [LastExecutionSummary.TopSetLine] = []
            for exercise in currentExercises {
                if let topSet = try await sessionSetRepo.topSet(sessionID: session.id, exerciseID: exercise.id) {
                    lines.append(LastExecutionSummary.TopSetLine(
                        id: exercise.clientUUID,
                        exerciseName: exercise.name,
                        display: formatTopSet(topSet, metricType: exercise.metricType),
                        removed: false
                    ))
                }
            }

            // Detect removed exercises: iterate all exercises, find those with a top set
            // in this session but not in the current routine
            let allExercises = try await exerciseRepo.listAll()
            for exercise in allExercises where !currentExerciseIDs.contains(exercise.id) {
                if let topSet = try await sessionSetRepo.topSet(sessionID: session.id, exerciseID: exercise.id) {
                    lines.append(LastExecutionSummary.TopSetLine(
                        id: exercise.clientUUID,
                        exerciseName: exercise.name,
                        display: formatTopSet(topSet, metricType: exercise.metricType),
                        removed: true
                    ))
                }
            }

            lastExecutionSummary = LastExecutionSummary(
                sessionID: session.clientUUID,
                finishedAt: finishedAt,
                totalDurationSecs: totalDurationSecs,
                topSets: lines
            )
        } catch {
            errorMessage = error.localizedDescription
            lastExecutionSummary = nil
        }
    }

    // MARK: - Private helpers

    private func formatTopSet(_ set: SessionSet, metricType: MetricType) -> String {
        switch metricType {
        case .reps, .repsBodyweight:
            return "× \(set.reps ?? 0)"
        case .time:
            return "\(set.durationSecs ?? 0)s"
        case .distance:
            let mDouble = set.distanceM ?? 0
            let m = Int(mDouble)
            return m >= 1000 ? String(format: "%.2f km", mDouble / 1000.0) : "\(m) m"
        }
    }
}
