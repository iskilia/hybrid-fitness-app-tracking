import SwiftUI

struct LiftActiveSessionView: View {
    let sessionID: UUID
    @State private var viewModel: LiftActiveSessionViewModel
    @State private var showAbandonAlert = false
    @Environment(\.databaseManager) private var dbManager
    @Environment(\.router) private var router

    init(sessionID: UUID, dbManager: DatabaseManager) {
        self.sessionID = sessionID
        self._viewModel = State(initialValue: LiftActiveSessionViewModel(sessionID: sessionID, dbManager: dbManager))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    timerHeader
                    ForEach(Array(viewModel.cards.enumerated()), id: \.element.id) { index, card in
                        LiftBlockCard(
                            blockNumber: index + 1,
                            exercise: card.exercise,
                            routineExercise: card.routineExercise,
                            distanceUnit: viewModel.distanceUnit,
                            rows: card.rows,
                            prevDisplays: prevDisplays(for: card),
                            isExpanded: viewModel.expandedCardID == card.id,
                            isDone: viewModel.doneCardIDs.contains(card.id),
                            actions: .init(
                                onTap: { viewModel.toggleExpand(card) },
                                onMarkAllDone: { Task { await viewModel.markCardDone(card, exerciseOrder: index + 1) } },
                                onNextBlock: { viewModel.advanceToNextCard(after: card) },
                                onAddSet: { viewModel.addSet(to: card) },
                                onRowCommit: { row in viewModel.persistSet(row, in: card, exerciseOrder: index + 1) }
                            )
                        )
                    }
                }
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, 120)
            }
            .background(AppColor.background)

            footerButtons
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("Abandon Session?", isPresented: $showAbandonAlert) {
            Button("Abandon", role: .destructive) {
                Task {
                    await viewModel.abandon()
                    router?.popToRoot()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All sets will be discarded.")
        }
        .confirmationDialog(
            "Your storage limit is full. Finishing will delete your oldest history. Continue?",
            isPresented: $viewModel.showStorageFullConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                Task { if await viewModel.confirmStorageEviction() { router?.popToRoot() } }
            }
            Button("Cancel", role: .cancel) { router?.popToRoot() }
        }
        .errorAlert(message: Binding(
            get: { viewModel.errorMessage },
            set: { viewModel.errorMessage = $0 }
        ))
    }

    // MARK: - Subviews

    private var timerHeader: some View {
        HStack {
            Text(viewModel.routine?.name ?? "Lift Session")
                .font(AppFont.displayMedium)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            TimelineView(.periodic(from: viewModel.session?.startedAt ?? .now, by: 0.5)) { _ in
                Text(elapsedString)
                    .font(AppFont.captionMono)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private var footerButtons: some View {
        VStack(spacing: AppSpacing.sm) {
            Button {
                Task {
                    await viewModel.persistAllRows()
                    let done = await viewModel.finishAndCheckStorage()
                    if done { router?.popToRoot() }
                }
            } label: {
                Text("FINISH")
                    .font(AppFont.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(AppColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            }

            Button {
                showAbandonAlert = true
            } label: {
                Text("ABANDON")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
        .background(AppColor.background.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Prev display hints

    private func prevDisplays(for card: ExerciseCardState) -> [String?] {
        card.rows.enumerated().map { index, row in
            guard index > 0 else { return nil }
            let prev = card.rows[index - 1]
            if card.exercise.metricType == .time {
                guard !prev.durationSecsText.isEmpty else { return nil }
                return "\(prev.durationSecsText)s"
            } else if card.exercise.metricType == .distance {
                guard !prev.distanceText.isEmpty else { return nil }
                let unit = viewModel.distanceUnit == .km ? "km" : "mi"
                return "\(prev.distanceText)\(unit)"
            } else {
                guard !prev.weightText.isEmpty || !prev.repsText.isEmpty else { return nil }
                return "\(prev.weightText.isEmpty ? "—" : prev.weightText)×\(prev.repsText.isEmpty ? "—" : prev.repsText)"
            }
        }
    }

    // MARK: - Elapsed timer

    private var elapsedString: String {
        guard let start = viewModel.session?.startedAt else { return "00:00" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
