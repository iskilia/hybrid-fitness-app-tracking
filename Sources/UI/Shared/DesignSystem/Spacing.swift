import CoreGraphics

// MARK: - AppSpacing

/// Named spacing constants derived from the Hybrid screenshot layouts.
/// All values are `CGFloat` for direct use with SwiftUI padding/frame modifiers.
public enum AppSpacing: Sendable {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat  = 4
    public static let sm: CGFloat  = 8
    public static let md: CGFloat  = 12
    public static let lg: CGFloat  = 16
    public static let xl: CGFloat  = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

// MARK: - AppRadius

/// Corner radius constants matching the card rounding visible in the screenshots.
/// Exercise/run thumbnail tiles use `md`, routine cards use `lg`, bottom sheet handle `xl`.
public enum AppRadius: Sendable {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
}

// MARK: - AppStroke

/// Stroke/border width constants.
public enum AppStroke: Sendable {
    /// Hairline separator (0.5 pt) used between list rows.
    public static let hairline: CGFloat = 0.5
    /// Thin border (1 pt) used for card outlines and input fields.
    public static let thin: CGFloat = 1
}
