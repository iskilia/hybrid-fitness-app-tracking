import XCTest
import SQLite3
@testable import Hybrid

/// PR E — de-SQL RunRoutineDetailViewModel: covers the repository methods that replaced
/// the VM's raw SQL (RoutineRepository.addRun, SessionRunRepository.templateIDs).
@MainActor
final class RunRoutineRepositoryTests: XCTestCase {

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass11-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    private func anyRunTemplateID(_ db: DatabaseManager) async throws -> Int {
        let templates = try await RunTemplateRepository(dbManager: db).listAll()
        guard let first = templates.first else { throw DatabaseError.notFound }
        return first.id
    }

    func testAddRunAppendsRoutineRun() async throws {
        let db = try makeTempDB()
        let routineRepo = RoutineRepository(dbManager: db)
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "Pass11 AddRun",
            type: .run, sortOrder: 1, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routineRepo.create(routine, exerciseEntries: [], runEntries: [])
        guard let saved = try await routineRepo.get(id: routineUUID) else {
            return XCTFail("routine must persist")
        }

        let tmplID = try await anyRunTemplateID(db)
        let run = RoutineRun(
            id: 0, clientUUID: UUID(), routineID: saved.id,
            runTemplateID: tmplID, sortOrder: 1, notes: nil, updatedAt: now
        )
        try await routineRepo.addRun(run)

        let runs = try await routineRepo.runs(routineIntID: saved.id)
        XCTAssertEqual(runs.count, 1, "addRun must append one routine_run row")
        XCTAssertEqual(runs.first?.runTemplateID, tmplID)
    }

    func testTemplateIDsForSession() async throws {
        let db = try makeTempDB()
        let session = try await SessionRepository(dbManager: db).start(routineID: nil, type: .run)
        let sessionRunRepo = SessionRunRepository(dbManager: db)
        let tmplID = try await anyRunTemplateID(db)

        let run = SessionRun(
            id: 0, clientUUID: UUID(), sessionID: session.id,
            runTemplateID: tmplID, runOrder: 1,
            actualDistanceKm: nil, durationSecs: nil, avgPaceSecs: nil,
            avgHR: nil, maxHR: nil, targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: Date()
        )
        try await sessionRunRepo.append(run)

        let ids = try await sessionRunRepo.templateIDs(forSession: session.id)
        XCTAssertEqual(ids, [tmplID], "templateIDs must return the recorded run's template id")
    }

    /// Locks the removed-slot Set semantics the VM relies on: `templateIDs` preserves
    /// duplicates when a template appears twice, and `Set(...).subtracting(current)`
    /// collapses them — reporting the slot removed iff it's absent from today's routine.
    func testTemplateIDsDedupRemovedSlot() async throws {
        let db = try makeTempDB()
        let session = try await SessionRepository(dbManager: db).start(routineID: nil, type: .run)
        let sessionRunRepo = SessionRunRepository(dbManager: db)
        let tmplID = try await anyRunTemplateID(db)

        for order in 1...2 {
            try await sessionRunRepo.append(SessionRun(
                id: 0, clientUUID: UUID(), sessionID: session.id,
                runTemplateID: tmplID, runOrder: order,
                actualDistanceKm: nil, durationSecs: nil, avgPaceSecs: nil,
                avgHR: nil, maxHR: nil, targetHRMin: nil, targetHRMax: nil,
                notes: nil, updatedAt: Date()
            ))
        }

        let ids = try await sessionRunRepo.templateIDs(forSession: session.id)
        XCTAssertEqual(ids.count, 2, "templateIDs must preserve duplicate template rows")

        // Template absent from today's routine → exactly one removed slot.
        XCTAssertEqual(Set(ids).subtracting([]), [tmplID],
            "Set.subtracting must collapse duplicates to a single removed slot")
        // Template still present today → not reported removed.
        XCTAssertTrue(Set(ids).subtracting([tmplID]).isEmpty,
            "a template still in the routine must not be flagged removed")
    }
}
