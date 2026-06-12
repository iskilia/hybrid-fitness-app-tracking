import Observation
import Foundation

@Observable
@MainActor
final class HomeViewModel {
    var stats: WeekStats?
    var routines: [Routine] = []
    // Set when load() fails; surfaced to the user via an alert in HomeView.
    var errorMessage: String?
    // Maps routine integer ID -> last performed date (nil = never)
    var lastPerformed: [Int: Date] = [:]
    // Maps routine integer ID -> (exerciseCount, runCount)
    var summaries: [Int: (exerciseCount: Int, runCount: Int)] = [:]

    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    func load() async {
        let routinesRepo = RoutineRepository(dbManager: dbManager)
        let sessionsRepo = SessionRepository(dbManager: dbManager)
        let weekStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        ) ?? .now

        do {
            let loaded = try await routinesRepo.list()
            self.routines = loaded
            self.stats = try await sessionsRepo.weekStats(weekStart: weekStart)

            // Load last-performed dates and summaries for each routine
            let allSessions = try await sessionsRepo.list(
                from: Date(timeIntervalSince1970: 0),
                to: .now
            )
            var lastMap: [Int: Date] = [:]
            for session in allSessions where session.status == .completed {
                if let rID = session.routineID {
                    if let existing = lastMap[rID] {
                        if session.startedAt > existing { lastMap[rID] = session.startedAt }
                    } else {
                        lastMap[rID] = session.startedAt
                    }
                }
            }
            self.lastPerformed = lastMap

            var sumMap: [Int: (exerciseCount: Int, runCount: Int)] = [:]
            for routine in loaded {
                let s = try await routinesRepo.summary(routineID: routine.clientUUID)
                sumMap[routine.id] = s
            }
            self.summaries = sumMap
        } catch {
            // Leave previous state on error; surface a reportable message to the user.
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived helpers

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 0..<12: return "Today, good morning."
        case 12..<17: return "Today, good afternoon."
        default:     return "Today, good evening."
        }
    }

    func lastPerformedText(for routine: Routine) -> String {
        guard let date = lastPerformed[routine.id] else { return "NEVER" }
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        switch days {
        case 0:       return "TODAY"
        case 1:       return "YESTERDAY"
        default:      return "\(days) DAYS AGO"
        }
    }

    func subtitleText(for routine: Routine) -> String {
        guard let s = summaries[routine.id] else { return "" }
        switch routine.type {
        case .lift:
            return s.exerciseCount == 1 ? "1 EXERCISE" : "\(s.exerciseCount) EXERCISES"
        case .run:
            return s.runCount == 1 ? "1 RUN" : "\(s.runCount) RUNS"
        case .mixed:
            let exPart = s.exerciseCount == 1 ? "1 EXERCISE" : "\(s.exerciseCount) EXERCISES"
            let runPart = s.runCount == 1 ? "1 RUN" : "\(s.runCount) RUNS"
            return "\(exPart) · \(runPart)"
        }
    }

    var sessionCount: String {
        "\(stats?.sessionCount ?? 0)"
    }
}
