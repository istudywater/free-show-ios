import Foundation

/// A transport connection is not operational until authentication and initial sync finish.
/// Credentials are supplied in memory; future persistence belongs in Keychain.
@MainActor
protocol ConnectionService {
    var state: ConnectionState { get }
    func connect(to endpoint: FreeShowEndpoint, password: String?) async throws
    func disconnect() async
}

@MainActor
protocol PresentationService {
    func snapshot() async throws -> PresentationSnapshot
    func presentation(id: String) async throws -> Presentation
    /// Server updates are authoritative. A future adapter must terminate on disconnect/error.
    func updates() -> AsyncThrowingStream<PresentationSnapshot, Error>
}

/// These operations change live output; browsing/preview selection is local application state.
/// Completion means the request was sent, not that the desktop confirmed its effect.
@MainActor
protocol OutputService {
    func present(_ slide: SlideReference) async throws
    func nextSlide() async throws
    func previousSlide() async throws
    /// FreeShow clear_all includes audio, backgrounds, overlays, and timers.
    func clearAll() async throws
    func restoreOutput() async throws
}

/// Reserved application-level operations, not promises of uniform server support.
/// No implementation or scripture UI ships in the foundation milestone.
@MainActor
protocol ScriptureService {
    func availableTranslations() async throws -> [ScriptureTranslation]
    func searchReference(_ query: String, translationID: String) async throws -> ScripturePassage
    func searchText(_ query: String, translationID: String) async throws -> [ScriptureSearchResult]
    func previewPassage(reference: String, translationID: String) async throws -> ScripturePassage
    func presentPassage(_ passage: ScripturePassage) async throws
    func nextScriptureSlide() async throws
    func previousScriptureSlide() async throws
}
