import XCTest
import SQLite3
@testable import Hybrid

/// Pass 8 — feedback-3: manual run pace (MM:SS wheel) + delete-all redirect.
@MainActor
final class RunPaceSettingsTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass8-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    private func persistedPace(_ db: DatabaseManager, sessionID: Int) async throws -> Int? {
        try await db.read { handle -> Int? in
            let stmt = try Hybrid.prepare(handle,
                "SELECT avg_pace_secs FROM session_run WHERE session_id = ?;")
            defer { Hybrid.finalize(stmt) }
            Hybrid.bindInt(stmt, 1, sessionID)
            guard try Hybrid.step(stmt) else { return nil }
            return sqlite3_column_type(stmt, 0) != SQLITE_NULL
                ? Int(sqlite3_column_int64(stmt, 0)) : nil
        }
    }

    // MARK: - Item 1: manual pace overrides computed on finish

    func testManualPacePersistsOnFinish() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)
        let session = try await sessionRepo.start(routineID: nil, type: .run)

        let vm = RunActiveSessionViewModel(dbManager: db)
        await vm.start(sessionID: session.clientUUID)

        // Pick 4:35 on the wheels = 275 sec/km
        vm.paceMinutes = 4
        vm.paceSeconds = 35

        await vm.finish()

        let pace = try await persistedPace(db, sessionID: session.id)
        XCTAssertEqual(pace, 275, "manual pace 4:35 must persist as avg_pace_secs = 275")
    }

    // MARK: - Item 1: 0:00 untouched falls back to computed pace

    func testZeroPaceFallsBackToComputed() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)
        let session = try await sessionRepo.start(routineID: nil, type: .run)

        let vm = RunActiveSessionViewModel(dbManager: db)
        await vm.start(sessionID: session.clientUUID)

        // Leave pace at 0:00; drive a computable pace: 600s / 2km = 300 sec/km
        vm.distanceText = "2.0"
        vm.elapsedSec = 600

        await vm.finish()

        let pace = try await persistedPace(db, sessionID: session.id)
        XCTAssertEqual(pace, 300,
            "0:00 manual pace must fall back to the computed pace (600s / 2km = 300)")
    }

    // MARK: - Item 2: delete-all clears logged sessions

    func testDeleteAllHistoryClearsSessions() async throws {
        let db = try makeTempDB()
        let sessionRepo = SessionRepository(dbManager: db)

        let session = try await sessionRepo.start(routineID: nil, type: .run)
        try await sessionRepo.finish(id: session.clientUUID)

        let before = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM session;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertGreaterThan(before, 0, "Precondition: at least one session exists")

        let settingsVM = SettingsViewModel(dbManager: db)
        await settingsVM.deleteAllHistory()

        XCTAssertNil(settingsVM.errorMessage,
            "deleteAllHistory must succeed (no error → view pops to Home)")

        let after = try await db.read { handle -> Int in
            let stmt = try Hybrid.prepare(handle, "SELECT COUNT(*) FROM session;")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        XCTAssertEqual(after, 0, "deleteAllHistory must remove every logged session")
    }
}
