import SwiftUI

/// A single editable set row inside an exercise card.
struct SetRow: View {
    let setIndex: Int
    let prevDisplay: String?
    let metricType: MetricType
    let distanceUnit: DistanceUnit
    @Bindable var row: SetRowState
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            // Set number
            Text("\(setIndex)")
                .font(AppFont.captionMono)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 20, alignment: .center)

            // Prev readout
            Text(prevDisplay ?? "—")
                .font(AppFont.captionMono)
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)

            if metricType == .time {
                // Timed hold: single seconds field
                TextField("Seconds", text: $row.durationSecsText)
                    .font(AppFont.captionMono)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .onSubmit { onCommit() }
            } else if metricType == .distance {
                // Distance field in user's unit (KM or MI)
                let placeholder = distanceUnit == .km ? "KM" : "MI"
                TextField(placeholder, text: $row.distanceText)
                    .font(AppFont.captionMono)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .onSubmit { onCommit() }
            } else {
                // Weight
                TextField("KG", text: $row.weightText)
                    .font(AppFont.captionMono)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .onSubmit { onCommit() }

                // Reps
                TextField("Reps", text: $row.repsText)
                    .font(AppFont.captionMono)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .onSubmit { onCommit() }
            }

            // RPE
            TextField("RPE", text: $row.rpeText)
                .font(AppFont.captionMono)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .onSubmit { onCommit() }

            // Completion checkmark
            Button {
                row.isCompleted.toggle()
                onCommit()
            } label: {
                Image(systemName: row.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.isCompleted ? AppColor.accent : AppColor.textSecondary)
            }
            .frame(width: 28)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
    }
}
