import SwiftUI

// TV W3 — Per-set pill chip used by routine detail screens.
// Populated by ui-lift-coder.

public struct SetPill: View {
    public let label: String
    public let body_: String

    public init(label: String, body: String) {
        self.label = label
        self.body_ = body
    }

    public var body: some View {
        Text("\(label) · \(body_)")
            .font(.caption)
    }
}
