import Foundation

// MARK: - Duration

/// Formats a total-seconds count as H:MM:SS (h > 0) or MM:SS.
/// Hours are unpadded (e.g. "1:05:03"), minutes are always zero-padded.
func formattedDuration(_ totalSecs: Int) -> String {
    let h = totalSecs / 3600
    let m = (totalSecs % 3600) / 60
    let s = totalSecs % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Distance

/// Formats a kilometre value as "N.0 KM" for whole numbers or "N.n KM" otherwise.
/// e.g. 5.0 → "5.0 KM", 10.5 → "10.5 KM".
///
/// Note: `IntervalDescription.swift` uses a compact no-space style ("5KM", "400M")
/// for interval chip labels — this is intentional and deliberately differs from `kmLabel`.
func kmLabel(_ km: Double) -> String {
    km.truncatingRemainder(dividingBy: 1) == 0
        ? "\(Int(km)).0 KM"
        : String(format: "%.1f KM", km)
}

// MARK: - Pace

/// Formats a pace in seconds-per-km as "M:SS /KM".
/// e.g. 270 → "4:30 /KM".
func paceLabel(_ secsPerKm: Int) -> String {
    String(format: "%d:%02d /KM", secsPerKm / 60, secsPerKm % 60)
}

// MARK: - RunTemplate metaLine

extension RunTemplate {
    /// Builds the summary meta-line for a run template.
    ///
    /// - Parameters:
    ///   - includeRunType: Prepend the run-type raw value (e.g. "STEADY").
    ///   - includeBpm: Append HR BPM range (e.g. "140–160 BPM") when available.
    ///   - includeZone: Append HR zone (e.g. "Z2-3") when available.
    ///
    /// Callers choose which fields to include to preserve each screen's existing output:
    ///   - RunTypesView: includeRunType=true, includeBpm=true,  includeZone=false
    ///   - RunRow:       includeRunType=true, includeBpm=false, includeZone=true
    ///   - subLine (MixedActiveSessionView): includeRunType=false, includeBpm=false, includeZone=true
    func metaLine(includeRunType: Bool, includeBpm: Bool, includeZone: Bool) -> String {
        var parts: [String] = []
        if includeRunType { parts.append(runType.rawValue) }
        if let km = targetTotalDistanceKm { parts.append(kmLabel(km)) }
        if let paceMin = targetPaceSecsMin { parts.append(paceLabel(paceMin)) }
        if includeBpm, let bMin = hrBpmMin, let bMax = hrBpmMax {
            parts.append("\(bMin)–\(bMax) BPM")
        }
        if includeZone, let zMin = hrZoneMin, let zMax = hrZoneMax {
            parts.append("Z\(zMin)-\(zMax)")
        }
        return parts.joined(separator: " \u{B7} ")
    }
}
