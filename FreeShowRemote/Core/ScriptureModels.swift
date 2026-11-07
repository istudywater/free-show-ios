import Foundation

struct ScriptureTranslation: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let source: Source
    var attribution: String = ""

    enum Source: Equatable, Sendable { case local, api, unknown }
}

struct ScripturePassage: Equatable, Sendable {
    let translationID: String
    let reference: String
    let verses: [ScriptureVerse]
    let commandReference: String
    let attribution: String
}

struct ScriptureVerse: Equatable, Sendable {
    let reference: String
    let text: String
}

struct ScriptureSearchResult: Identifiable, Equatable, Sendable {
    var id: String { translationID + ":" + commandReference }
    let translationID: String
    let reference: String
    let excerpt: String
    let commandReference: String
}

/// Normalized read-only data; no array index is assumed to be a canonical book/chapter number.
struct ScriptureBible: Sendable {
    struct Book: Sendable {
        let number: Int
        let name: String
        let abbreviation: String
        let key: String?
        var chapters: [Chapter]
    }
    struct Chapter: Sendable {
        let number: Int
        let key: String?
        let verses: [Verse]
    }
    struct Verse: Sendable {
        let number: Int
        let text: String
    }
    var books: [Book]
    let copyright: String

    init(_ value: JSONValue) throws {
        guard let rawBooks = value["books"].array else { throw ScriptureError.invalidData }
        books = try rawBooks.map { book in
            guard let number = book["number"].int, let name = book["name"].string, !name.isEmpty else { throw ScriptureError.invalidData }
            return Book(number: number, name: book["customName"].string ?? name,
                        abbreviation: book["abbreviation"].string ?? "", key: book["keyName"].string,
                        chapters: try Self.chapters(book["chapters"].array ?? []))
        }
        guard Set(books.map(\.number)).count == books.count else { throw ScriptureError.invalidData }
        copyright = value["metadata"]["copyright"].string ?? value["copyright"].string ?? ""
    }

    static func chapters(_ values: [JSONValue]) throws -> [Chapter] {
        let chapters = try values.map { chapter in
            guard let number = chapter["number"].int else { throw ScriptureError.invalidData }
            return Chapter(number: number, key: chapter["keyName"].string,
                           verses: try verses(chapter["verses"].array ?? []))
        }
        guard Set(chapters.map(\.number)).count == chapters.count else { throw ScriptureError.invalidData }
        return chapters
    }

    static func verses(_ values: [JSONValue]) throws -> [Verse] {
        let verses = try values.map { verse in
            guard let number = verse["number"].int, let text = verse["text"].string ?? verse["value"].string else { throw ScriptureError.invalidData }
            return Verse(number: number, text: plainScriptureText(text))
        }
        guard Set(verses.map(\.number)).count == verses.count else { throw ScriptureError.invalidData }
        return verses
    }

    func search(_ query: String, translationID: String) -> [ScriptureSearchResult] {
        let query = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var results: [ScriptureSearchResult] = []
        for book in books {
            for chapter in book.chapters {
                for verse in chapter.verses where verse.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(query) {
                    results.append(ScriptureSearchResult(translationID: translationID,
                        reference: "\(book.name) \(chapter.number):\(verse.number)", excerpt: verse.text,
                        commandReference: "\(book.number).\(chapter.number).\(verse.number)"))
                    if results.count == 50 { return results }
                }
            }
        }
        return results
    }
}

struct ScriptureReference: Equatable, Sendable {
    let book: Int
    let chapter: Int
    /// nil means the entire chapter; otherwise an explicit, validated verse selection.
    let verses: [Int]?

    static func parse(_ query: String, books: [ScriptureBible.Book]) throws -> ScriptureReference {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        let numeric = query.split(separator: ".", omittingEmptySubsequences: false)
        if numeric.count == 3, let book = Int(numeric[0]), let chapter = Int(numeric[1]), book > 0, chapter > 0 {
            return ScriptureReference(book: book, chapter: chapter, verses: try selection(String(numeric[2])))
        }
        let pattern = #"^(.+?)\s+(\d+)(?::\s*([\d,\s-]+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let bookRange = Range(match.range(at: 1), in: query),
              let chapterRange = Range(match.range(at: 2), in: query),
              let chapter = Int(query[chapterRange]), chapter > 0 else { throw ScriptureError.invalidReference }
        let name = normalize(String(query[bookRange]))
        guard !name.isEmpty else { throw ScriptureError.invalidReference }
        let exact = books.filter { normalize($0.name) == name || (!$0.abbreviation.isEmpty && normalize($0.abbreviation) == name) }
        let candidates = exact.isEmpty ? books.filter { normalize($0.name).hasPrefix(name) } : exact
        guard candidates.count == 1, let book = candidates.first else { throw ScriptureError.notFound }
        let verses = Range(match.range(at: 3), in: query).map { String(query[$0]) }
        return ScriptureReference(book: book.number, chapter: chapter, verses: try verses.map(selection))
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { !$0.isWhitespace && $0 != "." }
    }

    private static func selection(_ text: String) throws -> [Int] {
        var result: Set<Int> = []
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = part.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(bounds.count), let first = Int(bounds[0].trimmingCharacters(in: .whitespaces)), first > 0, first <= 1000 else { throw ScriptureError.invalidReference }
            let last: Int
            if bounds.count == 2 {
                guard let n = Int(bounds[1].trimmingCharacters(in: .whitespaces)), n >= first, n <= 1000 else { throw ScriptureError.invalidReference }
                last = n
            } else { last = first }
            result.formUnion(first...last)
            guard result.count <= 200 else { throw ScriptureError.invalidReference }
        }
        guard !result.isEmpty else { throw ScriptureError.invalidReference }
        return result.sorted()
    }
}

func plainScriptureText(_ input: String) -> String {
    var text = input.replacingOccurrences(of: #"(?i)<q(?:\s[^>]*)?>"#, with: "“", options: .regularExpression)
        .replacingOccurrences(of: #"(?i)</q>"#, with: "”", options: .regularExpression)
        .replacingOccurrences(of: #"(?i)<br\s*/?>|</(?:p|div|h[1-6])>"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    if let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) {
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text), let digitsRange = Range(match.range(at: 1), in: text) else { continue }
            let digits = String(text[digitsRange])
            let value = digits.hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            if let value, let scalar = UnicodeScalar(value) { text.replaceSubrange(range, with: String(scalar)) }
        }
    }
    for (entity, value) in [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
        text = text.replacingOccurrences(of: entity, with: value)
    }
    return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
}
