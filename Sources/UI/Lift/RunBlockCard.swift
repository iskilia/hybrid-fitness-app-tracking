import SwiftUI

// MARK: - RunBlockCard (run blocks only)

struct RunBlockCard: View {
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
        return tmpl.metaLine(includeRunType: false, includeBpm: false, includeZone: true)
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
                        Text(kmLabel(km))
                            .font(AppFont.bodyBold)
                            .foregroundStyle(AppColor.accent)
                    } else {
                        Text("— KM")
                            .font(AppFont.bodyBold)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if let paceMin = block.runTemplate?.targetPaceSecsMin {
                        Text(paceLabel(paceMin))
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
