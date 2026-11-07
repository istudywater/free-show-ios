import Combine

/// UI state lives on the main actor. Future service adapters are injected into this owner.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var connection: ConnectionState = .disconnected
    @Published private(set) var output: OutputState = .unknown

    /// Preview selection is deliberately independent from authoritative desktop output.
    @Published var selectedSlide: SlideReference?
}
