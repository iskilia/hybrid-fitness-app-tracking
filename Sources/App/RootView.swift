import SwiftUI

struct RootView: View {
    @State private var router = Router()
    @Environment(\.databaseManager) private var dbManager

    var body: some View {
        NavigationStack(path: $router.path) {
            if let db = dbManager {
                HomeView(viewModel: HomeViewModel(dbManager: db))
                    .navigationDestination(for: Route.self) { route in
                        routeView(route)
                    }
            } else {
                Text("Database unavailable")
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .environment(\.router, router)
        .background(AppColor.background)
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
        case .routineDetail(let id):
            Text("TODO: routineDetail(\(id))")
                .foregroundStyle(AppColor.textPrimary)
        case .session(let id):
            Text("TODO: session(\(id))")
                .foregroundStyle(AppColor.textPrimary)
        case .exerciseLibrary:
            Text("TODO: exerciseLibrary")
                .foregroundStyle(AppColor.textPrimary)
        case .runTypes:
            Text("TODO: runTypes")
                .foregroundStyle(AppColor.textPrimary)
        case .exerciseHistory(let id):
            Text("TODO: exerciseHistory(\(id))")
                .foregroundStyle(AppColor.textPrimary)
        case .settings:
            Text("TODO: settings")
                .foregroundStyle(AppColor.textPrimary)
        }
    }
}

#Preview {
    if let db = try? DatabaseManager(url: nil) {
        RootView()
            .environment(\.databaseManager, db)
    }
}
