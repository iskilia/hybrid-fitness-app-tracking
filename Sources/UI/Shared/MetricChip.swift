import SwiftUI

/// A stat tile displaying an ALL-CAPS label and a monospaced number value.
/// Used in the Home screen week metrics row.
struct MetricChip: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)

            HStack(alignment: .lastTextBaseline, spacing: AppSpacing.xxs) {
                Text(value)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()

                if let unit {
                    Text(unit)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HStack {
        MetricChip(label: "WEEK", value: "3", unit: "sessions")
        MetricChip(label: "VOLUME", value: "8.4", unit: "t")
        MetricChip(label: "DISTANCE", value: "14", unit: "km")
    }
    .padding()
    .background(AppColor.background)
}
