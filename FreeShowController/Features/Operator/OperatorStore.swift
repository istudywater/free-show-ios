import Foundation
import Combine

struct ProjectItemIntent {
    let projectID: String
    let item: ProjectItem
}

struct PresentIntent {
    let slide: SlideReference
    let presentation: Presentation
}

@MainActor
final class OperatorStore: ObservableObject {
    @Published var host = ""
    @Published var port = "5510"
    @Published var password = ""
    @Published var autoReconnect = true { didSet {
        if !autoReconnect && phase == .reconnecting { disconnect() }
        saveSettings()
    } }
    @Published private(set) var rememberPassword = false
    @Published private(set) var phase: ConnectionState = .disconnected
    @Published private(set) var snapshot = PresentationSnapshot(projects: [], activeProjectID: nil, output: .unknown, receivedAt: .distantPast)
    @Published private(set) var outputItemID: String?
    @Published private(set) var selectedProjectID = ""
    @Published private(set) var selectedItemID: String?
    @Published private(set) var presentation: Presentation?
    @Published private(set) var livePresentation: Presentation?
    @Published private(set) var selectedSlide: SlideReference?
    @Published private(set) var commandOutcomeUnknown = false
    @Published private(set) var isSending = false
    @Published private(set) var isLoading = false
    @Published private(set) var isDemo = false
    @Published private(set) var followsLive = true
    @Published private(set) var thumbnails: [SlideReference: Data] = [:]
    @Published private(set) var thumbnailLoading = false
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var previewError: String?
    @Published private(set) var thumbnailMessage: String?
    @Published var singleTapLive = false
    let scripture: ScriptureState
    let session: RemoteSession
    private let client: RemotePresentationService
    private let transport: SwitchableRemoteTransport
    private let defaults: UserDefaults
    private let vault: any CredentialVault
    private var generation = UUID()
    private var desired = false
    private var foreground = true
    private var attempting = false
    private var target: FreeShowEndpoint?
    private var sessionPassword = ""
    private var savedEndpoint: FreeShowEndpoint?
    private var connectionTask: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var loadingTask: Task<Void, Never>?
    private var visibleSlides: Set<SlideReference> = []
    private var thumbnailQueue: [SlideReference] = []
    private var thumbnailAttempts: Set<SlideReference> = []
    private var thumbnailGeneration = UUID()
    private var pauseAutomaticThumbnails = false
    private var thumbnailTask: Task<Void, Never>?
    private var queuedPreview: (String, String?)?
    private var queuedLive: SlideReference?
    private var previewTarget: (String, String?)?
    private var followingProject = true
    private var subscriptions: Set<AnyCancellable> = []
    private let freshnessLimit: TimeInterval
    private let watchdogInterval: Duration
    private let heartbeatInterval: Duration
    private let retryDelay: (Int) -> Duration
    private static let settingsKey = "FreeShowRemote.operator.connection"

    init(transport: SwitchableRemoteTransport, defaults: UserDefaults = .standard,
         vault: any CredentialVault, heartbeatInterval: Duration = .seconds(2),
         requestTimeout: Duration = .seconds(20), freshnessLimit: TimeInterval = 8, watchdogInterval: Duration = .seconds(1),
         retryDelay: @escaping (Int) -> Duration = { .seconds(min(30, 1 << min($0, 5))) }) {
        self.transport = transport; self.defaults = defaults; self.vault = vault
        self.heartbeatInterval = heartbeatInterval; self.retryDelay = retryDelay
        self.freshnessLimit = freshnessLimit; self.watchdogInterval = watchdogInterval
        session = RemoteSession(transport: transport, timeout: requestTimeout)
        client = RemotePresentationService(session: session)
        scripture = ScriptureState(service: RemoteScriptureService(session: session), managesConnection: false)
        if let data = defaults.data(forKey: Self.settingsKey), let settings = try? JSONDecoder().decode(ConnectionPreferences.self, from: data) {
            host = settings.host; port = settings.port; autoReconnect = settings.autoReconnect; rememberPassword = settings.rememberPassword
            savedEndpoint = try? RESTClient.endpoint(host: settings.host, port: settings.port)
        }
        scripture.onCommandUncertain = { [weak self] in
            self?.commandOutcomeUnknown = true
            self?.message = "A scripture command may have run. Check desktop output; it will not be replayed."
        }
        client.onChange = { [weak self] in self?.receive($0) }
        _ = session.observeDisconnect { [weak self] in self?.sessionEnded($0) }
        scripture.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }
    var canControl: Bool { phase == .connected && session.isReady && snapshot.output != .unknown && !isSending && !scripture.isBusy && !commandOutcomeUnknown }
    var selectedProject: ServiceProject? { snapshot.projects.first { $0.id == selectedProjectID } }
    var outputIsClear: Bool { client.slideLayerCleared == true || snapshot.output == .cleared }
    var canStartSelectedItem: Bool {
        guard canControl, selectedProjectID == snapshot.activeProjectID, let item = selectedItem, item.canStartByName else { return false }
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return selectedProject?.items.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name }.count == 1
    }
    var selectedItem: ProjectItem? { selectedProject?.items.first { $0.id == selectedItemID } }
    var currentReference: SlideReference? {
        if let pdf = client.pdfOutput { return SlideReference(presentationID: pdf.path, layoutID: Presentation.pdfLayoutID, index: pdf.page) }
        if case .live(let ref) = snapshot.output { return ref }
        return nil
    }
    var previewSlide: Slide? { presentation?.slides.first { $0.id == selectedSlide } }
    var currentSlide: Slide? { livePresentation?.slides.first { $0.id == currentReference } }
    var nextSlide: Slide? {
        guard let current = currentReference, let livePresentation,
              livePresentation.id == current.presentationID, livePresentation.layoutID == current.layoutID else { return nil }
        return livePresentation.slides.first { $0.id.index > current.index && !$0.isDisabled }
    }
    var isStale: Bool { phase != .connected }

    func connect() {
        do {
            let endpoint = try RESTClient.endpoint(host: host, port: port)
            var secret = password
            if secret.isEmpty && rememberPassword { secret = try vault.password(for: endpoint) ?? "" }
            start(endpoint: endpoint, password: secret, demo: false)
        } catch { errorMessage = error.localizedDescription }
    }
    func connect(to computer: DiscoveredComputer) { host = computer.host; port = String(computer.port); connect() }
    func startDemo() { start(endpoint: FreeShowEndpoint(host: "demo.local", port: 5510), password: "", demo: true) }
    private func start(endpoint: FreeShowEndpoint, password: String, demo: Bool) {
        disconnect()
        client.clearStoredData(); selectedProjectID = ""
        pauseAutomaticThumbnails = false; visibleSlides = []
        transport.useDemo(demo); isDemo = demo; desired = true; foreground = true
        target = endpoint; sessionPassword = password; followingProject = true; followsLive = true
        launchConnection()
    }
    func disconnect() {
        if isSending { commandOutcomeUnknown = true }
        desired = false; invalidateTasks()
        phase = .disconnected; isSending = false; isLoading = false; thumbnailLoading = false
        session.disconnect(); sessionPassword = ""; password = ""
        presentation = nil; livePresentation = nil; selectedSlide = nil; selectedItemID = nil
        queuedLive = nil; queuedPreview = nil; previewTarget = nil; thumbnails = [:]
        message = nil; errorMessage = nil; isDemo = false
    }
    func suspend() {
        foreground = false
        if isSending { commandOutcomeUnknown = true; message = "An interrupted command may have run. It will not be replayed." }
        invalidateTasks(); isSending = false; isLoading = false; thumbnailLoading = false
        phase = .disconnected; session.disconnect(); password = ""
        if !autoReconnect { desired = false; sessionPassword = "" }
    }
    func resume() {
        foreground = true
        if desired && autoReconnect && !session.isReady { launchConnection() }
    }
    func acknowledgeUncertainCommand() { commandOutcomeUnknown = false }
    func retry() {
        guard !isSending else { return }
        guard target != nil else { connect(); return }
        desired = true; foreground = true; invalidateTasks(); launchConnection()
    }
    func setRememberPassword(_ remember: Bool) {
        rememberPassword = remember
        do {
            let endpoint = target.flatMap { isDemo ? nil : $0 } ?? (try? RESTClient.endpoint(host: host, port: port))
            if let endpoint {
                if remember && phase == .connected && !sessionPassword.isEmpty { try vault.save(sessionPassword, for: endpoint) }
                else if !remember { try vault.remove(for: endpoint) }
            }
            saveSettings()
        } catch { errorMessage = error.localizedDescription }
    }
    func forgetPassword() { setRememberPassword(false); password = ""; sessionPassword = "" }

    func selectProject(_ id: String) {
        guard !isSending else { return }
        followingProject = false; followsLive = false
        if selectedProjectID != id { selectedProjectID = id; clearPreview() }
    }
    func followDesktopProject() {
        followingProject = true
        if let id = snapshot.activeProjectID { selectedProjectID = id; clearPreview() }
    }
    func selectItem(_ item: ProjectItem) {
        guard !isSending else { return }
        followsLive = false; selectedItemID = item.id; selectedSlide = nil; presentation = nil; previewError = nil; thumbnailMessage = nil
        guard item.canPreview, let id = item.presentationID else {
            previewTarget = nil
            message = item.canStartByName ? "\(item.kind.capitalized) selected. Start item requires confirmation and a unique name in the active desktop project." : "\(item.kind.capitalized) items are listed for context. This item needs desktop control or a unique supported media name."
            return
        }
        previewTarget = (id, item.previewLayoutID); queuedPreview = previewTarget; drainLoads()
    }
    func selectSlide(_ slide: Slide) {
        guard !isSending, !slide.isDisabled else { return }
        followsLive = false; selectedSlide = slide.id
    }
    func tapSlide(_ slide: Slide) {
        selectSlide(slide)
        if singleTapLive { goLive(slide) }
    }
    func holdSlide(_ slide: Slide) {
        guard !singleTapLive else { return }
        selectSlide(slide)
        goLive(slide)
    }
    private func goLive(_ slide: Slide) {
        guard let presentation, presentation.slides.contains(slide), !slide.isDisabled else { return }
        present(PresentIntent(slide: slide.id, presentation: presentation))
    }
    func toggleOutput() {
        guard canControl else { return }
        if !outputIsClear { send(.clear) }
        else if let slide = previewSlide { goLive(slide) }
        else { send(.restore) }
    }
    func followLive() {
        followsLive = true; selectedItemID = nil
        guard let ref = currentReference else { return }
        previewTarget = (ref.presentationID, ref.layoutID); selectedSlide = ref
        queuedPreview = previewTarget; drainLoads()
    }
    func present(_ intent: PresentIntent) {
        guard canControl else { return }
        mutate("Present") { try await self.client.presentValidated(intent.slide, preview: intent.presentation) }
    }
    func startProjectItem(_ intent: ProjectItemIntent) {
        guard canControl else { return }
        mutate("Start \(intent.item.kind)") { try await self.client.startProjectItem(projectID: intent.projectID, item: intent.item) }
    }
    func send(_ command: OutputCommand) {
        guard canControl else { return }
        mutate(command.title) { try await self.client.send(command) }
    }
    func activateSelectedProject() {
        guard canControl, !selectedProjectID.isEmpty else { return }
        let id = selectedProjectID
        mutate("Select project") { try await self.client.activateProject(id) }
    }
    func refresh() {
        guard phase == .connected, !session.hasPending("API:get_projects") else { return }
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            do { _ = try await self.client.snapshot() }
            catch { if token == self.generation { self.errorMessage = error.localizedDescription } }
            guard token == self.generation else { return }
            self.retryPreview()
        }
    }
    func retryPreview() {
        guard session.isReady else { return }
        previewError = nil; thumbnailMessage = nil
        client.invalidatePDFPreview()
        pauseAutomaticThumbnails = false; thumbnailAttempts = []; thumbnailGeneration = UUID()
        thumbnails = [:]
        if let target = previewTarget { queuedPreview = target; drainLoads() }
        if let ref = currentReference { queuedLive = ref; drainLoads() }
        for ref in visibleSlides { queueThumbnail(ref) }
        if let ref = selectedSlide { queueThumbnail(ref) }
    }
    func thumbnailVisible(_ reference: SlideReference) {
        visibleSlides.insert(reference)
        queueThumbnail(reference)
    }
    func thumbnailHidden(_ reference: SlideReference) {
        visibleSlides.remove(reference)
        thumbnailQueue.removeAll { $0 == reference }
    }
    private func queueThumbnail(_ reference: SlideReference) {
        guard reference.layoutID != Presentation.pdfLayoutID else { return }
        guard session.isReady, !pauseAutomaticThumbnails, thumbnails[reference] == nil,
              !thumbnailAttempts.contains(reference), !thumbnailQueue.contains(reference) else { return }
        thumbnailQueue.append(reference)
        drainThumbnails()
    }
    func loadSelectedThumbnail() {
        guard let ref = selectedSlide, session.isReady, !thumbnailLoading else { return }
        pauseAutomaticThumbnails = false
        thumbnailMessage = nil
        thumbnailAttempts.remove(ref); queueThumbnail(ref)
    }
    private func drainThumbnails() {
        guard thumbnailTask == nil, !thumbnailQueue.isEmpty, session.isReady else { return }
        thumbnailLoading = true; let token = generation
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.generation { self.thumbnailLoading = false; self.thumbnailTask = nil } }
            while !self.thumbnailQueue.isEmpty && token == self.generation && self.session.isReady {
                let ref = self.thumbnailQueue.removeFirst(), imageToken = self.thumbnailGeneration
                self.thumbnailAttempts.insert(ref)
                do {
                    let data = try await self.client.thumbnail(for: ref)
                    guard token == self.generation else { return }
                    if let data, imageToken == self.thumbnailGeneration {
                        if self.thumbnails.count >= 24 || self.thumbnails.values.reduce(0, { $0 + $1.count }) + data.count > 16_000_000 { self.thumbnails.removeAll() }
                        self.thumbnails[ref] = data
                    } else if imageToken == self.thumbnailGeneration {
                        self.thumbnailMessage = "FreeShow returned no rendered image. Text previews remain available. Enable a desktop output, then retry preview."
                    }
                } catch {
                    if token == self.generation {
                        self.pauseAutomaticThumbnails = true; self.thumbnailQueue = []
                        self.thumbnailMessage = "Rendered preview failed: \(error.localizedDescription)"
                    }
                    return
                }
            }
        }
    }

    private func launchConnection() {
        guard let target, desired, foreground else { return }
        let token = generation
        connectionTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 0
            while self.desired && self.foreground && token == self.generation {
                self.phase = attempt == 0 ? .connecting : .reconnecting
                self.attempting = true
                do {
                    try await self.client.connect(to: target, password: self.sessionPassword)
                    try Task.checkCancellation()
                    guard token == self.generation else { return }
                    try await self.scripture.adoptConnectedSession()
                    self.attempting = false; self.phase = .connected; self.errorMessage = nil
                    if !self.isDemo {
                        self.host = target.host; self.port = String(target.port); self.savedEndpoint = target; self.saveSettings()
                        if self.rememberPassword {
                            do {
                                if self.sessionPassword.isEmpty { try self.vault.remove(for: target) }
                                else { try self.vault.save(self.sessionPassword, for: target) }
                            } catch { self.errorMessage = error.localizedDescription }
                        }
                    } else { self.scripture.query = "Sample 1:1–3" }
                    self.message = self.isDemo ? "Offline rehearsal: browse, preview, then Present to simulate output." : "Browse a service item to preview; Present changes live output."
                    self.receive(self.client.latest)
                    if self.isDemo, self.previewTarget == nil, let first = self.selectedProject?.items.first(where: { $0.canPreview }) { self.selectItem(first) }
                    else if let target = self.previewTarget {
                        self.presentation = nil; self.selectedSlide = nil; self.queuedPreview = target; self.drainLoads()
                    }
                    self.startMonitoring(token: token)
                    return
                } catch {
                    guard token == self.generation, !Task.isCancelled else { return }
                    self.attempting = false
                    self.errorMessage = error.localizedDescription
                    let recoverable: Bool
                    switch error as? ScriptureError {
                    case .disconnected, .timeout, .libraryChanged, .transport: recoverable = true
                    default: recoverable = false
                    }
                    guard self.autoReconnect, self.desired, recoverable else {
                        self.desired = false
                        self.phase = error as? ScriptureError == .password ? .authenticationRequired : .failed(error.localizedDescription)
                        self.session.disconnect()
                        return
                    }
                    self.phase = .reconnecting
                    do { try await Task.sleep(for: self.retryDelay(attempt)) } catch { return }
                    attempt += 1
                }
            }
        }
    }
    private func sessionEnded(_ error: Error?) {
        guard desired, foreground, !attempting else { return }
        let wasSending = isSending, wasRendering = thumbnailLoading
        invalidateTasks(); isSending = false; isLoading = false; thumbnailLoading = false
        livePresentation = nil; selectedSlide = nil; thumbnails = [:]
        if wasRendering { pauseAutomaticThumbnails = true }
        if wasSending { commandOutcomeUnknown = true; message = "The command outcome is unknown. Check output after reconnecting; it will not be replayed." }
        if let error { errorMessage = error.localizedDescription }
        if error as? ScriptureError == .password || error as? ScriptureError == .capacity {
            desired = false; phase = .authenticationRequired; return
        }
        if error as? ScriptureError == .invalidData || error is OperatorError {
            desired = false; phase = .failed(error?.localizedDescription ?? "Unsupported server response"); return
        }
        if autoReconnect {
            phase = .reconnecting
            let token = generation
            connectionTask = Task { [weak self] in
                guard let self else { return }
                do { try await Task.sleep(for: self.retryDelay(0)) } catch { return }
                guard token == self.generation else { return }
                self.launchConnection()
            }
        } else { desired = false; phase = .failed("Connection lost") }
    }
    private func startMonitoring(token: UUID) {
        heartbeat?.cancel(); watchdog?.cancel()
        heartbeat = Task { [weak self] in
            guard let self else { return }
            var tick = 0
            while token == self.generation && self.desired && self.foreground {
                do { try await Task.sleep(for: self.heartbeatInterval) } catch { return }
                guard token == self.generation, self.session.isReady else { return }
                do {
                    if !self.session.hasPending("API:get_output") { try await self.client.refreshOutput() }
                    tick += 1
                    if tick % 5 == 0, !self.session.hasPending("API:get_projects") { _ = try await self.client.snapshot() }
                    if tick % 3 == 0, let target = self.previewTarget { self.queuedPreview = target; self.drainLoads() }
                    if let ref = self.currentReference { self.queuedLive = ref; self.drainLoads() }
                } catch {
                    if token == self.generation && self.session.isReady {
                        if error as? OperatorError == .unsupportedResponse { self.stopForUnsupported(error) }
                        else { self.errorMessage = error.localizedDescription }
                    }
                }
            }
        }
        watchdog = Task { [weak self] in
            guard let self else { return }
            while token == self.generation {
                do { try await Task.sleep(for: self.watchdogInterval) } catch { return }
                if self.phase == .connected && Date().timeIntervalSince(self.snapshot.receivedAt) > self.freshnessLimit { self.phase = .synchronizing }
            }
        }
    }
    private func receive(_ value: PresentationSnapshot) {
        snapshot = value; outputItemID = client.outputItemID
        guard session.isReady else { return }
        if phase == .synchronizing && client.state == .connected && value.output != .unknown { phase = .connected }
        else if phase == .connected && value.output == .unknown { phase = .synchronizing }
        if selectedProjectID.isEmpty || !value.projects.contains(where: { $0.id == selectedProjectID }) || followingProject {
            let id = value.activeProjectID ?? value.projects.first?.id ?? ""
            if id != selectedProjectID { selectedProjectID = id; clearPreview() }
        }
        if let selectedItemID {
            if let item = selectedProject?.items.first(where: { $0.id == selectedItemID }) {
                if item.canPreview && (item.presentationID != previewTarget?.0 || item.previewLayoutID != previewTarget?.1) { clearPreview() }
            } else { clearPreview() }
        }
        if let ref = currentReference {
            if livePresentation?.id != ref.presentationID || livePresentation?.layoutID != ref.layoutID { queuedLive = ref; drainLoads() }
            if followsLive {
                selectedSlide = ref
                if previewTarget?.0 != ref.presentationID || previewTarget?.1 != ref.layoutID {
                    previewTarget = (ref.presentationID, ref.layoutID); queuedPreview = previewTarget; drainLoads()
                }
            }
        } else { livePresentation = nil }
    }
    private func clearPreview() {
        selectedItemID = nil; selectedSlide = nil; presentation = nil; previewTarget = nil; queuedPreview = nil
        previewError = nil; thumbnailMessage = nil
    }
    private func drainLoads() {
        guard loadingTask == nil, session.isReady else { return }
        isLoading = true; let token = generation
        loadingTask = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.generation { self.isLoading = false; self.loadingTask = nil } }
            while token == self.generation && self.session.isReady {
                let request: (String, String?)
                if let queued = self.queuedPreview { request = queued; self.queuedPreview = nil }
                else if let live = self.queuedLive { request = (live.presentationID, live.layoutID); self.queuedLive = nil }
                else { return }
                do {
                    let presentation = try await self.client.presentation(id: request.0, layoutID: request.1)
                    guard token == self.generation else { return }
                    if self.previewTarget?.0 == request.0 && self.previewTarget?.1 == request.1 {
                        self.previewError = nil
                        let changed = self.presentation?.slides != presentation.slides
                        self.presentation = presentation
                        if changed {
                            self.thumbnails = [:]; self.thumbnailAttempts = []; self.thumbnailGeneration = UUID()
                            for ref in self.visibleSlides where presentation.slides.contains(where: { $0.id == ref }) { self.queueThumbnail(ref) }
                        }
                        if !presentation.slides.contains(where: { $0.id == self.selectedSlide }) {
                            self.selectedSlide = presentation.slides.first(where: { !$0.isDisabled })?.id
                        }
                    }
                    if let current = self.currentReference, presentation.id == current.presentationID && presentation.layoutID == current.layoutID {
                        self.livePresentation = presentation
                    }
                } catch {
                    if token == self.generation && !(error is CancellationError) {
                        self.previewError = error.localizedDescription
                    }
                }
            }
        }
    }
    private func mutate(_ label: String, work: @escaping @MainActor () async throws -> Void) {
        isSending = true; errorMessage = nil; message = nil; let token = generation
        commandTask = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.generation { self.isSending = false; self.commandTask = nil } }
            do {
                try await work()
                try Task.checkCancellation()
                guard token == self.generation else { return }
                self.message = "\(label) request sent. Output below is desktop-reported."
                if !self.session.hasPending("API:get_output") { try await self.client.refreshOutput() }
            } catch {
                guard token == self.generation else { return }
                self.errorMessage = error.localizedDescription
                if error as? OperatorError == .unsupportedResponse { self.stopForUnsupported(error); return }
                if error as? OperatorError == .changedPresentation, let target = self.previewTarget { self.queuedPreview = target; self.drainLoads() }
            }
        }
    }
    private func stopForUnsupported(_ error: Error) {
        if isSending { commandOutcomeUnknown = true }
        desired = false; invalidateTasks()
        isSending = false; isLoading = false; thumbnailLoading = false
        phase = .failed(error.localizedDescription); session.disconnect()
        errorMessage = error.localizedDescription
    }
    private func invalidateTasks() {
        generation = UUID(); attempting = false
        connectionTask?.cancel(); heartbeat?.cancel(); watchdog?.cancel(); commandTask?.cancel(); loadingTask?.cancel(); thumbnailTask?.cancel()
        connectionTask = nil; heartbeat = nil; watchdog = nil; commandTask = nil; loadingTask = nil; thumbnailTask = nil
        queuedPreview = nil; queuedLive = nil; thumbnailQueue = []; thumbnailAttempts = []; thumbnailGeneration = UUID()
    }
    private func saveSettings() {
        guard !isDemo else { return }
        let settings = ConnectionPreferences(host: savedEndpoint?.host ?? "", port: savedEndpoint.map { String($0.port) } ?? "5510", autoReconnect: autoReconnect, rememberPassword: rememberPassword)
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.settingsKey) }
    }
}
