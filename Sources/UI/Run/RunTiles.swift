import SwiftUI

struct DistanceTile: View {
    @Binding var distanceText: String

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("DISTANCE")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            TextField("0.00", text: $distanceText)
                .font(AppFont.metricSmall)
                .foregroundStyle(AppColor.textPrimary)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
            Text("KM")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
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
    @Binding var hrText: String
    let targetMin: Int?
    let targetMax: Int?

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("HR")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            TextField("--", text: $hrText)
                .font(AppFont.metricSmall)
                .foregroundStyle(AppColor.textPrimary)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
            Text("BPM")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
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
