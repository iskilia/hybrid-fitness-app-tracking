import Foundation
import Observation

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
    let runOrder: Int          // 1-based slot order for run blocks (0 for lift)
    var sessionRun: SessionRun?
    var runDistanceText: String
    var paceMinutes: Int   // MM:SS wheel, MIN 0…30
    var paceSeconds: Int   // MM:SS wheel, SEC 0…59
    var runHrText: String
    var runCadenceText: String
    /// When this run block first became active; used to compute per-block duration.
    var startedAt: Date?
    /// Per-block duration frozen at completion, so re-persisting a done block doesn't
    /// re-measure `now − startedAt` and absorb later blocks' wall-clock time.
    var elapsedSec: Int?
    // shared
    var isDone: Bool

    /// User-picked pace, nil when left at 0:00.
    var manualPaceSecPerKm: Int? {
        let total = paceMinutes * 60 + paceSeconds
        return total > 0 ? total : nil
    }

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
        runOrder: Int = 0,
        sessionRun: SessionRun? = nil,
        runDistanceText: String = "",
        paceMinutes: Int = 0,
        paceSeconds: Int = 0,
        runHrText: String = "",
        runCadenceText: String = "",
        startedAt: Date? = nil,
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
        self.runOrder = runOrder
        self.sessionRun = sessionRun
        self.runDistanceText = runDistanceText
        self.paceMinutes = paceMinutes
        self.paceSeconds = paceSeconds
        self.runHrText = runHrText
        self.runCadenceText = runCadenceText
        self.startedAt = startedAt
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
            let rawRuns = try await routineRepo.runs(routineIntID: routine.id)
            let templateRepo = RunTemplateRepository(dbManager: dbManager)
            let templatesByID = Dictionary(uniqueKeysWithValues: try await templateRepo.listAll().map { ($0.id, $0) })
            // Build run-block STATE only — the session_run row is created lazily on first
            // write (markRunBlockDone / persistAll) so abandoning the screen leaves no orphan rows.
            var runBlocks: [MixedBlockState] = []
            var runOrder = 1
            for routineRun in rawRuns {
                guard let tmpl = templatesByID[routineRun.runTemplateID] else { continue }
                runBlocks.append(MixedBlockState(
                    kind: .run,
                    sortOrder: routineRun.sortOrder,
                    runTemplate: tmpl,
                    routineRun: routineRun,
                    runOrder: runOrder
                ))
                runOrder += 1
            }

            // Order: all lift blocks by sort_order, then all run blocks by sort_order
            let sortedLift = liftBlocks.sorted { $0.sortOrder < $1.sortOrder }
            let sortedRun  = runBlocks.sorted  { $0.sortOrder < $1.sortOrder }
            self.blocks = sortedLift + sortedRun

            activeBlockID = blocks.first(where: { !$0.isDone })?.id
            touchStartForActiveRun()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Block control

    func expand(_ block: MixedBlockState) {
        activeBlockID = block.id
        touchStartForActiveRun()
    }

    /// Stamps `startedAt` on the active run block the first time it opens (per-block timer start).
    private func touchStartForActiveRun() {
        guard let id = activeBlockID,
              let b = blocks.first(where: { $0.id == id }),
              b.kind == .run, b.startedAt == nil else { return }
        b.startedAt = Date()
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
        // Freeze the measured duration at completion so later re-persists don't grow it.
        block.elapsedSec = block.startedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        await writeRunRow(block)
        block.isDone = true
        advanceToNextBlock(after: block)
    }

    func advanceToNextBlock(after block: MixedBlockState) {
        guard let idx = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let next = blocks[(idx + 1)...].first(where: { !$0.isDone })
        activeBlockID = next?.id
        touchStartForActiveRun()
    }

    /// True if the user entered any run metric (so persistAll should write even if not marked done).
    private func runBlockHasData(_ block: MixedBlockState) -> Bool {
        !block.runDistanceText.isEmpty
            || block.manualPaceSecPerKm != nil
            || !block.runHrText.isEmpty
    }

    /// Lazily creates the session_run row on first write, or updates it thereafter.
    /// Persists per-block duration measured from `startedAt`.
    private func writeRunRow(_ block: MixedBlockState) async {
        guard let s = session, let tmpl = block.runTemplate else { return }
        let distanceKm = Double(block.runDistanceText)
        let avgPaceSec = block.manualPaceSecPerKm
        let avgHr = Int(block.runHrText)
        // Reuse the value frozen at completion; for an in-progress (not-done) block measure live.
        // max(0, …) guards a backwards system-clock jump (NTP/manual change).
        let duration = block.elapsedSec ?? block.startedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0

        if let run = block.sessionRun {
            try? await sessionRunRepo.finish(
                id: run.clientUUID,
                distanceKm: distanceKm,
                durationSec: duration,
                avgPaceSecPerKm: avgPaceSec,
                avgHrBpm: avgHr
            )
        } else {
            let newRun = SessionRun(
                id: 0,
                clientUUID: UUID(),
                sessionID: s.id,
                runTemplateID: tmpl.id,
                runOrder: block.runOrder,
                actualDistanceKm: distanceKm,
                durationSecs: duration,
                avgPaceSecs: avgPaceSec,
                avgHR: avgHr,
                maxHR: nil,
                targetHRMin: tmpl.hrBpmMin,
                targetHRMax: tmpl.hrBpmMax,
                notes: nil,
                updatedAt: Date()
            )
            try? await sessionRunRepo.append(newRun)
            block.sessionRun = newRun
        }
    }

    // MARK: - Persist all

    func persistAll() async {
        for (index, block) in blocks.enumerated() {
            if block.kind == .lift {
                for row in block.rows {
                    await persistLiftRow(row, in: block, exerciseOrder: index + 1)
                }
            } else {
                // Skip untouched run blocks (never opened with data, not done) so no orphan rows.
                if block.sessionRun != nil || block.isDone || runBlockHasData(block) {
                    await writeRunRow(block)
                }
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
        let setNumber = (block.rows.firstIndex(where: { $0.id == row.id }) ?? 0) + 1
        do {
            try await SetRowPersistence.persist(
                row,
                exercise: exercise,
                sessionRowID: s.id,
                exerciseOrder: exerciseOrder,
                setNumber: setNumber,
                distanceUnit: distanceUnit,
                repo: sessionSetRepo
            )
        } catch {
            errorMessage = "Couldn't save set: \(error.userMessage)"
        }
    }
}
