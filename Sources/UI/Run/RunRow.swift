import SwiftUI

// MARK: - RunRow

/// A single run-template row for the run routine detail screen.
struct RunRow: View {
    let template: RunTemplate
    let intervals: [RunIntervalBlock]

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            typeTile
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(template.name)
                    .font(AppFont.bodyBold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(metaLine)
                    .font(AppFont.captionMono)
                    .foregroundStyle(AppColor.textSecondary)
                    .textCase(.uppercase)
                if let bpmText = bpmLine {
                    Text(bpmText)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                if !intervalDesc.isEmpty {
                    Text(intervalDesc)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Computed

    private var typeTile: some View {
        Text(template.runType.abbreviation)
            .font(AppFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(AppColor.accentDark)
            .frame(width: 44, height: 44)
            .background(AppColor.accentMuted)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    private var metaLine: String {
        template.metaLine(includeRunType: true, includeBpm: false, includeZone: true)
    }

    private var bpmLine: String? {
        guard let min = template.hrBpmMin, let max = template.hrBpmMax else { return nil }
        return "\(min)–\(max) BPM"
    }

    private var intervalDesc: String {
        IntervalDescription.describe(intervals)
    }
}

// MARK: - RunType abbreviation

extension RunType {
    var abbreviation: String {
        switch self {
        case .steady:    return "EZ"
        case .threshold: return "TMP"
        case .endurance: return "LNG"
        case .intervals: return "INT"
        case .fartlek:   return "FRT"
        case .recovery:  return "REC"
        }
    }
}
