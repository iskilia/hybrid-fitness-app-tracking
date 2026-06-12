import XCTest
import SQLite3
@testable import Hybrid

/// Phase 7 (PLAN.md T7.3): "seed 500 fake sessions, confirm < 10 MB".
final class DatabaseSizeTests: XCTestCase {

    func testFiveHundredSessionsUnderTenMegabytes() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-size-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let db = try DatabaseManager(url: tmp)
        let sessions = SessionRepository(dbManager: db)
        let sets = SessionSetRepository(dbManager: db)
        let runs = SessionRunRepository(dbManager: db)

        let bench = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
        let benchRowID = try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM exercise WHERE client_uuid = '\(bench.uuidString.lowercased())';")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }

        for i in 0..<500 {
            let isLift = i % 2 == 0
            let session = try await sessions.start(routineID: nil, type: isLift ? .lift : .run)

            if isLift {
                for n in 1...5 {
                    try await sets.append(SessionSet(
                        id: 0, clientUUID: UUID(),
                        sessionID: session.id, exerciseID: benchRowID,
                        exerciseOrder: 0, setNumber: n,
                        setType: .working,
                        weightKg: 80.0 + Double(n) * 2.5, reps: 5,
                        durationSecs: nil, distanceM: nil,
                        rpe: 8.0, completedAt: Date(),
                        notes: nil, updatedAt: Date()
                    ))
                }
            } else {
                let runUUID = UUID()
                try await runs.append(SessionRun(
                    id: 0, clientUUID: runUUID,
                    sessionID: session.id, runTemplateID: nil,
                    runOrder: 0, actualDistanceKm: nil, durationSecs: nil,
                    avgPaceSecs: nil, avgHR: nil, maxHR: nil,
                    targetHRMin: nil, targetHRMax: nil,
                    notes: nil, updatedAt: Date()
                ))
                try await runs.finish(id: runUUID, distanceKm: 5.0, durationSec: 1800,
                                      avgPaceSecPerKm: 360, avgHrBpm: 150)
            }

            try await sessions.finish(id: session.clientUUID)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: tmp.path)
        let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mb = Double(bytes) / (1024.0 * 1024.0)
        XCTAssertLessThan(mb, 10.0, "500 sessions produced \(String(format: "%.2f", mb)) MB — should be < 10 MB")
    }
}
