import Foundation

@MainActor
final class RemoteScriptureService: ScriptureService {
    var onDisconnect: ((Error?) -> Void)?
    var isConnected: Bool { session.isReady }
    private let session: RemoteSession
    private var cache: [String: ScriptureBible] = [:]
    private var prepared: ScripturePassage?
    private var hasPresented = false
    private var busy = false

    init(session: RemoteSession) {
        self.session = session
        session.onDisconnect = { [weak self] error in
            guard let self else { return }
            self.cache.removeAll()
            self.prepared = nil
            self.hasPresented = false
            self.busy = false
            self.onDisconnect?(error)
        }
    }

    func connect(to endpoint: FreeShowEndpoint, password: String?) async throws {
        try await session.connect(to: endpoint, password: password)
        let token = session.generation
        do {
            try Task.checkCancellation()
            _ = try await availableTranslations()
            try check(token)
        } catch {
            if session.generation == token { session.disconnect(error: error) }
            throw error
        }
    }

    func disconnect() { session.disconnect() }

    func availableTranslations() async throws -> [ScriptureTranslation] {
        guard session.isReady, let metadata = session.translations.object else { throw ScriptureError.disconnected }
        return try metadata.compactMap { id, value in
            guard value["collection"] == .null else { return nil }
            guard value.object != nil else { throw ScriptureError.invalidData }
            return ScriptureTranslation(id: id, name: value["customName"].string ?? value["name"].string ?? id,
                source: value["api"].bool == true ? .api : .local,
                attribution: plainScriptureText(value["attributionString"].string ?? ""))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func searchReference(_ query: String, translationID: String) async throws -> ScripturePassage {
        try await previewPassage(reference: query, translationID: translationID)
    }

    func previewPassage(reference: String, translationID: String) async throws -> ScripturePassage {
        return try await perform { token in
            self.prepared = nil
            let translation = try await self.translation(translationID)
            var bible = try await self.loadBible(translationID)
            let reference = try ScriptureReference.parse(reference, books: bible.books)
            guard let bookIndex = bible.books.firstIndex(where: { $0.number == reference.book }) else { throw ScriptureError.notFound }
            if translation.source == .api {
                bible = try await self.loadChapter(bible, id: translationID, bookIndex: bookIndex, number: reference.chapter)
            }
            let book = bible.books[bookIndex]
            guard let chapter = book.chapters.first(where: { $0.number == reference.chapter }), !chapter.verses.isEmpty else { throw ScriptureError.notFound }
            let wanted = reference.verses ?? chapter.verses.map(\.number).sorted()
            guard !wanted.isEmpty, wanted.count <= 200 else { throw ScriptureError.invalidReference }
            let selected = try wanted.map { number in
                guard let verse = chapter.verses.first(where: { $0.number == number }), !verse.text.isEmpty else { throw ScriptureError.notFound }
                return ScriptureVerse(reference: "\(book.name) \(chapter.number):\(number)", text: verse.text)
            }
            let verseLabel: String
            if let first = wanted.first, let last = wanted.last, wanted.count > 1, last - first + 1 == wanted.count {
                verseLabel = "\(first)–\(last)"
            } else { verseLabel = wanted.map(String.init).joined(separator: ",") }
            let passage = ScripturePassage(translationID: translationID,
                reference: "\(book.name) \(chapter.number):\(verseLabel)", verses: selected,
                commandReference: "\(book.number).\(chapter.number).\(wanted.map(String.init).joined(separator: ","))",
                attribution: [translation.attribution, plainScriptureText(bible.copyright)].filter { !$0.isEmpty }.joined(separator: "\n"))
            try self.check(token)
            self.prepared = passage
            return passage
        }
    }

    func searchText(_ query: String, translationID: String) async throws -> [ScriptureSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { throw ScriptureError.shortSearch }
        return try await perform { _ in
            self.prepared = nil
            let translation = try await self.translation(translationID)
            if translation.source == .local {
                let bible = try await self.loadBible(translationID)
                return await Task.detached(priority: .userInitiated) { bible.search(query, translationID: translationID) }.value
            }
            let response = try await self.session.request(channel: "SEARCH_SCRIPTURE", data: .object([
                "id": .string(translationID), "searchTerm": .string(query), "searchType": .string("text")
            ])) { data in
                data["id"].string == translationID && data["searchTerm"].string == query && data["searchType"].string == "text"
            }
            let result = response["searchResults"]
            guard result["type"].string == "text", result["error"].bool != true, let hits = result["results"].array else { throw ScriptureError.invalidData }
            var seen: Set<String> = []
            return try hits.prefix(50).compactMap { hit in
                guard let wire = hit["reference"].string else { throw ScriptureError.invalidData }
                guard let parsed = try? ScriptureReference.parse(wire, books: []),
                      let verses = parsed.verses, verses.count == 1 else { throw ScriptureError.invalidData }
                guard seen.insert(wire).inserted else { return nil }
                return ScriptureSearchResult(translationID: translationID,
                    reference: hit["referenceFull"].string.flatMap { $0.isEmpty ? nil : $0 } ?? wire,
                    excerpt: plainScriptureText(hit["verseText"].string ?? ""), commandReference: wire)
            }
        }
    }

    func presentPassage(_ passage: ScripturePassage) async throws {
        guard prepared == passage else { throw ScriptureError.notPreviewed }
        try await perform { token in
            try await self.command("start_scripture", data: .object([
                "id": .string(passage.translationID), "reference": .string(passage.commandReference)
            ]))
            try self.check(token)
            self.hasPresented = true
        }
    }

    func nextScriptureSlide() async throws { try await navigate("scripture_next") }
    func previousScriptureSlide() async throws { try await navigate("scripture_previous") }

    private func navigate(_ action: String) async throws {
        guard hasPresented else { throw ScriptureError.notPreviewed }
        try await perform { _ in try await self.command(action) }
    }

    private func command(_ action: String, data: JSONValue = .object([:])) async throws {
        let result = try await session.request(channel: "API:" + action, data: data)
        guard result == .null else { throw ScriptureError.invalidData }
    }

    private func translation(_ id: String) async throws -> ScriptureTranslation {
        guard let result = try await availableTranslations().first(where: { $0.id == id }) else { throw ScriptureError.notFound }
        return result
    }

    private func loadBible(_ id: String) async throws -> ScriptureBible {
        let token = session.generation
        if let bible = cache[id] { return bible }
        let response = try await session.request(channel: "GET_SCRIPTURE", data: .object(["id": .string(id)])) {
            $0["id"].string == id && $0["bookKey"] == .null && $0["chapterKey"] == .null
        }
        let payload = response["bible"]
        let bible = try await Task.detached(priority: .userInitiated) { try ScriptureBible(payload) }.value
        try Task.checkCancellation()
        try check(token)
        cache[id] = bible
        return bible
    }

    private func loadChapter(_ original: ScriptureBible, id: String, bookIndex: Int, number: Int) async throws -> ScriptureBible {
        let token = session.generation
        var bible = original
        guard let bookKey = bible.books[bookIndex].key else { throw ScriptureError.invalidData }
        if bible.books[bookIndex].chapters.isEmpty {
            let index = JSONValue.number(Double(bookIndex))
            let response = try await session.request(channel: "GET_SCRIPTURE", data: .object([
                "id": .string(id), "bookKey": .string(bookKey), "bookIndex": index
            ])) { $0["id"].string == id && $0["bookKey"].string == bookKey && $0["chapterKey"] == .null }
            try check(token)
            let update = response["bibleUpdate"]
            guard update["kind"].string == "chapters", update["id"].string == id,
                  update["bookIndex"] == index, let values = update["chapters"].array else { throw ScriptureError.invalidData }
            bible.books[bookIndex].chapters = try ScriptureBible.chapters(values)
        }
        guard let chapterIndex = bible.books[bookIndex].chapters.firstIndex(where: { $0.number == number }) else { throw ScriptureError.notFound }
        let chapter = bible.books[bookIndex].chapters[chapterIndex]
        if chapter.verses.isEmpty {
            guard let chapterKey = chapter.key else { throw ScriptureError.invalidData }
            let b = JSONValue.number(Double(bookIndex)), c = JSONValue.number(Double(chapterIndex))
            let response = try await session.request(channel: "GET_SCRIPTURE", data: .object([
                "id": .string(id), "bookKey": .string(bookKey), "chapterKey": .string(chapterKey),
                "bookIndex": b, "chapterIndex": c
            ])) { $0["id"].string == id && $0["bookKey"].string == bookKey && $0["chapterKey"].string == chapterKey }
            try check(token)
            let update = response["bibleUpdate"]
            guard update["kind"].string == "verses", update["id"].string == id,
                  update["bookIndex"] == b, update["chapterIndex"] == c,
                  let values = update["verses"].array else { throw ScriptureError.invalidData }
            bible.books[bookIndex].chapters[chapterIndex] = ScriptureBible.Chapter(number: chapter.number, key: chapterKey,
                verses: try ScriptureBible.verses(values))
        }
        try check(token)
        cache[id] = bible
        return bible
    }

    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard token == session.generation, session.isReady else { throw CancellationError() }
    }

    private func perform<T>(_ work: (UUID) async throws -> T) async throws -> T {
        guard session.isReady else { throw ScriptureError.disconnected }
        guard !busy else { throw ScriptureError.busy }
        busy = true
        let token = session.generation
        defer { if token == session.generation { busy = false } }
        do {
            let value = try await work(token)
            try Task.checkCancellation()
            guard session.generation == token, session.isReady else { throw CancellationError() }
            return value
        } catch {
            guard token == session.generation else { throw error }
            if error as? ScriptureError == .invalidData { session.disconnect(error: error) }
            throw error
        }
    }
}
