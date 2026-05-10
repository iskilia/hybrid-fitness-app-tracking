import SwiftUI

/// A single row in the exercise library picker.
struct ExerciseLibraryRow: View {
    let exercise: Exercise
    let equipment: Equipment?
    let muscles: [Muscle]
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            abbrevTile
            infoStack
            Spacer()
            addButton
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.lg)
        .background(AppColor.background)
    }
}

private extension ExerciseLibraryRow {

    var abbrevTile: some View {
        Text(abbreviation)
            .font(AppFont.bodyBold)
            .foregroundStyle(AppColor.textPrimary)
            .frame(width: 56, height: 56)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    var infoStack: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(exercise.name)
                .font(AppFont.bodyBold)
                .foregroundStyle(AppColor.textPrimary)

            Text(metaLine)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
        }
    }

    var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 32, height: 32)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    var abbreviation: String {
        let abbrev = exercise.abbreviation
        return abbrev.isEmpty ? String(exercise.name.prefix(3)).uppercased() : abbrev
    }

    var metaLine: String {
        let muscleNames = muscles.prefix(3).map { $0.displayName.uppercased() }
        let parts: [String] = [
            equipment?.displayName.uppercased(),
        ].compactMap { $0 } + muscleNames
        return parts.joined(separator: " · ")
    }
}
