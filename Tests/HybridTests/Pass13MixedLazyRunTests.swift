import XCTest
import SQLite3
@testable import Hybrid

/// PR D — lazy session_run creation (:195) + per-block run duration (:248).
@MainActor
final class Pass13MixedLazyRunTests: XCTestCase {

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass13-\(UUID().uuidString).sqlite")
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
            id: 0, clientUUID: routineUUID, name: "Pass13 Mixed Run",
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

    private func sessionRunCount(_ db: DatabaseManager, sessionID: Int) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM session_run WHERE session_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, sessionID)
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    /// :195 — loading then abandoning (no edits, no done) must NOT create a session_run row.
    func testAbandonLeavesNoSessionRunRows() async throws {
        let db = try makeTempDB()
        let (session, vm) = try await makeMixedRunSession(db)

        let afterLoad = try await sessionRunCount(db, sessionID: session.id)
        XCTAssertEqual(afterLoad, 0, "load() must not eagerly create session_run rows")

        await vm.saveAndExit()   // persistAll on an untouched session

        let afterAbandon = try await sessionRunCount(db, sessionID: session.id)
        XCTAssertEqual(afterAbandon, 0,
            "abandoning an untouched run block must leave no orphan session_run rows")
    }

    /// :248 — duration measured from the block's start is persisted (not 0).
    func testPerBlockDurationPersisted() async throws {
        let db = try makeTempDB()
        let (session, vm) = try await makeMixedRunSession(db)
        guard let runBlock = vm.blocks.first(where: { $0.kind == .run }) else {
            return XCTFail("mixed VM must build a run block")
        }
        runBlock.runDistanceText = "3"
        runBlock.startedAt = Date().addingTimeInterval(-120)   // opened ~2 min ago

        await vm.markRunBlockDone(runBlock)

        let rowCount = try await sessionRunCount(db, sessionID: session.id)
        XCTAssertEqual(rowCount, 1,
            "marking a run block done must create exactly one session_run row")
        let duration = try await db.read { handle -> Int? in
            let stmt = try Hybrid.prepare(handle,
                "SELECT duration_secs FROM session_run WHERE session_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, session.id)
            guard try Hybrid.step(stmt) else { return nil }
            return sqlite3_column_type(stmt, 0) != SQLITE_NULL ? Int(sqlite3_column_int64(stmt, 0)) : nil
        }
        guard let d = duration else { return XCTFail("duration_secs must be persisted") }
        XCTAssertGreaterThanOrEqual(d, 118, "per-block duration must reflect startedAt (~120s)")
        XCTAssertLessThanOrEqual(d, 135, "per-block duration must be bounded near 120s")
    }
}
