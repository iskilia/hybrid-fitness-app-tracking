import SwiftUI
import Charts

/// How much past data the history chart spans. The selection sets the chart's
/// visible time window; the user scrolls horizontally to see older windows.
enum HistoryRange: String, CaseIterable, Identifiable {
    case week, month, quarter, year, twoYears

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week:     return "1W"
        case .month:    return "1M"
        case .quarter:  return "1Q"
        case .year:     return "1Y"
        case .twoYears: return "2Y"
        }
    }

    /// Calendar span of the visible window, subtracted from the anchor (newest
    /// session) to find the window's left edge. Calendar arithmetic keeps the
    /// edges on true boundaries across variable month lengths and leap years.
    private var span: (component: Calendar.Component, value: Int) {
        switch self {
        case .week:     return (.day, 7)
        case .month:    return (.month, 1)
        case .quarter:  return (.month, 3)
        case .year:     return (.year, 1)
        case .twoYears: return (.year, 2)
        }
    }

    /// Left edge of the visible window ending at `anchor`.
    func windowStart(endingAt anchor: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: span.component, value: -span.value, to: anchor) ?? anchor
    }
}

struct ExerciseHistoryView: View {
    let exerciseID: UUID
    @State private var viewModel: ExerciseHistoryViewModel
    @State private var range: HistoryRange = .week
    @State private var scrollX: Date = .now

    init(exerciseID: UUID, dbManager: DatabaseManager) {
        self.exerciseID = exerciseID
        self._viewModel = State(initialValue: ExerciseHistoryViewModel(exerciseID: exerciseID, dbManager: dbManager))
    }

    /// Anchors the visible window so its right edge sits at the newest session,
    /// keeping the default view non-empty even if the last workout is old.
    private func anchorScroll() {
        guard let newest = viewModel.topSets.last?.date else { return }
        scrollX = range.windowStart(endingAt: newest)
    }

    /// Visible window width in seconds, derived from the calendar-anchored window.
    private var visibleDuration: TimeInterval {
        guard let newest = viewModel.topSets.last?.date else { return 7 * 86_400 }
        return newest.timeIntervalSince(range.windowStart(endingAt: newest))
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
        .onChange(of: viewModel.topSets.count) { anchorScroll() }
        .onChange(of: range) { anchorScroll() }
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
            Text("\(isTimeExercise ? "TOP-SET SECS" : "TOP-SET KG") · \(range.label)")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)

            Picker("Range", selection: $range) {
                ForEach(HistoryRange.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.segmented)

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
                .scrollableHistoryDomain(length: visibleDuration, position: $scrollX)
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
                .scrollableHistoryDomain(length: visibleDuration, position: $scrollX)
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
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// Shared axis, scroll, and frame config for the history charts. Keeps the
/// time / non-time chart branches from drifting apart.
private struct ScrollableHistoryDomain: ViewModifier {
    let length: TimeInterval
    @Binding var position: Date

    func body(content: Content) -> some View {
        content
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
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: length)
            .chartScrollPosition(x: $position)
            .frame(height: 180)
    }
}

private extension View {
    func scrollableHistoryDomain(length: TimeInterval, position: Binding<Date>) -> some View {
        modifier(ScrollableHistoryDomain(length: length, position: position))
    }
}
