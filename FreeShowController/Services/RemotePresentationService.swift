import Foundation

enum OperatorError: LocalizedError, Equatable {
    case unsupportedResponse, unavailablePresentation, unavailableLayout, missingSlide, changedPresentation, ambiguousItem, inactiveProject
    case incompletePresentation(String)
    var errorDescription: String? {
        switch self {
        case .incompletePresentation(let detail): "Slide preview unavailable: \(detail). Retry preview. If this continues, open the show on the Mac and check that its source file is available."
        case .unsupportedResponse: "FreeShow returned an unsupported response. Check the desktop version and reconnect."
        case .unavailablePresentation: "This presentation is unavailable. Refresh the project or select another item."
        case .unavailableLayout: "This presentation layout is unavailable. Select another item or refresh."
        case .ambiguousItem: "This item’s name is missing or duplicated in the project. Rename it uniquely on the desktop before starting it remotely."
        case .inactiveProject: "Select this project on the desktop first. Media start is limited to the confirmed active project."
        case .changedPresentation: "The desktop slides changed. Review the refreshed preview before presenting again."
        case .missingSlide: "The layout contains a missing slide. Repair the presentation on the desktop before presenting it."
        }
    }
}

struct PresentationDecoder {
    static func projects(_ value: JSONValue, shows: JSONValue) throws -> [ServiceProject] {
        let entries: [(String, JSONValue)]
        if let dictionary = value.object { entries = dictionary.map { ($0.key, $0.value) } }
        else if let array = value.array {
            entries = try array.map { item in
                guard let id = item["id"].string else { throw OperatorError.unsupportedResponse }
                return (id, item)
            }
        } else { throw OperatorError.unsupportedResponse }
        return try entries.filter { $0.1["deleted"].bool != true }.map { id, project in
            guard let name = project["name"].string, let rawItems = project["shows"].array else { throw OperatorError.unsupportedResponse }
            let items = rawItems.enumerated().map { index, item in
                let showID = item["id"].string
                let kind = item["type"].string ?? "show"
                return ProjectItem(id: "\(id):\(index)", presentationID: showID,
                    name: item["name"].string ?? showID.flatMap { shows[$0]["name"].string } ?? "Untitled item",
                    kind: kind, explicitName: item["name"].string, layoutID: item["layout"].string, index: index)
            }
            return ServiceProject(id: id, name: name, items: items)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func presentation(_ value: JSONValue, id: String, layoutID requested: String? = nil) throws -> Presentation {
        guard let name = value["name"].string, let slides = value["slides"].object,
              let layouts = value["layouts"].object else {
            let missing = ["name", "slides", "layouts"].filter { value[$0] == .null }
            throw OperatorError.incompletePresentation(value == .null ? "FreeShow returned no show data" : "FreeShow returned incomplete show data (\(missing.isEmpty ? "invalid field types" : missing.joined(separator: ", ")))" )
        }
        // An empty project layout means use the show's active layout. If older
        // show data omits it, a single layout is unambiguous; never guess among many.
        let explicit = requested.flatMap { $0.isEmpty ? nil : $0 }
        let active = value["settings"]["activeLayout"].string.flatMap { $0.isEmpty ? nil : $0 }
        guard let layoutID = explicit ?? active ?? (layouts.count == 1 ? layouts.keys.first : nil),
              let parents = layouts[layoutID]?["slides"].array else { throw OperatorError.unavailableLayout }
        var result: [Slide] = []
        let idForShow = id
        func append(_ id: String, data: JSONValue, parentDisabled: Bool) throws {
            guard let source = slides[id] else { throw OperatorError.missingSlide }
            let text = (source["items"].array ?? []).flatMap { item in
                (item["lines"].array ?? []).map { line in
                    (line["text"].array ?? []).compactMap { $0["value"].string }.joined()
                }
            }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(Slide(id: SlideReference(presentationID: idForShow, layoutID: layoutID, index: result.count),
                text: text, thumbnail: nil, sourceID: id, group: source["group"].string ?? "",
                isDisabled: parentDisabled || data["disabled"].bool == true))
        }
        for parent in parents {
            guard let slideID = parent["id"].string, let source = slides[slideID] else { throw OperatorError.missingSlide }
            try append(slideID, data: parent, parentDisabled: false)
            let children = (source["children"].array ?? []).flatMap { $0.array ?? [$0] }
            for child in children {
                guard let childID = child.string else { throw OperatorError.missingSlide }
                try append(childID, data: parent["children"][childID], parentDisabled: parent["disabled"].bool == true)
            }
        }
        return Presentation(id: id, name: name, layoutID: layoutID, slides: result)
    }

    static func output(_ value: JSONValue) -> OutputState {
        guard value != .null else { return .other(description: "No active output data") }
        guard let slide = value.object?["slide"] else { return .unknown }
        if slide == .null {
            if let type = value["background"]["type"].string, ["image", "video", "player"].contains(type) {
                return .other(description: "\(type.capitalized) on output — desktop rendering")
            }
            return .other(description: "Slide layer clear — backgrounds/audio may remain")
        }
        if slide["type"].string == "pdf", let page = slide["page"].nonnegativeInt {
            return .other(description: "PDF · \(slide["name"].string ?? "Document") · page \(page + 1) of \(slide["pages"].int.map(String.init) ?? "?")")
        }
        guard let id = slide["id"].string else { return .other(description: "Other desktop content") }
        if id == "temp" { return .other(description: "Scripture or temporary presentation") }
        guard let layout = slide["layout"].string, let index = slide["index"].nonnegativeInt else { return .unknown }
        return .live(SlideReference(presentationID: id, layoutID: layout, index: index))
    }
}

@MainActor
final class RemotePresentationService: ConnectionService, PresentationService, OutputService {
    private(set) var state: ConnectionState = .disconnected
    private(set) var outputItemID: String?
    private(set) var clearance: ClearedStatus?
    private(set) var slideLayerCleared: Bool?
    private(set) var latest = PresentationSnapshot(projects: [], activeProjectID: nil, output: .unknown, receivedAt: .distantPast)
    var onChange: ((PresentationSnapshot) -> Void)?
    private let session: RemoteSession
    private var rawProjects: JSONValue = .object([:])
    private var shows: JSONValue = .object([:])
    private var isReadingLibrary = false
    private var libraryWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReadingShow = false
    private var showWaiters: [CheckedContinuation<Void, Never>] = []
    private var revision = 0
    private var projectRevision = 0
    private var streams: [UUID: AsyncThrowingStream<PresentationSnapshot, Error>.Continuation] = [:]

    init(session: RemoteSession) {
        self.session = session
        _ = session.observeMessages { [weak self] in self?.receive($0) }
        _ = session.observeDisconnect { [weak self] error in
            guard let self else { return }
            self.state = .disconnected; self.clearance = nil; self.outputItemID = nil; self.slideLayerCleared = nil
            self.latest = PresentationSnapshot(projects: self.latest.projects, activeProjectID: self.latest.activeProjectID,
                output: .unknown, receivedAt: self.latest.receivedAt)
            self.onChange?(self.latest)
            let streams = self.streams; self.streams.removeAll()
            for stream in streams.values { stream.finish(throwing: error ?? CancellationError()) }
        }
    }
    func clearStoredData() {
        rawProjects = .object([:]); shows = .object([:]); clearance = nil; outputItemID = nil; slideLayerCleared = nil
        latest = PresentationSnapshot(projects: [], activeProjectID: nil, output: .unknown, receivedAt: .distantPast)
        publish()
    }
    func connect(to endpoint: FreeShowEndpoint, password: String?) async throws {
        state = .connecting
        try await session.connect(to: endpoint, password: password)
        state = .synchronizing
        _ = try await snapshot()
        try Task.checkCancellation()
        guard session.isReady else { throw ScriptureError.disconnected }
        state = .connected
    }
    func disconnect() async { session.disconnect() }
    func snapshot() async throws -> PresentationSnapshot {
        let token = session.generation, projectsVersion = projectRevision
        let (projects, library) = try await readLibrary()
        try check(token)
        guard library.object != nil else { throw OperatorError.unsupportedResponse }
        shows = library
        if projectRevision == projectsVersion { rawProjects = projects }
        latest = PresentationSnapshot(projects: try PresentationDecoder.projects(rawProjects, shows: shows),
            activeProjectID: latest.activeProjectID, output: latest.output, receivedAt: Date(), desktopSelectionID: latest.desktopSelectionID)
        try await refreshOutput()
        publish()
        return latest
    }
    func refreshOutput() async throws {
        let token = session.generation, version = revision
        let out = try await query("get_output")
        let cleared = try await query("get_cleared")
        try check(token)
        guard let flags = try? JSONDecoder().decode(ClearedStatus.self, from: JSONEncoder().encode(cleared)) else { throw OperatorError.unsupportedResponse }
        if revision == version {
            outputItemID = out["slide"]["id"].string ?? out["background"]["path"].string ?? out["background"]["id"].string
            clearance = flags
            slideLayerCleared = out.object?["slide"].map { $0 == .null } ?? flags.slide
            latest = PresentationSnapshot(projects: latest.projects, activeProjectID: latest.activeProjectID,
                output: flags.all && out != .null ? .cleared : PresentationDecoder.output(out), receivedAt: Date(), desktopSelectionID: latest.desktopSelectionID)
            publish()
        }
    }
    func presentation(id: String) async throws -> Presentation { try await presentation(id: id, layoutID: nil) }
    func presentation(id: String, layoutID: String?) async throws -> Presentation {
        if isReadingShow { await withCheckedContinuation { showWaiters.append($0) } }
        else { isReadingShow = true }
        defer {
            if showWaiters.isEmpty { isReadingShow = false }
            else { showWaiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        var value = try await query("get_show", fields: ["id": .string(id)])
        // The library is authoritative for titles; some cached show bodies omit one.
        if var body = value.object, body["name"]?.string == nil, let name = shows[id]["name"].string {
            body["name"] = .string(name); value = .object(body)
        }
        return try PresentationDecoder.presentation(value, id: id, layoutID: layoutID)
    }
    func thumbnail(for slide: SlideReference) async throws -> Data? {
        let result = try await query("get_slide_thumbnail", fields: ["showId": .string(slide.presentationID),
            "layoutId": .string(slide.layoutID), "index": .number(Double(slide.index))])
        guard let string = result.string, !string.isEmpty, string.count < 8_000_000 else { return nil }
        let base64 = string.hasPrefix("data:") ? String(string.split(separator: ",", maxSplits: 1).last ?? "") : string
        return Data(base64Encoded: base64)
    }
    func updates() -> AsyncThrowingStream<PresentationSnapshot, Error> {
        let id = UUID()
        return AsyncThrowingStream { continuation in
            streams[id] = continuation
            continuation.yield(latest)
            continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.streams[id] = nil } }
        }
    }
    func present(_ slide: SlideReference) async throws {
        guard slide.index >= 0 else { throw OperatorError.missingSlide }
        try await command("index_select_slide", fields: ["showId": .string(slide.presentationID),
            "layoutId": .string(slide.layoutID), "index": .number(Double(slide.index))])
    }
    func presentValidated(_ slide: SlideReference, preview: Presentation) async throws {
        let fresh = try await presentation(id: preview.id, layoutID: preview.layoutID)
        guard fresh.slides == preview.slides, fresh.slides.contains(where: { $0.id == slide && !$0.isDisabled }) else { throw OperatorError.changedPresentation }
        try await present(slide)
    }
    func startProjectItem(projectID: String, item: ProjectItem) async throws {
        guard latest.activeProjectID == projectID else { throw OperatorError.inactiveProject }
        let (projects, library) = try await readLibrary()
        let fresh = try PresentationDecoder.projects(projects, shows: library)
        guard latest.activeProjectID == projectID else { throw OperatorError.inactiveProject }
        guard let project = fresh.first(where: { $0.id == projectID }),
              let current = project.items.first(where: { $0.id == item.id }), current == item else { throw OperatorError.changedPresentation }
        guard current.canStartByName, let name = current.explicitName else { throw OperatorError.ambiguousItem }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard project.items.filter({ $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }).count == 1 else { throw OperatorError.ambiguousItem }
        try await command("name_start_project_item", fields: ["value": .string(name)])
    }
    func activateProject(_ id: String) async throws { try await command("id_select_project", fields: ["id": .string(id)]) }
    func nextSlide() async throws { try await command("next_slide") }
    func previousSlide() async throws { try await command("previous_slide") }
    func clearAll() async throws { try await command("clear_all") }
    func restoreOutput() async throws { try await command("restore_output") }
    func send(_ command: OutputCommand) async throws { try await self.command(command.rawValue) }

    private func readLibrary() async throws -> (JSONValue, JSONValue) {
        if isReadingLibrary { await withCheckedContinuation { libraryWaiters.append($0) } }
        else { isReadingLibrary = true }
        defer {
            if libraryWaiters.isEmpty { isReadingLibrary = false }
            else { libraryWaiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        let projects = try await query("get_projects")
        let shows = try await query("get_shows")
        return (projects, shows)
    }
    private func command(_ action: String, fields: [String: JSONValue] = [:]) async throws {
        guard session.isReady else { throw ScriptureError.disconnected }
        let result = try await query(action, fields: fields)
        guard result == .null else { throw OperatorError.unsupportedResponse }
    }
    private func query(_ action: String, fields: [String: JSONValue] = [:]) async throws -> JSONValue {
        try await session.request(channel: "API:" + action, data: .object(fields))
    }
    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard session.isReady, session.generation == token else { throw CancellationError() }
    }
    private func receive(_ message: RemoteMessage) {
        do {
            switch message.channel {
            case "PROJECTS":
                let projects = try PresentationDecoder.projects(message.data, shows: shows)
                projectRevision += 1; rawProjects = message.data
                latest = PresentationSnapshot(projects: projects,
                    activeProjectID: latest.activeProjectID, output: latest.output, receivedAt: Date(), desktopSelectionID: latest.desktopSelectionID)
            case "SHOWS":
                guard message.data.object != nil else { return }
                shows = message.data
                latest = PresentationSnapshot(projects: try PresentationDecoder.projects(rawProjects, shows: shows),
                    activeProjectID: latest.activeProjectID, output: latest.output, receivedAt: Date(), desktopSelectionID: latest.desktopSelectionID)
            case "PROJECT":
                latest = PresentationSnapshot(projects: latest.projects, activeProjectID: message.data.string,
                    output: latest.output, receivedAt: Date(), desktopSelectionID: latest.desktopSelectionID)
            case "OUT_DATA":
                revision += 1; clearance = nil
                slideLayerCleared = message.data.object?["slide"].map { $0 == .null }
                outputItemID = message.data["slide"]["id"].string ?? message.data["background"]["path"].string ?? message.data["background"]["id"].string
                latest = PresentationSnapshot(projects: latest.projects, activeProjectID: latest.activeProjectID,
                    output: PresentationDecoder.output(message.data), receivedAt: Date(), desktopSelectionID: latest.desktopSelectionID)
            case "ACTIVE_SHOW":
                latest.desktopSelectionID = message.data["id"].string ?? message.data.string
            default: return
            }
            publish()
        } catch {
            // A malformed push cannot replace a previously valid snapshot or enable controls.
            latest = PresentationSnapshot(projects: latest.projects, activeProjectID: latest.activeProjectID,
                output: .unknown, receivedAt: latest.receivedAt)
            publish()
        }
    }
    private func publish() { onChange?(latest); for stream in streams.values { stream.yield(latest) } }
}
