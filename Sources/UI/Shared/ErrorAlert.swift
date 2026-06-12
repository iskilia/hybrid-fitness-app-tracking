import SwiftUI

// MARK: - Error alert helper

extension View {
    /// Presents a "Couldn't free space" alert driven by an optional error-message string.
    /// Dismissing the alert clears the binding.
    func errorAlert(message: Binding<String?>) -> some View {
        self.alert(
            "Couldn't free space",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
