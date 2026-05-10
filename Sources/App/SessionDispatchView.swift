import SwiftUI

/// Resolves a session's WorkoutType and dispatches to the correct active-session view.
/// The run-coder should replace the TODO branch with RunActiveSessionView(sessionID:dbManager:).
struct SessionDispatchView: View {
    let sessionID: UUID
    let dbManager: DatabaseManager

    @State private var sessionType: WorkoutType?
    @State private var failed = false

    var body: some View {
        Group {
            if let type = sessionType {
                switch type {
                case .lift, .mixed:
                    LiftActiveSessionView(sessionID: sessionID, dbManager: dbManager)
                case .run:
                    // TODO: run-coder — replace with RunActiveSessionView(sessionID: sessionID, dbManager: dbManager)
                    Text("TODO: run session")
                        .foregroundStyle(AppColor.textPrimary)
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
