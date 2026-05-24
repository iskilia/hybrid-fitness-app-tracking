import SwiftUI

// MARK: - AppColor

/// Design-token namespace for the Hybrid app color palette.
/// All values are derived from screenshots/01–10-hybrid.png.
/// No asset catalog dependency — pure code.
public enum AppColor: Sendable {

    // MARK: Backgrounds

    /// Warm cream off-white used as the app-wide background (~#F5F0E8).
    public static let background = Color(hex: 0xF5F0E8)

    /// Slightly darker warm card surface used for exercise/run card tiles (~#EDE8DC).
    public static let surface = Color(hex: 0xEDE8DC)

    // MARK: Text

    /// Primary charcoal text (~#1C1C1A).
    public static let textPrimary = Color(hex: 0x1C1C1A)

    /// Muted grey used for secondary labels, metadata, unit suffixes (~#8A8478).
    public static let textSecondary = Color(hex: 0x8A8478)

    // MARK: Accent

    /// Bold orange used on START buttons and primary CTAs (~#C95E1E).
    public static let accent = Color(hex: 0xC95E1E)

    /// Darker burnt-orange used on LIFT badge dots and active badges (~#A84B12).
    public static let accentDark = Color(hex: 0xA84B12)

    /// Faded warm-orange used for muted badge backgrounds and tint fills (~#E8C4A0).
    public static let accentMuted = Color(hex: 0xE8C4A0)

    // MARK: Removed / De-emphasised

    /// Removed-from-routine rows in LastExecutionCard (V2).
    public static let textMutedRemoved = Color(hex: 0x9A9A9A)

    // MARK: Structure

    /// Hairline separator color (~#D4CDBE).
    public static let divider = Color(hex: 0xD4CDBE)

    // MARK: Semantic

    /// Success green — not prominently visible in screenshots; reserved (~#4A7C59).
    public static let success = Color(hex: 0x4A7C59)

    /// Warning amber — reserved for future use (~#C8882A).
    public static let warning = Color(hex: 0xC8882A)

    /// Danger red — reserved for destructive actions (~#B83C3C).
    public static let danger = Color(hex: 0xB83C3C)
}

// MARK: - Color(hex:) helper

internal extension Color {
    /// Initialise a `Color` from a 24-bit RGB hex literal, e.g. `Color(hex: 0xF5F0E8)`.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
