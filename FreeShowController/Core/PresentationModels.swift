import Foundation

/// App-level models, not FreeShow wire payloads. Adapters will normalize each transport.
struct ServiceProject: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let items: [ProjectItem]
}

struct ProjectItem: Identifiable, Equatable, Sendable {
    /// Identifies this occurrence in a project; the same show may occur more than once.
    let id: String
    let presentationID: String?
    let name: String
    let kind: String
    var explicitName: String? = nil
    var canStartByName: Bool { ["image", "video", "pdf", "audio", "overlay", "player"].contains(kind) && !(explicitName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    var layoutID: String? = nil
    var index: Int = 0
    var canPreview: Bool { kind == "show" && presentationID != nil }
}

struct Presentation: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let layoutID: String
    let slides: [Slide]
}

struct Slide: Identifiable, Equatable, Sendable {
    /// Layout position is part of identity because a layout can repeat a slide.
    let id: SlideReference
    let text: String
    let thumbnail: Data?
    var sourceID: String = ""
    var group: String = ""
    var isDisabled: Bool = false
}

struct SlideReference: Hashable, Sendable {
    let presentationID: String
    let layoutID: String
    /// Always zero-based within the flattened layout. Convert only at the transport boundary.
    let index: Int
}

enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case authenticationRequired
    case synchronizing
    case connected
    case reconnecting
    case failed(String)
}

struct FreeShowEndpoint: Equatable, Sendable {
    let host: String
    let port: UInt16
}

/// Unknown and stale output must never be displayed as a confirmed cleared output.
enum OutputState: Equatable, Sendable {
    case unknown
    case cleared
    case live(SlideReference)
    case other(description: String)
}

struct PresentationSnapshot: Equatable, Sendable {
    let projects: [ServiceProject]
    let activeProjectID: String?
    let output: OutputState
    let receivedAt: Date
    var desktopSelectionID: String? = nil
}
