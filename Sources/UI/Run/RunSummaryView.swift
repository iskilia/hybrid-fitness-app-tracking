import SwiftUI

struct RunSummaryView: View {
    let sessionRunID: UUID
    let dbManager: DatabaseManager
    let onDone: () -> Void

    @State private var run: SessionRun?
    @State private var splits: [SessionRunSplit] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    if let r = run {
                        totalsSection(r)
                        if !splits.isEmpty {
                            splitsSection
                        }
                    } else {
                        ProgressView()
                            .padding(.top, AppSpacing.xxl)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.xl)
            }
            .background(AppColor.background)
            .navigationTitle("Run Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .foregroundStyle(AppColor.accent)
                }
            }
            .task { await load() }
        }
    }

    private func totalsSection(_ r: SessionRun) -> some View {
        VStack(spacing: AppSpacing.md) {
            row("DISTANCE", value: distance(r))
            row("TIME", value: duration(r))
            row("PACE", value: pace(r))
            row("AVG HR", value: hr(r))
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("SPLITS")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
            ForEach(splits) { s in
                HStack {
                    Text(s.blockType?.rawValue ?? "—")
                        .font(AppFont.captionMono)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                    Text(String(format: "%.2f KM", s.distanceKm ?? 0))
                        .font(AppFont.bodyBold)
                        .foregroundStyle(AppColor.textPrimary)
                }
                .padding(.vertical, AppSpacing.xs)
                Divider().background(AppColor.divider)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.metricSmall)
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    private func distance(_ r: SessionRun) -> String {
        guard let km = r.actualDistanceKm else { return "—" }
        return String(format: "%.2f KM", km)
    }

    private func duration(_ r: SessionRun) -> String {
        guard let s = r.durationSecs else { return "—" }
        return formattedDuration(s)
    }

    private func pace(_ r: SessionRun) -> String {
        guard let p = r.avgPaceSecs, p > 0 else { return "—" }
        return paceLabel(p)
    }

    private func hr(_ r: SessionRun) -> String {
        guard let h = r.avgHR else { return "—" }
        return "\(h) BPM"
    }

    private func load() async {
        let repo = SessionRunRepository(dbManager: dbManager)
        do {
            run = try await repo.get(id: sessionRunID)
            splits = try await repo.splits(sessionRunID: sessionRunID)
        } catch {
            run = nil
        }
    }
}
