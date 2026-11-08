import Foundation

private func json(_ value: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(value.utf8)) }

@MainActor
final class ControlledRemote: RemoteTransport {
    var receive: ((RemoteEvent) -> Void)?
    let backend = DemoTransport()
    var messages: [RemoteMessage] = []
    var connectCount = 0
    var requiresPassword = false
    var failConnects = 0
    var disconnectAfterMutation = false
    var disconnectOnChannel: String?
    var alterShow = false
    var noOutput = false
    var corruptScripture = false
    var duplicateMediaName = false
    var missingShow = false
    var omitShowTitle = false
    var hold: Set<String> = []
    private var held: [(String, RemoteEvent, (RemoteEvent) -> Void)] = []
    func connect(to url: URL) {
        connectCount += 1
        if failConnects > 0 { failConnects -= 1; receive?(.closed); return }
        backend.receive = { [weak self] event in
            guard let self, let callback = self.receive else { return }
            if case .message(let message) = event {
                if self.missingShow && message.channel == "API:get_show" {
                    callback(.message(RemoteMessage(channel: message.channel, data: .null))); return
                }
                if self.omitShowTitle && message.channel == "API:get_show", var body = message.data.object {
                    body.removeValue(forKey: "name")
                    callback(.message(RemoteMessage(channel: message.channel, data: .object(body)))); return
                }
                if self.duplicateMediaName && message.channel == "API:get_projects", var projects = message.data.object,
                   var project = projects["service"]?.object, var items = project["shows"]?.array {
                    items.append(.object(["id": .string("another-document"), "name": .string("Announcements document"), "type": .string("pdf")]))
                    project["shows"] = .array(items); projects["service"] = .object(project)
                    callback(.message(RemoteMessage(channel: message.channel, data: .object(projects)))); return
                }
                if self.corruptScripture && message.channel == "GET_SCRIPTURE", var data = message.data.object {
                    data["bible"] = .object([:])
                    callback(.message(RemoteMessage(channel: message.channel, data: .object(data)))); return
                }
                if self.noOutput && message.channel == "API:get_output" {
                    callback(.message(RemoteMessage(channel: message.channel, data: .null))); return
                }
                if self.noOutput && message.channel == "API:get_cleared" {
                    callback(.message(RemoteMessage(channel: message.channel, data: .object(Dictionary(uniqueKeysWithValues: ["all", "background", "slide", "overlays", "audio", "slideTimers"].map { ($0, .bool(true)) }))))); return
                }
                if self.hold.contains(message.channel) { self.held.append((message.channel, event, callback)); return }
                if self.alterShow && message.channel == "API:get_show", var object = message.data.object,
                   var slides = object["slides"]?.object, var first = slides["slide0"]?.object {
                    first["items"] = json(#"[{"lines":[{"text":[{"value":"Changed on desktop"}]}]}]"#)
                    slides["slide0"] = .object(first); object["slides"] = .object(slides)
                    callback(.message(RemoteMessage(channel: message.channel, data: .object(object)))); return
                }
            }
            callback(event)
        }
        receive?(.connected)
    }
    func emit(_ message: RemoteMessage) throws {
        messages.append(message)
        if message.channel == "PASSWORD", requiresPassword {
            receive?(.message(RemoteMessage(channel: "PASSWORD", data: .object(["password": .bool(true)])))); return
        }
        if message.channel == "ACCESS" {
            if message.data == .string("fixture-secret") { try backend.emit(RemoteMessage(channel: "PASSWORD", data: .null)) }
            else { receive?(.message(RemoteMessage(channel: "ERROR", data: .object(["key": .string("wrongPass")])))) }
            return
        }
        if (disconnectAfterMutation && message.channel == "API:next_slide") || disconnectOnChannel == message.channel {
            disconnectAfterMutation = false; disconnectOnChannel = nil
            let saved = backend.receive; backend.receive = nil
            try backend.emit(message); backend.receive = saved
            receive?(.closed); return
        }
        try backend.emit(message)
    }
    func disconnect() { backend.disconnect() }
    func release(_ channel: String) {
        hold.remove(channel)
        let events = held.filter { $0.0 == channel }; held.removeAll { $0.0 == channel }
        for (_, event, callback) in events { callback(event) }
    }
    func count(_ channel: String) -> Int { messages.filter { $0.channel == channel }.count }
    func drop() { receive?(.closed) }
}

@main
struct OperatorTests {
    @MainActor
    static func main() async throws {
        var checks = 0
        func expect(_ condition: Bool, _ name: String) { precondition(condition, name); checks += 1 }
        func wait(_ name: String, _ condition: @escaping @MainActor () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(4)
            while !condition() {
                guard Date() < deadline else { fatalError("Timed out: \(name)") }
                try await Task.sleep(for: .milliseconds(3))
            }
        }
        let raw = json(#"{"name":"Repeated","settings":{"activeLayout":"a"},"layouts":{"a":{"slides":[{"id":"parent","children":{"child":{"disabled":true}}},{"id":"parent"}]}},"slides":{"parent":{"group":"Verse","children":["child"],"items":[{"lines":[{"text":[{"value":"First "},{"value":"line"}]},{"text":[{"value":"Second line"}]}]}]},"child":{"group":null,"items":[]}}}"#)
        let layout = try PresentationDecoder.presentation(raw, id: "show")
        expect(layout.slides.count == 4, "Parent/child occurrences flattened in layout order")
        expect(layout.slides.map(\.sourceID) == ["parent", "child", "parent", "child"], "Repeated children preserve occurrence identity")
        expect(Set(layout.slides.map(\.id)).count == 4, "Slide identity includes flattened position")
        expect(layout.slides[0].text == "First line\nSecond line", "Styled runs and line order")
        expect(layout.slides[1].isDisabled && !layout.slides[3].isDisabled, "Per-occurrence disabled state")
        expect(layout.slides.map { $0.id.index } == [0,1,2,3], "Zero-based Remote positions")
        let emptyProjectLayout = try PresentationDecoder.presentation(raw, id: "show", layoutID: "")
        expect(emptyProjectLayout == layout, "Empty project layout uses active layout")
        var legacy = raw.object!
        legacy["settings"] = .object([:])
        expect(try PresentationDecoder.presentation(.object(legacy), id: "show") == layout, "Single layout can be previewed without activeLayout metadata")
        do { _ = try PresentationDecoder.presentation(raw, id: "show", layoutID: "missing"); fatalError("Missing layout accepted") }
        catch { expect(error as? OperatorError == .unavailableLayout, "Missing layout rejected") }
        let missing = json(#"{"name":"Broken","settings":{"activeLayout":"a"},"layouts":{"a":{"slides":[{"id":"absent"}]}},"slides":{}}"#)
        do { _ = try PresentationDecoder.presentation(missing, id: "broken"); fatalError("Missing slide accepted") }
        catch { expect(error as? OperatorError == .missingSlide, "Missing slides cannot shift command indices") }
        let projectData = json(#"{"p":{"name":"Service","shows":[{"id":"show","layout":"a"},{"id":"section","type":"section","name":"Prayers"},{"id":"show","layout":"b"}]},"deleted":{"name":"Old","deleted":true,"shows":[]}}"#)
        let projects = try PresentationDecoder.projects(projectData, shows: json(#"{"show":{"name":"Library title"}}"#))
        expect(projects.count == 1 && projects[0].items.count == 3, "Deleted projects excluded and item order retained")
        expect(projects[0].items[0].name == "Library title", "Project title fallback")
        expect(!projects[0].items[1].canPreview, "Unsupported item is explicit")
        expect(projects[0].items[0].id != projects[0].items[2].id && projects[0].items[2].layoutID == "b", "Repeated project occurrences and layouts")
        expect(PresentationDecoder.output(.null) != .cleared, "Absent output is not cleared")
        expect(PresentationDecoder.output(json(#"{"slide":{"id":"temp"}}"#)) == .other(description: "Scripture or temporary presentation"), "Temporary scripture output is explicit")
        let live = PresentationDecoder.output(json(#"{"slide":{"id":"show","layout":"a","index":0}}"#))
        expect(live == .live(SlideReference(presentationID: "show", layoutID: "a", index: 0)), "Output index zero is valid")

        let suite = "FreeShowRemote.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = ControlledRemote(), vault = MemoryCredentialVault()
        let router = SwitchableRemoteTransport(live: fixture)
        let store = OperatorStore(transport: router, defaults: defaults, vault: vault, heartbeatInterval: .seconds(60), retryDelay: { _ in .milliseconds(5) })
        store.host = "fixture.local"; store.port = "5510"
        fixture.requiresPassword = true; store.password = "wrong"
        store.connect()
        try await wait("authentication failure") { store.phase == .authenticationRequired }
        let failedCount = fixture.connectCount
        try await Task.sleep(for: .milliseconds(30))
        expect(fixture.connectCount == failedCount, "Wrong password does not loop")
        store.password = "fixture-secret"; store.setRememberPassword(true); store.connect()
        try await wait("ready") { store.phase == .connected && store.scripture.isConnected }
        expect(store.snapshot.projects.count == 2 && store.snapshot.activeProjectID == "service", "Initial sync fetches full projects and active project")
        expect(store.canControl, "Controls enabled after sync")
        let endpoint = FreeShowEndpoint(host: "fixture.local", port: 5510)
        expect(try vault.password(for: endpoint) == "fixture-secret", "Opt-in password saved in vault")
        let settings = defaults.data(forKey: "FreeShowRemote.operator.connection")!
        expect(!String(decoding: settings, as: UTF8.self).contains("fixture-secret"), "No password in preferences")
        let item = store.selectedProject!.items[0]
        store.selectItem(item)
        try await wait("presentation") { store.presentation?.id == "welcome" && !store.isLoading }
        expect(fixture.count("API:index_select_slide") == 0, "Browsing sends no live command")
        expect(store.presentation?.slides.count == 3, "Slide navigator receives all slides")
        let intent = PresentIntent(slide: store.previewSlide!.id, presentation: store.presentation!)
        store.present(intent); store.present(intent)
        try await wait("present") { !store.isSending && store.currentReference?.index == 0 }
        expect(fixture.count("API:index_select_slide") == 1, "Repeated Present sends once")
        for _ in 0..<100 { store.send(.next) }
        try await wait("next") { !store.isSending && store.currentReference?.index == 1 }
        expect(fixture.count("API:next_slide") == 1, "Rapid taps do not duplicate a command")
        fixture.hold.insert("API:get_slide_thumbnail")
        store.loadSelectedThumbnail()
        try await wait("thumbnail pending") { store.session.hasPending("API:get_slide_thumbnail") }
        store.send(.previous)
        try await wait("controls during capture") { !store.isSending && store.currentReference?.index == 0 }
        expect(store.canControl && store.thumbnailLoading, "Thumbnail rendering cannot block live controls")
        fixture.release("API:get_slide_thumbnail")
        try await wait("capture release") { !store.thumbnailLoading }
        let beforeChanged = fixture.count("API:index_select_slide")
        fixture.alterShow = true; store.present(intent)
        try await wait("changed layout rejected") { !store.isSending && store.errorMessage != nil }
        expect(fixture.count("API:index_select_slide") == beforeChanged, "Changed desktop content is revalidated before Present")
        fixture.alterShow = false
        try await wait("refresh after change") { !store.isLoading }
        let beforeReconnect = fixture.count("API:get_projects")
        fixture.disconnectAfterMutation = true; store.send(.next)
        try await wait("reconnect") { store.phase == .connected && fixture.count("API:get_projects") > beforeReconnect }
        expect(fixture.count("API:next_slide") == 2, "Interrupted command was not replayed")
        expect(store.commandOutcomeUnknown && !store.canControl, "Uncertain command requires output check")
        expect(store.currentReference?.index == 1, "Reconnect refreshes actual output")
        store.acknowledgeUncertainCommand()
        expect(store.canControl, "Output acknowledgement restores controls")
        store.scripture.query = "Sample 1:1"; store.scripture.search()
        try await wait("scripture preview") { !store.scripture.isBusy && store.scripture.preview != nil }
        store.scripture.present()
        try await wait("scripture present") { !store.scripture.isBusy && store.scripture.canNavigate }
        let projectsBeforeScriptureLoss = fixture.count("API:get_projects")
        fixture.disconnectOnChannel = "API:scripture_next"
        store.scripture.navigate(next: true)
        try await wait("scripture reconnect") { store.phase == .connected && fixture.count("API:get_projects") > projectsBeforeScriptureLoss }
        expect(store.commandOutcomeUnknown && !store.canControl && !store.scripture.canNavigate, "Interrupted scripture command is also uncertain")
        expect(fixture.count("API:scripture_next") == 1, "Scripture command is not replayed")
        store.acknowledgeUncertainCommand()
        store.present(intent)
        try await wait("return to native show") { !store.isSending && store.currentReference?.presentationID == "welcome" }
        let oldCallback = fixture.receive
        fixture.drop()
        try await wait("second reconnect") { store.phase == .connected && fixture.connectCount > failedCount + 2 }
        oldCallback?(.closed)
        expect(store.phase == .connected, "Previous socket callback cannot close replacement")
        let media = store.selectedProject!.items.first(where: { $0.kind == "pdf" })!
        store.selectItem(media)
        expect(fixture.count("API:name_start_project_item") == 0 && store.canStartSelectedItem, "Media selection is read-only")
        let mediaIntent = ProjectItemIntent(projectID: store.selectedProjectID, item: media)
        store.startProjectItem(mediaIntent); store.startProjectItem(mediaIntent)
        try await wait("start PDF") { !store.isSending && store.outputItemID == "demo-document" }
        expect(fixture.count("API:name_start_project_item") == 1, "Confirmed media start sends once")
        expect(store.canControl && store.snapshot.output == .other(description: "PDF · Announcements document · page 1 of 2"), "PDF output is known and navigable")
        store.send(.next)
        try await wait("PDF next page") { !store.isSending && store.snapshot.output == .other(description: "PDF · Announcements document · page 2 of 2") }
        expect(store.canControl, "Native Next controls PDF pages")
        fixture.duplicateMediaName = true
        store.startProjectItem(mediaIntent)
        try await wait("ambiguous media blocked") { !store.isSending && store.errorMessage != nil }
        expect(fixture.count("API:name_start_project_item") == 1, "Duplicate media names never dispatch a start")
        fixture.duplicateMediaName = false
        store.present(intent)
        try await wait("native after media") { !store.isSending && store.currentReference?.presentationID == "welcome" }

        store.selectProject("rehearsal")
        expect(store.selectedProject?.items.isEmpty == true, "Empty project handled")
        expect(store.snapshot.activeProjectID == "service", "Local project browsing does not change desktop")
        store.activateSelectedProject()
        try await wait("desktop project") { !store.isSending && store.snapshot.activeProjectID == "rehearsal" }
        expect(fixture.count("API:id_select_project") == 1, "Desktop project selection is explicit")
        store.startProjectItem(mediaIntent)
        try await wait("inactive project blocked") { !store.isSending && store.errorMessage != nil }
        expect(fixture.count("API:name_start_project_item") == 1, "Media cannot start from a different active project")
        store.suspend()
        expect(!store.canControl && !store.scripture.isConnected && store.snapshot.output == .unknown, "Background invalidates state")
        store.resume()
        try await wait("foreground refresh") { store.phase == .connected && store.scripture.isConnected }
        expect(store.snapshot.activeProjectID == "rehearsal", "Foreground performs full sync")
        let stressStart = Date()
        let beforeStress = fixture.count("API:next_slide") + fixture.count("API:previous_slide")
        for index in 0..<200 {
            store.send(index.isMultiple(of: 2) ? .next : .previous)
            try await wait("navigation stress") { !store.isSending }
        }
        expect(fixture.count("API:next_slide") + fixture.count("API:previous_slide") == beforeStress + 200, "200 sequential navigation operations issue exactly 200 commands")
        expect(store.canControl && Date().timeIntervalSince(stressStart) < 15, "Bounded navigation stress remains responsive")
        store.autoReconnect = false; fixture.drop()
        let stoppedCount = fixture.connectCount
        try await Task.sleep(for: .milliseconds(40))
        expect(fixture.connectCount == stoppedCount && !store.canControl, "Auto reconnect preference respected")
        store.forgetPassword()
        expect(try vault.password(for: endpoint) == nil && !store.rememberPassword, "Forget removes credential")
        store.disconnect()
        let restored = OperatorStore(transport: SwitchableRemoteTransport(live: ControlledRemote()), defaults: defaults, vault: vault)
        expect(restored.host == "fixture.local" && restored.port == "5510", "Last computer remembered")
        expect(restored.password.isEmpty && restored.phase == .disconnected, "Restoring settings does not silently connect or expose password")
        restored.startDemo()
        try await wait("demo") { restored.phase == .connected && restored.isDemo }
        expect(restored.snapshot.projects.count == 2, "Offline demo supplies real UI model")
        restored.scripture.query = "Sample 1:1-3"; restored.scripture.search()
        try await wait("demo scripture") { !restored.scripture.isBusy && restored.scripture.preview != nil }
        expect(restored.scripture.preview?.verses.count == 3, "Shared session scripture preview")
        restored.disconnect()

        // Watchdog disables commands before a slow/failed heartbeat can leave stale truth onscreen.
        let staleFixture = ControlledRemote()
        let stale = OperatorStore(transport: SwitchableRemoteTransport(live: staleFixture), defaults: defaults, vault: vault,
            heartbeatInterval: .milliseconds(10), requestTimeout: .milliseconds(250), freshnessLimit: 0.04,
            watchdogInterval: .milliseconds(5), retryDelay: { _ in .seconds(60) })
        stale.host = "fixture.local"; stale.connect()
        try await wait("freshness ready") { stale.phase == .connected }
        staleFixture.hold.insert("API:get_output")
        try await wait("watchdog") { stale.phase == .synchronizing }
        expect(!stale.canControl && stale.isStale, "Stale data disables commands before timeout")
        stale.disconnect()

        // A late read must not overwrite a newer desktop-originated output push.
        let pushFixture = ControlledRemote()
        let pushSession = RemoteSession(transport: pushFixture)
        let pushClient = RemotePresentationService(session: pushSession)
        try await pushClient.connect(to: endpoint, password: nil)
        pushFixture.hold.insert("API:get_output")
        let reading = Task { try await pushClient.refreshOutput() }
        try await wait("held output") { pushSession.hasPending("API:get_output") }
        _ = try await pushSession.request(channel: "API:index_select_slide", data: .object([
            "showId": .string("welcome"), "layoutId": .string("main"), "index": .number(2)
        ]))
        pushFixture.release("API:get_output")
        try await reading.value
        expect(pushClient.latest.output == .live(SlideReference(presentationID: "welcome", layoutID: "main", index: 2)), "Newer desktop push wins over old read")
        pushFixture.noOutput = true
        try await pushClient.refreshOutput()
        expect(pushClient.latest.output == .other(description: "No active output data"), "Vacuous all-cleared flags do not hide absent output data")
        let stream = pushClient.updates()
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        pushFixture.drop()
        do { _ = try await iterator.next(); fatalError("Update stream stayed open") }
        catch { expect(error as? ScriptureError == .disconnected, "Update streams terminate on loss") }
        expect(pushClient.latest.output == .unknown, "Disconnect invalidates previously live output")

        let badFixture = ControlledRemote()
        let bad = OperatorStore(transport: SwitchableRemoteTransport(live: badFixture), defaults: defaults, vault: vault, heartbeatInterval: .seconds(60), retryDelay: { _ in .milliseconds(5) })
        bad.host = "fixture.local"; bad.autoReconnect = true; bad.connect()
        try await wait("bad data fixture ready") { bad.phase == .connected }
        badFixture.corruptScripture = true
        bad.scripture.query = "Sample 1:1"; bad.scripture.search()
        try await wait("unsupported scripture stops") { if case .failed = bad.phase { return true }; return false }
        expect(bad.errorMessage != nil && bad.scripture.errorMessage != nil, "Shared-session schema errors remain visible")
        let badCount = badFixture.connectCount
        try await Task.sleep(for: .milliseconds(30))
        expect(badFixture.connectCount == badCount, "Unsupported data does not create a reconnect loop")
        bad.disconnect()

        let interactionFixture = ControlledRemote()
        let interactive = OperatorStore(transport: SwitchableRemoteTransport(live: interactionFixture), defaults: defaults, vault: vault, heartbeatInterval: .seconds(60))
        interactive.host = "fixture.local"; interactive.connect()
        try await wait("automatic live preview") { interactive.phase == .connected && interactive.presentation != nil && !interactive.isLoading }
        expect(interactive.followsLive && interactive.presentation?.id == "welcome", "Connecting loads the current live slide grid automatically")
        interactionFixture.missingShow = true
        interactive.retryPreview()
        try await wait("missing show diagnostic") { !interactive.isLoading && interactive.previewError != nil }
        expect(interactive.previewError!.contains("no show data"), "Preview failure identifies the missing desktop data")
        interactionFixture.missingShow = false; interactionFixture.omitShowTitle = true
        interactive.retryPreview()
        try await wait("preview recovered") { !interactive.isLoading && interactive.previewError == nil }
        expect(interactive.presentation?.name == "Welcome", "Library title repairs show bodies that omit a name")
        let ref = interactive.previewSlide!.id
        interactive.thumbnailVisible(ref)
        try await wait("empty image response") { !interactive.thumbnailLoading && interactionFixture.count("API:get_slide_thumbnail") > 0 }
        let oldCaptures = interactionFixture.count("API:get_slide_thumbnail")
        interactive.refresh()
        try await wait("refresh retries images") { interactionFixture.count("API:get_slide_thumbnail") > oldCaptures && !interactive.thumbnailLoading && !interactive.isLoading }
        expect(interactive.thumbnailMessage != nil, "Unavailable rendered images explain the text fallback")
        let secondSlide = interactive.presentation!.slides[1]
        let beforeTap = interactionFixture.count("API:index_select_slide")
        interactive.tapSlide(secondSlide)
        expect(interactive.selectedSlide == secondSlide.id && interactionFixture.count("API:index_select_slide") == beforeTap, "Protected single tap only previews")
        interactive.holdSlide(secondSlide)
        try await wait("hold presents") { !interactive.isSending && interactive.currentReference == secondSlide.id }
        expect(interactionFixture.count("API:index_select_slide") == beforeTap + 1, "Protected long press presents once")
        interactive.singleTapLive = true
        let thirdSlide = interactive.presentation!.slides[2]
        interactive.tapSlide(thirdSlide)
        interactive.holdSlide(thirdSlide)
        try await wait("single tap presents") { !interactive.isSending && interactive.currentReference == thirdSlide.id }
        expect(interactionFixture.count("API:index_select_slide") == beforeTap + 2, "Direct mode presents on tap without duplicating long-press commands")
        interactive.toggleOutput()
        try await wait("dock clears") { !interactive.isSending && interactive.outputIsClear }
        expect(interactionFixture.count("API:clear_all") == 1, "Dock clears live output")
        interactive.toggleOutput()
        try await wait("dock goes live") { !interactive.isSending && interactive.currentReference == thirdSlide.id }
        expect(!interactive.outputIsClear, "Dock goes live with selected slide after clearing")
        interactive.disconnect()
        let beforeOfflineTap = interactionFixture.count("API:index_select_slide")
        interactive.tapSlide(thirdSlide)
        expect(interactionFixture.count("API:index_select_slide") == beforeOfflineTap, "Slide gestures cannot send when disconnected")

        print("Passed \(checks) operator checks.")
    }
}
