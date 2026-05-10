import SwiftUI

// MARK: - AppFont

/// Design-token namespace for Hybrid app typography.
/// Uses SF Pro (system font) throughout. Monospaced-digit variants are used
/// for all numeric readouts (timers, metrics, weights).
public enum AppFont: Sendable {

    // MARK: Display — greeting & screen titles

    /// Large italic serif-style greeting headline (e.g. "Today, good morning.").
    /// Rendered at 40 pt bold italic to match the prominent greeting in screenshot 01.
    public static let displayLarge: Font = .system(size: 40, weight: .bold, design: .serif).italic()

    /// Screen-level display title (e.g. "Your plans." italic heading in screenshot 02).
    public static let displayMedium: Font = .system(size: 32, weight: .bold, design: .serif).italic()

    /// Smaller display for routine/session titles (e.g. "Push Day", "Tempo Tuesday").
    public static let displaySmall: Font = .system(size: 26, weight: .bold, design: .default)

    // MARK: Content hierarchy

    /// Section headline, e.g. "LIFT · 2 ROUTINES" uppercase labels (~13 pt semibold).
    public static let headline: Font = .system(size: 13, weight: .semibold, design: .default)

    /// Card title, e.g. routine name "Heavy Lower" (~18 pt semibold).
    public static let title: Font = .system(size: 18, weight: .semibold, design: .default)

    /// Standard body text (~15 pt regular).
    public static let body: Font = .system(size: 15, weight: .regular, design: .default)

    /// Emphasised body, e.g. exercise name in list rows (~15 pt semibold).
    public static let bodyBold: Font = .system(size: 15, weight: .semibold, design: .default)

    // MARK: Supporting text

    /// Small caption for metadata labels (e.g. "4 EXERCISES", "BARBELL · CHEST · TRICEPS") (~12 pt regular).
    public static let caption: Font = .system(size: 12, weight: .regular, design: .default)

    /// Monospaced caption used for pace, BPM, and compact numeric metadata (~12 pt).
    public static let captionMono: Font = .system(size: 12, weight: .regular, design: .monospaced)
        .monospacedDigit()

    // MARK: Metrics — week stats, timer readouts

    /// Large metric display for prominent stats: timer "00:18:54", week volume "8.4" (~48 pt bold).
    public static let metricLarge: Font = .system(size: 48, weight: .bold, design: .monospaced)
        .monospacedDigit()

    /// Smaller metric for secondary stats: session count "3", distance "14" (~28 pt semibold).
    public static let metricSmall: Font = .system(size: 28, weight: .semibold, design: .monospaced)
        .monospacedDigit()
}
