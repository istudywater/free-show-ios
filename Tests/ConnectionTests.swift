import Foundation

@MainActor
final class MockTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest) async throws -> (Data, HTTPURLResponse) = { request in
        (statusFixture, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try await handler(request)
    }
}

private let statusFixture = Data("""
{"action":"get_cleared","data":{"all":false,"background":true,"slide":false,"overlays":true,"audio":true,"slideTimers":true}}
""".utf8)

@main
struct ConnectionTests {
    @MainActor
    static func main() async throws {
        var count = 0
        func expect(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            count += 1
        }
        func response(_ request: URLRequest, _ status: Int, _ body: Data = Data()) -> (Data, HTTPURLResponse) {
            (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        func action(_ request: URLRequest) -> String? {
            (try? JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])?["action"] as? String
        }
        let endpoint = try RESTClient.endpoint(host: "  freeshow.local  ", port: "5506")
        expect(endpoint.host == "freeshow.local", "Host normalization")
        for host in ["", "http://host", "host:5506", "host/path", "user@host", "host?query", "bad host"] {
            do { _ = try RESTClient.endpoint(host: host, port: "5506"); preconditionFailure("Accepted invalid host") }
            catch { expect(error as? APIError == .invalidEndpoint, "Reject invalid host \(host)") }
        }
        for port in ["0", "65536", "abc", "-1"] {
            do { _ = try RESTClient.endpoint(host: "host", port: port); preconditionFailure("Accepted invalid port") }
            catch { expect(error as? APIError == .invalidEndpoint, "Reject invalid port") }
        }
        let ipv6 = try RESTClient.endpoint(host: "[fe80::1]", port: "5506")
        let mock = MockTransport()
        let client = RESTClient(transport: mock)
        try await client.connect(to: ipv6, password: nil)
        expect(mock.requests.last?.url?.absoluteString == "http://[fe80::1]:5506/", "IPv6 URL")
        await client.disconnect()
        try await client.connect(to: endpoint, password: " secret ")
        let request = mock.requests.last!
        expect(request.httpMethod == "POST" && request.url?.path == "/", "REST uses POST at root")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret", "Bearer password")
        expect(action(request) == "get_cleared", "Connect uses read-only query")
        expect(client.state == .connected && client.clearedStatus?.all == false, "Validated handshake")
        expect(request.timeoutInterval == 15, "Bounded request timeout")

        mock.handler = { response($0, 204) }
        for command in OutputCommand.allCases {
            try await client.send(command)
            expect(action(mock.requests.last!) == command.rawValue, "Correct command \(command)")
        }
        expect(client.clearedStatus == nil, "Sending does not confirm output")
        try await client.present(SlideReference(presentationID: "show", layoutID: "layout", index: 0))
        let body = try JSONSerialization.jsonObject(with: mock.requests.last!.httpBody!) as! [String: Any]
        expect(body["index"] as? Int == 1 && body["showId"] as? String == "show", "Flattened one-based slide command")
        await client.disconnect()
        do { try await client.nextSlide(); preconditionFailure("Command without connection") }
        catch { expect(error as? APIError == .notConnected, "Disconnected controls blocked") }

        for (status, body) in [(204, Data()), (200, Data("{}".utf8)), (200, Data("<html>Wrong server</html>".utf8)),
                               (200, Data("{\"action\":\"wrong\",\"data\":{}}".utf8)),
                               (200, Data("{\"action\":\"get_cleared\",\"data\":{\"all\":true}}".utf8))] {
            mock.handler = { response($0, status, body) }
            do { try await client.connect(to: endpoint, password: nil); preconditionFailure("Malformed handshake accepted") }
            catch { expect(error as? APIError == .invalidResponse, "Reject malformed/empty query response") }
            expect(client.state != .connected, "Bad query never enables controls")
        }
        mock.handler = { response($0, 401) }
        do { try await client.connect(to: endpoint, password: "wrong"); preconditionFailure("Unauthorized handshake accepted") }
        catch { expect(client.state == .authenticationRequired, "Wrong password is actionable") }
        mock.handler = { response($0, 503) }
        do { try await client.connect(to: endpoint, password: nil); preconditionFailure("Server error accepted") }
        catch { expect(error as? APIError == .http(503), "HTTP errors surfaced") }
        mock.handler = { response($0, 200, statusFixture) }
        try await client.connect(to: endpoint, password: nil)
        expect(mock.requests.last?.value(forHTTPHeaderField: "Authorization") == nil, "Omit absent password")
        let beforeTimeout = mock.requests.count
        mock.handler = { _ in throw URLError(.timedOut) }
        do { try await client.nextSlide(); preconditionFailure("Timeout accepted") }
        catch { expect((error as? URLError)?.code == .timedOut, "Timeout surfaced") }
        expect(mock.requests.count == beforeTimeout + 1, "No automatic retry of uncertain command")
        expect(client.state != .connected && client.clearedStatus == nil, "Failure invalidates readiness and output")

        // Suspend an actual in-flight request, disconnect, then finish its stale response.
        var pending: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        mock.handler = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let stale = Task { try await client.connect(to: endpoint, password: "old") }
        while pending == nil { await Task.yield() }
        do { try await client.connect(to: endpoint, password: nil); preconditionFailure("Overlapping request accepted") }
        catch { expect(error as? APIError == .busy, "Serialize requests") }
        await client.disconnect()
        pending!.resume(returning: response(mock.requests.last!, 200, statusFixture))
        do { try await stale.value; preconditionFailure("Stale response accepted") }
        catch { expect(error is CancellationError, "Reject previous session replies") }
        expect(client.state == .disconnected && client.clearedStatus == nil, "Disconnect cannot be undone by late reply")

        mock.handler = { response($0, 200, statusFixture) }
        try await client.connect(to: endpoint, password: nil)
        mock.handler = { response($0, 401) }
        do { try await client.clearAll(); preconditionFailure("Expired auth accepted") }
        catch { expect(client.state == .authenticationRequired, "Password change disables live commands") }


        // UI owner prevents repeated taps and preserves command uncertainty if refresh fails.
        mock.handler = { response($0, 200, statusFixture) }
        let state = AppState(client: client)
        state.connect(host: "host.local", port: "5506", password: "")
        while state.isBusy { await Task.yield() }
        expect(state.connection == .connected && state.checkedAt != nil, "UI reports checked snapshot")
        var commandCount = 0
        mock.handler = { request in
            if action(request) == "get_cleared" { throw URLError(.timedOut) }
            commandCount += 1
            return response(request, 204)
        }
        state.send(.next)
        state.send(.next)
        while state.isBusy { await Task.yield() }
        expect(commandCount == 1, "Repeated taps send one command")
        expect(state.message?.contains("request sent") == true && state.errorMessage != nil, "Refresh failure retains command acceptance")
        expect(state.output == .unknown && state.checkedAt == nil && state.connection != .connected, "Failed refresh invalidates snapshot")
        state.disconnect()
        while state.isBusy { await Task.yield() }
        expect(state.connection == .disconnected, "Explicit disconnect")
        // A late UI connection reply must not revive a disconnected screen.
        pending = nil
        mock.handler = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        state.connect(host: "host.local", port: "5506", password: "")
        while pending == nil { await Task.yield() }
        state.disconnect()
        while state.isBusy { await Task.yield() }
        pending!.resume(returning: response(mock.requests.last!, 200, statusFixture))
        for _ in 0..<20 { await Task.yield() }
        expect(state.connection == .disconnected && state.checkedAt == nil && state.message == nil, "Late UI reply stays disconnected")

        let allCleared = Data("{\"action\":\"get_cleared\",\"data\":{\"all\":true,\"background\":true,\"slide\":true,\"overlays\":true,\"audio\":true,\"slideTimers\":true}}".utf8)
        mock.handler = { response($0, 200, allCleared) }
        state.connect(host: "host.local", port: "5506", password: "")
        while state.isBusy { await Task.yield() }
        expect(state.output == .cleared, "Cleared label requires a server snapshot")
        print("Passed \(count) connection checks.")
    }
}
