import SwiftUI

@main
@MainActor
struct FreeShowRemoteApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            FoundationView(state: state)
        }
    }
}
