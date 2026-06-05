import SwiftUI

// MARK: - LiftBlockCard

/// Reusable lift block card used by both LiftActiveSessionView and MixedActiveSessionView (lift path).
/// Owns the collapsed header + expanded lift body UI.
struct LiftBlockCard: View {
    /// Callbacks the card can fire. `onAddSet`/`onRowCommit` are optional (Mixed omits them).
    struct Actions {
        let onTap: () -> Void
        let onMarkAllDone: () -> Void
        let onNextBlock: () -> Void
        var onAddSet: (() -> Void)? = nil
        var onRowCommit: ((SetRowState) -> Void)? = nil
    }

    let blockNumber: Int
    let exercise: Exercise
    let routineExercise: RoutineExercise
    let distanceUnit: DistanceUnit
    let rows: [SetRowState]
    let prevDisplays: [String?]
    let isExpanded: Bool
    let isDone: Bool
    let actions: Actions

    private var metricType: MetricType { exercise.metricType }

    private var thumbnailText: String {
        let a = exercise.abbreviation
        return a.isEmpty ? String(exercise.name.prefix(3)).uppercased() : a
    }

    var body: some View {
        VStack(spacing: 0) {
            collapsedHeader
                .contentShape(Rectangle())
                .onTapGesture { actions.onTap() }

            if isExpanded {
                Divider().background(AppColor.divider)
                liftExpandedBody
            }
        }
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(isExpanded ? AppColor.accent : Color.clear, lineWidth: AppStroke.thin)
        )
        .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Collapsed header

    private var collapsedHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            statusNode

            thumbnailTile

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack(spacing: AppSpacing.xs) {
                    BadgeView(kind: .lift)
                    statePill
                }
                Text(exercise.name)
                    .font(AppFont.bodyBold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subLine)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                Text(progressReadout)
                    .font(AppFont.captionMono)
                    .foregroundStyle(AppColor.textSecondary)
                setDots
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(AppSpacing.md)
    }

    private var statusNode: some View {
        Group {
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.accent)
                    .font(.system(size: 20))
            } else {
                ZStack {
                    Circle()
                        .stroke(AppColor.divider, lineWidth: AppStroke.thin)
                        .frame(width: 24, height: 24)
                    Text("\(blockNumber)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .frame(width: 24)
    }

    private var thumbnailTile: some View {
        Text(thumbnailText)
            .font(AppFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(AppColor.accentDark)
            .frame(width: 44, height: 44)
            .background(AppColor.accentMuted)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    private var statePill: some View {
        Text(isDone ? "DONE" : "QUEUED")
            .font(AppFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(isDone ? AppColor.success : AppColor.textSecondary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background((isDone ? AppColor.success : AppColor.textSecondary).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    private var subLine: String {
        let sets = routineExercise.targetSets ?? rows.count
        let repStr: String
        if let lo = routineExercise.targetRepMin, let hi = routineExercise.targetRepMax { repStr = "\(lo)–\(hi)" }
        else if let lo = routineExercise.targetRepMin { repStr = "\(lo)" }
        else { repStr = "—" }
        let topKg = rows.compactMap { Double($0.weightText) }.max()
        let kgStr: String
        if let kg = topKg {
            kgStr = kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg)) KG" : String(format: "%.1f KG", kg)
        } else { kgStr = "" }
        let kgPart = kgStr.isEmpty ? "" : " · \(kgStr)"
        return "\(sets) × \(repStr)\(kgPart)"
    }

    private var progressReadout: String {
        let done = rows.filter { $0.isCompleted }.count
        return "\(done) / \(rows.count)"
    }

    private var setDots: some View {
        let completedCount = rows.filter { $0.isCompleted }.count
        return HStack(spacing: 2) {
            ForEach(rows.indices, id: \.self) { i in
                Circle()
                    .fill(i < completedCount ? AppColor.accent : AppColor.divider)
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Expanded lift body

    private var liftExpandedBody: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if let notes = routineExercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(AppFont.body.italic())
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
            }

            setTableHeader

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                LiftSetRow(
                    setIndex: index + 1,
                    prevDisplay: index < prevDisplays.count ? prevDisplays[index] : nil,
                    metricType: metricType,
                    distanceUnit: distanceUnit,
                    row: row,
                    onCommit: actions.onRowCommit.map { commit in { commit(row) } }
                )
                if index < rows.count - 1 {
                    Divider().background(AppColor.divider).padding(.leading, AppSpacing.md)
                }
            }

            if let addSet = actions.onAddSet {
                Button {
                    addSet()
                } label: {
                    Text("+ ADD SET")
                        .font(AppFont.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                }
                .padding(.horizontal, AppSpacing.md)
            }

            HStack(spacing: AppSpacing.sm) {
                Button {
                    actions.onMarkAllDone()
                } label: {
                    Text("MARK ALL DONE")
                        .font(AppFont.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColor.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                .stroke(AppColor.divider, lineWidth: AppStroke.thin)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                }

                Button {
                    actions.onNextBlock()
                } label: {
                    Text("NEXT BLOCK →")
                        .font(AppFont.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.md)
        }
    }

    private var setTableHeader: some View {
        HStack(spacing: AppSpacing.xs) {
            Text("SET").frame(width: 24, alignment: .center)
            Text("PREV").frame(maxWidth: .infinity, alignment: .center)
            if metricType == .time {
                Text("SECS").frame(maxWidth: .infinity, alignment: .center)
            } else if metricType == .distance {
                Text(distanceUnit == .km ? "KM" : "MI").frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text("KG").frame(maxWidth: .infinity, alignment: .center)
                Text("REPS").frame(maxWidth: .infinity, alignment: .center)
            }
            Image(systemName: "checkmark").frame(width: 28, alignment: .center)
        }
        .font(AppFont.caption)
        .foregroundStyle(AppColor.textSecondary)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColor.divider.opacity(0.4))
    }
}

// MARK: - LiftSetRow

/// Single editable set row for LiftBlockCard. Supports .reps (KG+REPS), .time (SECS), .distance (KM/MI).
/// No RPE column (per spec OPEN Q1).
private struct LiftSetRow: View {
    let setIndex: Int
    let prevDisplay: String?
    let metricType: MetricType
    let distanceUnit: DistanceUnit
    @Bindable var row: SetRowState
    let onCommit: (() -> Void)?

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Text("\(setIndex)")
                .font(AppFont.captionMono)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 24, alignment: .center)

            Text(prevDisplay ?? "—")
                .font(AppFont.captionMono)
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)

            if metricType == .time {
                TextField("Seconds", text: $row.durationSecsText)
                    .font(AppFont.captionMono)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if metricType == .distance {
                let placeholder = distanceUnit == .km ? "KM" : "MI"
                TextField(placeholder, text: $row.distanceText)
                    .font(AppFont.captionMono)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                TextField("KG", text: $row.weightText)
                    .font(AppFont.captionMono)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                TextField("Reps", text: $row.repsText)
                    .font(AppFont.captionMono)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Button {
                row.isCompleted.toggle()
                onCommit?()
            } label: {
                Image(systemName: row.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.isCompleted ? AppColor.accent : AppColor.textSecondary)
            }
            .frame(width: 28)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
    }
}
