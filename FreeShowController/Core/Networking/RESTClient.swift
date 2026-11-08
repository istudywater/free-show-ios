import Foundation
import OSLog

@MainActor
protocol HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Redirects are rejected: a connection must stay on the operator's chosen endpoint.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, response)
    }
}

enum APIError: LocalizedError, Equatable {
    case invalidEndpoint, unauthorized, invalidResponse, notConnected, busy
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter a hostname or IP address without a scheme, path, or port, and a port from 1 to 65535."
        case .unauthorized: "The API password was rejected. Check the General API password in FreeShow settings."
        case .invalidResponse: "This server did not return the expected FreeShow API response. Check its version, API setting, and REST port."
        case .notConnected: "Connect to the FreeShow API first."
        case .busy: "Wait for the current request to finish."
        case .http(let status): "FreeShow returned HTTP \(status). Check the API settings and port."
        }
    }
}

struct ClearedStatus: Decodable, Equatable, Sendable {
    let all: Bool
    let background: Bool
    let slide: Bool
    let overlays: Bool
    let audio: Bool
    let slideTimers: Bool
}

enum OutputCommand: String, CaseIterable, Sendable {
    case previous = "previous_slide"
    case next = "next_slide"
    case clear = "clear_all"
    case restore = "restore_output"

    var title: String {
        switch self {
        case .previous: "Previous"
        case .next: "Next"
        case .clear: "Clear all"
        case .restore: "Restore output"
        }
    }
}

/// REST readiness is a successful authenticated query, not a persistent socket connection.
@MainActor
final class RESTClient: ConnectionService, OutputService {
    private(set) var state: ConnectionState = .disconnected
    private(set) var clearedStatus: ClearedStatus?
    private let transport: any HTTPTransport
    private var endpoint: URL?
    private var password: String?
    private var generation = UUID()
    private var inFlight = false
    private let logger = Logger(subsystem: "org.istudywater.FreeShowRemote", category: "REST")

    init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    static func endpoint(host: String, port: String) throws -> FreeShowEndpoint {
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace }),
              host.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\@?#%")) == nil,
              !host.contains(":") || host.filter({ $0 == ":" }).count >= 2,
              let number = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)), number > 0 else {
            throw APIError.invalidEndpoint
        }
        let endpoint = FreeShowEndpoint(host: host, port: number)
        _ = try url(for: endpoint)
        return endpoint
    }

    private static func url(for endpoint: FreeShowEndpoint) throws -> URL {
        guard endpoint.port > 0 else { throw APIError.invalidEndpoint }
        var components = URLComponents()
        components.scheme = "http"
        components.host = endpoint.host.contains(":") ? "[\(endpoint.host)]" : endpoint.host
        components.port = Int(endpoint.port)
        components.path = "/"
        guard let url = components.url, url.host != nil else { throw APIError.invalidEndpoint }
        return url
    }

    func connect(to endpoint: FreeShowEndpoint, password: String?) async throws {
        guard !inFlight else { throw APIError.busy }
        self.endpoint = try Self.url(for: endpoint)
        self.password = password?.trimmingCharacters(in: .whitespacesAndNewlines)
        generation = UUID()
        state = .connecting
        clearedStatus = nil
        do {
            _ = try await refreshStatus()
            state = .connected
        } catch {
            if !(error is CancellationError) { recordFailure(error) }
            throw error
        }
    }

    func disconnect() async {
        generation = UUID()
        endpoint = nil
        password = nil
        clearedStatus = nil
        state = .disconnected
        // An old request may still be winding down. Its defer is generation-scoped.
        inFlight = false
    }

    func refreshStatus() async throws -> ClearedStatus {
        let data = try await request(action: "get_cleared", query: true)
        struct Envelope: Decodable { let action: String; let data: ClearedStatus }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.action == "get_cleared" else {
            recordFailure(APIError.invalidResponse)
            throw APIError.invalidResponse
        }
        clearedStatus = envelope.data
        state = .connected
        return envelope.data
    }

    func send(_ command: OutputCommand) async throws {
        guard state == .connected else { throw APIError.notConnected }
        _ = try await request(action: command.rawValue)
        // No optimistic output update. HTTP acceptance alone cannot confirm a live change.
        clearedStatus = nil
    }

    func present(_ slide: SlideReference) async throws {
        guard slide.index >= 0, slide.index < Int.max else { throw APIError.invalidResponse }
        guard state == .connected else { throw APIError.notConnected }
        _ = try await request(action: "index_select_slide", fields: [
            "index": slide.index + 1, "showId": slide.presentationID, "layoutId": slide.layoutID
        ])
        clearedStatus = nil
    }

    func nextSlide() async throws { try await send(.next) }
    func previousSlide() async throws { try await send(.previous) }
    func clearAll() async throws { try await send(.clear) }
    func restoreOutput() async throws { try await send(.restore) }

    private func request(action: String, fields: [String: Any] = [:], query: Bool = false) async throws -> Data {
        guard let endpoint else { throw APIError.notConnected }
        guard !inFlight else { throw APIError.busy }
        let current = generation
        inFlight = true
        defer { if generation == current { inFlight = false } }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let password, !password.isEmpty {
            request.setValue("Bearer \(password)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: fields.merging(["action": action]) { _, new in new })
        logger.debug("Sending API action \(action, privacy: .public)")
        do {
            try Task.checkCancellation()
            let (data, response) = try await transport.data(for: request)
            guard generation == current else { throw CancellationError() }
            try Task.checkCancellation()
            logger.debug("API action \(action, privacy: .public) returned HTTP \(response.statusCode)")
            if response.statusCode == 401 { throw APIError.unauthorized }
            guard (200...299).contains(response.statusCode) else { throw APIError.http(response.statusCode) }
            if query && (response.statusCode == 204 || data.isEmpty) { throw APIError.invalidResponse }
            return data
        } catch {
            guard generation == current else { throw CancellationError() }
            if !(error is CancellationError) { recordFailure(error) }
            throw error
        }
    }

    private func recordFailure(_ error: Error) {
        clearedStatus = nil
        state = (error as? APIError) == .unauthorized ? .authenticationRequired : .failed("API request failed")
        // Deliberately omit credentials, response bodies, URLs, and arbitrary error descriptions.
        logger.error("API request failed; reconnect before sending further commands")
    }
}
