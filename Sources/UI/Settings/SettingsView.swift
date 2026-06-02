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
                    ForEach(Array(stride(from: 10, through: 200, by: 10)), id: \.self) { mb in
                        Text("\(mb) MB").tag(mb)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        // PASS 2: extend this onChange to trigger limit-decrease eviction.
        // Pass 1 only persists the value.
        .onChange(of: viewModel.maxDataMb) { _, _ in Task { await viewModel.save() } }
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
