import SwiftUI

// MARK: - RunActiveSessionView

struct RunActiveSessionView: View {
    let sessionID: UUID
    @State private var vm: RunActiveSessionViewModel
    @Environment(\.router) private var router
    @State private var showSummary = false
    @State private var showPaceSheet = false

    private let dbManager: DatabaseManager

    init(sessionID: UUID, dbManager: DatabaseManager) {
        self.sessionID = sessionID
        self.dbManager = dbManager
        _vm = State(initialValue: RunActiveSessionViewModel(dbManager: dbManager))
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                timerSection
                Divider().background(AppColor.divider)
                metricsSection
                if !vm.intervals.isEmpty { intervalStrip }
                Spacer()
                controlButtons
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarTitle }
        .task { await vm.start(sessionID: sessionID) }
        .sheet(isPresented: $showPaceSheet) {
            let bindable = Bindable(vm)
            PacePickerSheet(
                minutes: bindable.paceMinutes,
                seconds: bindable.paceSeconds
            ) { showPaceSheet = false }
        }
        .sheet(isPresented: $showSummary) {
            RunSummaryView(
                sessionRunID: vm.sessionRun?.clientUUID ?? UUID(),
                dbManager: dbManager
            ) {
                showSummary = false
                Task {
                    let done = await vm.checkStorageAfterFinish()
                    if done { router?.popToRoot() }
                }
            }
        }
        .confirmationDialog(
            "Your storage limit is full. Finishing will delete your oldest history. Continue?",
            isPresented: $vm.showStorageFullConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                Task { if await vm.confirmStorageEviction() { router?.popToRoot() } }
            }
            Button("Cancel", role: .cancel) { router?.popToRoot() }
        }
        .alert(
            "Couldn't free space",
            isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Timer

    private var timerSection: some View {
        Text(vm.elapsedFormatted)
            .font(AppFont.metricLarge)
            .monospacedDigit()
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xxl)
    }

    // MARK: - Metrics grid

    private var metricsSection: some View {
        let bindable = Bindable(vm)
        return HStack(spacing: AppSpacing.sm) {
            DistanceTile(distanceText: bindable.distanceText)
            PaceTile(value: vm.paceDisplay) { showPaceSheet = true }
            HRTile(hrText: bindable.hrText,
                   targetMin: vm.runTemplate?.hrBpmMin,
                   targetMax: vm.runTemplate?.hrBpmMax)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xl)
    }

    // MARK: - Interval strip

    private var intervalStrip: some View {
        IntervalStripView(intervals: vm.intervals, current: vm.currentInterval)
            .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Buttons

    private var controlButtons: some View {
        HStack(spacing: AppSpacing.md) {
            Button(vm.isPaused ? "RESUME" : "PAUSE") { vm.togglePause() }
                .buttonStyle(SecondaryButtonStyle())
            Button("FINISH") {
                Task {
                    await vm.finish()
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
            Text(vm.runTemplate?.name ?? "RUN")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
        }
    }
}
