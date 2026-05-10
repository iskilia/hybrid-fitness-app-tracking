import SwiftUI

struct LiftRoutineDetailView: View {
    let routineID: UUID
    @State private var viewModel: LiftRoutineDetailViewModel
    @State private var showExerciseLibrary = false
    @Environment(\.databaseManager) private var dbManager
    @Environment(\.router) private var router

    init(routineID: UUID, dbManager: DatabaseManager) {
        self.routineID = routineID
        self._viewModel = State(initialValue: LiftRoutineDetailViewModel(dbManager: dbManager))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    exerciseListSection
                }
                .padding(.bottom, 100)  // space for START button
            }
            .background(AppColor.background)

            startButton
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { addExerciseButton }
        .task { await viewModel.load(routineID: routineID) }
        .sheet(isPresented: $showExerciseLibrary) {
            if let db = dbManager {
                ExerciseLibraryView(dbManager: db, onSelect: { _ in
                    showExerciseLibrary = false
                    // T5 will wire adding exercise to routine
                })
            }
        }
    }
}

// MARK: - Subviews

private extension LiftRoutineDetailView {

    var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if let routine = viewModel.routine {
                HStack(spacing: AppSpacing.md) {
                    BadgeView(kind: routine.type)
                    Text("\(viewModel.entries.count) EXERCISES")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(.uppercase)
                }
                Text(routine.name)
                    .font(AppFont.displayMedium)
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
    }

    var exerciseListSection: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.entries) { entry in
                ExerciseRow(
                    exercise: entry.exercise,
                    equipment: entry.equipment,
                    primaryMuscle: entry.primaryMuscle,
                    trailingContent: AnyView(repRangeLabel(for: entry))
                )
                Divider()
                    .background(AppColor.divider)
                    .padding(.leading, AppSpacing.lg + 56 + AppSpacing.md)
            }
        }
    }

    func repRangeLabel(for entry: LiftRoutineDetailEntry) -> some View {
        let re = entry.routineExercise
        let weightText: String
        if let w = entry.lastWeightKg {
            weightText = w.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(w))KG"
                : String(format: "%.1fKG", w)
        } else {
            weightText = "--"
        }
        let repText: String
        if let lo = re.targetRepMin, let hi = re.targetRepMax {
            repText = "\(lo)–\(hi)"
        } else if let lo = re.targetRepMin {
            repText = "\(lo)+"
        } else {
            repText = "--"
        }
        return Text("\(weightText) × \(repText)")
            .font(AppFont.captionMono)
            .foregroundStyle(AppColor.textSecondary)
    }

    var startButton: some View {
        Button {
            Task {
                guard let db = dbManager else { return }
                let sessionRepo = SessionRepository(dbManager: db)
                let session = try? await sessionRepo.start(routineID: routineID, type: .lift)
                if let s = session {
                    router?.push(.session(s.clientUUID))
                }
            }
        } label: {
            Text("START")
                .font(AppFont.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .background(AppColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
        .background(
            AppColor.background
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ToolbarContentBuilder
    var addExerciseButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showExerciseLibrary = true
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
            LiftRoutineDetailView(routineID: UUID(), dbManager: db)
        }
        .environment(\.databaseManager, db)
        .environment(\.router, Router())
        .background(AppColor.background)
    }
}
