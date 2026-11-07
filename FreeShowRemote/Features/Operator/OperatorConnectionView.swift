import SwiftUI

struct OperatorConnectionView: View {
    @ObservedObject var store: OperatorStore
    @ObservedObject var discovery: BonjourDiscovery
    private var locked: Bool {
        switch store.phase { case .connecting, .connected, .reconnecting, .synchronizing: true; default: false }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("FreeShow computer") {
                    TextField("IP address or hostname", text: $store.host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).disabled(locked)
                    LabeledContent("RemoteShow port") {
                        TextField("5510", text: $store.port).multilineTextAlignment(.trailing).keyboardType(.numberPad).disabled(locked)
                    }
                    SecureField("RemoteShow password (if configured)", text: $store.password).disabled(locked)
                    Text("Enable RemoteShow in FreeShow Desktop. This connection supplies projects, live state, slide control, and scripture. Its password is separate from the General API password.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if locked {
                        Button(store.isDemo ? "Exit demo" : "Disconnect", role: .destructive) { store.disconnect() }
                    } else {
                        Button("Connect") { discovery.stop(); store.connect() }
                            .disabled(store.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ConnectionIndicator(phase: store.phase, demo: store.isDemo)
                    if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
                }
                Section("Nearby computers") {
                    Button(discovery.isSearching ? "Stop searching" : "Find FreeShow computers") {
                        if discovery.isSearching { discovery.stop() } else { discovery.start() }
                    }
                    .disabled(locked)
                    if discovery.isSearching { ProgressView("Looking on your local network…") }
                    ForEach(discovery.computers) { computer in
                        Button {
                            discovery.stop(); store.connect(to: computer)
                        } label: {
                            VStack(alignment: .leading) {
                                Label(computer.name, systemImage: "desktopcomputer")
                                Text("RemoteShow · port \(computer.port)").font(.caption).foregroundStyle(.secondary)
                            }.frame(minHeight: 44)
                        }.disabled(locked)
                    }
                    if let error = discovery.errorMessage { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    if discovery.computers.isEmpty { Text("No computers listed. Discovery needs local-network access and a shared network; manual connection is always available.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Connection preferences") {
                    Toggle("Automatically reconnect", isOn: $store.autoReconnect)
                    Toggle("Save Remote password in Keychain", isOn: Binding(get: { store.rememberPassword }, set: { store.setRememberPassword($0) })).disabled(store.isDemo)
                    Button("Forget this computer’s saved password") { store.forgetPassword() }.disabled(store.isDemo)
                    Text("The last computer is remembered without a password. A saved password stays on this device. Backgrounding pauses the session; returning reconnects and refreshes state when automatic reconnection is enabled.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Simulator & rehearsal") {
                    Button("Try offline demo") { discovery.stop(); store.startDemo() }
                    Text("Explore a sample service and demo passage. Demo controls never contact a computer.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    Text("FreeShow Remote · iPadOS 17+")
                    Text("RemoteShow transport: Socket.IO-Client-Swift 16.1.1 and Starscream 4.0.8.").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("Open-source notices") { NoticesView() }
                }
            }
            .navigationTitle("Connection")
            .onDisappear { discovery.stop() }
        }
    }
}

struct ConnectionIndicator: View {
    let phase: ConnectionState
    let demo: Bool
    var body: some View {
        Label(label, systemImage: symbol).font(.subheadline.weight(.semibold))
            .foregroundStyle(phase == .connected ? Color.green : Color.secondary)
            .accessibilityLabel("Connection: \(label)")
    }
    private var symbol: String { phase == .connected ? (demo ? "play.circle" : "network") : "wifi.slash" }
    private var label: String {
        if demo && phase == .connected { return "DEMO · no computer connected" }
        switch phase {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .authenticationRequired: return "Password or connection limit requires attention"
        case .synchronizing: return "Checking desktop state — controls paused"
        case .connected: return "Connected · desktop state synchronized"
        case .reconnecting: return "Connection lost · reconnecting…"
        case .failed: return "Connection unavailable"
        }
    }
}

private struct NoticesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(["SocketIO-LICENSE", "Starscream-LICENSE"], id: \.self) { name in
                    Text(name).font(.headline)
                    Text(text(name)).font(.caption).textSelection(.enabled)
                }
            }.padding()
        }.navigationTitle("Open-source notices")
    }
    private func text(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"), let value = try? String(contentsOf: url, encoding: .utf8) else { return "Notice unavailable." }
        return value
    }
}
