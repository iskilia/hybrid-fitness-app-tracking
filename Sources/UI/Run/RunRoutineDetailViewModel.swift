import Foundation
import Observation

// MARK: - RunRoutineDetailViewModel

@Observable
@MainActor
final class RunRoutineDetailViewModel {
    var routine: Routine?
    var entries: [(run: RoutineRun, template: RunTemplate, intervals: [RunIntervalBlock])] = []
    var isLoading = false
    var errorMessage: String?
    var lastExecutionSummary: LastExecutionSummary? = nil
    var isLoadingLastExecution: Bool = false

    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Load

    func load(routineID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let routineRepo = RoutineRepository(dbManager: dbManager)
            routine = try await routineRepo.get(id: routineID)

            guard let r = routine else { return }

            let templateRepo = RunTemplateRepository(dbManager: dbManager)
            let runEntries = try await routineRepo.runs(routineIntID: r.id)
            let templatesByID = Dictionary(uniqueKeysWithValues: try await templateRepo.listAll().map { ($0.id, $0) })
            var built: [(run: RoutineRun, template: RunTemplate, intervals: [RunIntervalBlock])] = []
            for entry in runEntries {
                guard let tmpl = templatesByID[entry.runTemplateID] else { continue }
                let blocks = try await templateRepo.intervals(for: tmpl.clientUUID)
                built.append((run: entry, template: tmpl, intervals: blocks))
            }
            entries = built
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add run

    func addRun(_ template: RunTemplate, routineID: UUID) async {
        guard let r = routine else { return }
        let now = Date()
        let newRun = RoutineRun(
            id: 0,
            clientUUID: UUID(),
            routineID: r.id,
            runTemplateID: template.id,
            sortOrder: entries.count + 1,
            notes: nil,
            updatedAt: now
        )
        do {
            try await RoutineRepository(dbManager: dbManager).addRun(newRun)
            await load(routineID: routineID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Start session

    func startSession(routineID: UUID) async -> UUID? {
        do {
            let repo = SessionRepository(dbManager: dbManager)
            let session = try await repo.start(routineID: routineID, type: .run)
            return session.clientUUID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - TV5.2b: Load last execution summary

    func loadLastExecution(routineID: UUID) async {
        isLoadingLastExecution = true
        defer { isLoadingLastExecution = false }
        do {
            // Resolve routine (use already-loaded value if available)
            let r: Routine
            if let loaded = routine {
                r = loaded
            } else {
                let routineRepo = RoutineRepository(dbManager: dbManager)
                guard let fetched = try await routineRepo.get(id: routineID) else {
                    lastExecutionSummary = nil
                    return
                }
                r = fetched
            }

            let sessionRepo = SessionRepository(dbManager: dbManager)
            guard let session = try await sessionRepo.lastCompletedSession(forRoutineID: r.id) else {
                lastExecutionSummary = nil
                return
            }

            let finishedAt = session.finishedAt!
            let totalDurationSecs = Int(finishedAt.timeIntervalSince(session.startedAt))

            let sessionRunRepo = SessionRunRepository(dbManager: dbManager)

            // Build TopSetLine for each slot in the current routine order
            var lines: [LastExecutionSummary.TopSetLine] = []
            let currentTemplateIDs = Set(entries.map { $0.template.id })

            for entry in entries {
                if let sessionRun = try await sessionRunRepo.bestRunForSlot(
                    sessionID: session.id,
                    templateID: entry.template.id
                ) {
                    lines.append(LastExecutionSummary.TopSetLine(
                        id: entry.run.clientUUID,
                        exerciseName: entry.template.name,
                        display: formatRunSummary(sessionRun, runType: entry.template.runType),
                        removed: false
                    ))
                }
            }

            // Detect removed slots: find template IDs in the prior session not in today's routine
            let priorTemplateIDs = try await sessionRunRepo.templateIDs(forSession: session.id)
            let removedTemplateIDs = Set(priorTemplateIDs).subtracting(currentTemplateIDs)
            if !removedTemplateIDs.isEmpty {
                let templateRepo = RunTemplateRepository(dbManager: dbManager)
                let allTemplates = try await templateRepo.listAll()
                let templateByID = Dictionary(uniqueKeysWithValues: allTemplates.map { ($0.id, $0) })

                for templateID in removedTemplateIDs {
                    guard let tmpl = templateByID[templateID] else { continue }
                    if let sessionRun = try await sessionRunRepo.bestRunForSlot(
                        sessionID: session.id,
                        templateID: templateID
                    ) {
                        lines.append(LastExecutionSummary.TopSetLine(
                            id: sessionRun.clientUUID,
                            exerciseName: tmpl.name,
                            display: formatRunSummary(sessionRun, runType: tmpl.runType),
                            removed: true
                        ))
                    }
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

    // MARK: - Helpers

    var runCount: Int { entries.count }

    private func formatRunSummary(_ r: SessionRun, runType: RunType) -> String {
        func hms(_ secs: Int) -> String {
            let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
            return h > 0
                ? String(format: "%d:%02d:%02d", h, m, s)
                : String(format: "%02d:%02d", m, s)
        }
        func paceFormatted(_ secsPerKm: Int) -> String {
            let m = secsPerKm / 60, s = secsPerKm % 60
            return String(format: "%d'%02d\"/km", m, s)
        }

        let isDistance: Bool = {
            switch runType {
            case .steady, .threshold, .endurance, .recovery: return true
            case .intervals, .fartlek: return false
            }
        }()

        if r.durationSecs == nil && r.avgPaceSecs == nil {
            return "\(hms(r.durationSecs ?? 0)) · pace not recorded"
        }
        if isDistance {
            var parts: [String] = []
            if let d = r.actualDistanceKm { parts.append(String(format: "%.2f km", d)) }
            if let dur = r.durationSecs { parts.append(hms(dur)) }
            if let pace = r.avgPaceSecs { parts.append(paceFormatted(pace)) }
            if let hr = r.avgHR { parts.append("avg \(hr) bpm") }
            return parts.joined(separator: " · ")
        } else {
            var parts: [String] = []
            if let dur = r.durationSecs { parts.append(hms(dur)) }
            if let pace = r.avgPaceSecs { parts.append("avg \(paceFormatted(pace))") }
            if let hr = r.avgHR { parts.append("avg \(hr) bpm") }
            return parts.isEmpty ? hms(r.durationSecs ?? 0) : parts.joined(separator: " · ")
        }
    }

}
