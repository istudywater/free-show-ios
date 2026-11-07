import Combine
import Foundation

@MainActor
final class ScriptureState: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isBusy = false
    @Published private(set) var translations: [ScriptureTranslation] = []
    @Published private(set) var results: [ScriptureSearchResult] = []
    @Published private(set) var preview: ScripturePassage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var message: String?
    @Published private(set) var isSendingCommand = false
    var onCommandUncertain: (() -> Void)?
    @Published private(set) var canNavigate = false
    @Published var selectedTranslationID = "" { didSet { if oldValue != selectedTranslationID { clearSearch() } } }
    @Published var query = "" { didSet { if oldValue != query { clearSearch() } } }
    @Published var searchByText = false { didSet { if oldValue != searchByText { clearSearch() } } }
    let managesConnection: Bool
    private let service: RemoteScriptureService
    private var operation: Task<Void, Never>?
    private var generation = UUID()

    init(service: RemoteScriptureService, managesConnection: Bool = true) {
        self.managesConnection = managesConnection
        self.service = service
        service.onDisconnect = { [weak self] error in
            guard let self else { return }
            if self.managesConnection {
                guard let error else { return }
                self.disconnect()
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            } else {
                self.resetLocal()
                if let error, !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func connect(host: String, port: String, password: String) {
        guard !isBusy, !isConnected else { return }
        let endpoint: FreeShowEndpoint
        do { endpoint = try RESTClient.endpoint(host: host, port: port) }
        catch { errorMessage = error.localizedDescription; return }
        run {
            try await self.service.connect(to: endpoint, password: password)
            try Task.checkCancellation()
            let translations = try await self.service.availableTranslations()
            try Task.checkCancellation()
            self.translations = translations
            self.selectedTranslationID = translations.first?.id ?? ""
            self.isConnected = true
            self.message = translations.isEmpty ? "No individual translations are available. Add a Bible in FreeShow; collections are not supported yet." : "Choose a translation, then search or preview a reference."
        }
    }

    func adoptConnectedSession() async throws {
        resetLocal()
        let values = try await service.availableTranslations()
        try Task.checkCancellation()
        translations = values
        selectedTranslationID = values.first?.id ?? ""
        isConnected = true
    }

    func search() {
        guard isConnected, !isBusy else { return }
        preview = nil
        results = []
        let query = self.query, id = selectedTranslationID, text = searchByText
        run {
            if text {
                let results = try await self.service.searchText(query, translationID: id)
                try Task.checkCancellation()
                self.results = results
                self.message = results.isEmpty ? "No matching verses." : "Showing up to 50 matches. Select one to preview it."
            } else {
                let passage = try await self.service.searchReference(query, translationID: id)
                try Task.checkCancellation()
                self.preview = passage
            }
        }
    }

    func select(_ result: ScriptureSearchResult) {
        guard isConnected, !isBusy, result.translationID == selectedTranslationID else { return }
        preview = nil
        run {
            let passage = try await self.service.previewPassage(reference: result.commandReference, translationID: result.translationID)
            try Task.checkCancellation()
            self.preview = passage
        }
    }

    func present() {
        guard isConnected, !isBusy, let preview else { return }
        isSendingCommand = true
        run {
            try await self.service.presentPassage(preview)
            try Task.checkCancellation()
            self.canNavigate = true
            self.message = "Present request sent for \(preview.reference). A live output change is not confirmed."
        }
    }

    func navigate(next: Bool) {
        guard isConnected, !isBusy, canNavigate else { return }
        isSendingCommand = true
        run {
            if next { try await self.service.nextScriptureSlide() }
            else { try await self.service.previousScriptureSlide() }
            try Task.checkCancellation()
            self.message = "Scripture navigation request sent. Check the desktop output; preview is unchanged."
        }
    }

    func disconnect() {
        resetLocal()
        if managesConnection { service.disconnect() }
    }

    private func resetLocal() {
        if isSendingCommand { onCommandUncertain?() }
        isSendingCommand = false
        generation = UUID()
        operation?.cancel(); operation = nil
        isConnected = false; isBusy = false; canNavigate = false
        translations = []; results = []; preview = nil
        selectedTranslationID = ""
        errorMessage = nil; message = nil
    }

    private func clearSearch() {
        preview = nil; results = []; message = nil; errorMessage = nil
        // The UI disables editing during operations. Programmatic edits also invalidate old results.
        if isBusy && isConnected {
            disconnect()
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        isBusy = true; errorMessage = nil; message = nil
        let token = generation
        operation = Task {
            do {
                try await work()
            } catch {
                guard generation == token else { return }
                preview = nil
                isConnected = service.isConnected
                if !isConnected { canNavigate = false }
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
            guard generation == token else { return }
            isBusy = false; isSendingCommand = false; operation = nil
        }
    }
}
