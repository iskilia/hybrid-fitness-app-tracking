import SwiftUI

struct RoutinesView: View {
    @Bindable var viewModel: RoutinesViewModel
    @Environment(\.router) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            headerSection
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)
            routinesList
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
            Text("routines.")
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
        List {
            ForEach(viewModel.routines) { routine in
                RoutineCard(
                    routine: routine,
                    lastPerformedText: viewModel.lastPerformedText(for: routine),
                    subtitleText: viewModel.subtitleText(for: routine),
                    onStart: { router?.push(.routineDetail(routine.clientUUID, routine.type)) }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await viewModel.delete(routine) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColor.background)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                router?.push(.routineBuilder)
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
