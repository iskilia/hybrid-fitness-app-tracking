import SwiftUI

struct DistanceTile: View {
    let distanceKm: Double
    let onIncrement: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("DISTANCE")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text(String(format: "%.2f", distanceKm))
                .font(AppFont.metricSmall)
                .foregroundStyle(AppColor.textPrimary)
            Text("KM")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Button("+0.1", action: onIncrement)
                .font(AppFont.captionMono)
                .foregroundStyle(AppColor.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(AppFont.metricSmall)
                .foregroundStyle(AppColor.textPrimary)
            Text(unit)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Color.clear.frame(height: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

struct HRTile: View {
    let hrBpm: Int?
    let targetMin: Int?
    let targetMax: Int?
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("HR")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text(hrBpm.map { String($0) } ?? "--")
                .font(AppFont.metricSmall)
                .foregroundStyle(AppColor.textPrimary)
            Text("BPM")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            HStack(spacing: AppSpacing.sm) {
                Button("−", action: onDecrement)
                Button("+", action: onIncrement)
            }
            .font(AppFont.captionMono)
            .foregroundStyle(AppColor.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(alignment: .top) {
            if let min = targetMin, let max = targetMax {
                Text("\(min)–\(max)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 2)
            }
        }
    }
}

struct IntervalStripView: View {
    let intervals: [RunIntervalBlock]
    let current: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(Array(intervals.enumerated()), id: \.element.id) { idx, block in
                    Text(IntervalDescription.short(for: block))
                        .font(AppFont.captionMono)
                        .foregroundStyle(idx == current ? .white : AppColor.textPrimary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(idx == current ? AppColor.accent : AppColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                }
            }
        }
    }
}
