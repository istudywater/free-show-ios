import SwiftUI

struct FoundationView: View {
    @ObservedObject var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text("Your service, within reach")
                        .font(.largeTitle.bold())

                    Text("Control FreeShow from your iPad while your presentation computer manages the screens.")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Label(connectionLabel, systemImage: "wifi.slash")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.quaternary, in: Capsule())

                    Text("Your service playlist and slides will appear here once connected.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)
                .padding(40)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("FreeShow Remote")
        }
    }

    private var connectionLabel: String {
        switch state.connection {
        case .disconnected: "Not connected"
        case .connecting: "Connecting"
        case .authenticationRequired: "Password required"
        case .synchronizing: "Synchronizing"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting"
        case .failed: "Connection unavailable"
        }
    }
}
