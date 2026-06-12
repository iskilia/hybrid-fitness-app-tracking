import SwiftUI

struct RoutineBuilderView: View {
    @State private var viewModel: RoutineBuilderViewModel
    @State private var showExerciseLibrary = false
    @State private var showRunPicker = false
    @Environment(\.router) private var router

    init(dbManager: DatabaseManager) {
        self._viewModel = State(initialValue: RoutineBuilderViewModel(dbManager: dbManager))
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
                BadgeView(kind: viewModel.derivedType)
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
            TextField("Routine name", text: $viewModel.name)
                .font(AppFont.displayMedium)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
    }

    var exerciseListSection: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.entries) { entry in
                @Bindable var bindableEntry = entry
                SwipeToDeleteRow(onDelete: { viewModel.remove(entry) }) {
                    VStack(spacing: 0) {
                        ExerciseRow(
                            exercise: entry.exercise,
                            equipment: nil,
                            primaryMuscle: nil,
                            trailingContent: nil
                        )
                        HStack(spacing: AppSpacing.md) {
                            entryField(label: "SETS", value: $bindableEntry.targetSets)
                            entryField(label: "REP MIN", value: $bindableEntry.targetRepMin)
                            entryField(label: "REP MAX", value: $bindableEntry.targetRepMax)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.sm)
                    }
                }
                Divider()
                    .background(AppColor.divider)
                    .padding(.leading, AppSpacing.lg + 56 + AppSpacing.md)
            }
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
                RunRow(template: template, intervals: [])
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
            Text("CREATE")
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

// MARK: - SwipeToDeleteRow

/// Swipe-to-delete for rows hosted in a ScrollView (where List's
/// .swipeActions isn't available). Swipe left past half the reveal
/// width to open; tap the trash to delete, swipe right to close.
private struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var isOpen = false

    private let revealWidth: CGFloat = 72

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(AppColor.danger)
            }
            content()
                .background(AppColor.background)
                .offset(x: offset)
                .gesture(dragGesture)
        }
        .clipped()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let base: CGFloat = isOpen ? -revealWidth : 0
                offset = min(0, max(-revealWidth, base + value.translation.width))
            }
            .onEnded { value in
                let base: CGFloat = isOpen ? -revealWidth : 0
                isOpen = base + value.translation.width < -revealWidth / 2
                withAnimation(.easeOut(duration: 0.2)) {
                    offset = isOpen ? -revealWidth : 0
                }
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
