import SwiftUI

struct ConnectionView: View {
    @ObservedObject var state: AppState
    @State private var host = ""
    @State private var port = "5506"
    @State private var password = ""
    @State private var confirmClear = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("FreeShow computer") {
                    TextField("IP address or hostname", text: $host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disabled(state.isBusy || state.connection == .connected)
                    TextField("REST port", text: $port)
                        .keyboardType(.numberPad)
                        .disabled(state.isBusy || state.connection == .connected)
                    SecureField("General API password (if configured)", text: $password)
                        .textContentType(.password)
                        .disabled(state.isBusy || state.connection == .connected)
                    Text("Enable the General API in FreeShow. Its password and port are separate from RemoteShow. The default REST port is 5506.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Connection") {
                    Label(connectionLabel, systemImage: state.connection == .connected ? "network" : "wifi.slash")
                    if state.isBusy { ProgressView("Waiting for FreeShow…") }
                    if state.connection == .connected || state.isBusy {
                        Button("Disconnect") { state.disconnect(); password = "" }
                    } else {
                        Button("Connect") { state.connect(host: host, port: port, password: password) }
                            .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let error = state.errorMessage {
                        Text(error).foregroundStyle(.red).accessibilityLabel("Error: \(error)")
                    }
                    if let message = state.message { Text(message).font(.callout) }
                }

                Section {
                    controlButton("Previous slide", symbol: "backward.end.fill") { state.send(.previous) }
                    controlButton("Next slide", symbol: "forward.end.fill") { state.send(.next) }
                    controlButton("Clear all outputs", symbol: "clear") { confirmClear = true }
                    controlButton("Restore output", symbol: "arrow.uturn.backward") { state.send(.restore) }
                } header: {
                    Text("Live controls")
                } footer: {
                    Text("Commands affect active desktop outputs. Clear all also clears audio, backgrounds, overlays, and timers. Restore depends on FreeShow’s cached state and output lock.")
                }

                Section("Last output check") {
                    Text(outputLabel)
                    if let date = state.checkedAt {
                        LabeledContent("Checked at", value: date.formatted(date: .omitted, time: .standard))
                    }
                    Text("Status is a snapshot. Desktop changes are not monitored in this prototype.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Refresh status") { state.refresh() }
                        .disabled(state.connection != .connected || state.isBusy)
                }
            }
            .navigationTitle("FreeShow Remote")
            .confirmationDialog("Clear all active outputs?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear all outputs", role: .destructive) { state.send(.clear) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This also clears audio, backgrounds, overlays, and timers.")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { confirmClear = false; password = "" }
        }
    }

    private func controlButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(state.connection == .connected && !state.isBusy ? Color.accentColor : Color.secondary)
                .frame(minHeight: 44)
        }
        .disabled(state.connection != .connected || state.isBusy)
    }

    private var connectionLabel: String {
        switch state.connection {
        case .disconnected: "Not connected"
        case .connecting: "Checking API…"
        case .authenticationRequired: "API password required or incorrect"
        case .synchronizing: "Checking output…"
        case .connected: "API ready — last request succeeded"
        case .reconnecting: "Reconnecting"
        case .failed: "API unavailable — reconnect to retry"
        }
    }

    private var outputLabel: String {
        switch state.output {
        case .unknown: "Output status unknown"
        case .cleared: "All output cleared at last check"
        case .live: "Presentation active at last check"
        case .other(let description): description
        }
    }
}
