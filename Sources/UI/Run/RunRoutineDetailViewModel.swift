import Foundation
import Observation
import SQLite3

// MARK: - RunRoutineDetailViewModel

@Observable
@MainActor
final class RunRoutineDetailViewModel {
    var routine: Routine?
    var entries: [(run: RoutineRun, template: RunTemplate, intervals: [RunIntervalBlock])] = []
    var isLoading = false
    var errorMessage: String?

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
            let runEntries = try await fetchRoutineRuns(routineIntID: r.id)
            var built: [(run: RoutineRun, template: RunTemplate, intervals: [RunIntervalBlock])] = []
            for entry in runEntries {
                let templates = try await templateRepo.listAll()
                guard let tmpl = templates.first(where: { $0.id == entry.runTemplateID }) else { continue }
                let blocks = try await templateRepo.intervals(for: tmpl.clientUUID)
                built.append((run: entry, template: tmpl, intervals: blocks))
            }
            entries = built
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

    // MARK: - Helpers

    var runCount: Int { entries.count }

    private func fetchRoutineRuns(routineIntID: Int) async throws -> [RoutineRun] {
        try await dbManager.read { db in
            let sql = """
                SELECT id, client_uuid, routine_id, run_template_id, sort_order, notes, updated_at
                FROM routine_run
                WHERE routine_id = ?
                ORDER BY sort_order ASC;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, routineIntID)
            var result: [RoutineRun] = []
            while try step(stmt) {
                guard
                    let uuidStr = columnText(stmt, 1),
                    let uuid = UUID(uuidString: uuidStr),
                    let updatedAt = columnDate(stmt, 6)
                else { continue }
                result.append(RoutineRun(
                    id: columnInt(stmt, 0) ?? 0,
                    clientUUID: uuid,
                    routineID: columnInt(stmt, 2) ?? 0,
                    runTemplateID: columnInt(stmt, 3) ?? 0,
                    sortOrder: columnInt(stmt, 4) ?? 0,
                    notes: columnText(stmt, 5),
                    updatedAt: updatedAt
                ))
            }
            return result
        }
    }
}
