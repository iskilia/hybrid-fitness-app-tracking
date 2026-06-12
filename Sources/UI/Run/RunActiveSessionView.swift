import SwiftUI

// MARK: - RunActiveSessionView

struct RunActiveSessionView: View {
    let sessionID: UUID
    @State private var viewModel: RunActiveSessionViewModel
    @Environment(\.router) private var router
    @State private var showSummary = false
    @State private var showPaceSheet = false

    private let dbManager: DatabaseManager

    init(sessionID: UUID, dbManager: DatabaseManager) {
        self.sessionID = sessionID
        self.dbManager = dbManager
        _viewModel = State(initialValue: RunActiveSessionViewModel(dbManager: dbManager))
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                timerSection
                Divider().background(AppColor.divider)
                metricsSection
                if !viewModel.intervals.isEmpty { intervalStrip }
                Spacer()
                controlButtons
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarTitle }
        .task { await viewModel.start(sessionID: sessionID) }
        .sheet(isPresented: $showPaceSheet) {
            let bindable = Bindable(viewModel)
            PacePickerSheet(
                minutes: bindable.paceMinutes,
                seconds: bindable.paceSeconds
            ) { showPaceSheet = false }
        }
        .sheet(isPresented: $showSummary) {
            RunSummaryView(
                sessionRunID: viewModel.sessionRun?.clientUUID ?? UUID(),
                dbManager: dbManager
            ) {
                showSummary = false
                Task {
                    let done = await viewModel.checkStorageAfterFinish()
                    if done { router?.popToRoot() }
                }
            }
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

    // MARK: - Timer

    private var timerSection: some View {
        Text(viewModel.elapsedFormatted)
            .font(AppFont.metricLarge)
            .monospacedDigit()
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xxl)
    }

    // MARK: - Metrics grid

    private var metricsSection: some View {
        let bindable = Bindable(viewModel)
        return HStack(spacing: AppSpacing.sm) {
            DistanceTile(distanceText: bindable.distanceText)
            PaceTile(value: viewModel.paceDisplay) { showPaceSheet = true }
            HRTile(hrText: bindable.hrText,
                   targetMin: viewModel.runTemplate?.hrBpmMin,
                   targetMax: viewModel.runTemplate?.hrBpmMax)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xl)
    }

    // MARK: - Interval strip

    private var intervalStrip: some View {
        IntervalStripView(intervals: viewModel.intervals, current: viewModel.currentInterval)
            .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Buttons

    private var controlButtons: some View {
        HStack(spacing: AppSpacing.md) {
            Button(viewModel.isPaused ? "RESUME" : "PAUSE") { viewModel.togglePause() }
                .buttonStyle(SecondaryButtonStyle())
            Button("FINISH") {
                Task {
                    await viewModel.finish()
                    showSummary = true
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xxl)
    }

    private var toolbarTitle: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(viewModel.runTemplate?.name ?? "RUN")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
        }
    }
}
