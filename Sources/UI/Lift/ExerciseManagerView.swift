import SwiftUI

/// Exercise library management screen, reached from Home.
/// Lists all exercises; custom exercises can be added, edited, and deleted.
struct ExerciseManagerView: View {
    @State private var viewModel: ExerciseLibraryViewModel
    @State private var editingExercise: EditingExerciseID?
    @State private var showNewEditor = false
    @State private var exerciseToDelete: Exercise?
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self._viewModel = State(initialValue: ExerciseLibraryViewModel(dbManager: dbManager))
        self.dbManager = dbManager
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            exerciseList
        }
        .background(AppColor.background)
        .navigationTitle("EXERCISE LIBRARY")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { addCustomButton }
        .task { await viewModel.load() }
        .sheet(isPresented: $showNewEditor, onDismiss: reload) {
            CustomExerciseEditorView(dbManager: dbManager)
        }
        .sheet(item: $editingExercise, onDismiss: reload) { editing in
            CustomExerciseEditorView(dbManager: dbManager, editingExerciseID: editing.id)
        }
        .confirmationDialog(
            "Delete this exercise? All logged sets and routine entries for it will be deleted too.",
            isPresented: Binding(
                get: { exerciseToDelete != nil },
                set: { if !$0 { exerciseToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let exercise = exerciseToDelete {
                    exerciseToDelete = nil
                    Task { await viewModel.delete(exercise) }
                }
            }
            Button("Cancel", role: .cancel) { exerciseToDelete = nil }
        }
    }

    private func reload() {
        Task { await viewModel.load() }
    }
}

// MARK: - Subviews

private extension ExerciseManagerView {

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

    var exerciseList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let custom = viewModel.filteredExercises.filter { $0.isCustom }
                let base = viewModel.filteredExercises.filter { !$0.isCustom }
                if !custom.isEmpty {
                    sectionHeader("CUSTOM")
                    ForEach(custom) { exercise in
                        row(exercise, isCustom: true)
                    }
                }
                if !base.isEmpty {
                    sectionHeader("BUILT-IN")
                    ForEach(base) { exercise in
                        row(exercise, isCustom: false)
                    }
                }
            }
        }
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppFont.headline)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xs)
    }

    @ViewBuilder
    func row(_ exercise: Exercise, isCustom: Bool) -> some View {
        ExerciseRow(
            exercise: exercise,
            equipment: viewModel.equipmentByExerciseID[exercise.id],
            primaryMuscle: viewModel.musclesByExerciseID[exercise.id]?.first,
            trailingContent: isCustom ? AnyView(customActions(for: exercise)) : nil
        )
        .task { await viewModel.loadMuscles(for: exercise) }
        Divider()
            .background(AppColor.divider)
            .padding(.leading, AppSpacing.lg + 56 + AppSpacing.md)
    }

    func customActions(for exercise: Exercise) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                editingExercise = EditingExerciseID(id: exercise.id)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            }
            Button {
                exerciseToDelete = exercise
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            }
        }
    }

    var addCustomButton: some View {
        Button {
            showNewEditor = true
        } label: {
            Label("ADD CUSTOM EXERCISE", systemImage: "plus")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColor.surface)
        }
    }
}

// MARK: - sheet(item:) wrapper

private struct EditingExerciseID: Identifiable {
    let id: Int
}

#Preview {
    if let db = try? DatabaseManager(url: nil) {
        NavigationStack {
            ExerciseManagerView(dbManager: db)
        }
        .background(AppColor.background)
    }
}
