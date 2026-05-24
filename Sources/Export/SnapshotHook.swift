import Foundation

// TV6.1 — Thin indirection so repositories can fire snapshot writes without
// holding a SnapshotWriter reference or knowing about the Documents URL.
// App configures `current` once at launch with the live SnapshotWriter; repos
// call `notifyChange()` after their commits. Debounce is internal to the
// writer, so callers are fire-and-forget.

public enum SnapshotHook {

    public nonisolated(unsafe) static var current: SnapshotWriter?

    /// UserDefaults key controlling whether auto-update fires from repo hooks.
    public static let autoEnabledKey = "snapshot.auto_enabled"

    /// Default true — toggled OFF by Settings (TV6.2).
    public static var isAutoEnabled: Bool {
        get { UserDefaults.standard.object(forKey: autoEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoEnabledKey) }
    }

    /// Fire-and-forget snapshot write. Honours the auto-update toggle.
    public static func notifyChange() {
        guard isAutoEnabled, let writer = current else { return }
        Task { await writer.write() }
    }

    /// Manual write — ignores the toggle. Used by the "Refresh LLM snapshot"
    /// button (TV6.3).
    public static func forceWrite() {
        guard let writer = current else { return }
        Task { await writer.write() }
    }
}
