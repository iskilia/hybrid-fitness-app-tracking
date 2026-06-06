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
                                BlockCard(
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
        .alert(
            "Couldn't free space",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
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
        guard let start = viewModel.session?.startedAt else { return "0:00:00" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    private var tonnageString: String {
        let t = viewModel.liftTonnage
        return t.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(t)) T" : String(format: "%.1f T", t)
    }

    private var distanceString: String {
        let d = viewModel.runDistanceKm
        return d.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(d)).0 KM" : String(format: "%.1f KM", d)
    }
}

// MARK: - BlockCard (run blocks only)

private struct BlockCard: View {
    @Bindable var block: MixedBlockState
    let blockNumber: Int
    let isExpanded: Bool
    let distanceUnit: DistanceUnit
    let onTap: () -> Void
    let onNextBlock: () -> Void
    let onMarkRunDone: () -> Void

    @State private var showPaceSheet = false

    /// Formatted manual pace for the tile (e.g. "4:35"), or a placeholder.
    private var paceDisplay: String {
        guard let p = block.manualPaceSecPerKm else { return "—:—" }
        return String(format: "%d:%02d", p / 60, p % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed header — always visible
            collapsedHeader
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

            // Expanded body
            if isExpanded {
                Divider().background(AppColor.divider)
                runExpandedBody
            }
        }
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(isExpanded ? AppColor.accent : Color.clear, lineWidth: AppStroke.thin)
        )
        .padding(.horizontal, AppSpacing.lg)
        .sheet(isPresented: $showPaceSheet) {
            PacePickerSheet(
                minutes: $block.paceMinutes,
                seconds: $block.paceSeconds
            ) { showPaceSheet = false }
        }
    }

    // MARK: Collapsed header

    private var collapsedHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            statusNode
            thumbnailTile

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack(spacing: AppSpacing.xs) {
                    BadgeView(kind: .run)
                    statePill
                }
                Text(block.runTemplate?.name ?? "")
                    .font(AppFont.bodyBold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subLine)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                Text(progressReadout)
                    .font(AppFont.captionMono)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(AppSpacing.md)
    }

    private var statusNode: some View {
        Group {
            if block.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.accent)
                    .font(.system(size: 20))
            } else {
                ZStack {
                    Circle()
                        .stroke(AppColor.divider, lineWidth: AppStroke.thin)
                        .frame(width: 24, height: 24)
                    Text("\(blockNumber)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .frame(width: 24)
    }

    private var thumbnailTile: some View {
        Text(block.runTemplate?.runType.abbreviation ?? "RUN")
            .font(AppFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(AppColor.accentDark)
            .frame(width: 44, height: 44)
            .background(AppColor.accentMuted)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    private var statePill: some View {
        Text(block.isDone ? "DONE" : "QUEUED")
            .font(AppFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(block.isDone ? AppColor.success : AppColor.textSecondary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background((block.isDone ? AppColor.success : AppColor.textSecondary).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    private var subLine: String {
        guard let tmpl = block.runTemplate else { return "" }
        var parts: [String] = []
        if let km = tmpl.targetTotalDistanceKm {
            parts.append(km.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(km)).0 KM" : String(format: "%.1f KM", km))
        }
        if let paceMin = tmpl.targetPaceSecsMin {
            let m = paceMin / 60; let s = paceMin % 60
            parts.append(String(format: "%d:%02d /KM", m, s))
        }
        if let zMin = tmpl.hrZoneMin, let zMax = tmpl.hrZoneMax {
            parts.append("Z\(zMin)-\(zMax)")
        }
        return parts.joined(separator: " · ")
    }

    private var progressReadout: String {
        let entered = Double(block.runDistanceText) ?? 0.0
        let target  = block.runTemplate?.targetTotalDistanceKm ?? 0.0
        return String(format: "%.1f / %.1f", entered, target)
    }

    // MARK: Expanded RUN body

    private var runExpandedBody: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Coaching note
            if let notes = block.routineRun?.notes, !notes.isEmpty {
                Text(notes)
                    .font(AppFont.body.italic())
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
            }

            // Distance + target
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("READY")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    HStack(alignment: .lastTextBaseline, spacing: AppSpacing.xs) {
                        TextField("0.00", text: $block.runDistanceText)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColor.textPrimary)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 160)
                        Text("km")
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    Text("TARGET")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    if let km = block.runTemplate?.targetTotalDistanceKm {
                        let kmStr = km.truncatingRemainder(dividingBy: 1) == 0
                            ? "\(Int(km)).0 KM" : String(format: "%.1f KM", km)
                        Text(kmStr)
                            .font(AppFont.bodyBold)
                            .foregroundStyle(AppColor.accent)
                    } else {
                        Text("— KM")
                            .font(AppFont.bodyBold)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if let paceMin = block.runTemplate?.targetPaceSecsMin {
                        let m = paceMin / 60; let s = paceMin % 60
                        Text(String(format: "%d:%02d /KM", m, s))
                            .font(AppFont.captionMono)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if let bpmMin = block.runTemplate?.hrBpmMin, let bpmMax = block.runTemplate?.hrBpmMax {
                        Text("\(bpmMin)–\(bpmMax) BPM")
                            .font(AppFont.captionMono)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)

            // Editable fields row
            HStack(spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("PACE")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    Button { showPaceSheet = true } label: {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(paceDisplay)
                                .font(AppFont.captionMono)
                                .foregroundStyle(AppColor.textPrimary)
                                .frame(minWidth: 48, alignment: .leading)
                            Text("/km")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let zMin = block.runTemplate?.hrZoneMin, let zMax = block.runTemplate?.hrZoneMax {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("HR · Z\(zMin)-\(zMax)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            TextField("—", text: $block.runHrText)
                                .font(AppFont.captionMono)
                                .keyboardType(.numberPad)
                                .frame(width: 40)
                            Text("bpm")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("HR")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            TextField("—", text: $block.runHrText)
                                .font(AppFont.captionMono)
                                .keyboardType(.numberPad)
                                .frame(width: 40)
                            Text("bpm")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("CADENCE")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        TextField("—", text: $block.runCadenceText)
                            .font(AppFont.captionMono)
                            .keyboardType(.numberPad)
                            .frame(width: 40)
                        Text("spm")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)

            // Mark as Done button
            Button {
                onMarkRunDone()
            } label: {
                Text("Mark as Done")
                    .font(AppFont.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.md)
        }
    }
}

