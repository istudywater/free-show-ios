import Foundation

private func json(_ text: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
private let metadata = json(#"{"local":{"name":"Local fixture"},"api":{"name":"API fixture","api":true,"attributionString":"Provider attribution"},"collection":{"collection":{"versions":["local"]}}}"#)
private let localBible = json(#"{"metadata":{"copyright":"Fixture attribution"},"books":[{"number":43,"name":"John","abbreviation":"Jn","chapters":[{"number":3,"verses":[{"number":16,"text":"A <i>sample</i> of love &amp; grace."},{"number":17,"text":"A second sample."},{"number":18,"text":"A third sample."}]}]},{"number":29,"name":"Joel","chapters":[{"number":1,"verses":[{"number":1,"text":"Another fixture."}]}]}]}"#)

@MainActor
final class FixtureRemote: RemoteTransport {
    var receive: ((RemoteEvent) -> Void)?
    var emitted: [RemoteMessage] = []
    var requiresPassword = false
    var silent = false
    var accessBeforeMetadata = true
    var lastURL: URL?
    var responseOverride: ((RemoteMessage) -> JSONValue?)?
    func connect(to url: URL) { lastURL = url; receive?(.connected) }
    func disconnect() {}
    func reply(_ channel: String, _ data: JSONValue) { receive?(.message(RemoteMessage(channel: channel, data: data))) }
    func initialize() {
        if accessBeforeMetadata { reply("ACCESS", .null); reply("SCRIPTURE", metadata) }
        else { reply("SCRIPTURE", metadata); reply("ACCESS", .null) }
    }
    func emit(_ message: RemoteMessage) throws {
        emitted.append(message)
        guard !silent else { return }
        if let override = responseOverride?(message) { reply(message.channel, override); return }
        switch message.channel {
        case "PASSWORD":
            if requiresPassword { reply("PASSWORD", .object(["password": .bool(true)])) } else { initialize() }
        case "ACCESS":
            if message.data == .string("remote secret") { initialize() }
            else { reply("ERROR", .object(["key": .string("wrongPass")])) }
        case "GET_SCRIPTURE":
            var data = message.data.object!
            if message.data["id"].string == "local" { data["bible"] = localBible }
            else if message.data["chapterKey"] != .null {
                data["bibleUpdate"] = .object(["kind": .string("verses"), "id": .string("api"),
                    "bookIndex": message.data["bookIndex"], "chapterIndex": message.data["chapterIndex"],
                    "verses": localBible["books"].array![0]["chapters"].array![0]["verses"]])
            } else if message.data["bookKey"] != .null {
                data["bibleUpdate"] = json(#"{"kind":"chapters","id":"api","bookIndex":0,"chapters":[{"number":"3","keyName":"3"}]}"#)
            } else { data["bible"] = json(#"{"books":[{"number":43,"name":"John","keyName":"JHN","chapters":[]}]}"#) }
            reply(message.channel, .object(data))
        case "SEARCH_SCRIPTURE":
            var data = message.data.object!
            data["searchResults"] = json(#"{"type":"text","results":[{"reference":"43.3.16","referenceFull":"John 3:16","verseText":"A sample of love &amp; grace."}]}"#)
            reply(message.channel, .object(data))
        default: if message.channel.hasPrefix("API:") { reply(message.channel, .null) }
        }
    }
}

@main
struct ScriptureTests {
    @MainActor
    static func main() async throws {
        var count = 0
        func expect(_ condition: Bool, _ label: String) { precondition(condition, label); count += 1 }
        func expectError(_ expected: ScriptureError, _ work: () async throws -> Void) async {
            do { try await work(); preconditionFailure("Expected \(expected)") }
            catch { expect(error as? ScriptureError == expected, "Expected \(expected), got \(error)") }
        }
        let transport = FixtureRemote()
        let session = RemoteSession(transport: transport)
        let service = RemoteScriptureService(session: session)
        let endpoint = FreeShowEndpoint(host: "fixture.local", port: 5510)
        try await service.connect(to: endpoint, password: nil)
        expect(service.isConnected, "Passwordless initialization")
        expect(transport.lastURL?.absoluteString == "http://fixture.local:5510", "Separate Remote endpoint")
        let translations = try await service.availableTranslations()
        expect(translations.count == 2 && !translations.contains(where: { $0.id == "collection" }), "Collections excluded")
        expect(translations.first(where: { $0.id == "api" })?.source == .api, "API metadata")
        let passage = try await service.searchReference("Jn 3:16–18", translationID: "local")
        expect(passage.verses.count == 3 && passage.commandReference == "43.3.16,17,18", "Full range and canonical numbers")
        expect(passage.reference == "John 3:16–18", "Readable reference")
        expect(passage.verses[0].text == "A sample of love & grace.", "Plain text sanitization")
        expect(passage.attribution == "Fixture attribution", "Local attribution")
        expect(!transport.emitted.contains(where: { $0.channel.hasPrefix("API:") }), "Reference search never presents")
        await expectError(.notFound) { _ = try await service.previewPassage(reference: "John 3:16-19", translationID: "local") }
        await expectError(.notPreviewed) { try await service.presentPassage(passage) }
        let hits = try await service.searchText("SAMPLE", translationID: "local")
        expect(hits.count == 3 && hits[0].commandReference == "43.3.16", "Local case-insensitive search")
        expect(!transport.emitted.contains(where: { $0.channel.hasPrefix("API:") }), "Text search never presents")
        await expectError(.shortSearch) { _ = try await service.searchText("ab", translationID: "local") }
        let single = try await service.previewPassage(reference: hits[0].commandReference, translationID: "local")
        expect(single.verses.count == 1, "Match selection previews")
        try await service.presentPassage(single)
        expect(transport.emitted.last == RemoteMessage(channel: "API:start_scripture", data: .object([
            "id": .string("local"), "reference": .string("43.3.16")
        ])), "Explicit Present sends correct translation/reference")
        try await service.nextScriptureSlide(); try await service.previousScriptureSlide()
        expect(transport.emitted.suffix(2).map(\.channel) == ["API:scripture_next", "API:scripture_previous"], "Native navigation")
        service.disconnect()
        await expectError(.notPreviewed) { try await service.presentPassage(single) }
        await expectError(.notPreviewed) { try await service.nextScriptureSlide() }
        transport.requiresPassword = true
        await expectError(.password) { try await service.connect(to: endpoint, password: nil) }
        await expectError(.password) { try await service.connect(to: endpoint, password: "wrong") }
        transport.accessBeforeMetadata = false
        try await service.connect(to: endpoint, password: "remote secret")
        expect(service.isConnected, "Password and metadata-before-ACCESS order")
        expect(transport.emitted.filter({ $0.channel == "ACCESS" }).last?.data == .string("remote secret"), "String ACCESS payload")
        transport.emitted.removeAll()
        let api = try await service.previewPassage(reference: "John 3:16-18", translationID: "api")
        expect(api.verses.count == 3 && api.attribution == "Provider attribution", "API preview and attribution")
        let reads = transport.emitted.filter { $0.channel == "GET_SCRIPTURE" }
        expect(reads.count == 3, "API books, chapters, verses")
        expect(reads[1].data["bookIndex"] == .number(0) && reads[1].data["bookKey"] == .string("JHN"), "Book key/index distinct from canonical number")
        expect(reads[2].data["chapterIndex"] == .number(0) && reads[2].data["chapterKey"] == .string("3"), "Chapter key/index distinct from number")
        expect(!transport.emitted.contains(where: { $0.channel.hasPrefix("API:") }), "API preview never presents")
        let apiHits = try await service.searchText("sample", translationID: "api")
        expect(apiHits.first?.commandReference == "43.3.16", "API text results")
        expect(transport.emitted.last?.data["searchType"] == .string("text"), "API search envelope")
        await expectError(.notPreviewed) { try await service.presentPassage(api) }
        let beforeCache = transport.emitted.count
        _ = try await service.previewPassage(reference: "John 3", translationID: "api")
        expect(transport.emitted.count == beforeCache, "API cache avoids repeated reads")
        let bible = try ScriptureBible(localBible)
        for invalid in ["John 3:18-16", "John 3:0", "John 3:16-4:2", "John 3:16oops", "John 3:1-9999999", "John 3:"] {
            do { _ = try ScriptureReference.parse(invalid, books: bible.books); preconditionFailure("Invalid reference accepted") }
            catch { expect(error as? ScriptureError == .invalidReference, "Strict parser: \(invalid)") }
        }
        do { _ = try ScriptureReference.parse("Jo 3:16", books: bible.books); preconditionFailure("Ambiguous book accepted") }
        catch { expect(error as? ScriptureError == .notFound, "Ambiguous abbreviation rejected") }
        let mixed = try ScriptureReference.parse("John 3:16, 17 - 18,16", books: bible.books)
        expect(mixed.verses == [16,17,18], "Deduplicate ranges with spaces")
        let whole = try await service.previewPassage(reference: "John 3", translationID: "local")
        expect(whole.verses.count == 3, "Whole chapter")

        let timeoutTransport = FixtureRemote()
        let timeoutSession = RemoteSession(transport: timeoutTransport, timeout: .milliseconds(100))
        try await timeoutSession.connect(to: endpoint, password: nil)
        let oldReceive = timeoutTransport.receive
        timeoutTransport.silent = true
        await expectError(.timeout) { _ = try await timeoutSession.request(channel: "API:scripture_next") }
        expect(!timeoutSession.isReady && timeoutTransport.emitted.filter({ $0.channel == "API:scripture_next" }).count == 1, "Timeout closes without replay")
        timeoutTransport.silent = false
        try await timeoutSession.connect(to: endpoint, password: nil)
        oldReceive?(.closed)
        expect(timeoutSession.isReady, "Previous-session callbacks ignored")
        timeoutTransport.silent = true
        let start = timeoutTransport.emitted.count
        let pending = Task { try await timeoutSession.request(channel: "GET_SCRIPTURE") { $0["id"].string == "local" } }
        while timeoutTransport.emitted.count == start { await Task.yield() }
        timeoutTransport.reply("GET_SCRIPTURE", .object(["id": .string("wrong")]))
        timeoutTransport.reply("GET_SCRIPTURE", .object(["id": .string("local")]))
        let result = try await pending.value
        expect(result["id"].string == "local", "Wrong-translation replies ignored")
        let beforeCancel = timeoutTransport.emitted.count
        let cancelled = Task { try await timeoutSession.request(channel: "GET_SCRIPTURE") }
        while timeoutTransport.emitted.count == beforeCancel { await Task.yield() }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancellation accepted") }
        catch { expect(error is CancellationError && !timeoutSession.isReady, "Cancellation discards session") }
        transport.reply("SCRIPTURE", .object([:]))
        expect(!service.isConnected, "Library change invalidates cache")
        await expectError(.notPreviewed) { try await service.presentPassage(whole) }
        transport.requiresPassword = false
        transport.silent = true
        let beforeReconnect = transport.emitted.count
        let oldConnect = Task { try await service.connect(to: endpoint, password: nil) }
        while transport.emitted.count == beforeReconnect { await Task.yield() }
        service.disconnect()
        transport.silent = false
        try await service.connect(to: endpoint, password: nil)
        do { try await oldConnect.value; preconditionFailure("Old connect accepted") }
        catch { expect(error is CancellationError, "Old connect is cancelled") }
        expect(service.isConnected, "Old connection cleanup cannot disconnect the replacement")
        service.disconnect()
        let state = ScriptureState(service: service)
        state.connect(host: "fixture.local", port: "5510", password: "")
        while state.isBusy { await Task.yield() }
        expect(state.isConnected && state.translations.count == 2 && !state.selectedTranslationID.isEmpty, "UI initialization does not cancel itself")
        state.selectedTranslationID = "local"; state.query = "John 3:16-18"
        state.search(); state.search()
        while state.isBusy { await Task.yield() }
        expect(state.preview?.verses.count == 3 && !state.canNavigate, "UI preview without live navigation")
        state.query = "John 3:16"
        expect(state.preview == nil, "Query edit invalidates preview")
        state.search()
        while state.isBusy { await Task.yield() }
        state.present(); state.present()
        while state.isBusy { await Task.yield() }
        expect(state.canNavigate && state.message?.contains("not confirmed") == true, "UI does not claim output confirmation")
        expect(transport.emitted.filter({ $0.channel == "API:start_scripture" }).count == 1, "Repeated Present sends once")
        state.disconnect()
        expect(!state.isConnected && state.preview == nil && !state.canNavigate, "Disconnect clears UI")
        print("Passed \(count) scripture checks.")
    }
}
