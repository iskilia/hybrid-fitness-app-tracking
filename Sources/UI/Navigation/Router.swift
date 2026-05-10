import Observation
import SwiftUI

// MARK: - Route

enum Route: Hashable, Sendable {
    case home
    case routines
    case routineDetail(UUID)
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
