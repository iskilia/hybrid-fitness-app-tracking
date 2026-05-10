import SwiftUI

struct CustomExerciseEditorView: View {
    @State private var viewModel: CustomExerciseEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(dbManager: DatabaseManager) {
        self._viewModel = State(initialValue: CustomExerciseEditorViewModel(dbManager: dbManager))
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                equipmentSection
                metricTypeSection
                muscleSection
                notesSection
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.background)
            .navigationTitle("NEW EXERCISE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarButtons }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.didSave) { _, saved in
            if saved { dismiss() }
        }
    }
}

// MARK: - Sections

private extension CustomExerciseEditorView {

    var nameSection: some View {
        Section("NAME") {
            TextField("Exercise name", text: $viewModel.name)
            TextField("Abbreviation (max 4)", text: Binding(
                get: { viewModel.abbreviation },
                set: { viewModel.abbreviation = String($0.prefix(4)) }
            ))
        }
    }

    var equipmentSection: some View {
        Section("EQUIPMENT") {
            Picker("Equipment", selection: $viewModel.selectedEquipmentID) {
                ForEach(viewModel.allEquipment) { eq in
                    Text(eq.displayName).tag(Optional(eq.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    var metricTypeSection: some View {
        Section("METRIC TYPE") {
            Picker("Metric", selection: $viewModel.metricType) {
                Text("Reps").tag(MetricType.reps)
                Text("Time").tag(MetricType.time)
                Text("Distance").tag(MetricType.distance)
                Text("Bodyweight Reps").tag(MetricType.repsBodyweight)
            }
            .pickerStyle(.segmented)
        }
    }

    var muscleSection: some View {
        Section("MUSCLES") {
            ForEach($viewModel.muscleSelections) { $sel in
                MuscleToggleRow(selection: $sel)
            }
        }
    }

    var notesSection: some View {
        Section("NOTES & FORM") {
            TextField("Notes", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...6)
            TextField("Form link (URL)", text: $viewModel.formLink)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
        }
    }

    @ToolbarContentBuilder
    var toolbarButtons: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(AppColor.textSecondary)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Save") {
                Task { await viewModel.save() }
            }
            .disabled(!viewModel.isValid || viewModel.isSaving)
            .foregroundStyle(viewModel.isValid ? AppColor.accent : AppColor.textSecondary)
        }
    }
}

// MARK: - MuscleToggleRow

private struct MuscleToggleRow: View {
    @Binding var selection: MuscleSelection

    var body: some View {
        HStack {
            Toggle(selection.muscle.displayName, isOn: $selection.isSelected)
            if selection.isSelected {
                Picker("", selection: $selection.role) {
                    Text("Primary").tag(MuscleRole.primary)
                    Text("Secondary").tag(MuscleRole.secondary)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
