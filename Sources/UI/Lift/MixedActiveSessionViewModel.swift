import Foundation
import Observation
import SQLite3

// MARK: - BlockKind

enum BlockKind {
    case lift, run
}

// MARK: - MixedBlockState

@Observable
@MainActor
final class MixedBlockState: Identifiable {
    let id: UUID
    let kind: BlockKind
    let sortOrder: Int
    // LIFT
    let exercise: Exercise?
    let routineExercise: RoutineExercise?
    var rows: [SetRowState]
    var prevDisplays: [String?]
    // RUN
    let runTemplate: RunTemplate?
    let routineRun: RoutineRun?
    var sessionRun: SessionRun?
    var runDistanceText: String
    var runPaceText: String
    var runHrText: String
    var runCadenceText: String
    // shared
    var isDone: Bool

    init(
        id: UUID = UUID(),
        kind: BlockKind,
        sortOrder: Int,
        exercise: Exercise? = nil,
        routineExercise: RoutineExercise? = nil,
        rows: [SetRowState] = [],
        prevDisplays: [String?] = [],
        runTemplate: RunTemplate? = nil,
        routineRun: RoutineRun? = nil,
        sessionRun: SessionRun? = nil,
        runDistanceText: String = "",
        runPaceText: String = "",
        runHrText: String = "",
        runCadenceText: String = "",
        isDone: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.sortOrder = sortOrder
        self.exercise = exercise
        self.routineExercise = routineExercise
        self.rows = rows
        self.prevDisplays = prevDisplays
        self.runTemplate = runTemplate
        self.routineRun = routineRun
        self.sessionRun = sessionRun
        self.runDistanceText = runDistanceText
        self.runPaceText = runPaceText
        self.runHrText = runHrText
        self.runCadenceText = runCadenceText
        self.isDone = isDone
    }
}

// MARK: - MixedActiveSessionViewModel

@Observable
@MainActor
final class MixedActiveSessionViewModel {
    var session: Session?
    var routine: Routine?
    var blocks: [MixedBlockState] = []
    var activeBlockID: UUID?
    var distanceUnit: DistanceUnit = .km
    var errorMessage: String?
    var showStorageFullConfirm = false

    private let sessionID: UUID
    private let sessionRepo: SessionRepository
    private let sessionSetRepo: SessionSetRepository
    private let sessionRunRepo: SessionRunRepository
    private let routineRepo: RoutineRepository
    private let exerciseRepo: ExerciseRepository
    private let storageGuard: StorageGuard
    private let profileRepo: UserProfileRepository
    private let dbManager: DatabaseManager
    private var maxDataMb: Int = 10

    init(sessionID: UUID, dbManager: DatabaseManager) {
        self.sessionID = sessionID
        self.dbManager = dbManager
        self.sessionRepo    = SessionRepository(dbManager: dbManager)
        self.sessionSetRepo = SessionSetRepository(dbManager: dbManager)
        self.sessionRunRepo = SessionRunRepository(dbManager: dbManager)
        self.routineRepo    = RoutineRepository(dbManager: dbManager)
        self.exerciseRepo   = ExerciseRepository(dbManager: dbManager)
        self.storageGuard   = StorageGuard(dbManager: dbManager)
        self.profileRepo    = UserProfileRepository(dbManager: dbManager)
    }

    // MARK: - Load

    func load() async {
        do {
            if let p = try await profileRepo.get() {
                maxDataMb = p.maxDataMb
                distanceUnit = p.distanceUnit
            }

            let s = try await sessionRepo.get(id: sessionID)
            self.session = s
            guard let s else { return }

            if let routineRowID = s.routineID {
                let allRoutines = try await routineRepo.list()
                self.routine = allRoutines.first(where: { $0.id == routineRowID })
            }
            guard let routine else { return }

            // --- Build lift blocks ---
            let routineExercises = try await routineRepo.listExercises(routineID: routine.clientUUID)
            let allExercises     = try await exerciseRepo.listAll()
            let exerciseByID     = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })
            let du = distanceUnit

            var liftBlocks: [MixedBlockState] = []
            for re in routineExercises {
                guard let exercise = exerciseByID[re.exerciseID] else { continue }

                // Previous best per row
                let topSets = try await sessionSetRepo.topSetPerSession(exerciseID: exercise.clientUUID, limit: 1)
                var prevDisplay: String? = nil
                if let top = topSets.first {
                    let wStr = top.weightKg.truncatingRemainder(dividingBy: 1) == 0
                        ? "\(Int(top.weightKg))" : String(format: "%.1f", top.weightKg)
                    prevDisplay = "\(wStr) × \(top.reps ?? 0)"
                }

                // Build rows — one per targetSets (or 1)
                let count = re.targetSets ?? 1
                var rows: [SetRowState] = []
                var prevDisplays: [String?] = []
                let targetWeight: Double? = topSets.first?.weightKg
                let targetReps: Int? = re.targetRepMin
                for _ in 0..<count {
                    rows.append(SetRowState(
                        weight: targetWeight,
                        reps: targetReps,
                        distanceUnit: du
                    ))
                    prevDisplays.append(prevDisplay)
                }

                liftBlocks.append(MixedBlockState(
                    kind: .lift,
                    sortOrder: re.sortOrder,
                    exercise: exercise,
                    routineExercise: re,
                    rows: rows,
                    prevDisplays: prevDisplays
                ))
            }

            // --- Build run blocks ---
            let rawRuns = try await fetchRoutineRuns(routineIntID: routine.id)
            let templateRepo = RunTemplateRepository(dbManager: dbManager)
            var runBlocks: [MixedBlockState] = []
            var runOrder = 1
            for routineRun in rawRuns {
                let templates = try await templateRepo.listAll()
                guard let tmpl = templates.first(where: { $0.id == routineRun.runTemplateID }) else { continue }

                // Create SessionRun row up front
                let newRun = SessionRun(
                    id: 0,
                    clientUUID: UUID(),
                    sessionID: s.id,
                    runTemplateID: tmpl.id,
                    runOrder: runOrder,
                    actualDistanceKm: nil,
                    durationSecs: nil,
                    avgPaceSecs: nil,
                    avgHR: nil,
                    maxHR: nil,
                    targetHRMin: tmpl.hrBpmMin,
                    targetHRMax: tmpl.hrBpmMax,
                    notes: nil,
                    updatedAt: Date()
                )
                try await sessionRunRepo.append(newRun)

                runBlocks.append(MixedBlockState(
                    kind: .run,
                    sortOrder: routineRun.sortOrder,
                    runTemplate: tmpl,
                    routineRun: routineRun,
                    sessionRun: newRun
                ))
                runOrder += 1
            }

            // Order: all lift blocks by sort_order, then all run blocks by sort_order
            let sortedLift = liftBlocks.sorted { $0.sortOrder < $1.sortOrder }
            let sortedRun  = runBlocks.sorted  { $0.sortOrder < $1.sortOrder }
            self.blocks = sortedLift + sortedRun

            activeBlockID = blocks.first(where: { !$0.isDone })?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Block control

    func expand(_ block: MixedBlockState) {
        activeBlockID = block.id
    }

    func markLiftBlockDone(_ block: MixedBlockState) async {
        guard let blockIndex = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let exerciseOrder = blockIndex + 1
        for row in block.rows {
            await persistLiftRow(row, in: block, exerciseOrder: exerciseOrder)
        }
        for row in block.rows { row.isCompleted = true }
        block.isDone = true
        advanceToNextBlock(after: block)
    }

    func markRunBlockDone(_ block: MixedBlockState) async {
        guard let run = block.sessionRun else {
            block.isDone = true
            advanceToNextBlock(after: block)
            return
        }
        let distanceKm = Double(block.runDistanceText) ?? 0.0
        let paceText = block.runPaceText  // e.g. "4:35"
        let avgPaceSec = parsePaceSecs(paceText)
        let avgHr = Int(block.runHrText)
        try? await sessionRunRepo.finish(
            id: run.clientUUID,
            distanceKm: distanceKm,
            durationSec: 0,
            avgPaceSecPerKm: avgPaceSec,
            avgHrBpm: avgHr
        )
        block.isDone = true
        advanceToNextBlock(after: block)
    }

    func advanceToNextBlock(after block: MixedBlockState) {
        guard let idx = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let next = blocks[(idx + 1)...].first(where: { !$0.isDone })
        activeBlockID = next?.id
    }

    // MARK: - Persist all

    func persistAll() async {
        for (index, block) in blocks.enumerated() {
            if block.kind == .lift {
                for row in block.rows {
                    await persistLiftRow(row, in: block, exerciseOrder: index + 1)
                }
            } else {
                guard let run = block.sessionRun else { continue }
                let distanceKm = Double(block.runDistanceText) ?? 0.0
                let avgPaceSec = parsePaceSecs(block.runPaceText)
                let avgHr = Int(block.runHrText)
                try? await sessionRunRepo.finish(
                    id: run.clientUUID,
                    distanceKm: distanceKm,
                    durationSec: 0,
                    avgPaceSecPerKm: avgPaceSec,
                    avgHrBpm: avgHr
                )
            }
        }
    }

    // MARK: - Finish / Save

    func saveAndExit() async {
        await persistAll()
        // leave session OPEN — caller pops
    }

    func finish() async -> Bool {
        await persistAll()
        try? await sessionRepo.finish(id: sessionID)
        if let p = try? await profileRepo.get() { maxDataMb = p.maxDataMb }
        let over = (try? await storageGuard.isOverLimit(maxDataMb: maxDataMb)) ?? false
        if over { showStorageFullConfirm = true; return false }
        return true
    }

    func confirmStorageEviction() async -> Bool {
        do {
            _ = try await storageGuard.reconcile(maxDataMb: maxDataMb)
            return true
        } catch {
            errorMessage = "Couldn't free space: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Computed totals

    var liftTonnage: Double {
        blocks.filter { $0.kind == .lift && $0.isDone }.flatMap { block in
            block.rows.compactMap { row -> Double? in
                guard let kg = Double(row.weightText), let reps = Int(row.repsText) else { return nil }
                return kg * Double(reps)
            }
        }.reduce(0, +)
    }

    var runDistanceKm: Double {
        blocks.filter { $0.kind == .run && $0.isDone }.compactMap { Double($0.runDistanceText) }.reduce(0, +)
    }

    var completedBlockCount: Int {
        blocks.filter { $0.isDone }.count
    }

    // MARK: - Private helpers

    private func persistLiftRow(_ row: SetRowState, in block: MixedBlockState, exerciseOrder: Int) async {
        guard let s = session, let exercise = block.exercise else { return }
        let isTime     = exercise.metricType == .time
        let isDistance = exercise.metricType == .distance
        if isTime,      row.durationSecsText.isEmpty { return }
        if isDistance,  row.distanceText.isEmpty     { return }
        if !isTime && !isDistance, row.weightText.isEmpty && row.repsText.isEmpty { return }

        let now = Date()
        let setNumber = (block.rows.firstIndex(where: { $0.id == row.id }) ?? 0) + 1
        let rpe = Double(row.rpeText)
        let du = distanceUnit

        let weightKg:     Double? = (isTime || isDistance) ? nil : Double(row.weightText)
        let reps:         Int?    = (isTime || isDistance) ? nil : Int(row.repsText)
        let durationSecs: Int?    = isTime ? Int(row.durationSecsText) : nil
        let distanceM:    Double? = isDistance
            ? Double(row.distanceText).map { du == .km ? $0 * 1000.0 : $0 * 1609.344 }
            : nil

        if let existing = row.persistedSet {
            let updated = SessionSet(
                id: existing.id,
                clientUUID: existing.clientUUID,
                sessionID: existing.sessionID,
                exerciseID: existing.exerciseID,
                exerciseOrder: exerciseOrder,
                setNumber: setNumber,
                setType: existing.setType,
                weightKg: weightKg,
                reps: reps,
                durationSecs: durationSecs,
                distanceM: distanceM,
                rpe: rpe,
                completedAt: row.isCompleted ? now : existing.completedAt,
                notes: nil,
                updatedAt: now
            )
            try? await sessionSetRepo.update(updated)
        } else {
            let newSet = SessionSet(
                id: 0,
                clientUUID: row.id,
                sessionID: s.id,
                exerciseID: exercise.id,
                exerciseOrder: exerciseOrder,
                setNumber: setNumber,
                setType: .working,
                weightKg: weightKg,
                reps: reps,
                durationSecs: durationSecs,
                distanceM: distanceM,
                rpe: rpe,
                completedAt: row.isCompleted ? now : nil,
                notes: nil,
                updatedAt: now
            )
            try? await sessionSetRepo.append(newSet)
            row.persistedSet = newSet
        }
    }

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

    private func parsePaceSecs(_ text: String) -> Int? {
        // Expects "M:SS" format
        let parts = text.split(separator: ":").map { String($0) }
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}
