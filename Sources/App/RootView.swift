import SwiftUI

struct RootView: View {
    @State private var router = Router()
    // Owned in @State so it survives RootView body re-evaluations (every push/pop
    // mutates router.path, which re-runs body). Building it inline here would mint a
    // fresh HomeViewModel with stats == nil on every navigation, dropping the loaded
    // Home metrics.
    @State private var homeViewModel: HomeViewModel?
    @Environment(\.databaseManager) private var dbManager

    var body: some View {
        NavigationStack(path: $router.path) {
            Group {
                if let vm = homeViewModel {
                    HomeView(viewModel: vm)
                        .navigationDestination(for: Route.self) { route in
                            routeView(route)
                        }
                } else if dbManager == nil {
                    Text("Database unavailable")
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .environment(\.router, router)
        .background(AppColor.background)
        .onAppear {
            if homeViewModel == nil, let db = dbManager {
                homeViewModel = HomeViewModel(dbManager: db)
            }
        }
    }

    @ViewBuilder
    private func routeView(_ route: Route) -> some View {
        switch route {
        case .home:
            if let db = dbManager {
                HomeView(viewModel: HomeViewModel(dbManager: db))
            }
        case .routines:
            if let db = dbManager {
                RoutinesView(viewModel: RoutinesViewModel(dbManager: db))
            }
        case .routineDetail(let id, let type):
            if let db = dbManager {
                switch type {
                case .lift, .mixed:
                    LiftRoutineDetailView(routineID: id, dbManager: db)
                case .run:
                    RunRoutineDetailView(routineID: id, dbManager: db)
                }
            }
        case .session(let id):
            // Dispatch to lift or run based on session type.
            // TODO: run-coder — replace the Text placeholder below with RunActiveSessionView(sessionID: id)
            if let db = dbManager {
                SessionDispatchView(sessionID: id, dbManager: db)
            }
        case .exerciseLibrary:
            if let db = dbManager {
                ExerciseLibraryView(dbManager: db, onSelect: { _ in })
            }
        case .runTypes:
            if let db = dbManager {
                RunTypesView(dbManager: db) { _ in }
            }
        case .exerciseHistory(let id):
            if let db = dbManager {
                ExerciseHistoryView(exerciseID: id, dbManager: db)
            }
        case .settings:
            if let db = dbManager {
                SettingsView(dbManager: db)
            }
        }
    }
}

#Preview {
    if let db = try? DatabaseManager(url: nil) {
        RootView()
            .environment(\.databaseManager, db)
    }
}
