import Observation
import SwiftUI

// MARK: - Route

enum Route: Hashable, Sendable {
    case home
    case routines
    /// Includes the routine's WorkoutType so RootView can dispatch to the correct lane
    /// without an async fetch. Update callers to pass `routine.type`.
    case routineDetail(UUID, WorkoutType)
    case routineBuilder
    case session(UUID)
    case exerciseLibrary
    case runTypes
    case exerciseHistory(UUID)
    case settings
}

// MARK: - Router

@Observable
@MainActor
final class Router {
    var path: [Route] = []

    func push(_ route: Route) { path.append(route) }
    func pop() { _ = path.popLast() }
    func popToRoot() { path.removeAll() }
}

// MARK: - EnvironmentValues

private struct RouterKey: EnvironmentKey {
    static let defaultValue: Router? = nil
}

extension EnvironmentValues {
    var router: Router? {
        get { self[RouterKey.self] }
        set { self[RouterKey.self] = newValue }
    }
}
