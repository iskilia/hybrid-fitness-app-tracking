import SwiftUI

/// Reusable exercise list row used by the routine detail and exercise library screens.
struct ExerciseRow: View {
    let exercise: Exercise
    let equipment: Equipment?
    let primaryMuscle: Muscle?

    /// Optional right-side trailing content (e.g. weight × rep range, or a + button).
    var trailingContent: AnyView?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            abbrevTile
            infoStack
            Spacer()
            if let trailing = trailingContent {
                trailing
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.lg)
        .background(AppColor.background)
    }
}

// MARK: - Subviews

private extension ExerciseRow {

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

    var abbreviation: String {
        let abbrev = exercise.abbreviation
        return abbrev.isEmpty ? String(exercise.name.prefix(3)).uppercased() : abbrev
    }

    var metaLine: String {
        let parts: [String?] = [
            equipment?.displayName.uppercased(),
            primaryMuscle?.displayName.uppercased()
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Preview

#Preview {
    let exercise = Exercise(
        id: 1,
        clientUUID: UUID(),
        name: "Bench Press",
        abbreviation: "BNC",
        equipmentID: 1,
        metricType: .reps,
        isCustom: false,
        notes: nil,
        formLink: nil,
        createdAt: .now,
        updatedAt: .now,
        deletedAt: nil
    )
    let equipment = Equipment(id: 1, code: "BARBELL", displayName: "Barbell")
    let muscle = Muscle(id: 1, code: "CHEST", displayName: "Chest", groupName: "UPPER")

    ExerciseRow(
        exercise: exercise,
        equipment: equipment,
        primaryMuscle: muscle,
        trailingContent: AnyView(Text("90KG × 5–8").font(AppFont.caption))
    )
    .background(AppColor.background)
}
