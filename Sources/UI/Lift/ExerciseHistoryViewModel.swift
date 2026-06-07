import Foundation
import Observation

// MARK: - TopSetPoint

struct TopSetPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let weightKg: Double
    let reps: Int
    let durationSecs: Int?
}

// MARK: - ExerciseHistoryViewModel

@Observable
@MainActor
final class ExerciseHistoryViewModel {
    var exercise: Exercise?
    var topSets: [TopSetPoint] = []
    var errorMessage: String?

    private let exerciseID: UUID
    private let exerciseRepo: ExerciseRepository
    private let sessionSetRepo: SessionSetRepository

    init(exerciseID: UUID, dbManager: DatabaseManager) {
        self.exerciseID     = exerciseID
        self.exerciseRepo   = ExerciseRepository(dbManager: dbManager)
        self.sessionSetRepo = SessionSetRepository(dbManager: dbManager)
    }

    func load() async {
        do {
            self.exercise = try await exerciseRepo.get(id: exerciseID)

            if exercise?.metricType == .time {
                // Best duration per completed session, dated on the session's started_at.
                let raw = try await sessionSetRepo.topDurationPerSession(exerciseID: exerciseID, limit: nil)
                // topDurationPerSession returns newest first; reverse for chronological chart display.
                self.topSets = raw.reversed().map {
                    TopSetPoint(date: $0.sessionDate, weightKg: 0, reps: 0, durationSecs: $0.durationSecs)
                }
            } else {
                let raw = try await sessionSetRepo.topSetPerSession(exerciseID: exerciseID, limit: nil)
                // topSetPerSession returns newest first; reverse for chronological chart display
                self.topSets = raw.reversed().map {
                    TopSetPoint(date: $0.sessionDate, weightKg: $0.weightKg, reps: $0.reps, durationSecs: nil)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
