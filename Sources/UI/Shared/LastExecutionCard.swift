import SwiftUI

// TV5.1 — Shared "Last time" recall card.

// MARK: - Public model

public struct LastExecutionSummary: Sendable, Equatable {
    public let sessionID: UUID
    public let finishedAt: Date
    public let totalDurationSecs: Int

    public struct TopSetLine: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let exerciseName: String
        public let display: String
        public let removed: Bool

        public init(id: UUID, exerciseName: String, display: String, removed: Bool) {
            self.id = id
            self.exerciseName = exerciseName
            self.display = display
            self.removed = removed
        }
    }

    public let topSets: [TopSetLine]

    public init(
        sessionID: UUID,
        finishedAt: Date,
        totalDurationSecs: Int,
        topSets: [TopSetLine]
    ) {
        self.sessionID = sessionID
        self.finishedAt = finishedAt
        self.totalDurationSecs = totalDurationSecs
        self.topSets = topSets
    }
}

// MARK: - Private helpers

private func formattedDuration(_ totalSecs: Int) -> String {
    let h = totalSecs / 3600
    let m = (totalSecs % 3600) / 60
    let s = totalSecs % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%02d:%02d", m, s)
    }
}

private func relativeString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .spellOut
    return formatter.localizedString(for: date, relativeTo: .now)
}

// MARK: - View

public struct LastExecutionCard: View {
    public let summary: LastExecutionSummary?
    public let isLoading: Bool
    public let onTap: () -> Void

    public init(summary: LastExecutionSummary?, isLoading: Bool, onTap: @escaping () -> Void) {
        self.summary = summary
        self.isLoading = isLoading
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let summary {
                populatedView(summary)
            } else {
                emptyView
            }
        }
    }

    // MARK: Loading skeleton

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(AppColor.divider)
                .frame(height: 14)
                .frame(maxWidth: 160)

            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(AppColor.divider)
                .frame(height: 12)
                .frame(maxWidth: 100)

            VStack(spacing: AppSpacing.xs) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .fill(AppColor.divider)
                        .frame(height: 12)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .redacted(reason: .placeholder)
        .padding(AppSpacing.lg)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: Empty state

    private var emptyView: some View {
        Button(action: onTap) {
            Text("First time on this routine — no comparison yet")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.lg)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: Populated state

    private func populatedView(_ s: LastExecutionSummary) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {

                // Header — "Last time — 3 days ago"
                HStack(spacing: AppSpacing.xxs) {
                    Text("Last time — ")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    Text(relativeString(from: s.finishedAt))
                        .font(AppFont.captionMono)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Divider()
                    .background(AppColor.divider)

                // Total duration row
                HStack {
                    Text("TOTAL")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text(formattedDuration(s.totalDurationSecs))
                        .font(AppFont.captionMono)
                        .foregroundStyle(AppColor.textPrimary)
                }

                // Per-exercise rows
                if !s.topSets.isEmpty {
                    Divider()
                        .background(AppColor.divider)

                    ForEach(s.topSets) { line in
                        topSetRow(line)
                    }
                }
            }
            .padding(AppSpacing.lg)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func topSetRow(_ line: LastExecutionSummary.TopSetLine) -> some View {
        HStack {
            Text(line.exerciseName)
                .font(AppFont.caption)
                .foregroundStyle(line.removed ? AppColor.textMutedRemoved : AppColor.textPrimary)

            Spacer()

            Text(line.display)
                .font(AppFont.captionMono)
                .foregroundStyle(line.removed ? AppColor.textMutedRemoved : AppColor.textSecondary)

            if line.removed {
                Text("removed")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textMutedRemoved)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(AppColor.textMutedRemoved.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleSets: [LastExecutionSummary.TopSetLine] = [
        .init(id: UUID(), exerciseName: "Back Squat", display: "92.5 KG × 5", removed: false),
        .init(id: UUID(), exerciseName: "Romanian DL", display: "80 KG × 8", removed: false),
        .init(id: UUID(), exerciseName: "Leg Press", display: "120 KG × 10", removed: true),
    ]

    let populated = LastExecutionSummary(
        sessionID: UUID(),
        finishedAt: Date(timeIntervalSinceNow: -3 * 86400),
        totalDurationSecs: 3725,
        topSets: sampleSets
    )

    ScrollView {
        VStack(spacing: AppSpacing.xl) {
            // Loading state
            LastExecutionCard(summary: nil, isLoading: true, onTap: {})

            // Empty state
            LastExecutionCard(summary: nil, isLoading: false, onTap: {})

            // Populated state (3 rows, last marked removed)
            LastExecutionCard(summary: populated, isLoading: false, onTap: {})
        }
        .padding(AppSpacing.lg)
    }
    .background(AppColor.background)
}
