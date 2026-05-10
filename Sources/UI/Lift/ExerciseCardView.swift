import SwiftUI

/// Card encapsulating an exercise and its editable set rows during an active lift session.
struct ExerciseCardView: View {
    @Bindable var card: ExerciseCardState
    let exerciseOrder: Int
    let onCommitRow: (SetRowState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            setRowHeader
            ForEach(Array(card.rows.enumerated()), id: \.element.id) { index, row in
                SetRow(
                    setIndex: index + 1,
                    prevDisplay: prevDisplay(for: index),
                    row: row,
                    onCommit: { onCommitRow(row) }
                )
                Divider()
                    .background(AppColor.divider)
                    .padding(.leading, AppSpacing.md)
            }
            addSetButton
        }
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Private

    private var cardHeader: some View {
        HStack(spacing: AppSpacing.md) {
            // Abbrev tile
            Text(abbrev)
                .font(AppFont.bodyBold)
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 48, height: 48)
                .background(AppColor.background)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(card.exercise.name)
                    .font(AppFont.bodyBold)
                    .foregroundStyle(AppColor.textPrimary)
                if let prev = card.previousBest {
                    Text(prev)
                        .font(AppFont.captionMono)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .padding(AppSpacing.md)
    }

    private var setRowHeader: some View {
        HStack(spacing: AppSpacing.xs) {
            Text("SET")
                .frame(width: 20, alignment: .center)
            Text("PREV")
                .frame(maxWidth: .infinity, alignment: .center)
            Text("KG")
                .frame(maxWidth: .infinity, alignment: .center)
            Text("REPS")
                .frame(maxWidth: .infinity, alignment: .center)
            Text("RPE")
                .frame(maxWidth: .infinity, alignment: .center)
            Image(systemName: "checkmark")
                .frame(width: 28, alignment: .center)
        }
        .font(AppFont.caption)
        .foregroundStyle(AppColor.textSecondary)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColor.divider.opacity(0.4))
    }

    private var addSetButton: some View {
        Button {
            card.rows.append(SetRowState())
        } label: {
            Text("+ ADD SET")
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm)
        }
    }

    private var abbrev: String {
        let a = card.exercise.abbreviation
        return a.isEmpty ? String(card.exercise.name.prefix(3)).uppercased() : a
    }

    /// Show the previous row's weight × reps as the "prev" hint for the current row.
    private func prevDisplay(for index: Int) -> String? {
        guard index > 0 else { return nil }
        let prev = card.rows[index - 1]
        guard !prev.weightText.isEmpty || !prev.repsText.isEmpty else { return nil }
        return "\(prev.weightText.isEmpty ? "—" : prev.weightText)×\(prev.repsText.isEmpty ? "—" : prev.repsText)"
    }
}
