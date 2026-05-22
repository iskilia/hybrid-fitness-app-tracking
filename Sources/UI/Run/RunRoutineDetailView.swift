import SwiftUI

// MARK: - RunRoutineDetailView

struct RunRoutineDetailView: View {
    let routineID: UUID
    @State private var viewModel: RunRoutineDetailViewModel
    @Environment(\.router) private var router
    @Environment(\.databaseManager) private var dbManager

    init(routineID: UUID, dbManager: DatabaseManager) {
        self.routineID = routineID
        _viewModel = State(initialValue: RunRoutineDetailViewModel(dbManager: dbManager))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                headerSection
                runList
                lastExecutionSection
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { startButton }
        .task {
            await viewModel.load(routineID: routineID)
            await viewModel.loadLastExecution(routineID: routineID)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            BadgeView(kind: .run)
            Text(viewModel.routine?.name ?? "")
                .font(AppFont.displayMedium)
                .foregroundStyle(AppColor.textPrimary)
            Text("\(viewModel.runCount) RUNS")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
        }
    }

    // MARK: - Run list

    @ViewBuilder
    private var runList: some View {
        ForEach(viewModel.entries, id: \.run.id) { entry in
            RunRow(template: entry.template, intervals: entry.intervals)
        }
        addRunButton
    }

    private var addRunButton: some View {
        Button {
            router?.push(.runTypes)
        } label: {
            Label("ADD RUN", systemImage: "plus")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.accent)
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.lg)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
    }

    // MARK: - Last execution card

    private var lastExecutionSection: some View {
        LastExecutionCard(
            summary: viewModel.lastExecutionSummary,
            isLoading: viewModel.isLoadingLastExecution,
            onTap: {
                if let s = viewModel.lastExecutionSummary {
                    router?.push(.session(s.sessionID))
                }
            }
        )
    }

    // MARK: - Start button

    private var startButton: some View {
        Button {
            Task {
                if let sessionID = await viewModel.startSession(routineID: routineID) {
                    router?.push(.session(sessionID))
                }
            }
        } label: {
            HStack {
                Text("START")
                    .font(AppFont.headline)
                    .fontWeight(.bold)
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.lg)
            .background(AppColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.lg)
        .background(AppColor.background)
    }
}
