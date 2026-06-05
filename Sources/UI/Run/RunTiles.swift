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

struct PaceTile: View {
    let value: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.xs) {
                Text("PACE")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Text(value)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(AppColor.textPrimary)
                Text("/KM")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Color.clear.frame(height: 16)
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.md)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
    }
}

struct PacePickerSheet: View {
    @Binding var minutes: Int
    @Binding var seconds: Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("PACE /KM")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, AppSpacing.lg)

            HStack(spacing: AppSpacing.sm) {
                Picker("MIN", selection: $minutes) {
                    ForEach(0...30, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Text(":")
                    .font(AppFont.metricSmall)
                    .foregroundStyle(AppColor.textPrimary)

                Picker("SEC", selection: $seconds) {
                    ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }

            Button("Done", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.lg)
        }
        .presentationDetents([.height(280)])
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
