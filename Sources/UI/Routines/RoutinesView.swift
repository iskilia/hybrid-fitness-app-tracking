import SwiftUI

struct RoutinesView: View {
    @Bindable var viewModel: RoutinesViewModel
    @Environment(\.router) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                headerSection
                routinesList
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await viewModel.load() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Your")
                .font(AppFont.displayMedium)
                .foregroundStyle(AppColor.textPrimary)
            Text("plans.")
                .font(AppFont.displayMedium)
                .foregroundStyle(AppColor.accent)

            Text("\(viewModel.activeCount) ACTIVE · MAX 10")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, AppSpacing.xs)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var routinesList: some View {
        ForEach(viewModel.routines) { routine in
            RoutineCard(
                routine: routine,
                lastPerformedText: viewModel.lastPerformedText(for: routine),
                subtitleText: viewModel.subtitleText(for: routine),
                onStart: { router?.push(.routineDetail(routine.clientUUID, routine.type)) }
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                router?.push(.routineDetail(UUID(), .lift))
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
    }
}

#Preview {
    if let db = try? DatabaseManager(url: nil) {
        NavigationStack {
            RoutinesView(viewModel: RoutinesViewModel(dbManager: db))
        }
        .environment(\.router, Router())
        .background(AppColor.background)
    }
}
