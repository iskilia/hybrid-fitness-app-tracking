import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Hybrid")
                    .font(.largeTitle)
                    .bold()
                Text("v0.0 bootstrap")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    RootView()
}
