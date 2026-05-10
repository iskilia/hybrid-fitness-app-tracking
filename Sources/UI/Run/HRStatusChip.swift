import SwiftUI

// MARK: - HRStatus

enum HRStatus {
    case withinTarget   // green
    case slightlyOff    // amber — within 5–10 bpm outside range
    case farOff         // red — more than 10 bpm outside range
    case noTarget       // no target configured

    var color: Color {
        switch self {
        case .withinTarget: return AppColor.success
        case .slightlyOff:  return AppColor.warning
        case .farOff:       return AppColor.danger
        case .noTarget:     return AppColor.textSecondary
        }
    }
}

// MARK: - HRStatusChip

/// Small chip showing current HR vs target range.
/// Green = within target, amber = ≤10 bpm out, red = >10 bpm out.
struct HRStatusChip: View {
    let currentBpm: Int?
    let targetMin: Int?
    let targetMax: Int?

    private var status: HRStatus {
        guard let bpm = currentBpm else { return .noTarget }
        guard let lo = targetMin, let hi = targetMax else { return .noTarget }
        if bpm >= lo && bpm <= hi { return .withinTarget }
        let delta = bpm < lo ? lo - bpm : bpm - hi
        return delta <= 10 ? .slightlyOff : .farOff
    }

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if let lo = targetMin, let hi = targetMax {
                Text("TARGET \(lo)–\(hi) BPM")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            if let bpm = currentBpm {
                Text("\(bpm) BPM")
                    .font(AppFont.captionMono)
                    .foregroundStyle(status.color)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(status.color.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Text("NO HR")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}

#Preview {
    VStack(spacing: AppSpacing.lg) {
        HRStatusChip(currentBpm: 145, targetMin: 128, targetMax: 142)
        HRStatusChip(currentBpm: 150, targetMin: 128, targetMax: 142)
        HRStatusChip(currentBpm: 165, targetMin: 128, targetMax: 142)
        HRStatusChip(currentBpm: nil, targetMin: 128, targetMax: 142)
        HRStatusChip(currentBpm: 145, targetMin: nil, targetMax: nil)
    }
    .padding()
    .background(AppColor.background)
}
