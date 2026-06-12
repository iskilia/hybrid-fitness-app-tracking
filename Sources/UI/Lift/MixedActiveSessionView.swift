import SwiftUI

// MARK: - MixedActiveSessionView

struct MixedActiveSessionView: View {
    let sessionID: UUID
    @State private var viewModel: MixedActiveSessionViewModel
    @Environment(\.router) private var router

    init(sessionID: UUID, dbManager: DatabaseManager) {
        self.sessionID = sessionID
        self._viewModel = State(initialValue: MixedActiveSessionViewModel(sessionID: sessionID, dbManager: dbManager))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                stickyHeader
                Divider().background(AppColor.divider)
                ScrollView {
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(Array(viewModel.blocks.enumerated()), id: \.element.id) { index, block in
                            if block.kind == .lift {
                                if let exercise = block.exercise, let routineExercise = block.routineExercise {
                                    LiftBlockCard(
                                        blockNumber: index + 1,
                                        exercise: exercise,
                                        routineExercise: routineExercise,
                                        distanceUnit: viewModel.distanceUnit,
                                        rows: block.rows,
                                        prevDisplays: block.prevDisplays,
                                        isExpanded: viewModel.activeBlockID == block.id,
                                        isDone: block.isDone,
                                        actions: .init(
                                            onTap: { viewModel.expand(block) },
                                            onMarkAllDone: { Task { await viewModel.markLiftBlockDone(block) } },
                                            onNextBlock: { viewModel.advanceToNextBlock(after: block) }
                                        )
                                    )
                                } else {
                                    // load() only appends a .lift block when both resolve; enforce in debug.
                                    let _ = assertionFailure("lift block missing exercise/routineExercise")
                                    EmptyView()
                                }
                            } else {
                                RunBlockCard(
                                    block: block,
                                    blockNumber: index + 1,
                                    isExpanded: viewModel.activeBlockID == block.id,
                                    distanceUnit: viewModel.distanceUnit,
                                    onTap: { viewModel.expand(block) },
                                    onNextBlock: { viewModel.advanceToNextBlock(after: block) },
                                    onMarkRunDone: { Task { await viewModel.markRunBlockDone(block) } }
                                )
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.md)
                    .padding(.bottom, 140)
                }
                .background(AppColor.background)
            }

            stickyFooter
        }
        .background(AppColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
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
        .errorAlert("Couldn't free space", message: $viewModel.errorMessage)
    }

    // MARK: - Sticky header

    private var stickyHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            TimelineView(.periodic(from: viewModel.session?.startedAt ?? .now, by: 1)) { _ in
                Text(elapsedString)
                    .font(AppFont.captionMono)
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
            }
            Spacer()
            // LIFT TONNAGE chip
            HStack(spacing: AppSpacing.xs) {
                BadgeView(kind: .lift)
                Text(tonnageString)
                    .font(AppFont.captionMono)
                    .foregroundStyle(AppColor.textPrimary)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

            // RUN DISTANCE chip
            HStack(spacing: AppSpacing.xs) {
                BadgeView(kind: .run)
                Text(distanceString)
                    .font(AppFont.captionMono)
                    .foregroundStyle(AppColor.textPrimary)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColor.background)
    }

    // MARK: - Sticky footer

    private var stickyFooter: some View {
        VStack(spacing: AppSpacing.xs) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("\(viewModel.completedBlockCount) OF \(viewModel.blocks.count) BLOCKS COMPLETE")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Text("\(tonnageString) LIFTED · \(distanceString) RUN")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppSpacing.sm) {
                Button {
                    Task {
                        await viewModel.saveAndExit()
                        router?.popToRoot()
                    }
                } label: {
                    Text("SAVE & EXIT")
                        .font(AppFont.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                }

                Button {
                    Task {
                        let done = await viewModel.finish()
                        if done { router?.popToRoot() }
                    }
                } label: {
                    Text("FINISH")
                        .font(AppFont.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
        .padding(.top, AppSpacing.sm)
        .background(AppColor.background.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Helpers

    private var elapsedString: String {
        guard let start = viewModel.session?.startedAt else { return formattedDuration(0) }
        let elapsed = Int(Date().timeIntervalSince(start))
        return formattedDuration(elapsed)
    }

    private var tonnageString: String {
        let t = viewModel.liftTonnage
        return t.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(t)) T" : String(format: "%.1f T", t)
    }

    private var distanceString: String {
        kmLabel(viewModel.runDistanceKm)
    }
}
