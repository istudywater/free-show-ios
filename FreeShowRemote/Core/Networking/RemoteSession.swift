import Foundation

/// Sendable JSON keeps untyped Socket.IO values inside the transport adapter.
enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSONValue { object?[key] ?? .null }
    var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
    var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    var string: String? {
        switch self {
        case .string(let s): s
        case .number(let n) where n.isFinite && n.rounded() == n && abs(n) < 1_000_000: String(Int(n))
        default: nil
        }
    }
    var int: Int? {
        guard let s = string, let n = Int(s), n > 0, n < 1_000_000 else { return nil }
        return n
    }
    var nonnegativeInt: Int? {
        guard let s = string, let n = Int(s), n >= 0, n < 1_000_000 else { return nil }
        return n
    }
    var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
}

struct RemoteMessage: Codable, Equatable, Sendable {
    let channel: String
    let data: JSONValue
}

enum RemoteEvent: Sendable {
    case connected, closed
    case failed(String)
    case message(RemoteMessage)
}

@MainActor
protocol RemoteTransport: AnyObject {
    var receive: ((RemoteEvent) -> Void)? { get set }
    func connect(to url: URL)
    func emit(_ message: RemoteMessage) throws
    func disconnect()
}

enum ScriptureError: LocalizedError, Equatable {
    case transport(String)
    case disconnected, password, capacity, timeout, invalidData, libraryChanged, busy, notFound, invalidReference, shortSearch, notPreviewed
    var errorDescription: String? {
        switch self {
        case .transport(let reason): "RemoteShow connection failed: \(reason)"
        case .disconnected: "RemoteShow disconnected. Check its host, port, and settings, then connect again."
        case .password: "RemoteShow needs its own password. Check the Remote password in FreeShow settings."
        case .capacity: "FreeShow's Remote connection limit was reached."
        case .timeout: "RemoteShow did not reply in time. The session was closed. A presentation command may have run; it was not retried. Check the desktop before reconnecting."
        case .invalidData: "The scripture response is unsupported or incomplete. Check the FreeShow version and translation."
        case .libraryChanged: "The desktop Bible library changed. Reconnecting will refresh it."
        case .busy: "Wait for the current scripture request to finish."
        case .notFound: "No matching book, chapter, or verses were returned. Try a full book name or another translation."
        case .invalidReference: "Enter a single chapter or a verse range, such as John 3:16–18. Cross-chapter references are not supported yet."
        case .shortSearch: "Enter at least three characters for a text search."
        case .notPreviewed: "Preview the passage again before presenting it."
        }
    }
}

/// Requests are serialized per channel. Independent reads cannot block live controls.
/// Any timeout/cancellation discards the connection, so a late reply cannot match a retry.
@MainActor
final class RemoteSession {
    private(set) var isReady = false
    private(set) var translations: JSONValue = .null
    private(set) var generation = UUID()
    var onDisconnect: ((Error?) -> Void)?
    private let transport: any RemoteTransport
    private let timeout: Duration
    private struct Pending {
        let id: UUID
        let continuation: CheckedContinuation<JSONValue, Error>
        let matches: (JSONValue) -> Bool
        let timer: Task<Void, Never>
    }
    private var pending: [String: Pending] = [:]
    private var messageObservers: [UUID: (RemoteMessage) -> Void] = [:]
    private var disconnectObservers: [UUID: (Error?) -> Void] = [:]
    private var password: String?
    private var authorized = false
    private var sentPassword = false

    init(transport: any RemoteTransport, timeout: Duration = .seconds(20)) {
        self.transport = transport
        self.timeout = timeout
    }
    func observeMessages(_ handler: @escaping (RemoteMessage) -> Void) -> UUID {
        let id = UUID(); messageObservers[id] = handler; return id
    }
    func observeDisconnect(_ handler: @escaping (Error?) -> Void) -> UUID {
        let id = UUID(); disconnectObservers[id] = handler; return id
    }
    func removeObserver(_ id: UUID) { messageObservers[id] = nil; disconnectObservers[id] = nil }
    func hasPending(_ channel: String) -> Bool { pending[channel] != nil }

    func connect(to endpoint: FreeShowEndpoint, password: String?) async throws {
        disconnect()
        var components = URLComponents()
        components.scheme = "http"
        components.host = endpoint.host.contains(":") ? "[\(endpoint.host)]" : endpoint.host
        components.port = Int(endpoint.port)
        guard let url = components.url, url.host != nil, endpoint.port > 0 else { throw APIError.invalidEndpoint }
        self.password = password
        let token = generation
        transport.receive = { [weak self] event in
            guard let self, self.generation == token else { return }
            self.receive(event)
        }
        _ = try await wait(channel: "INITIALIZATION", matches: { _ in true }) { self.transport.connect(to: url) }
    }
    func request(channel: String, data: JSONValue = .object([:]), matching: @escaping (JSONValue) -> Bool = { _ in true }) async throws -> JSONValue {
        guard isReady else { throw ScriptureError.disconnected }
        guard pending[channel] == nil else { throw ScriptureError.busy }
        return try await wait(channel: channel, matches: matching) { try self.transport.emit(RemoteMessage(channel: channel, data: data)) }
    }
    func disconnect(error: Error? = nil) { close(error: error) }

    private func wait(channel: String, matches: @escaping (JSONValue) -> Bool, send: () throws -> Void) async throws -> JSONValue {
        try Task.checkCancellation()
        let token = generation, requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard let self, self.generation == token, self.pending[channel]?.id == requestID else { return }
                    self.close(error: ScriptureError.timeout)
                }
                pending[channel] = Pending(id: requestID, continuation: continuation, matches: matches, timer: timer)
                do { try send() } catch { close(error: error) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.pending[channel]?.id == requestID else { return }
                self.close(error: CancellationError())
            }
        }
    }
    private func receive(_ event: RemoteEvent) {
        switch event {
        case .connected:
            do { try transport.emit(RemoteMessage(channel: "PASSWORD", data: .null)) }
            catch { close(error: error) }
        case .closed: close(error: ScriptureError.disconnected)
        case .failed(let reason): close(error: ScriptureError.transport(reason))
        case .message(let message):
            for observer in Array(messageObservers.values) { observer(message) }
            switch message.channel {
            case "PASSWORD":
                guard !sentPassword, message.data["password"].bool == true else { return }
                guard let password, !password.isEmpty else { close(error: ScriptureError.password); return }
                sentPassword = true
                do { try transport.emit(RemoteMessage(channel: "ACCESS", data: .string(password))) }
                catch { close(error: error) }
            case "ACCESS":
                authorized = true; password = nil
                finishInitialization()
            case "SCRIPTURE":
                guard message.data.object != nil else { close(error: ScriptureError.invalidData); return }
                if isReady && translations != message.data { close(error: ScriptureError.libraryChanged); return }
                translations = message.data
                finishInitialization()
            case "ERROR":
                close(error: message.data["key"].string == "overLimit" ? ScriptureError.capacity : ScriptureError.password)
            default:
                guard let request = pending[message.channel], request.matches(message.data) else { return }
                finish(channel: message.channel, data: message.data)
            }
        }
    }
    private func finishInitialization() {
        guard authorized, translations.object != nil, pending["INITIALIZATION"] != nil else { return }
        isReady = true
        finish(channel: "INITIALIZATION", data: translations)
    }
    private func finish(channel: String, data: JSONValue) {
        guard let request = pending.removeValue(forKey: channel) else { return }
        request.timer.cancel()
        request.continuation.resume(returning: data)
    }
    private func close(error: Error?) {
        generation = UUID()
        let requests = Array(pending.values); pending.removeAll()
        isReady = false; translations = .null
        password = nil; authorized = false; sentPassword = false
        transport.receive = nil; transport.disconnect()
        for request in requests { request.timer.cancel(); request.continuation.resume(throwing: error ?? CancellationError()) }
        onDisconnect?(error)
        for observer in Array(disconnectObservers.values) { observer(error) }
    }
}
