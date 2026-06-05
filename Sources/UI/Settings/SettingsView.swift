import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var showDeleteHistoryConfirm = false
    @Environment(\.router) private var router

    init(dbManager: DatabaseManager) {
        _viewModel = State(initialValue: SettingsViewModel(dbManager: dbManager))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                unitsSection
                dataLimitSection
                deleteHistorySection
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
        .alert(
            "Couldn't free space",
            isPresented: Binding(
                get: { viewModel.storageErrorMessage != nil },
                set: { if !$0 { viewModel.storageErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.storageErrorMessage ?? "")
        }
    }

    private var limitOptions: [Int] {
        Array(stride(from: 10, through: 200, by: 10))
    }

    private var deleteHistorySection: some View {
        Button(role: .destructive) {
            showDeleteHistoryConfirm = true
        } label: {
            HStack {
                Text("Delete all history")
                    .font(AppFont.body)
                Spacer()
                Image(systemName: "trash")
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.red)
        .confirmationDialog(
            "Delete all history?",
            isPresented: $showDeleteHistoryConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete all history", role: .destructive) {
                Task {
                    await viewModel.deleteAllHistory()
                    if viewModel.storageErrorMessage == nil { router?.popToRoot() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every logged session. Your routines and exercises are kept. This can't be undone.")
        }
    }

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
