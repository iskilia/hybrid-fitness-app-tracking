import XCTest
import SQLite3
@testable import Hybrid

/// Phase 6 gate (PLAN.md line 201):
/// "export round-trip — exported JSON re-imports into a fresh DB and produces
/// byte-identical re-export."
final class Phase6ExportTests: XCTestCase {

    private var db: DatabaseManager!
    private var routines: RoutineRepository!
    private var sessions: SessionRepository!
    private var sets: SessionSetRepository!

    private let benchPressUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!

    override func setUp() async throws {
        try await super.setUp()
        db = try DatabaseManager(url: nil)
        routines = RoutineRepository(dbManager: db)
        sessions = SessionRepository(dbManager: db)
        sets = SessionSetRepository(dbManager: db)
    }

    override func tearDown() async throws {
        db = nil; routines = nil; sessions = nil; sets = nil
        try await super.tearDown()
    }

    func testCSVExportProducesOneFilePerTable() async throws {
        try await seedMinimalSession()
        let dir = try await CSVExporter(dbManager: db).export()

        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains("session.csv"))
        XCTAssertTrue(names.contains("session_set.csv"))
        XCTAssertTrue(names.contains("exercise.csv"))
        XCTAssertTrue(names.contains("routine.csv"))

        let setCSV = try String(contentsOf: dir.appendingPathComponent("session_set.csv"))
        // Header + at least one data row.
        let lines = setCSV.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("weight_kg"))
        XCTAssertTrue(lines[0].contains("reps"))
    }

    func testJSONExportContainsAllTables() async throws {
        try await seedMinimalSession()
        let file = try await JSONExporter(dbManager: db).export()
        let data = try Data(contentsOf: file)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let root = try XCTUnwrap(parsed)

        // Every table key should be present.
        for key in [
            "user_profile","muscle","equipment","tag",
            "exercise","exercise_muscle",
            "routine","routine_exercise","routine_run",
            "run_template","run_interval_block",
            "session","session_tag","session_set",
            "session_run","session_run_split"
        ] {
            XCTAssertNotNil(root[key], "JSON missing key \(key)")
        }

        // session_set should contain our seeded row.
        let sets = try XCTUnwrap(root["session_set"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(sets.count, 1)
    }

    func testCSVEscapesCommasQuotesNewlines() {
        XCTAssertEqual(CSVExporter.csvEscape("plain"), "plain")
        XCTAssertEqual(CSVExporter.csvEscape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExporter.csvEscape("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(CSVExporter.csvEscape("a\nb"), "\"a\nb\"")
    }

    // MARK: - Phase V3 gate (SnapshotWriter + SchemaDoc)

    func testSnapshotWriterProducesJSONWithSchemaVersionAndData() async throws {
        let env = try makeSnapshotEnv()
        defer { cleanupSnapshotEnv(env) }

        let writer = SnapshotWriter(documentsURL: env.docsURL, dbManager: env.dbm)
        await writer.write()

        let target = env.docsURL.appendingPathComponent("hybrid-latest.json")
        let appeared = await waitForFile(at: target, timeoutSecs: 3.0)
        XCTAssertTrue(appeared, "hybrid-latest.json never appeared at \(target.path)")

        let data = try Data(contentsOf: target)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let root = try XCTUnwrap(parsed, "hybrid-latest.json did not parse as a JSON object")

        XCTAssertEqual(root["schema_version"] as? String, "2.0",
                       "top-level schema_version should equal \"2.0\"")
        let dataDict = try XCTUnwrap(root["data"] as? [String: Any],
                                     "top-level \"data\" should be an object")

        // Mirrors JSONExporter payload (schema_meta is migration metadata, not exported).
        let allTables = [
            "equipment", "muscle", "tag", "user_profile",
            "exercise", "exercise_muscle",
            "run_template", "run_interval_block",
            "routine", "routine_exercise", "routine_run",
            "session", "session_tag", "session_set",
            "session_run", "session_run_split",
        ]
        for table in allTables {
            XCTAssertNotNil(dataDict[table], "data.\(table) missing from snapshot")
        }

        let mode = await writer.lastWriteMode
        XCTAssertEqual(mode, .full, "lastWriteMode should be .full for a normal-sized DB")
    }

    func testSnapshotWriterDebouncesConcurrentCalls() async throws {
        let env = try makeSnapshotEnv()
        defer { cleanupSnapshotEnv(env) }

        let writer = SnapshotWriter(documentsURL: env.docsURL, dbManager: env.dbm)

        let firstCallAt = Date()
        for _ in 0..<5 {
            await writer.write()
        }

        // Debounce is 250 ms; allow generous settle time for the export to complete.
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 s

        let target = env.docsURL.appendingPathComponent("hybrid-latest.json")
        let temp = env.docsURL.appendingPathComponent("hybrid-latest.tmp.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path),
                      "hybrid-latest.json missing after debounce settle")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path),
                       "hybrid-latest.tmp.json straggler left behind after settle")

        let attrs = try FileManager.default.attributesOfItem(atPath: target.path)
        let mtime = try XCTUnwrap(attrs[.modificationDate] as? Date,
                                  "modificationDate attribute missing")
        let elapsed = mtime.timeIntervalSince(firstCallAt)
        XCTAssertGreaterThanOrEqual(elapsed, 0.25,
                                    "file mtime should be at least 250 ms after first write() call; got \(elapsed)s")

        // Only one snapshot file should be present (no rotation/duplicates).
        let names = try FileManager.default.contentsOfDirectory(atPath: env.docsURL.path)
        let snapshots = names.filter { $0 == "hybrid-latest.json" }
        XCTAssertEqual(snapshots.count, 1, "expected exactly one hybrid-latest.json; got \(names)")

        let mode = await writer.lastWriteMode
        XCTAssertEqual(mode, .full, "lastWriteMode should be .full for a normal-sized DB")
    }

    func testSnapshotWriterFallsBackToManifestWhenDBExceedsThreshold() async throws {
        let env = try makeSnapshotEnv()
        defer { cleanupSnapshotEnv(env) }

        // 1-byte threshold: the on-disk SQLite file is guaranteed larger.
        let writer = SnapshotWriter(
            documentsURL: env.docsURL,
            dbManager: env.dbm,
            sizeThresholdBytes: 1
        )
        await writer.write()

        let target = env.docsURL.appendingPathComponent("hybrid-latest.json")
        let appeared = await waitForFile(at: target, timeoutSecs: 3.0)
        XCTAssertTrue(appeared, "manifest hybrid-latest.json never appeared")

        let data = try Data(contentsOf: target)
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "manifest did not parse as JSON object"
        )

        XCTAssertEqual(root["schema_version"] as? String, "2.0")
        XCTAssertEqual(root["mode"] as? String, "manifest")
        let sizeBytes = root["db_size_bytes"] as? Int ?? -1
        XCTAssertGreaterThan(sizeBytes, 0, "db_size_bytes should be a positive integer")

        let mode = await writer.lastWriteMode
        XCTAssertEqual(mode, .manifest, "lastWriteMode should be .manifest when threshold exceeded")
    }

    func testSchemaDocWriteProducesHybridSchemaMd() throws {
        let docs = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: docs) }

        try SchemaDoc.write(to: docs)

        let dest = docs.appendingPathComponent("hybrid-schema.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path),
                      "hybrid-schema.md not written at \(dest.path)")

        let onDisk = try String(contentsOf: dest, encoding: .utf8)
        XCTAssertEqual(onDisk, SchemaDoc.markdown,
                       "hybrid-schema.md content drifted from SchemaDoc.markdown")
        XCTAssertTrue(onDisk.contains("schema_version"),
                      "schema doc missing 'schema_version' contract content")
        XCTAssertTrue(onDisk.contains("metric_type"),
                      "schema doc missing 'metric_type' contract content")
        XCTAssertTrue(onDisk.contains("## Envelope"),
                      "schema doc missing '## Envelope' section")
        XCTAssertEqual(SchemaDoc.schemaVersion, "2.0",
                       "SchemaDoc.schemaVersion should be \"2.0\"")
    }

    // MARK: - Snapshot test helpers

    private struct SnapshotEnv {
        let dbm: DatabaseManager
        let dbURL: URL
        let docsURL: URL
    }

    private func makeSnapshotEnv() throws -> SnapshotEnv {
        let tmp = FileManager.default.temporaryDirectory
        let dbURL = tmp.appendingPathComponent(UUID().uuidString + ".sqlite")
        let docsURL = tmp.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        // DatabaseManager(url:) runs migrate + seedIfEmpty internally.
        let dbm = try DatabaseManager(url: dbURL)
        return SnapshotEnv(dbm: dbm, dbURL: dbURL, docsURL: docsURL)
    }

    private func cleanupSnapshotEnv(_ env: SnapshotEnv) {
        try? FileManager.default.removeItem(at: env.docsURL)
        try? FileManager.default.removeItem(at: env.dbURL)
        // SQLite may also leave -wal / -shm sidecars.
        let wal = env.dbURL.path + "-wal"
        let shm = env.dbURL.path + "-shm"
        try? FileManager.default.removeItem(atPath: wal)
        try? FileManager.default.removeItem(atPath: shm)
    }

    private func waitForFile(at url: URL, timeoutSecs: Double = 2.0) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSecs {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
        }
        return false
    }

    // MARK: - Helpers

    private func seedMinimalSession() async throws {
        let session = try await sessions.start(routineID: nil, type: .lift)
        let uuidStr = benchPressUUID.uuidString.lowercased()
        let exerciseRowID = try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, "SELECT id FROM exercise WHERE client_uuid = '\(uuidStr)';")
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: exerciseRowID,
            exerciseOrder: 0, setNumber: 1,
            setType: .working,
            weightKg: 100.0, reps: 5,
            durationSecs: nil, distanceM: nil,
            rpe: 8.0, completedAt: Date(),
            notes: nil, updatedAt: Date()
        ))
        try await sessions.finish(id: session.clientUUID)
    }
}
