import XCTest
import SQLite3
@testable import Hybrid

/// PR C — mixed run-block pace via the MM:SS wheel (replaces the free-text field).
@MainActor
final class Pass12MixedPaceTests: XCTestCase {

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass12-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    private func anyRunTemplateID(_ db: DatabaseManager) async throws -> Int {
        let templates = try await RunTemplateRepository(dbManager: db).listAll()
        guard let first = templates.first else { throw DatabaseError.notFound }
        return first.id
    }

    private func makeMixedRunSession(_ db: DatabaseManager) async throws -> (session: Session, vm: MixedActiveSessionViewModel) {
        let routineRepo = RoutineRepository(dbManager: db)
        let tmplID = try await anyRunTemplateID(db)
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID, name: "Pass12 Mixed Run",
            type: .mixed, sortOrder: 1, createdAt: now, updatedAt: now, deletedAt: nil
        )
        let run = RoutineRun(
            id: 0, clientUUID: UUID(), routineID: 0,
            runTemplateID: tmplID, sortOrder: 1, notes: nil, updatedAt: now
        )
        try await routineRepo.create(routine, exerciseEntries: [], runEntries: [run])

        let session = try await SessionRepository(dbManager: db).start(routineID: routineUUID, type: .mixed)
        let vm = MixedActiveSessionViewModel(sessionID: session.clientUUID, dbManager: db)
        await vm.load()
        return (session, vm)
    }

    private func persistedPace(_ db: DatabaseManager, sessionID: Int) async throws -> Int? {
        try await db.read { handle -> Int? in
            let stmt = try Hybrid.prepare(handle,
                "SELECT avg_pace_secs FROM session_run WHERE session_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, sessionID)
            guard try Hybrid.step(stmt) else { return nil }
            return sqlite3_column_type(stmt, 0) != SQLITE_NULL ? Int(sqlite3_column_int64(stmt, 0)) : nil
        }
    }

    func testWheelPacePersists() async throws {
        let db = try makeTempDB()
        let (session, vm) = try await makeMixedRunSession(db)
        guard let runBlock = vm.blocks.first(where: { $0.kind == .run }) else {
            return XCTFail("mixed VM must build a run block")
        }
        runBlock.paceMinutes = 4
        runBlock.paceSeconds = 35
        await vm.markRunBlockDone(runBlock)

        let pace = try await persistedPace(db, sessionID: session.id)
        XCTAssertEqual(pace, 275, "wheel pace 4:35 must persist as avg_pace_secs = 275")
    }

    func testZeroPacePersistsNil() async throws {
        let db = try makeTempDB()
        let (session, vm) = try await makeMixedRunSession(db)
        guard let runBlock = vm.blocks.first(where: { $0.kind == .run }) else {
            return XCTFail("mixed VM must build a run block")
        }
        runBlock.runDistanceText = "5"   // some data, but pace untouched at 0:00
        await vm.markRunBlockDone(runBlock)

        let pace = try await persistedPace(db, sessionID: session.id)
        XCTAssertNil(pace, "0:00 pace must persist as NULL avg_pace_secs")
    }
}
