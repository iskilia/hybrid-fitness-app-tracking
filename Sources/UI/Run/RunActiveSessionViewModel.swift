import Foundation
import Observation
import SQLite3

// MARK: - RunActiveSessionViewModel

@Observable
@MainActor
final class RunActiveSessionViewModel {

    // MARK: - Persisted state

    var session: Session?
    var sessionRun: SessionRun?
    var runTemplate: RunTemplate?
    var intervals: [RunIntervalBlock] = []

    // MARK: - Live metrics

    var elapsedSec: Int = 0
    var currentInterval: Int = 0

    // V1 data source — swap for V2 wearable bridge without touching the view
    private let dataSource: ManualRunDataSource = ManualRunDataSource()

    var distanceKm: Double {
        get { dataSource.currentDistanceKm }
        set { dataSource.currentDistanceKm = newValue }
    }

    var hrBpm: Int? {
        get { dataSource.currentHrBpm }
        set { dataSource.currentHrBpm = newValue }
    }

    var paceSecPerKm: Int? {
        dataSource.currentPaceSecPerKm(elapsedSec: elapsedSec)
    }

    // MARK: - Typed entry state

    var distanceText: String = ""
    var hrText: String = ""

    // MARK: - Manual pace entry (MM:SS wheel)

    var paceMinutes: Int = 0   // UI range 0…30
    var paceSeconds: Int = 0   // UI range 0…59

    /// User-picked pace, nil when left at 0:00 (then the computed pace is used).
    var manualPaceSecPerKm: Int? {
        let total = paceMinutes * 60 + paceSeconds
        return total > 0 ? total : nil
    }

    // MARK: - UI state

    var isPaused = false
    var isFinished = false
    var errorMessage: String?

    // MARK: - Storage guard

    private let storageGuard: StorageGuard
    private let profileRepo: UserProfileRepository
    var showStorageFullConfirm = false
    private var maxDataMb: Int = 10

    // MARK: - Private

    private let dbManager: DatabaseManager
    private var timerTask: Task<Void, Never>?

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
        self.storageGuard = StorageGuard(dbManager: dbManager)
        self.profileRepo = UserProfileRepository(dbManager: dbManager)
    }

    // MARK: - Load & start

    func start(sessionID: UUID) async {
        do {
            let sessionRepo = SessionRepository(dbManager: dbManager)
            guard let s = try await sessionRepo.get(id: sessionID) else { return }
            session = s

            if let routineIntID = s.routineID {
                let template = try await fetchFirstRunTemplate(routineIntID: routineIntID)
                runTemplate = template
                if let tmpl = template {
                    intervals = try await RunTemplateRepository(dbManager: dbManager)
                        .intervals(for: tmpl.clientUUID)
                }
            }

            let newRun = SessionRun(
                id: 0,
                clientUUID: UUID(),
                sessionID: s.id,
                runTemplateID: runTemplate?.id,
                runOrder: 1,
                actualDistanceKm: nil,
                durationSecs: nil,
                avgPaceSecs: nil,
                avgHR: nil,
                maxHR: nil,
                targetHRMin: runTemplate?.hrBpmMin,
                targetHRMax: runTemplate?.hrBpmMax,
                notes: nil,
                updatedAt: Date()
            )
            try await SessionRunRepository(dbManager: dbManager).append(newRun)
            sessionRun = newRun

            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Timer control

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            timerTask?.cancel()
        } else {
            startTimer()
        }
    }

    /// Parse typed text fields into the data source. Must be called before reading distanceKm/hrBpm.
    func commitTypedMetrics() {
        if let d = Double(distanceText) { distanceKm = d }
        hrBpm = Int(hrText)
    }

    func finish() async {
        commitTypedMetrics()
        timerTask?.cancel()
        isFinished = true
        guard let run = sessionRun, let sess = session else { return }
        do {
            try await SessionRunRepository(dbManager: dbManager).finish(
                id: run.clientUUID,
                distanceKm: distanceKm,
                durationSec: elapsedSec,
                avgPaceSecPerKm: manualPaceSecPerKm ?? paceSecPerKm,
                avgHrBpm: hrBpm
            )
            try await SessionRepository(dbManager: dbManager).finish(id: sess.clientUUID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Storage check (called after summary sheet dismisses)

    func checkStorageAfterFinish() async -> Bool {   // true => safe to pop
        if let p = try? await profileRepo.get() { maxDataMb = p.maxDataMb }
        let over = (try? await storageGuard.isOverLimit(maxDataMb: maxDataMb)) ?? false
        if over { showStorageFullConfirm = true; return false }
        return true
    }

    /// Returns true if eviction succeeded (caller may pop to Home); false on failure,
    /// in which case `errorMessage` is set and the caller should keep the user here.
    func confirmStorageEviction() async -> Bool {
        do {
            _ = try await storageGuard.reconcile(maxDataMb: maxDataMb)
            return true
        } catch {
            errorMessage = "Couldn't free space: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Private helpers

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.elapsedSec += 1
            }
        }
    }

    private func fetchFirstRunTemplate(routineIntID: Int) async throws -> RunTemplate? {
        try await dbManager.read { db in
            let sql = """
                SELECT rt.id, rt.client_uuid, rt.name, rt.run_type,
                       rt.target_total_distance_km, rt.target_work_distance_km,
                       rt.target_pace_secs_min, rt.target_pace_secs_max,
                       rt.hr_zone_min, rt.hr_zone_max, rt.hr_bpm_min, rt.hr_bpm_max,
                       rt.is_custom, rt.created_at, rt.updated_at, rt.deleted_at
                FROM run_template rt
                JOIN routine_run rr ON rr.run_template_id = rt.id
                WHERE rr.routine_id = ?
                  AND rt.deleted_at IS NULL
                ORDER BY rr.sort_order ASC
                LIMIT 1;
                """
            let stmt = try prepare(db, sql)
            defer { finalize(stmt) }
            bindInt(stmt, 1, routineIntID)
            guard try step(stmt) else { return nil }
            guard
                let uuidStr = columnText(stmt, 1),
                let uuid = UUID(uuidString: uuidStr),
                let name = columnText(stmt, 2),
                let runTypeStr = columnText(stmt, 3),
                let runType = RunType(rawValue: runTypeStr),
                let createdAt = columnDate(stmt, 13),
                let updatedAt = columnDate(stmt, 14)
            else { return nil }
            return RunTemplate(
                id: Int(sqlite3_column_int64(stmt, 0)),
                clientUUID: uuid,
                name: name,
                runType: runType,
                targetTotalDistanceKm: columnDouble(stmt, 4),
                targetWorkDistanceKm: columnDouble(stmt, 5),
                targetPaceSecsMin: columnInt(stmt, 6),
                targetPaceSecsMax: columnInt(stmt, 7),
                hrZoneMin: columnInt(stmt, 8),
                hrZoneMax: columnInt(stmt, 9),
                hrBpmMin: columnInt(stmt, 10),
                hrBpmMax: columnInt(stmt, 11),
                isCustom: columnBool(stmt, 12),
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: columnDate(stmt, 15)
            )
        }
    }
}

// MARK: - Formatting helpers

extension RunActiveSessionViewModel {
    var elapsedFormatted: String {
        formattedDuration(elapsedSec)
    }

    var paceFormatted: String {
        guard let p = paceSecPerKm else { return "--:--" }
        return String(format: "%d:%02d", p / 60, p % 60)
    }

    /// Tile display: manual pick if set, else the computed pace.
    var paceDisplay: String {
        guard let p = manualPaceSecPerKm else { return paceFormatted }
        return String(format: "%d:%02d", p / 60, p % 60)
    }

    var distanceFormatted: String {
        String(format: "%.2f", distanceKm)
    }
}
