import SwiftUI

// MARK: - SwipeToDeleteRow

/// Swipe-to-delete for rows hosted in a ScrollView (where List's
/// .swipeActions isn't available). Swipe left past half the reveal
/// width to open; tap the trash to delete, swipe right to close.
struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var isOpen = false

    private let revealWidth: CGFloat = 72

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(AppColor.danger)
            }
            content()
                .background(AppColor.background)
                .offset(x: offset)
                .gesture(dragGesture)
        }
        .clipped()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let base: CGFloat = isOpen ? -revealWidth : 0
                offset = min(0, max(-revealWidth, base + value.translation.width))
            }
            .onEnded { value in
                let base: CGFloat = isOpen ? -revealWidth : 0
                isOpen = base + value.translation.width < -revealWidth / 2
                withAnimation(.easeOut(duration: 0.2)) {
                    offset = isOpen ? -revealWidth : 0
                }
            }
    }
}
