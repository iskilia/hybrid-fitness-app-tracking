import SwiftUI

/// Small pill badge displaying LIFT / RUN / MIXED with an orange dot indicator.
struct BadgeView: View {
    let kind: WorkoutType

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(AppColor.accentDark)
                .frame(width: 6, height: 6)

            Text(kind.rawValue)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.accentDark)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColor.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }
}

#Preview {
    HStack(spacing: 12) {
        BadgeView(kind: .lift)
        BadgeView(kind: .run)
        BadgeView(kind: .mixed)
    }
    .padding()
    .background(AppColor.background)
}
