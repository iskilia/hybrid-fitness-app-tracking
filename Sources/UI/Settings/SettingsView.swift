import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var shareURL: URL?
    @State private var showShare = false

    init(dbManager: DatabaseManager) {
        _viewModel = State(initialValue: SettingsViewModel(dbManager: dbManager))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                unitsSection
                bodyweightSection
                exportSection
                footer
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColor.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
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

    private var bodyweightSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("BODYWEIGHT")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
            HStack {
                TextField("0", text: $viewModel.bodyWeightInput)
                    .keyboardType(.decimalPad)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                Text(viewModel.weightUnit.rawValue)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .onSubmit { Task { await viewModel.save() } }
    }

    private var exportSection: some View {
        VStack(spacing: AppSpacing.md) {
            Text("EXPORT")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
            HStack(spacing: AppSpacing.md) {
                Button("EXPORT CSV") {
                    Task {
                        if let url = await viewModel.exportCSV() {
                            shareURL = url
                            showShare = true
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("EXPORT JSON") {
                    Task {
                        if let url = await viewModel.exportJSON() {
                            shareURL = url
                            showShare = true
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            if viewModel.isExporting {
                ProgressView()
            }
        }
    }

    private var footer: some View {
        Text(viewModel.footerText)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, AppSpacing.xl)
    }
}

// UIKit share sheet bridge.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
