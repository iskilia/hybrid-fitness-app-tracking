import SwiftUI

// MARK: - FilterChip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : AppColor.textPrimary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(isSelected ? AppColor.accent : AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }
}

// MARK: - EquipmentFilterRow

struct EquipmentFilterRow: View {
    let codes: [String]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(codes, id: \.self) { code in
                    FilterChip(
                        label: displayName(for: code),
                        isSelected: selected == code,
                        onTap: { selected = (selected == code) ? nil : code }
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    private func displayName(for code: String) -> String {
        code.replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - MuscleGroupFilterRow

struct MuscleGroupFilterRow: View {
    let groups: [String]
    @Binding var selected: String?

    private let displayMap: [String: String] = [
        "UPPER": "UPPER",
        "LOWER": "LOWER",
        "CORE": "CORE",
        "FULL_BODY": "FULL BODY"
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(groups, id: \.self) { group in
                    FilterChip(
                        label: displayMap[group] ?? group,
                        isSelected: selected == group,
                        onTap: { selected = (selected == group) ? nil : group }
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }
}
