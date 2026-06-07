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
                // For timed exercises, compute the best (max) duration_secs per completed session.
                let allSets = try await sessionSetRepo.historyByExercise(exerciseID: exerciseID, monthsBack: nil)
                // Group by session and take the max duration per session.
                var bySession: [Int: (date: Date, duration: Int)] = [:]
                for s in allSets {
                    guard let dur = s.durationSecs else { continue }
                    if let existing = bySession[s.sessionID] {
                        if dur > existing.duration {
                            // historyByExercise doesn't expose session date directly; use completedAt as proxy.
                            bySession[s.sessionID] = (date: existing.date, duration: dur)
                        }
                    } else {
                        let date = s.completedAt ?? s.updatedAt
                        bySession[s.sessionID] = (date: date, duration: dur)
                    }
                }
                self.topSets = bySession.values
                    .sorted { $0.date < $1.date }
                    .map { TopSetPoint(date: $0.date, weightKg: 0, reps: 0, durationSecs: $0.duration) }
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
