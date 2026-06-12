import SwiftUI

// MARK: - CustomRunTemplateEditorView

struct CustomRunTemplateEditorView: View {
    @State private var viewModel: CustomRunTemplateEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(dbManager: DatabaseManager) {
        _viewModel = State(initialValue: CustomRunTemplateEditorViewModel(dbManager: dbManager))
    }

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                paceSection
                heartRateSection
                notesSection
                blocksSection
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.background)
            .navigationTitle("CUSTOM RUN TYPE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
    }

    // MARK: - Basic info

    private var basicSection: some View {
        Section("NAME & TYPE") {
            TextField("Name", text: $viewModel.name)
            Picker("Run Type", selection: $viewModel.runType) {
                ForEach(RunType.allCases, id: \.self) { type in
                    Text(type.filterLabel).tag(type)
                }
            }
            .pickerStyle(.segmented)
            TextField("Distance (km)", text: $viewModel.distanceKm)
                .keyboardType(.decimalPad)
        }
    }

    // MARK: - Pace

    private var paceSection: some View {
        Section("TARGET PACE /KM") {
            HStack {
                Text("Min")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                TextField("4", text: $viewModel.paceMinMin)
                    .keyboardType(.numberPad)
                    .frame(width: 40)
                Text(":")
                TextField("30", text: $viewModel.paceMinSec)
                    .keyboardType(.numberPad)
                    .frame(width: 40)
            }
            HStack {
                Text("Max")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                TextField("5", text: $viewModel.paceMaxMin)
                    .keyboardType(.numberPad)
                    .frame(width: 40)
                Text(":")
                TextField("00", text: $viewModel.paceMaxSec)
                    .keyboardType(.numberPad)
                    .frame(width: 40)
            }
        }
    }

    // MARK: - HR

    private var heartRateSection: some View {
        Section("TARGET HR (BPM)") {
            HStack {
                TextField("Min BPM", text: $viewModel.hrMin)
                    .keyboardType(.numberPad)
                Text("–")
                    .foregroundStyle(AppColor.textSecondary)
                TextField("Max BPM", text: $viewModel.hrMax)
                    .keyboardType(.numberPad)
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section("NOTES") {
            TextField("Optional notes", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...)
        }
    }

    // MARK: - Interval blocks

    private var blocksSection: some View {
        Section("INTERVAL BLOCKS") {
            ForEach($viewModel.blocks) { $block in
                IntervalBlockEditorView(block: $block)
            }
            .onDelete { viewModel.removeBlock(at: $0) }

            Button {
                viewModel.addBlock()
            } label: {
                Label("Add Block", systemImage: "plus")
                    .foregroundStyle(AppColor.accent)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(AppColor.textPrimary)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Save") {
                Task {
                    if await viewModel.save() { dismiss() }
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(AppColor.accent)
            .disabled(viewModel.isSaving)
        }
    }
}
