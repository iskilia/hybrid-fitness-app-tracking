import XCTest
import SQLite3
@testable import Hybrid

/// Phase 2 gate (PLAN.md line 143):
/// "integration tests cover repo round-trip for each entity. CASCADE deletes verified."
final class Phase2RepositoryTests: XCTestCase {

    // MARK: - In-memory stack (rebuilt per test)

    private var db: DatabaseManager!
    private var routines: RoutineRepository!
    private var exercises: ExerciseRepository!
    private var runTemplates: RunTemplateRepository!
    private var sessions: SessionRepository!
    private var sets: SessionSetRepository!
    private var runs: SessionRunRepository!

    // Seed UUIDs (deterministic per SeedData.swift).
    private let benchPressUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
    private let backSquatLikelyUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000002")!
    private let fiveByEightHundredUUID = UUID(uuidString: "00000000-0000-0000-0002-000000000004")!

    // Muscle ID-as-UUID encoding (per ExerciseRepository.resolveMuscleID).
    private func muscleUUID(_ id: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", id))!
    }

    override func setUp() async throws {
        try await super.setUp()
        db = try DatabaseManager(url: nil)
        routines = RoutineRepository(dbManager: db)
        exercises = ExerciseRepository(dbManager: db)
        runTemplates = RunTemplateRepository(dbManager: db)
        sessions = SessionRepository(dbManager: db)
        sets = SessionSetRepository(dbManager: db)
        runs = SessionRunRepository(dbManager: db)
    }

    override func tearDown() async throws {
        db = nil
        routines = nil
        exercises = nil
        runTemplates = nil
        sessions = nil
        sets = nil
        runs = nil
        try await super.tearDown()
    }

    // MARK: - 1. Routine round-trip

    func testRoutineCRUDRoundTrip() async throws {
        // Seed: bench press exercise (id=1), 5×800m run template (id=4) already in DB.

        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0,
            clientUUID: routineUUID,
            name: "Push Day",
            type: .lift,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )

        // Step 1: create the routine alone so we can resolve its row id.
        try await routines.create(routine, exerciseEntries: [], runEntries: [])
        let stored = try await routines.get(id: routineUUID)
        XCTAssertNotNil(stored)
        let routineRowID = stored!.id

        // Step 2: replace via update with one exercise + one run entry.
        let exerciseEntry = RoutineExercise(
            id: 0,
            clientUUID: UUID(),
            routineID: routineRowID,
            exerciseID: 1,             // Bench Press seed
            sortOrder: 0,
            targetSets: 3,
            targetRepMin: 5,
            targetRepMax: 8,
            targetRPE: 8.0,
            targetDurationSecsMin: nil,
            targetDurationSecsMax: nil,
            notes: nil,
            updatedAt: now
        )
        let runEntry = RoutineRun(
            id: 0,
            clientUUID: UUID(),
            routineID: routineRowID,
            runTemplateID: 4,          // 5×800m seed
            sortOrder: 0,
            notes: nil,
            updatedAt: now
        )
        try await routines.update(routine, exerciseEntries: [exerciseEntry], runEntries: [runEntry])

        // list() returns it
        let listed = try await routines.list()
        XCTAssertTrue(listed.contains { $0.clientUUID == routineUUID })

        // routine_exercise + routine_run rows persisted
        let exCount = try await rawScalarInt("SELECT COUNT(*) FROM routine_exercise WHERE routine_id = \(routineRowID);")
        let runCount = try await rawScalarInt("SELECT COUNT(*) FROM routine_run WHERE routine_id = \(routineRowID);")
        XCTAssertEqual(exCount, 1)
        XCTAssertEqual(runCount, 1)

        // Update name via another update().
        let renamed = Routine(
            id: routineRowID,
            clientUUID: routineUUID,
            name: "Pull Day",
            type: .lift,
            sortOrder: 0,
            createdAt: now,
            updatedAt: Date(),
            deletedAt: nil
        )
        try await routines.update(renamed, exerciseEntries: [exerciseEntry], runEntries: [runEntry])
        let renamedRead = try await routines.get(id: routineUUID)
        XCTAssertEqual(renamedRead?.name, "Pull Day")

        // Soft delete → no longer in list.
        try await routines.softDelete(id: routineUUID)
        let afterDelete = try await routines.list()
        XCTAssertFalse(afterDelete.contains { $0.clientUUID == routineUUID })
    }

    // MARK: - 2. Exercise round-trip

    func testExerciseCRUDRoundTrip() async throws {
        // listBase populated by seed
        let baseList = try await exercises.listBase()
        XCTAssertGreaterThan(baseList.count, 0, "Seed exercises missing from listBase()")

        let now = Date()
        let customUUID = UUID()
        let custom = Exercise(
            id: 0,
            clientUUID: customUUID,
            name: "Custom Lateral Raise",
            abbreviation: "LAT",
            equipmentID: 2,            // DUMBBELL seed id
            metricType: .reps,
            isCustom: true,
            notes: nil,
            formLink: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try await exercises.create(custom, muscles: [
            (muscleUUID(4), .primary),    // Shoulders
            (muscleUUID(6), .secondary),  // Triceps
        ])

        let customList = try await exercises.listCustom()
        XCTAssertTrue(customList.contains { $0.clientUUID == customUUID })

        let muscles = try await exercises.musclesFor(exerciseID: customUUID)
        XCTAssertEqual(muscles.count, 2)
        let roles = Set(muscles.map { $0.1 })
        XCTAssertEqual(roles, Set([.primary, .secondary]))

        let equipment = try await exercises.equipmentFor(exerciseID: customUUID)
        XCTAssertEqual(equipment?.code, "DUMBBELL")

        try await exercises.softDelete(id: customUUID)
        let afterDelete = try await exercises.listCustom()
        XCTAssertFalse(afterDelete.contains { $0.clientUUID == customUUID })
    }

    // MARK: - 3. Exercise search

    func testExerciseSearch() async throws {
        let results = try await exercises.search(query: "press")
        let names = results.map { $0.name.lowercased() }
        XCTAssertTrue(names.contains("bench press"), "Bench Press missing from 'press' search")
        XCTAssertTrue(names.contains("overhead press"), "Overhead Press missing from 'press' search")
    }

    // MARK: - 4. RunTemplate round-trip

    func testRunTemplateCRUDRoundTrip() async throws {
        let baseList = try await runTemplates.listBase()
        XCTAssertGreaterThan(baseList.count, 0, "Seed run templates missing from listBase()")

        let intervals = try await runTemplates.intervals(for: fiveByEightHundredUUID)
        XCTAssertGreaterThan(intervals.count, 0, "5×800m intervals missing")

        let now = Date()
        let customUUID = UUID()
        let custom = RunTemplate(
            id: 0,
            clientUUID: customUUID,
            name: "Custom Hill Repeats",
            runType: .intervals,
            targetTotalDistanceKm: 6.0,
            targetWorkDistanceKm: 4.0,
            targetPaceSecsMin: 220,
            targetPaceSecsMax: 240,
            hrZoneMin: 3,
            hrZoneMax: 4,
            hrBpmMin: 150,
            hrBpmMax: 175,
            isCustom: true,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        let blocks = [
            RunIntervalBlock(id: 0, runTemplateID: 0, sortOrder: 0, blockType: .warmup,
                             repeatCount: 1, distanceKm: 1.0, durationSecs: nil,
                             targetPaceSecs: nil, hrZone: 2, notes: nil),
            RunIntervalBlock(id: 0, runTemplateID: 0, sortOrder: 1, blockType: .work,
                             repeatCount: 5, distanceKm: 0.4, durationSecs: nil,
                             targetPaceSecs: 210, hrZone: 4, notes: nil),
            RunIntervalBlock(id: 0, runTemplateID: 0, sortOrder: 2, blockType: .cooldown,
                             repeatCount: 1, distanceKm: 1.0, durationSecs: nil,
                             targetPaceSecs: nil, hrZone: 2, notes: nil),
        ]
        try await runTemplates.create(custom, blocks: blocks)

        let customList = try await runTemplates.listCustom()
        XCTAssertTrue(customList.contains { $0.clientUUID == customUUID })

        let customBlocks = try await runTemplates.intervals(for: customUUID)
        XCTAssertEqual(customBlocks.count, 3)

        try await runTemplates.softDelete(id: customUUID)
        let afterDelete = try await runTemplates.listCustom()
        XCTAssertFalse(afterDelete.contains { $0.clientUUID == customUUID })
    }

    // MARK: - 5. Session lifecycle (start → finish)

    func testSessionLifecycle() async throws {
        let started = try await sessions.start(routineID: nil, type: .lift)
        XCTAssertEqual(started.status, .inProgress)
        XCTAssertNil(started.finishedAt)

        try await sessions.finish(id: started.clientUUID)
        let finished = try await sessions.get(id: started.clientUUID)
        XCTAssertEqual(finished?.status, .completed)
        XCTAssertNotNil(finished?.finishedAt)
    }

    // MARK: - 6. Session abandon

    func testSessionAbandon() async throws {
        let started = try await sessions.start(routineID: nil, type: .lift)
        try await sessions.abandon(id: started.clientUUID)
        let after = try await sessions.get(id: started.clientUUID)
        XCTAssertEqual(after?.status, .abandoned)
        XCTAssertNotNil(after?.finishedAt)
    }

    // MARK: - 7. SessionSet round-trip

    func testSessionSetCRUDRoundTrip() async throws {
        let session = try await sessions.start(routineID: nil, type: .lift)
        let exerciseRowID = try await resolveExerciseRowID(uuid: benchPressUUID)
        let now = Date()

        // Append 3 sets with stable client UUIDs we can reuse.
        var setUUIDs: [UUID] = []
        for n in 1...3 {
            let setUUID = UUID()
            setUUIDs.append(setUUID)
            let set = SessionSet(
                id: 0,
                clientUUID: setUUID,
                sessionID: session.id,
                exerciseID: exerciseRowID,
                exerciseOrder: 0,
                setNumber: n,
                setType: .working,
                weightKg: 60.0 + Double(n) * 5.0,
                reps: 5,
                durationSecs: nil,
                distanceM: nil,
                rpe: 7.0,
                completedAt: now,
                notes: nil,
                updatedAt: now
            )
            try await sets.append(set)
        }

        var listed = try await sets.list(sessionID: session.clientUUID, exerciseID: benchPressUUID)
        XCTAssertEqual(listed.count, 3)
        XCTAssertEqual(listed.map { $0.setNumber }, [1, 2, 3])

        // Update set 2 — change reps to 10.
        let original = listed[1]
        let updated = SessionSet(
            id: original.id,
            clientUUID: original.clientUUID,
            sessionID: original.sessionID,
            exerciseID: original.exerciseID,
            exerciseOrder: original.exerciseOrder,
            setNumber: original.setNumber,
            setType: original.setType,
            weightKg: original.weightKg,
            reps: 10,
            durationSecs: original.durationSecs,
            distanceM: original.distanceM,
            rpe: original.rpe,
            completedAt: original.completedAt,
            notes: original.notes,
            updatedAt: Date()
        )
        try await sets.update(updated)
        listed = try await sets.list(sessionID: session.clientUUID, exerciseID: benchPressUUID)
        XCTAssertEqual(listed.first { $0.setNumber == 2 }?.reps, 10)

        // Delete set 3.
        try await sets.delete(id: setUUIDs[2])
        listed = try await sets.list(sessionID: session.clientUUID, exerciseID: benchPressUUID)
        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(listed.map { $0.setNumber }, [1, 2])
    }

    // MARK: - 8. SessionRun round-trip

    func testSessionRunCRUDRoundTrip() async throws {
        let session = try await sessions.start(routineID: nil, type: .run)
        let now = Date()
        let runUUID = UUID()
        let run = SessionRun(
            id: 0,
            clientUUID: runUUID,
            sessionID: session.id,
            runTemplateID: nil,
            runOrder: 0,
            actualDistanceKm: nil,
            durationSecs: nil,
            avgPaceSecs: nil,
            avgHR: nil,
            maxHR: nil,
            targetHRMin: nil,
            targetHRMax: nil,
            notes: nil,
            updatedAt: now
        )
        try await runs.append(run)

        // Resolve session_run integer id for splits.
        let sessionRunRowID = try await rawScalarInt("SELECT id FROM session_run WHERE client_uuid = '\(runUUID.uuidString.lowercased())';")

        try await runs.finish(id: runUUID, distanceKm: 5.0, durationSec: 1800,
                              avgPaceSecPerKm: 360, avgHrBpm: 150)

        let finishedDistance = try await rawScalarDouble("SELECT actual_distance_km FROM session_run WHERE client_uuid = '\(runUUID.uuidString.lowercased())';")
        XCTAssertEqual(finishedDistance, 5.0, accuracy: 0.001)

        let split1 = SessionRunSplit(id: 0, sessionRunID: sessionRunRowID,
                                     sortOrder: 0, blockType: .work,
                                     distanceKm: 1.0, durationSecs: 360,
                                     avgPaceSecs: 360, avgHR: 150)
        let split2 = SessionRunSplit(id: 0, sessionRunID: sessionRunRowID,
                                     sortOrder: 1, blockType: .work,
                                     distanceKm: 1.0, durationSecs: 350,
                                     avgPaceSecs: 350, avgHR: 155)
        try await runs.addSplit(split1)
        try await runs.addSplit(split2)

        let splits = try await runs.splits(sessionRunID: runUUID)
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits.map { $0.sortOrder }, [0, 1])
    }

    // MARK: - 9. Week stats

    /// Locks in the actual semantics: weekStats counts every session whose
    /// `started_at` falls in [weekStart, weekStart+7d) regardless of status.
    func testWeekStats() async throws {
        let weekStart = startOfThisWeek()

        // Two lift sessions with sets.
        let exerciseRowID = try await resolveExerciseRowID(uuid: benchPressUUID)

        for sessionIdx in 0..<2 {
            let s = try await sessions.start(routineID: nil, type: .lift)
            // Append 3 sets — 100×5, 80×8, 60×10 — tonnage per session = 500+640+600 = 1740
            let setSpecs: [(weight: Double, reps: Int, n: Int)] = [
                (100.0, 5, 1), (80.0, 8, 2), (60.0, 10, 3)
            ]
            for spec in setSpecs {
                let setUUID = UUID()
                let set = SessionSet(
                    id: 0, clientUUID: setUUID,
                    sessionID: s.id, exerciseID: exerciseRowID,
                    exerciseOrder: 0, setNumber: spec.n,
                    setType: .working,
                    weightKg: spec.weight, reps: spec.reps,
                    durationSecs: nil, distanceM: nil,
                    rpe: nil, completedAt: nil,
                    notes: nil, updatedAt: Date()
                )
                try await sets.append(set)
            }
            try await sessions.finish(id: s.clientUUID)
            _ = sessionIdx
        }

        // One run session — 5 km.
        let runSession = try await sessions.start(routineID: nil, type: .run)
        let runUUID = UUID()
        let run = SessionRun(
            id: 0, clientUUID: runUUID,
            sessionID: runSession.id, runTemplateID: nil,
            runOrder: 0, actualDistanceKm: nil, durationSecs: nil,
            avgPaceSecs: nil, avgHR: nil, maxHR: nil,
            targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: Date()
        )
        try await runs.append(run)
        try await runs.finish(id: runUUID, distanceKm: 5.0, durationSec: 1800,
                              avgPaceSecPerKm: 360, avgHrBpm: 150)
        try await sessions.finish(id: runSession.clientUUID)

        // Outside-window session: insert raw with started_at = 30 days ago.
        let outsideEpoch = Int(Date().timeIntervalSince1970) - 30 * 24 * 60 * 60
        let outsideUUID = UUID().uuidString.lowercased()
        try await rawExec("""
            INSERT INTO session (client_uuid, type, status, started_at, updated_at)
            VALUES ('\(outsideUUID)', 'LIFT', 'COMPLETED', \(outsideEpoch), \(outsideEpoch));
            """)

        let stats = try await sessions.weekStats(weekStart: weekStart)
        XCTAssertEqual(stats.sessionCount, 3,
                       "expected 3 sessions in current week (2 lift + 1 run); got \(stats.sessionCount)")
        XCTAssertEqual(stats.totalTonnageKg, 1740.0 * 2, accuracy: 0.01,
                       "expected 3480 kg total tonnage; got \(stats.totalTonnageKg)")
        XCTAssertEqual(stats.totalDistanceKm, 5.0, accuracy: 0.001)
    }

    // MARK: - 10. Top set per session

    func testTopSetPerSession() async throws {
        let exerciseRowID = try await resolveExerciseRowID(uuid: benchPressUUID)

        // Three completed sessions with distinct heaviest sets: 100, 110, 120.
        let heavy: [Double] = [100.0, 110.0, 120.0]
        for h in heavy {
            let s = try await sessions.start(routineID: nil, type: .lift)
            // 3 sets — heaviest at the end so we exercise MAX semantics.
            let setSpecs: [(weight: Double, setNumber: Int)] = [
                (h - 20.0, 1), (h - 10.0, 2), (h, 3)
            ]
            for spec in setSpecs {
                let set = SessionSet(
                    id: 0, clientUUID: UUID(),
                    sessionID: s.id, exerciseID: exerciseRowID,
                    exerciseOrder: 0, setNumber: spec.setNumber,
                    setType: .working,
                    weightKg: spec.weight, reps: 5,
                    durationSecs: nil, distanceM: nil,
                    rpe: nil, completedAt: nil,
                    notes: nil, updatedAt: Date()
                )
                try await sets.append(set)
            }
            try await sessions.finish(id: s.clientUUID)
        }

        let tops = try await sets.topSetPerSession(exerciseID: benchPressUUID, limit: 12)
        XCTAssertEqual(tops.count, 3, "expected one top set per session")
        let weights = Set(tops.map { $0.weightKg })
        XCTAssertEqual(weights, Set([100.0, 110.0, 120.0]))
    }

    // MARK: - 11. History by exercise

    func testHistoryByExercise() async throws {
        let exerciseRowID = try await resolveExerciseRowID(uuid: benchPressUUID)
        var totalSets = 0
        for setsPerSession in [3, 3, 3] {
            let s = try await sessions.start(routineID: nil, type: .lift)
            for n in 1...setsPerSession {
                let set = SessionSet(
                    id: 0, clientUUID: UUID(),
                    sessionID: s.id, exerciseID: exerciseRowID,
                    exerciseOrder: 0, setNumber: n,
                    setType: .working,
                    weightKg: 80.0, reps: 5,
                    durationSecs: nil, distanceM: nil,
                    rpe: nil, completedAt: nil,
                    notes: nil, updatedAt: Date()
                )
                try await sets.append(set)
                totalSets += 1
            }
            try await sessions.finish(id: s.clientUUID)
        }

        let history = try await sets.historyByExercise(exerciseID: benchPressUUID, monthsBack: 12)
        XCTAssertEqual(history.count, totalSets)
    }

    // MARK: - 12. Routine cap (10 max)

    func testRoutineCapEnforcement() async throws {
        let now = Date()
        for i in 0..<10 {
            let r = Routine(
                id: 0, clientUUID: UUID(),
                name: "R\(i)", type: .lift,
                sortOrder: i, createdAt: now, updatedAt: now, deletedAt: nil
            )
            try await routines.create(r, exerciseEntries: [], runEntries: [])
        }

        let eleventh = Routine(
            id: 0, clientUUID: UUID(),
            name: "R11", type: .lift,
            sortOrder: 10, createdAt: now, updatedAt: now, deletedAt: nil
        )
        do {
            try await routines.create(eleventh, exerciseEntries: [], runEntries: [])
            XCTFail("Expected DatabaseError.conflict on 11th routine, got success")
        } catch let DatabaseError.conflict(msg) {
            XCTAssertFalse(msg.isEmpty, "conflict message should not be empty")
        } catch {
            XCTFail("Expected DatabaseError.conflict, got \(error)")
        }
    }

    // MARK: - 13. CASCADE on session

    func testCascadeDeleteSession() async throws {
        let session = try await sessions.start(routineID: nil, type: .lift)
        let exerciseRowID = try await resolveExerciseRowID(uuid: benchPressUUID)
        let now = Date()

        let set = SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: exerciseRowID,
            exerciseOrder: 0, setNumber: 1,
            setType: .working,
            weightKg: 80.0, reps: 5,
            durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        )
        try await sets.append(set)

        let runUUID = UUID()
        let run = SessionRun(
            id: 0, clientUUID: runUUID,
            sessionID: session.id, runTemplateID: nil,
            runOrder: 0, actualDistanceKm: nil, durationSecs: nil,
            avgPaceSecs: nil, avgHR: nil, maxHR: nil,
            targetHRMin: nil, targetHRMax: nil,
            notes: nil, updatedAt: now
        )
        try await runs.append(run)

        let sessionRunRowID = try await rawScalarInt("SELECT id FROM session_run WHERE client_uuid = '\(runUUID.uuidString.lowercased())';")
        try await runs.addSplit(SessionRunSplit(
            id: 0, sessionRunID: sessionRunRowID, sortOrder: 0, blockType: .work,
            distanceKm: 1.0, durationSecs: 360, avgPaceSecs: 360, avgHR: 150
        ))

        // Sanity: rows exist.
        let preSets = try await rawScalarInt("SELECT COUNT(*) FROM session_set WHERE session_id = \(session.id);")
        let preRuns = try await rawScalarInt("SELECT COUNT(*) FROM session_run WHERE session_id = \(session.id);")
        let preSplits = try await rawScalarInt("SELECT COUNT(*) FROM session_run_split WHERE session_run_id = \(sessionRunRowID);")
        XCTAssertEqual(preSets, 1)
        XCTAssertEqual(preRuns, 1)
        XCTAssertEqual(preSplits, 1)

        // Hard delete the session row.
        try await rawExec("DELETE FROM session WHERE id = \(session.id);")

        let postSets = try await rawScalarInt("SELECT COUNT(*) FROM session_set WHERE session_id = \(session.id);")
        let postRuns = try await rawScalarInt("SELECT COUNT(*) FROM session_run WHERE session_id = \(session.id);")
        let postSplits = try await rawScalarInt("SELECT COUNT(*) FROM session_run_split WHERE session_run_id = \(sessionRunRowID);")
        XCTAssertEqual(postSets, 0, "session_set should CASCADE on session delete")
        XCTAssertEqual(postRuns, 0, "session_run should CASCADE on session delete")
        XCTAssertEqual(postSplits, 0, "session_run_split should CASCADE via session_run")
    }

    // MARK: - 14. CASCADE on routine

    func testCascadeDeleteRoutine() async throws {
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID,
            name: "Cascade", type: .lift,
            sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routines.create(routine, exerciseEntries: [], runEntries: [])
        let stored = try await routines.get(id: routineUUID)
        let routineRowID = stored!.id

        let exerciseEntry = RoutineExercise(
            id: 0, clientUUID: UUID(),
            routineID: routineRowID, exerciseID: 1, sortOrder: 0,
            targetSets: 3, targetRepMin: 5, targetRepMax: 8,
            targetRPE: nil, targetDurationSecsMin: nil, targetDurationSecsMax: nil,
            notes: nil, updatedAt: now
        )
        let runEntry = RoutineRun(
            id: 0, clientUUID: UUID(),
            routineID: routineRowID, runTemplateID: 4, sortOrder: 0,
            notes: nil, updatedAt: now
        )
        try await routines.update(routine, exerciseEntries: [exerciseEntry], runEntries: [runEntry])

        let preEx = try await rawScalarInt("SELECT COUNT(*) FROM routine_exercise WHERE routine_id = \(routineRowID);")
        let preRun = try await rawScalarInt("SELECT COUNT(*) FROM routine_run WHERE routine_id = \(routineRowID);")
        XCTAssertEqual(preEx, 1)
        XCTAssertEqual(preRun, 1)

        try await rawExec("DELETE FROM routine WHERE id = \(routineRowID);")

        let postEx = try await rawScalarInt("SELECT COUNT(*) FROM routine_exercise WHERE routine_id = \(routineRowID);")
        let postRun = try await rawScalarInt("SELECT COUNT(*) FROM routine_run WHERE routine_id = \(routineRowID);")
        XCTAssertEqual(postEx, 0, "routine_exercise should CASCADE on routine delete")
        XCTAssertEqual(postRun, 0, "routine_run should CASCADE on routine delete")
    }

    // MARK: - 15. CASCADE on run_template

    func testCascadeDeleteRunTemplate() async throws {
        let now = Date()
        let templateUUID = UUID()
        let template = RunTemplate(
            id: 0, clientUUID: templateUUID,
            name: "Cascade Tpl", runType: .intervals,
            targetTotalDistanceKm: 6.0, targetWorkDistanceKm: 4.0,
            targetPaceSecsMin: 200, targetPaceSecsMax: 230,
            hrZoneMin: 3, hrZoneMax: 4,
            hrBpmMin: 150, hrBpmMax: 175,
            isCustom: true, createdAt: now, updatedAt: now, deletedAt: nil
        )
        let blocks = (0..<3).map { i in
            RunIntervalBlock(
                id: 0, runTemplateID: 0, sortOrder: i,
                blockType: .work, repeatCount: 1,
                distanceKm: 1.0, durationSecs: nil,
                targetPaceSecs: nil, hrZone: 3, notes: nil
            )
        }
        try await runTemplates.create(template, blocks: blocks)

        let templateRow = try await runTemplates.get(id: templateUUID)
        let templateRowID = templateRow!.id

        let preBlocks = try await rawScalarInt("SELECT COUNT(*) FROM run_interval_block WHERE run_template_id = \(templateRowID);")
        XCTAssertEqual(preBlocks, 3)

        try await rawExec("DELETE FROM run_template WHERE id = \(templateRowID);")

        let postBlocks = try await rawScalarInt("SELECT COUNT(*) FROM run_interval_block WHERE run_template_id = \(templateRowID);")
        XCTAssertEqual(postBlocks, 0, "run_interval_block should CASCADE on run_template delete")
    }

    // MARK: - Phase V2 — TV2.1: RoutineExercise timed targets round-trip

    func testRoutineExerciseRoundTripsTimedTargetsViaRepository() async throws {
        // Plank is seed exercise ID 29 (metric_type = TIME).
        let plankUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000029")!
        let plankRowID = try await resolveExerciseRowID(uuid: plankUUID)

        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID,
            name: "Core Hold Day", type: .lift,
            sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routines.create(routine, exerciseEntries: [], runEntries: [])
        let stored = try await routines.get(id: routineUUID)
        let routineRowID = stored!.id

        let timedEntry = RoutineExercise(
            id: 0,
            clientUUID: UUID(),
            routineID: routineRowID,
            exerciseID: plankRowID,
            sortOrder: 0,
            targetSets: 3,
            targetRepMin: nil,
            targetRepMax: nil,
            targetRPE: nil,
            targetDurationSecsMin: 30,
            targetDurationSecsMax: 45,
            notes: nil,
            updatedAt: now
        )
        try await routines.update(routine, exerciseEntries: [timedEntry], runEntries: [])

        let listed = try await routines.listExercises(routineID: routineUUID)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].targetDurationSecsMin, 30,
                       "target_duration_secs_min should round-trip via listExercises")
        XCTAssertEqual(listed[0].targetDurationSecsMax, 45,
                       "target_duration_secs_max should round-trip via listExercises")
        XCTAssertEqual(listed[0].exerciseID, plankRowID)
    }

    // MARK: - Phase V2 — TV2.2: lastCompletedSession

    func testLastCompletedSessionReturnsMostRecentCompleted() async throws {
        // Build a routine and stamp three sessions on it: IN_PROGRESS, ABANDONED, COMPLETED.
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID,
            name: "Last-Completed R", type: .lift,
            sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routines.create(routine, exerciseEntries: [], runEntries: [])
        let routineRowID = (try await routines.get(id: routineUUID))!.id

        // 1. IN_PROGRESS (just start, do not finish).
        _ = try await sessions.start(routineID: routineUUID, type: .lift)

        // 2. ABANDONED.
        let abandonMe = try await sessions.start(routineID: routineUUID, type: .lift)
        try await sessions.abandon(id: abandonMe.clientUUID)

        // 3. COMPLETED — this is the one we expect back.
        let completed = try await sessions.start(routineID: routineUUID, type: .lift)
        try await sessions.finish(id: completed.clientUUID)

        let last = try await sessions.lastCompletedSession(forRoutineID: routineRowID)
        XCTAssertNotNil(last)
        XCTAssertEqual(last?.clientUUID, completed.clientUUID,
                       "lastCompletedSession must return the COMPLETED session, not IN_PROGRESS/ABANDONED")
        XCTAssertEqual(last?.status, .completed)
    }

    func testLastCompletedSessionReturnsNilForUnusedRoutine() async throws {
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID,
            name: "Untouched R", type: .lift,
            sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routines.create(routine, exerciseEntries: [], runEntries: [])
        let routineRowID = (try await routines.get(id: routineUUID))!.id

        let last = try await sessions.lastCompletedSession(forRoutineID: routineRowID)
        XCTAssertNil(last,
                     "lastCompletedSession should return nil when no sessions exist for the routine")
    }

    func testLastCompletedSessionReturnsMostRecentWhenMultipleCompleted() async throws {
        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID,
            name: "Two-Completed R", type: .lift,
            sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routines.create(routine, exerciseEntries: [], runEntries: [])
        let routineRowID = (try await routines.get(id: routineUUID))!.id

        // Two completed sessions; force distinct finished_at via raw UPDATE
        // (finish() stores Date() at integer-second resolution → two consecutive finishes may tie).
        let earlier = try await sessions.start(routineID: routineUUID, type: .lift)
        try await sessions.finish(id: earlier.clientUUID)
        let earlierEpoch = Int(Date().timeIntervalSince1970) - 3600
        try await rawExec("UPDATE session SET finished_at = \(earlierEpoch) WHERE client_uuid = '\(earlier.clientUUID.uuidString.lowercased())';")

        let later = try await sessions.start(routineID: routineUUID, type: .lift)
        try await sessions.finish(id: later.clientUUID)
        let laterEpoch = Int(Date().timeIntervalSince1970)
        try await rawExec("UPDATE session SET finished_at = \(laterEpoch) WHERE client_uuid = '\(later.clientUUID.uuidString.lowercased())';")

        let last = try await sessions.lastCompletedSession(forRoutineID: routineRowID)
        XCTAssertEqual(last?.clientUUID, later.clientUUID,
                       "lastCompletedSession should return the session with the later finished_at")
    }

    // MARK: - Phase V2 — TV2.3 / TV2.3a: metric-type immutability + lock check

    func testExerciseUpdateRejectsMetricTypeChangeWhenSetsExist() async throws {
        // Use Back Squat (seed id 2, metric_type = REPS).
        let backSquat = try await exercises.get(id: backSquatLikelyUUID)
        XCTAssertNotNil(backSquat, "Back Squat seed should be present")
        let exerciseRowID = backSquat!.id

        // Log a session_set against Back Squat so the immutability guard kicks in.
        let session = try await sessions.start(routineID: nil, type: .lift)
        let now = Date()
        let set = SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: exerciseRowID,
            exerciseOrder: 0, setNumber: 1,
            setType: .working,
            weightKg: 100.0, reps: 5,
            durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        )
        try await sets.append(set)

        // Build a flipped-metric clone (REPS → TIME) and expect a conflict.
        let flipped = Exercise(
            id: backSquat!.id,
            clientUUID: backSquat!.clientUUID,
            name: backSquat!.name,
            abbreviation: backSquat!.abbreviation,
            equipmentID: backSquat!.equipmentID,
            metricType: .time,
            isCustom: backSquat!.isCustom,
            notes: backSquat!.notes,
            formLink: backSquat!.formLink,
            createdAt: backSquat!.createdAt,
            updatedAt: Date(),
            deletedAt: nil
        )
        do {
            try await exercises.update(flipped, muscles: [])
            XCTFail("Expected DatabaseError.conflict on metric_type change after a set was logged")
        } catch let DatabaseError.conflict(msg) {
            XCTAssertFalse(msg.isEmpty, "conflict message should not be empty")
        } catch {
            XCTFail("Expected DatabaseError.conflict, got \(error)")
        }
    }

    func testExerciseUpdateAllowsMetricTypeChangeWhenNoSetsExist() async throws {
        // Build a fresh custom exercise with metric_type = REPS; no sets logged.
        let now = Date()
        let customUUID = UUID()
        let custom = Exercise(
            id: 0,
            clientUUID: customUUID,
            name: "Custom Convertible",
            abbreviation: "CCV",
            equipmentID: 3,
            metricType: .reps,
            isCustom: true,
            notes: nil,
            formLink: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try await exercises.create(custom, muscles: [(muscleUUID(11), .primary)])

        let stored = try await exercises.get(id: customUUID)
        XCTAssertNotNil(stored)
        let rowID = stored!.id

        // Flip to TIME; no sets exist, so this must succeed.
        let flipped = Exercise(
            id: rowID,
            clientUUID: customUUID,
            name: stored!.name,
            abbreviation: stored!.abbreviation,
            equipmentID: stored!.equipmentID,
            metricType: .time,
            isCustom: stored!.isCustom,
            notes: stored!.notes,
            formLink: stored!.formLink,
            createdAt: stored!.createdAt,
            updatedAt: Date(),
            deletedAt: nil
        )
        try await exercises.update(flipped, muscles: [(muscleUUID(11), .primary)])

        let after = try await exercises.get(id: customUUID)
        XCTAssertEqual(after?.metricType, .time,
                       "metric_type should flip to TIME when no sets reference the exercise")
    }

    func testMetricTypeLockedReturnsTrueAfterFirstSet() async throws {
        // Fresh custom exercise — no sets yet.
        let now = Date()
        let customUUID = UUID()
        let custom = Exercise(
            id: 0,
            clientUUID: customUUID,
            name: "Custom Locker",
            abbreviation: "CLK",
            equipmentID: 3,
            metricType: .reps,
            isCustom: true,
            notes: nil,
            formLink: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try await exercises.create(custom, muscles: [(muscleUUID(11), .primary)])
        let rowID = (try await exercises.get(id: customUUID))!.id

        let preLock = try await exercises.metricTypeLocked(exerciseID: rowID)
        XCTAssertFalse(preLock, "metric_type should be unlocked before any sets exist")

        // Append a single REPS-shaped set.
        let session = try await sessions.start(routineID: nil, type: .lift)
        let set = SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: rowID,
            exerciseOrder: 0, setNumber: 1,
            setType: .working,
            weightKg: 40.0, reps: 8,
            durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        )
        try await sets.append(set)

        let postLock = try await exercises.metricTypeLocked(exerciseID: rowID)
        XCTAssertTrue(postLock, "metric_type should lock after the first session_set is logged")
    }

    // MARK: - Phase V2 — TV2.4: set-shape validation per metric_type

    func testSessionSetAppendRejectsTimeRowWithReps() async throws {
        let plankUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000029")!
        let plankRowID = try await resolveExerciseRowID(uuid: plankUUID)
        let session = try await sessions.start(routineID: nil, type: .lift)
        let now = Date()

        // 1. TIME with both duration AND reps → reject.
        let badBoth = SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: plankRowID,
            exerciseOrder: 0, setNumber: 1,
            setType: .working,
            weightKg: nil, reps: 5,
            durationSecs: 30, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        )
        do {
            try await sets.append(badBoth)
            XCTFail("Expected reject on TIME exercise with both duration_secs and reps")
        } catch {
            // Expected
        }

        // 2. TIME with both nil → reject.
        let badNeither = SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: plankRowID,
            exerciseOrder: 0, setNumber: 2,
            setType: .working,
            weightKg: nil, reps: nil,
            durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        )
        do {
            try await sets.append(badNeither)
            XCTFail("Expected reject on TIME exercise with no duration_secs")
        } catch {
            // Expected
        }

        // 3. TIME with duration only → accept.
        let good = SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: plankRowID,
            exerciseOrder: 0, setNumber: 3,
            setType: .working,
            weightKg: nil, reps: nil,
            durationSecs: 30, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        )
        try await sets.append(good)

        let listed = try await sets.list(sessionID: session.clientUUID, exerciseID: plankUUID)
        XCTAssertEqual(listed.count, 1, "Only the duration-only TIME set should have persisted")
        XCTAssertEqual(listed[0].durationSecs, 30)
        XCTAssertNil(listed[0].reps)
    }

    func testSessionSetAppendRejectsRepsRowWithDuration() async throws {
        // Back Squat = REPS.
        let exerciseRowID = try await resolveExerciseRowID(uuid: backSquatLikelyUUID)
        let session = try await sessions.start(routineID: nil, type: .lift)
        let now = Date()

        // 1. REPS with both reps AND duration → reject.
        let badBoth = SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: exerciseRowID,
            exerciseOrder: 0, setNumber: 1,
            setType: .working,
            weightKg: 100.0, reps: 5,
            durationSecs: 30, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        )
        do {
            try await sets.append(badBoth)
            XCTFail("Expected reject on REPS exercise with duration_secs set")
        } catch {
            // Expected
        }

        // 2. REPS with reps nil → reject.
        let badNoReps = SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: exerciseRowID,
            exerciseOrder: 0, setNumber: 2,
            setType: .working,
            weightKg: 100.0, reps: nil,
            durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        )
        do {
            try await sets.append(badNoReps)
            XCTFail("Expected reject on REPS exercise with no reps")
        } catch {
            // Expected
        }

        // 3. REPS with reps only → accept.
        let good = SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: exerciseRowID,
            exerciseOrder: 0, setNumber: 3,
            setType: .working,
            weightKg: 100.0, reps: 5,
            durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        )
        try await sets.append(good)

        let listed = try await sets.list(sessionID: session.clientUUID, exerciseID: backSquatLikelyUUID)
        XCTAssertEqual(listed.count, 1, "Only the reps-only REPS set should have persisted")
        XCTAssertEqual(listed[0].reps, 5)
        XCTAssertNil(listed[0].durationSecs)
    }

    // MARK: - Phase V2 — TV2.5: topSet within one session

    func testTopSetForTimeExerciseReturnsLongestHold() async throws {
        let plankUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000029")!
        let plankRowID = try await resolveExerciseRowID(uuid: plankUUID)
        let session = try await sessions.start(routineID: nil, type: .lift)
        let now = Date()

        let durations = [20, 45, 30]
        for (i, secs) in durations.enumerated() {
            let s = SessionSet(
                id: 0, clientUUID: UUID(),
                sessionID: session.id, exerciseID: plankRowID,
                exerciseOrder: 0, setNumber: i + 1,
                setType: .working,
                weightKg: nil, reps: nil,
                durationSecs: secs, distanceM: nil,
                rpe: nil, completedAt: nil,
                notes: nil, updatedAt: now
            )
            try await sets.append(s)
        }

        let top = try await sets.topSet(sessionID: session.id, exerciseID: plankRowID)
        XCTAssertNotNil(top, "topSet should return a row for a TIME exercise with sets logged")
        XCTAssertEqual(top?.durationSecs, 45,
                       "topSet on a TIME exercise should pick the longest hold")
    }

    func testTopSetForRepsExerciseReturnsHeaviestThenMostReps() async throws {
        let exerciseRowID = try await resolveExerciseRowID(uuid: backSquatLikelyUUID)
        let session = try await sessions.start(routineID: nil, type: .lift)
        let now = Date()

        let specs: [(weight: Double, reps: Int, setNumber: Int)] = [
            (100.0, 5, 1),
            (120.0, 3, 2),
            (120.0, 5, 3),
        ]
        for spec in specs {
            let s = SessionSet(
                id: 0, clientUUID: UUID(),
                sessionID: session.id, exerciseID: exerciseRowID,
                exerciseOrder: 0, setNumber: spec.setNumber,
                setType: .working,
                weightKg: spec.weight, reps: spec.reps,
                durationSecs: nil, distanceM: nil,
                rpe: nil, completedAt: nil,
                notes: nil, updatedAt: now
            )
            try await sets.append(s)
        }

        let top = try await sets.topSet(sessionID: session.id, exerciseID: exerciseRowID)
        XCTAssertNotNil(top, "topSet should return a row for a REPS exercise with sets logged")
        XCTAssertEqual(top?.weightKg, 120.0,
                       "topSet on a REPS exercise should pick the heaviest weight")
        XCTAssertEqual(top?.reps, 5,
                       "topSet should tie-break by reps DESC when weight is tied")
    }

    func testTopSetReturnsNilForEmptySessionExercisePair() async throws {
        let exerciseRowID = try await resolveExerciseRowID(uuid: backSquatLikelyUUID)
        let session = try await sessions.start(routineID: nil, type: .lift)

        let top = try await sets.topSet(sessionID: session.id, exerciseID: exerciseRowID)
        XCTAssertNil(top, "topSet should return nil when no sets exist for the session/exercise pair")
    }

    // MARK: - Helpers

    /// Returns the exercise's integer row ID looked up by client_uuid.
    private func resolveExerciseRowID(uuid: UUID) async throws -> Int {
        try await rawScalarInt("SELECT id FROM exercise WHERE client_uuid = '\(uuid.uuidString.lowercased())';")
    }

    /// Computes the start of the current calendar week.
    private func startOfThisWeek() -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    /// Runs a parameterless SQL statement on the actor.
    private func rawExec(_ sql: String) async throws {
        try await db.transaction { handle in
            try Hybrid.execSQL(handle, sql)
        }
    }

    /// Runs a SELECT-of-one-int and returns the value.
    private func rawScalarInt(_ sql: String) async throws -> Int {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, sql)
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    /// Runs a SELECT-of-one-double and returns the value.
    private func rawScalarDouble(_ sql: String) async throws -> Double {
        try await db.read { handle in
            let stmt = try Hybrid.prepare(handle, sql)
            defer { Hybrid.finalize(stmt) }
            guard try Hybrid.step(stmt) else { return 0.0 }
            return sqlite3_column_double(stmt, 0)
        }
    }

    // MARK: - Phase V7 — TV7.1 case #1: timed-hold custom exercise create round-trips

    func testTimedHoldCustomExerciseCreateRoundTrips() async throws {
        let now = Date()
        let customUUID = UUID()
        let custom = Exercise(
            id: 0,
            clientUUID: customUUID,
            name: "Custom L-Sit Hold",
            abbreviation: "CLS",
            equipmentID: 3,            // BODYWEIGHT
            metricType: .time,
            isCustom: true,
            notes: nil,
            formLink: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try await exercises.create(custom, muscles: [
            (muscleUUID(11), .primary),  // Core
        ])

        let stored = try await exercises.get(id: customUUID)
        XCTAssertNotNil(stored, "Custom timed-hold exercise should be retrievable post-create")
        XCTAssertEqual(stored?.metricType, .time,
                       "Custom timed-hold exercise should round-trip metric_type = TIME")
        XCTAssertEqual(stored?.name, "Custom L-Sit Hold")
        XCTAssertEqual(stored?.isCustom, true)

        let inCustomList = try await exercises.listCustom()
        XCTAssertTrue(inCustomList.contains { $0.clientUUID == customUUID },
                      "Custom timed-hold should appear in listCustom()")
    }

    // MARK: - Phase V7 — TV7.1 case #2: mixed rep-based + time-based routine round-trips

    func testRoutineWithMixedRepAndTimeItemsRoundTrips() async throws {
        // Bench Press (REPS, seed id 1) + Plank (TIME, seed id 29).
        let plankUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000029")!
        let plankRowID = try await resolveExerciseRowID(uuid: plankUUID)
        let benchRowID = try await resolveExerciseRowID(uuid: benchPressUUID)

        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID,
            name: "Mixed Day", type: .lift,
            sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routines.create(routine, exerciseEntries: [], runEntries: [])
        let routineRowID = (try await routines.get(id: routineUUID))!.id

        let repsEntry = RoutineExercise(
            id: 0, clientUUID: UUID(),
            routineID: routineRowID, exerciseID: benchRowID, sortOrder: 0,
            targetSets: 3, targetRepMin: 5, targetRepMax: 8,
            targetRPE: 8.0,
            targetDurationSecsMin: nil, targetDurationSecsMax: nil,
            notes: nil, updatedAt: now
        )
        let timeEntry = RoutineExercise(
            id: 0, clientUUID: UUID(),
            routineID: routineRowID, exerciseID: plankRowID, sortOrder: 1,
            targetSets: 3, targetRepMin: nil, targetRepMax: nil,
            targetRPE: nil,
            targetDurationSecsMin: 30, targetDurationSecsMax: 45,
            notes: nil, updatedAt: now
        )
        try await routines.update(routine, exerciseEntries: [repsEntry, timeEntry], runEntries: [])

        let listed = try await routines.listExercises(routineID: routineUUID)
        XCTAssertEqual(listed.count, 2, "Mixed routine should have two routine_exercise rows")

        let repsRow = try XCTUnwrap(listed.first(where: { $0.exerciseID == benchRowID }))
        XCTAssertEqual(repsRow.targetRepMin, 5)
        XCTAssertEqual(repsRow.targetRepMax, 8)
        XCTAssertNil(repsRow.targetDurationSecsMin,
                     "REPS entry should not carry duration targets")
        XCTAssertNil(repsRow.targetDurationSecsMax)

        let timeRow = try XCTUnwrap(listed.first(where: { $0.exerciseID == plankRowID }))
        XCTAssertEqual(timeRow.targetDurationSecsMin, 30)
        XCTAssertEqual(timeRow.targetDurationSecsMax, 45)
        XCTAssertNil(timeRow.targetRepMin,
                     "TIME entry should not carry rep targets")
        XCTAssertNil(timeRow.targetRepMax)
    }

    // MARK: - Phase V7 — TV7.1 case #8: LastExecutionSummary mutes removed exercises

    func testLastExecutionSummaryMutesExercisesRemovedFromRoutine() async throws {
        // Build a routine containing Bench Press + Back Squat. Run a session
        // that logs sets for BOTH exercises. Then edit the routine to drop
        // Back Squat. Reopen via the lift VM's loadLastExecution; assert that
        // Back Squat surfaces as a `removed: true` row.

        let benchRowID = try await resolveExerciseRowID(uuid: benchPressUUID)
        let backSquatRowID = try await resolveExerciseRowID(uuid: backSquatLikelyUUID)

        let now = Date()
        let routineUUID = UUID()
        let routine = Routine(
            id: 0, clientUUID: routineUUID,
            name: "Drop-an-exercise R", type: .lift,
            sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil
        )
        try await routines.create(routine, exerciseEntries: [], runEntries: [])
        let routineRowID = (try await routines.get(id: routineUUID))!.id

        let benchEntry = RoutineExercise(
            id: 0, clientUUID: UUID(),
            routineID: routineRowID, exerciseID: benchRowID, sortOrder: 0,
            targetSets: 3, targetRepMin: 5, targetRepMax: 8,
            targetRPE: nil, targetDurationSecsMin: nil, targetDurationSecsMax: nil,
            notes: nil, updatedAt: now
        )
        let backSquatEntry = RoutineExercise(
            id: 0, clientUUID: UUID(),
            routineID: routineRowID, exerciseID: backSquatRowID, sortOrder: 1,
            targetSets: 3, targetRepMin: 5, targetRepMax: 8,
            targetRPE: nil, targetDurationSecsMin: nil, targetDurationSecsMax: nil,
            notes: nil, updatedAt: now
        )
        try await routines.update(routine, exerciseEntries: [benchEntry, backSquatEntry], runEntries: [])

        // Session: log a set for each exercise, then finish.
        let session = try await sessions.start(routineID: routineUUID, type: .lift)
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: benchRowID,
            exerciseOrder: 0, setNumber: 1,
            setType: .working,
            weightKg: 100.0, reps: 5,
            durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        ))
        try await sets.append(SessionSet(
            id: 0, clientUUID: UUID(),
            sessionID: session.id, exerciseID: backSquatRowID,
            exerciseOrder: 1, setNumber: 1,
            setType: .working,
            weightKg: 120.0, reps: 5,
            durationSecs: nil, distanceM: nil,
            rpe: nil, completedAt: nil,
            notes: nil, updatedAt: now
        ))
        try await sessions.finish(id: session.clientUUID)

        // Drop Back Squat from the routine — keep only Bench Press.
        try await routines.update(routine, exerciseEntries: [benchEntry], runEntries: [])

        // Exercise the lift VM. load() rebuilds entries; loadLastExecution()
        // composes the summary against the now-shorter routine.
        let dbm = db!
        let vm = await MainActor.run { LiftRoutineDetailViewModel(dbManager: dbm) }
        await vm.load(routineID: routineUUID)
        await vm.loadLastExecution(routineID: routineUUID)
        let summary = try await MainActor.run {
            try XCTUnwrap(vm.lastExecutionSummary,
                          "loadLastExecution should produce a summary when a COMPLETED session exists")
        }

        // Bench Press is current → not removed. Back Squat is dropped → removed.
        let benchLine = summary.topSets.first(where: { $0.exerciseName == "Bench Press" })
        XCTAssertNotNil(benchLine, "Bench Press (still in routine) should appear in the summary")
        XCTAssertEqual(benchLine?.removed, false,
                       "Bench Press (still in routine) should not be marked removed")

        let backSquatLine = summary.topSets.first(where: { $0.exerciseName == "Back Squat" })
        XCTAssertNotNil(backSquatLine,
                        "Back Squat (logged last session, dropped from routine) should still appear in the summary as a muted row")
        XCTAssertEqual(backSquatLine?.removed, true,
                       "Back Squat should be marked removed=true after being dropped from the routine")
    }
}
