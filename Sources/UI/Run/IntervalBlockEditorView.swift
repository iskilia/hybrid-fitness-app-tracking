import SwiftUI

// MARK: - IntervalBlockEditorView

/// Editable row for a single RunIntervalBlock within the custom template editor.
struct IntervalBlockEditorView: View {
    @Binding var block: EditableBlock

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Picker("Type", selection: $block.blockType) {
                    ForEach(IntervalBlockType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textPrimary)

                Spacer()

                HStack(spacing: AppSpacing.xs) {
                    Text("×")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    TextField("1", text: $block.repeatCount)
                        .keyboardType(.numberPad)
                        .font(AppFont.caption)
                        .frame(width: 32)
                        .multilineTextAlignment(.trailing)
                }
            }

            HStack(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("DIST (KM)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                    TextField("0.8", text: $block.distanceKm)
                        .keyboardType(.decimalPad)
                        .font(AppFont.captionMono)
                        .padding(AppSpacing.xs)
                        .background(AppColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                }
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("PACE (SECS)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                    TextField("210", text: $block.targetPaceSecs)
                        .keyboardType(.numberPad)
                        .font(AppFont.captionMono)
                        .padding(AppSpacing.xs)
                        .background(AppColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColor.background)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }
}

// MARK: - IntervalBlockType CaseIterable

extension IntervalBlockType: CaseIterable {
    public static var allCases: [IntervalBlockType] {
        [.warmup, .work, .recovery, .rest, .cooldown, .tempo]
    }
}
