import Foundation

// MARK: - RunSessionDataSource

/// Abstracts the source of live run metrics.
/// V1: manual entry (user bumps values via UI controls).
/// V2: HealthKit / WatchConnectivity feed implements this protocol.
@MainActor
protocol RunSessionDataSource: AnyObject {
    /// Total distance covered, in kilometres.
    var currentDistanceKm: Double { get set }
    /// Current heart rate in BPM. Nil if not yet entered.
    var currentHrBpm: Int? { get set }
    /// Computed pace in seconds per kilometre. Nil when distance is zero.
    func currentPaceSecPerKm(elapsedSec: Int) -> Int?
}

// MARK: - ManualRunDataSource (V1)

/// V1 manual-entry implementation.  The user directly sets distance and HR
/// through UI controls; pace is derived from distance / elapsed time.
/// V2: HealthKit / WatchConnectivity feed implements RunSessionDataSource.
@MainActor
final class ManualRunDataSource: RunSessionDataSource {
    var currentDistanceKm: Double = 0.0
    var currentHrBpm: Int? = nil

    func currentPaceSecPerKm(elapsedSec: Int) -> Int? {
        guard currentDistanceKm > 0, elapsedSec > 0 else { return nil }
        return Int(Double(elapsedSec) / currentDistanceKm)
    }
}
