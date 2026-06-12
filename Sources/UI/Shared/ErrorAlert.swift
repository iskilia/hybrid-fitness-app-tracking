import SwiftUI

// MARK: - Error alert helper

extension View {
    /// Presents an alert driven by an optional error-message string.
    /// Dismissing the alert clears the binding.
    func errorAlert(_ title: String, message: Binding<String?>) -> some View {
        self.alert(
            title,
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
