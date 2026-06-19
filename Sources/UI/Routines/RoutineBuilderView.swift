import SwiftUI

struct RoutineBuilderView: View {
    @State private var viewModel: RoutineBuilderViewModel
    @State private var showExerciseLibrary = false
    @State private var showRunPicker = false
    @Environment(\.router) private var router

    init(dbManager: DatabaseManager, editRoutineID: UUID? = nil) {
        self._viewModel = State(initialValue: RoutineBuilderViewModel(dbManager: dbManager, editRoutineID: editRoutineID))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    exerciseListSection
                    addExerciseButton
                        .padding(AppSpacing.lg)
                    runListSection
                    addRunButton
                        .padding(AppSpacing.lg)
                }
                .padding(.bottom, 100)
            }
            .background(AppColor.background)

            createButton
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(isPresented: $showExerciseLibrary) {
            // Sheet stays open so several exercises can be added in one visit;
            // the user closes it with the library's Close button.
            ExerciseLibraryView(dbManager: viewModel.dbManager, onSelect: { exercise in
                viewModel.add(exercise)
            })
        }
        .sheet(isPresented: $showRunPicker) {
            NavigationStack {
                RunTypesView(dbManager: viewModel.dbManager) { template in
                    viewModel.addRun(template)
                    showRunPicker = false
                }
            }
        }
        .confirmationDialog(
            "This will delete your oldest history. Continue?",
            isPresented: $viewModel.showEvictionConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) { Task { await viewModel.confirmEviction() } }
            Button("Cancel", role: .cancel) { viewModel.cancelEviction() }
        }
        .alert("Not enough space", isPresented: $viewModel.showImpossibleAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Not enough space — edit your data first.")
        }
        .onChange(of: viewModel.didCreate) { _, created in
            if created { router?.pop() }
        }
        .onChange(of: viewModel.didCancel) { _, cancelled in
            if cancelled { router?.popToRoot() }
        }
    }
}

// MARK: - Subviews

private extension RoutineBuilderView {

    var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                Text("\(viewModel.entries.count) EXERCISES")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .textCase(.uppercase)
                if !viewModel.runEntries.isEmpty {
                    Text("\(viewModel.runEntries.count) RUNS")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(.uppercase)
                }
            }
            TextField("Name your routine", text: $viewModel.name)
                .font(AppFont.displayMedium)
                .foregroundStyle(AppColor.textPrimary)
            if viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Give your routine a name to continue.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accent)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
    }

    @ViewBuilder
    var exerciseListSection: some View {
        let canReorder = viewModel.entries.count >= 2
        VStack(spacing: 0) {
            ForEach(viewModel.entries) { entry in
                exerciseEntryRow(entry, canReorder: canReorder)
                Divider()
                    .background(AppColor.divider)
                    .padding(.leading, AppSpacing.lg + 56 + AppSpacing.md)
            }
        }
    }

    func exerciseEntryRow(_ entry: ExerciseEntry, canReorder: Bool) -> some View {
        @Bindable var bindableEntry = entry
        let index = viewModel.entries.firstIndex { $0.id == entry.id } ?? 0
        return SwipeToDeleteRow(onDelete: { viewModel.remove(entry) }) {
            VStack(spacing: 0) {
                ExerciseRow(
                    exercise: entry.exercise,
                    equipment: nil,
                    primaryMuscle: nil,
                    trailingContent: canReorder
                        ? AnyView(reorderControls(entry, index: index))
                        : nil
                )
                HStack(spacing: AppSpacing.md) {
                    entryField(label: "SETS", value: $bindableEntry.targetSets)
                    entryField(label: "REP MIN", value: $bindableEntry.targetRepMin)
                    entryField(label: "REP MAX", value: $bindableEntry.targetRepMax)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.sm)

                notesField(text: $bindableEntry.notes)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.sm)
            }
        }
    }

    func reorderControls(_ entry: ExerciseEntry, index: Int) -> some View {
        VStack(spacing: 0) {
            Button { viewModel.moveUp(entry) } label: {
                Image(systemName: "chevron.up")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(index == 0)
            .accessibilityLabel("Move \(entry.exercise.name) up")

            Button { viewModel.moveDown(entry) } label: {
                Image(systemName: "chevron.down")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(index == viewModel.entries.count - 1)
            .accessibilityLabel("Move \(entry.exercise.name) down")
        }
        .font(AppFont.caption)
        .foregroundStyle(AppColor.accent)
        .buttonStyle(.plain)
    }

    func notesField(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("NOTES")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            TextField("Add a note", text: text, axis: .vertical)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1...3)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    private func entryField(label: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            TextField("—", text: Binding(
                get: { value.wrappedValue.map { "\($0)" } ?? "" },
                set: { value.wrappedValue = Int($0) }
            ))
            .font(AppFont.captionMono)
            .keyboardType(.numberPad)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
        .frame(maxWidth: .infinity)
    }

    var runListSection: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.runEntries) { template in
                SwipeToDeleteRow(onDelete: { viewModel.removeRun(template) }) {
                    RunRow(template: template, intervals: [])
                        .background(AppColor.background)
                }
                Divider()
                    .background(AppColor.divider)
                    .padding(.leading, AppSpacing.lg + 56 + AppSpacing.md)
            }
        }
    }

    var addRunButton: some View {
        Button {
            showRunPicker = true
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

    var createButton: some View {
        Button {
            Task { await viewModel.create() }
        } label: {
            Text(viewModel.isEditing ? "SAVE" : "CREATE")
                .font(AppFont.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .background(viewModel.isValid ? AppColor.accent : AppColor.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .disabled(!viewModel.isValid)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
        .background(
            AppColor.background
                .ignoresSafeArea(edges: .bottom)
        )
    }

    var addExerciseButton: some View {
        Button {
            showExerciseLibrary = true
        } label: {
            Label("ADD EXERCISE", systemImage: "plus")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.accent)
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.lg)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
    }
}

#Preview {
    if let db = try? DatabaseManager(url: nil) {
        NavigationStack {
            RoutineBuilderView(dbManager: db)
        }
        .environment(\.router, Router())
        .background(AppColor.background)
    }
}
