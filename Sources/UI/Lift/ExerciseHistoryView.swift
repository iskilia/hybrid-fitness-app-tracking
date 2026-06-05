import SwiftUI
import Charts

struct ExerciseHistoryView: View {
    let exerciseID: UUID
    @State private var viewModel: ExerciseHistoryViewModel

    init(exerciseID: UUID, dbManager: DatabaseManager) {
        self.exerciseID = exerciseID
        self._viewModel = State(initialValue: ExerciseHistoryViewModel(exerciseID: exerciseID, dbManager: dbManager))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                headerSection
                if viewModel.topSets.isEmpty {
                    emptyState
                } else {
                    chartSection
                    sessionListSection
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.lg)
        }
        .background(AppColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: AppSpacing.md) {
            if let exercise = viewModel.exercise {
                Text(abbrev(exercise))
                    .font(AppFont.bodyBold)
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 56, height: 56)
                    .background(AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

                Text(exercise.name)
                    .font(AppFont.displayMedium)
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32))
                .foregroundStyle(AppColor.textSecondary)
            Text("No history yet.")
                .font(AppFont.bodyBold)
                .foregroundStyle(AppColor.textSecondary)
            Text("Complete a session to start tracking.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Chart

    private var isTimeExercise: Bool {
        viewModel.exercise?.metricType == .time
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(isTimeExercise ? "TOP-SET SECS · LAST 12 SESSIONS" : "TOP-SET KG · LAST 12 SESSIONS")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)

            if isTimeExercise {
                Chart(viewModel.topSets) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Seconds", point.durationSecs ?? 0)
                    )
                    .foregroundStyle(AppColor.accent)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Seconds", point.durationSecs ?? 0)
                    )
                    .foregroundStyle(AppColor.accent)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 180)
            } else {
                Chart(viewModel.topSets) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("KG", point.weightKg)
                    )
                    .foregroundStyle(AppColor.accent)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("KG", point.weightKg)
                    )
                    .foregroundStyle(AppColor.accent)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - Session list

    private var sessionListSection: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.topSets.reversed()) { point in
                HStack {
                    Text(formattedDate(point.date))
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if isTimeExercise {
                        Text("\(point.durationSecs ?? 0)s")
                            .font(AppFont.captionMono)
                            .foregroundStyle(AppColor.textSecondary)
                    } else {
                        let wStr = point.weightKg.truncatingRemainder(dividingBy: 1) == 0
                            ? "\(Int(point.weightKg)) KG" : String(format: "%.1f KG", point.weightKg)
                        Text("\(wStr) × \(point.reps)")
                            .font(AppFont.captionMono)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(.vertical, AppSpacing.md)
                Divider()
                    .background(AppColor.divider)
            }
        }
    }

    // MARK: - Helpers

    private func abbrev(_ exercise: Exercise) -> String {
        let a = exercise.abbreviation
        return a.isEmpty ? String(exercise.name.prefix(3)).uppercased() : a
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date)
    }
}
