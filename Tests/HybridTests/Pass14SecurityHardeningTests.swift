import XCTest
import SQLite3
@testable import Hybrid

/// F3 — SQLite hardening: no statement may reach another file via ATTACH.
@MainActor
final class Pass14SecurityHardeningTests: XCTestCase {

    private func makeTempDB() throws -> DatabaseManager {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-pass14-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return try DatabaseManager(url: tmp)
    }

    /// ATTACH DATABASE must be denied so a query cannot open another file in the sandbox.
    func testAttachDatabaseIsDenied() async throws {
        let db = try makeTempDB()
        let victimPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-attack-\(UUID().uuidString).sqlite").path

        do {
            try await db.read { handle in
                try Hybrid.execSQL(handle, "ATTACH DATABASE '\(victimPath)' AS evil;")
            }
            XCTFail("ATTACH must be denied")
        } catch {
            // expected — authorizer denies / attach limit is zero
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: victimPath),
            "a denied ATTACH must not create or open any file")
    }

    /// Hardening must not break ordinary parameterized reads on the seeded DB.
    func testNormalQueryStillWorks() async throws {
        let db = try makeTempDB()
        let exercises = try await ExerciseRepository(dbManager: db).listAll()
        XCTAssertFalse(exercises.isEmpty, "seeded exercises must still be readable after hardening")
    }
}
