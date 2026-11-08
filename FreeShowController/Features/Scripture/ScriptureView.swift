import SwiftUI

struct ScriptureView: View {
    @ObservedObject var state: ScriptureState
    @State private var host = ""
    @State private var port = "5510"
    @State private var password = ""
    @State private var confirmPresent = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                if state.managesConnection {
                Section("RemoteShow connection") {
                    TextField("FreeShow IP address or hostname", text: $host)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                        .disabled(state.isConnected || state.isBusy)
                    TextField("Remote port", text: $port).keyboardType(.numberPad)
                        .disabled(state.isConnected || state.isBusy)
                    SecureField("RemoteShow password (if configured)", text: $password)
                        .disabled(state.isConnected || state.isBusy)
                    Text("Use the same FreeShow computer as Live Controls. RemoteShow must be enabled separately; its default port is 5510 and its password may differ from the General API password.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if state.isConnected || state.isBusy {
                        Button("Disconnect scripture") { state.disconnect(); password = "" }
                    } else {
                        Button("Connect scripture") { state.connect(host: host, port: port, password: password) }
                            .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Label(state.isConnected ? "RemoteShow ready" : "Scripture disconnected", systemImage: state.isConnected ? "network" : "wifi.slash")
                }
                } else {
                    Section {
                        Label(state.isConnected ? "Using the operator connection" : "Connect in the Connection tab", systemImage: state.isConnected ? "network" : "wifi.slash")
                        Text("Scripture shares the operator connection. Search and preview leave output unchanged.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if state.isBusy { Section { ProgressView("Waiting for scripture…") } }
                if let error = state.errorMessage { Section { Text(error).foregroundStyle(.red) } }
                if let message = state.message { Section { Text(message) } }

                Section("Find scripture") {
                    Picker("Translation", selection: $state.selectedTranslationID) {
                        Text("Choose a translation").tag("")
                        ForEach(state.translations) { translation in
                            Text(translation.name + (translation.source == .api ? " (API)" : " (local)")).tag(translation.id)
                        }
                    }
                    .disabled(!state.isConnected || state.isBusy)
                    Picker("Search by", selection: $state.searchByText) {
                        Text("Reference").tag(false)
                        Text("Text").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!state.isConnected || state.isBusy)
                    TextField(state.searchByText ? "Words from a verse" : "John 3:16–18", text: $state.query)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .disabled(!state.isConnected || state.isBusy)
                        .onSubmit { state.search() }
                    Button(state.searchByText ? "Search text" : "Preview reference") { state.search() }
                        .disabled(!state.isConnected || state.isBusy || state.selectedTranslationID.isEmpty || state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("Search and preview do not change live output. References support a single chapter, verse, or same-chapter range. Preview supports up to 200 verses; text searches show at most 50 matches. Collections are not included.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if !state.results.isEmpty {
                    Section("Matches — tap to preview") {
                        ForEach(state.results) { result in
                            Button { state.select(result) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(result.reference).font(.headline)
                                    Text(result.excerpt).foregroundStyle(.secondary).lineLimit(3)
                                }.frame(minHeight: 44)
                            }
                            .disabled(state.isBusy || !state.isConnected)
                        }
                    }
                }
                if let preview = state.preview {
                    Section("Passage preview") {
                        Text(preview.reference).font(.title2.bold())
                        Text(state.translations.first(where: { $0.id == preview.translationID })?.name ?? "")
                            .foregroundStyle(.secondary)
                        ForEach(Array(preview.verses.enumerated()), id: \.offset) { _, verse in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(verse.reference).font(.caption).foregroundStyle(.secondary)
                                Text(verse.text).textSelection(.enabled)
                            }
                        }
                        if !preview.attribution.isEmpty { Text(preview.attribution).font(.footnote).foregroundStyle(.secondary) }
                        Button("Present passage…") { confirmPresent = true }
                            .disabled(state.isBusy || !state.isConnected)
                    }
                }
                Section {
                    Button("Previous scripture slide") { state.navigate(next: false) }
                        .disabled(!state.isConnected || state.isBusy || !state.canNavigate)
                    Button("Next scripture slide") { state.navigate(next: true) }
                        .disabled(!state.isConnected || state.isBusy || !state.canNavigate)
                } header: {
                    Text("Live scripture navigation")
                } footer: {
                    Text("Enabled after you explicitly present a passage in this session. These buttons control the desktop’s current scripture output. Preview text is not a live output monitor.")
                }
            }
            .navigationTitle("Scripture")
            .confirmationDialog("Present this passage on active outputs?", isPresented: $confirmPresent, titleVisibility: .visible) {
                Button("Present passage") { state.present() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(state.preview?.reference ?? "Preview a passage first.")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { confirmPresent = false; password = "" }
        }
        .onChange(of: state.isConnected) { _, connected in
            if !connected { confirmPresent = false }
        }
    }
}
