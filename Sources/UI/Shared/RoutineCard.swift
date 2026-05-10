import SwiftUI

/// Card tile for a single routine shown on the Home and Routines screens.
struct RoutineCard: View {
    let routine: Routine
    let lastPerformedText: String
    let subtitleText: String
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.sm) {
                        BadgeView(kind: routine.type)
                        Text(lastPerformedText)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Text(routine.name)
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)

                    Text(subtitleText)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(.uppercase)
                }

                Spacer()

                Button(action: onStart) {
                    Text("START")
                        .font(AppFont.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

#Preview {
    RoutineCard(
        routine: Routine(
            id: 1,
            clientUUID: UUID(),
            name: "Heavy Lower",
            type: .lift,
            sortOrder: 0,
            createdAt: .now,
            updatedAt: .now,
            deletedAt: nil
        ),
        lastPerformedText: "4 DAYS AGO",
        subtitleText: "4 EXERCISES",
        onStart: {}
    )
    .padding()
    .background(AppColor.background)
}
