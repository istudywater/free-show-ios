import Foundation

struct ScriptureTranslation: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let source: Source

    enum Source: Equatable, Sendable {
        case local
        case api
        case unknown
    }
}

struct ScripturePassage: Equatable, Sendable {
    let translationID: String
    let reference: String
    let verses: [ScriptureVerse]
}

struct ScriptureVerse: Equatable, Sendable {
    let reference: String
    let text: String
}

struct ScriptureSearchResult: Equatable, Sendable {
    let translationID: String
    let reference: String
    let excerpt: String
}
