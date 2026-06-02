import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(dbManager: DatabaseManager) {
        _viewModel = State(initialValue: SettingsViewModel(dbManager: dbManager))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                unitsSection
                dataLimitSection
                #if DEBUG
                debugSection   // TEMP PASS-2 TESTING — remove before merge.
                #endif
                footer
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColor.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("UNITS")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)

            HStack {
                Text("Weight")
                    .font(AppFont.body)
                Spacer()
                Picker("Weight", selection: $viewModel.weightUnit) {
                    Text("KG").tag(WeightUnit.kg)
                    Text("LB").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            HStack {
                Text("Distance")
                    .font(AppFont.body)
                Spacer()
                Picker("Distance", selection: $viewModel.distanceUnit) {
                    Text("KM").tag(DistanceUnit.km)
                    Text("MI").tag(DistanceUnit.mi)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .onChange(of: viewModel.weightUnit) { _, _ in Task { await viewModel.save() } }
        .onChange(of: viewModel.distanceUnit) { _, _ in Task { await viewModel.save() } }
    }

    private var dataLimitSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("DATA LIMIT")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)

            HStack {
                Text("Max data")
                    .font(AppFont.body)
                Spacer()
                Picker("Max data", selection: $viewModel.maxDataMb) {
                    ForEach(limitOptions, id: \.self) { mb in
                        Text("\(mb) MB").tag(mb)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .onChange(of: viewModel.maxDataMb) { _, newValue in
            Task { await viewModel.handleMaxDataChange(to: newValue) }
        }
        .alert("Lower data limit?", isPresented: $viewModel.showLimitDecreaseConfirm) {
            Button("Cancel", role: .cancel) { viewModel.cancelLimitDecrease() }
            Button("Delete history", role: .destructive) { Task { await viewModel.confirmLimitDecrease() } }
        } message: {
            Text("Lowering the limit will permanently delete your oldest history to fit the new size. This can't be undone.")
        }
    }

    // TEMP PASS-2 TESTING — small options let the limit drop below seeded data. Remove before merge.
    private var limitOptions: [Int] {
        #if DEBUG
        return [1, 2, 5] + Array(stride(from: 10, through: 200, by: 10))
        #else
        return Array(stride(from: 10, through: 200, by: 10))
        #endif
    }

    #if DEBUG
    // TEMP PASS-2 TESTING — remove before merge.
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("DEBUG · STORAGE TEST")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)

            Text(String(format: "Logical size: %.2f MB  ·  limit: %d MB",
                        viewModel.debugLogicalMB, viewModel.maxDataMb))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)

            HStack {
                Button("Seed 200") { Task { await viewModel.debugSeed(200) } }
                Spacer()
                Button("Seed 1000") { Task { await viewModel.debugSeed(1000) } }
                Spacer()
                Button("Refresh size") { Task { await viewModel.debugRefreshLogical() } }
            }
            .font(AppFont.body)
            .disabled(viewModel.debugBusy)

            if viewModel.debugBusy {
                Text("Seeding…").font(AppFont.caption).foregroundStyle(AppColor.accent)
            }
            Text("Seed ~1000 to pass 1 MB, set limit to 1 MB, then finish a session / lower the limit / add an exercise to trigger eviction.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .task { await viewModel.debugRefreshLogical() }
    }
    #endif

    private var footer: some View {
        VStack(spacing: AppSpacing.sm) {
            Text(viewModel.footerText)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, AppSpacing.xl)
    }
}
