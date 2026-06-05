import SwiftUI

/// Resolves a session's WorkoutType and dispatches to the correct active-session view.
struct SessionDispatchView: View {
    let sessionID: UUID
    let dbManager: DatabaseManager

    @State private var sessionType: WorkoutType?
    @State private var failed = false

    var body: some View {
        Group {
            if let type = sessionType {
                switch type {
                case .lift:
                    LiftActiveSessionView(sessionID: sessionID, dbManager: dbManager)
                case .run:
                    RunActiveSessionView(sessionID: sessionID, dbManager: dbManager)
                case .mixed:
                    MixedActiveSessionView(sessionID: sessionID, dbManager: dbManager)
                }
            } else if failed {
                Text("Session not found.")
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColor.background)
            }
        }
        .task {
            guard sessionType == nil else { return }
            do {
                let repo = SessionRepository(dbManager: dbManager)
                let s = try await repo.get(id: sessionID)
                sessionType = s?.type
                if s == nil { failed = true }
            } catch {
                failed = true
            }
        }
    }
}
