import SwiftUI

@main
@MainActor
struct FreeShowRemoteApp: App {
    @StateObject private var store = OperatorStore(transport: SwitchableRemoteTransport(live: SocketIOTransport()), vault: KeychainVault())
    @StateObject private var discovery = BonjourDiscovery()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                OperatorView(store: store, discovery: discovery)
                    .tabItem { Label("Operator", systemImage: "play.rectangle") }
                ScriptureView(state: store.scripture)
                    .disabled(store.phase != .connected || store.isSending || store.commandOutcomeUnknown)
                    .tabItem { Label("Scripture", systemImage: "book") }
                OperatorConnectionView(store: store, discovery: discovery)
                    .tabItem { Label("Connection", systemImage: "network") }
            }
            .task {
                #if DEBUG
                if CommandLine.arguments.contains("--demo") { store.startDemo() }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { discovery.stop(); store.suspend() }
                else if phase == .active { store.resume() }
            }
        }
    }
}
