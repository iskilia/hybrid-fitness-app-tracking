import Foundation

// MARK: - IntervalDescription

/// Builds a compact human-readable description from a set of RunIntervalBlock rows.
/// Example output: "5 × 800M @ 3:30 + 200M JOG" or "2K WU · 5K T · 1K CD"
enum IntervalDescription {
    static func describe(_ blocks: [RunIntervalBlock]) -> String {
        guard !blocks.isEmpty else { return "" }

        // Group consecutive WORK+RECOVERY pairs that share the same repeat_count
        var parts: [String] = []
        var i = 0
        while i < blocks.count {
            let block = blocks[i]
            // If WORK block with a potential following RECOVERY, try to pair them
            if block.blockType == .work,
               i + 1 < blocks.count,
               blocks[i + 1].blockType == .recovery,
               block.repeatCount > 1 {
                let work = block
                let rec = blocks[i + 1]
                let workLabel = distanceLabel(work)
                let paceLabel = paceLabel(work)
                let recLabel = distanceLabel(rec)
                var part = "\(work.repeatCount) \u{D7} \(workLabel)"
                if let p = paceLabel { part += " @ \(p)" }
                part += " + \(recLabel) JOG"
                parts.append(part)
                i += 2
            } else {
                parts.append(blockShortLabel(block))
                i += 1
            }
        }
        return parts.joined(separator: " \u{B7} ")
    }

    // MARK: - Private helpers

    private static func distanceLabel(_ block: RunIntervalBlock) -> String {
        if let km = block.distanceKm {
            let m = Int(km * 1000)
            if m >= 1000 {
                let formatted = km.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(km))KM" : String(format: "%.1fKM", km)
                return formatted
            } else {
                return "\(m)M"
            }
        }
        if let secs = block.durationSecs {
            let mins = secs / 60
            return "\(mins)MIN"
        }
        return ""
    }

    private static func paceLabel(_ block: RunIntervalBlock) -> String? {
        guard let secs = block.targetPaceSecs, secs > 0 else { return nil }
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }

    static func short(for block: RunIntervalBlock) -> String {
        blockShortLabel(block)
    }

    private static func blockShortLabel(_ block: RunIntervalBlock) -> String {
        let dist = distanceLabel(block)
        let suffix: String
        switch block.blockType {
        case .warmup:   suffix = "WU"
        case .work:     suffix = "T"
        case .recovery: suffix = "REC"
        case .rest:     suffix = "REST"
        case .cooldown: suffix = "CD"
        case .tempo:    suffix = "T"
        }
        let prefix = dist.isEmpty ? "" : "\(dist) "
        return "\(prefix)\(suffix)"
    }
}
