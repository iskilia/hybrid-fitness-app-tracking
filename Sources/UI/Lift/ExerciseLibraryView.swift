import SwiftUI

struct ExerciseLibraryView: View {
    @State private var viewModel: ExerciseLibraryViewModel
    @State private var showCustomEditor = false
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?
    let onSelect: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.databaseManager) private var dbManager

    init(dbManager: DatabaseManager, onSelect: @escaping (Exercise) -> Void) {
        self._viewModel = State(initialValue: ExerciseLibraryViewModel(dbManager: dbManager))
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                filterSection
                exerciseList
            }
            .background(AppColor.background)
            .navigationTitle("EXERCISES")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeButton }
            .safeAreaInset(edge: .bottom) { addCustomButton }
            .overlay(alignment: .bottom) { toast }
            .sheet(isPresented: $showCustomEditor, onDismiss: {
                // Refresh so a just-created custom exercise shows up immediately.
                Task { await viewModel.load() }
            }) {
                if let db = dbManager {
                    CustomExerciseEditorView(dbManager: db)
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

// MARK: - Subviews

private extension ExerciseLibraryView {

    var searchBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.textSecondary)
            TextField("Search", text: $viewModel.searchQuery)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(AppSpacing.sm)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
    }

    var filterSection: some View {
        VStack(spacing: AppSpacing.xs) {
            EquipmentFilterRow(
                codes: viewModel.distinctEquipmentCodes,
                selected: $viewModel.selectedEquipmentCode
            )
            MuscleGroupFilterRow(
                groups: viewModel.distinctMuscleGroups,
                selected: $viewModel.selectedMuscleGroup
            )
        }
        .padding(.bottom, AppSpacing.xs)
    }

    var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredExercises) { exercise in
                    ExerciseLibraryRow(
                        exercise: exercise,
                        equipment: viewModel.equipmentByExerciseID[exercise.id],
                        muscles: viewModel.musclesByExerciseID[exercise.id] ?? [],
                        onAdd: {
                            onSelect(exercise)
                            showToast("Added \(exercise.name)")
                        }
                    )
                    .task { await viewModel.loadMuscles(for: exercise) }
                    Divider()
                        .background(AppColor.divider)
                        .padding(.leading, AppSpacing.lg + 56 + AppSpacing.md)
                }
            }
        }
    }

    @ViewBuilder
    var toast: some View {
        if let message = toastMessage {
            Text(message)
                .font(AppFont.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColor.textPrimary)
                .clipShape(Capsule())
                .padding(.bottom, AppSpacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toastMessage = message }
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { toastMessage = nil }
        }
    }

    var addCustomButton: some View {
        Button {
            showCustomEditor = true
        } label: {
            Label("ADD CUSTOM EXERCISE", systemImage: "plus")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColor.surface)
        }
    }

    @ToolbarContentBuilder
    var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Close") { dismiss() }
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}
