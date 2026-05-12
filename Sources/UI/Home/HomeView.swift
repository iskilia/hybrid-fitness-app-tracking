import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.router) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                greetingSection
                weekMetricsSection
                routineCardsSection
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await viewModel.load() }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        Text(viewModel.greeting)
            .font(AppFont.displayLarge)
            .foregroundStyle(AppColor.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Week Metrics

    private var weekMetricsSection: some View {
        HStack(spacing: 0) {
            MetricChip(label: "WEEK", value: viewModel.sessionCount, unit: "sessions")
            Divider()
                .frame(height: 40)
                .padding(.horizontal, AppSpacing.md)
            MetricChip(label: "VOLUME", value: viewModel.formattedVolume, unit: "t")
            Divider()
                .frame(height: 40)
                .padding(.horizontal, AppSpacing.md)
            MetricChip(label: "DISTANCE", value: viewModel.formattedDistance, unit: "km")
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Routine Cards

    @ViewBuilder
    private var routineCardsSection: some View {
        if !viewModel.routines.isEmpty {
            routineTypeHeader
            ForEach(viewModel.routines) { routine in
                RoutineCard(
                    routine: routine,
                    lastPerformedText: viewModel.lastPerformedText(for: routine),
                    subtitleText: viewModel.subtitleText(for: routine),
                    onStart: { router?.push(.routineDetail(routine.clientUUID, routine.type)) }
                )
            }
        }
    }

    private var routineTypeHeader: some View {
        let liftCount = viewModel.routines.filter { $0.type == .lift }.count
        let runCount = viewModel.routines.filter { $0.type == .run }.count
        let parts = [
            liftCount > 0 ? "LIFT · \(liftCount)" : nil,
            runCount > 0 ? "RUN · \(runCount)" : nil
        ].compactMap { $0 }.joined(separator: "  ")
        return Text(parts.isEmpty ? "ROUTINES" : parts + " ROUTINES")
            .font(AppFont.headline)
            .foregroundStyle(AppColor.textSecondary)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                router?.push(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                router?.push(.routines)
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
    }
}

#Preview {
    if let db = try? DatabaseManager(url: nil) {
        NavigationStack {
            HomeView(viewModel: HomeViewModel(dbManager: db))
        }
        .environment(\.router, Router())
        .background(AppColor.background)
    }
}
