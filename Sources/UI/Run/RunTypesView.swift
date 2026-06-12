import SwiftUI

// MARK: - RunTypesView

struct RunTypesView: View {
    @State private var viewModel: RunTypesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCustomEditor = false
    let onSelect: (RunTemplate) -> Void

    init(dbManager: DatabaseManager, onSelect: @escaping (RunTemplate) -> Void) {
        _viewModel = State(initialValue: RunTypesViewModel(dbManager: dbManager))
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
            typeFilterChips
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
            Divider().foregroundStyle(AppColor.divider)
            templateList
        }
        .background(AppColor.background)
        .navigationTitle("RUN TYPES")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await viewModel.load() }
        .sheet(isPresented: $showCustomEditor, onDismiss: {
            // Refresh so a just-created custom run type shows up immediately.
            Task { await viewModel.load() }
        }) {
            CustomRunTemplateEditorView(dbManager: viewModel.dbManager)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.textSecondary)
            TextField("Search run types...", text: $viewModel.searchText)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(AppSpacing.md)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Type filter chips

    private var typeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(RunType.allCases, id: \.self) { type in
                    typeChip(type)
                }
            }
        }
    }

    private func typeChip(_ type: RunType) -> some View {
        let isSelected = viewModel.selectedType == type
        return Button {
            viewModel.toggleTypeFilter(type)
        } label: {
            Text(type.filterLabel)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : AppColor.accentDark)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(isSelected ? AppColor.accentDark : AppColor.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - Template list

    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredTemplates) { template in
                    RunTypeRow(template: template) {
                        onSelect(template)
                        dismiss()
                    }
                    Divider()
                        .foregroundStyle(AppColor.divider)
                        .padding(.leading, 60 + AppSpacing.lg)
                }
                addCustomButton
                    .padding(AppSpacing.lg)
            }
        }
    }

    private var addCustomButton: some View {
        Button {
            showCustomEditor = true
        } label: {
            Text("+ ADD CUSTOM RUN TYPE")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.accent)
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.lg)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showCustomEditor = true
            } label: {
                Label("NEW", systemImage: "plus")
                    .font(AppFont.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .background(AppColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            }
        }
    }
}

// MARK: - RunTypeRow

private struct RunTypeRow: View {
    let template: RunTemplate
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Text(template.runType.abbreviation)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.accentDark)
                .frame(width: 44, height: 44)
                .background(AppColor.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(template.name)
                    .font(AppFont.bodyBold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(metaLine)
                    .font(AppFont.captionMono)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(AppColor.textPrimary)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    private var metaLine: String {
        template.metaLine(includeRunType: true, includeBpm: true, includeZone: false)
    }
}

// MARK: - RunType helpers

extension RunType: CaseIterable {
    public static var allCases: [RunType] {
        [.steady, .threshold, .endurance, .intervals, .fartlek, .recovery]
    }

    var filterLabel: String {
        switch self {
        case .steady:    return "EASY"
        case .threshold: return "TEMPO"
        case .endurance: return "LONG"
        case .intervals: return "INTERVAL"
        case .fartlek:   return "FARTLEK"
        case .recovery:  return "RECOVERY"
        }
    }
}
