import Foundation
@preconcurrency import SocketIO

/// The library implements Engine.IO/Socket.IO framing, ping/pong, and websocket transport.
/// All callbacks are configured on the main queue; untyped values do not escape here.
@MainActor
final class SocketIOTransport: RemoteTransport {
    var receive: ((RemoteEvent) -> Void)?
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var generation = UUID()

    func connect(to url: URL) {
        disconnect()
        let token = generation
        let manager = SocketManager(socketURL: url, config: [
            // Start with HTTP polling and negotiate a WebSocket upgrade, as the
            // browser client does. A usable polling connection can stay active
            // when a network or server rejects the upgrade.
            .version(.three), .reconnects(false),
            .log(false), .handleQueue(.main)
        ])
        self.manager = manager
        let socket = manager.defaultSocket
        self.socket = socket
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.receive?(.connected)
            }
        }
        socket.on(clientEvent: .disconnect) { [weak self] values, _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.receive?(.failed(Self.failureDescription(values, fallback: "The server closed the connection.")))
            }
        }
        socket.on(clientEvent: .error) { [weak self] values, _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.receive?(.failed(Self.failureDescription(values, fallback: "Socket.IO could not establish or maintain the connection.")))
            }
        }
        socket.on("REMOTE") { [weak self] values, _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == token, let value = values.first,
                      JSONSerialization.isValidJSONObject(value),
                      let data = try? JSONSerialization.data(withJSONObject: value),
                      let message = try? JSONDecoder().decode(RemoteMessage.self, from: data) else { return }
                self.receive?(.message(message))
            }
        }
        socket.connect()
    }

    private static func failureDescription(_ values: [Any], fallback: String) -> String {
        if let error = values.first as? NSError {
            return "\(error.localizedDescription) (\(error.domain), \(error.code))"
        }
        if let reason = values.first as? String, !reason.isEmpty {
            return String(reason.prefix(500))
        }
        return fallback
    }

    func emit(_ message: RemoteMessage) throws {
        guard let socket, socket.status == .connected else { throw ScriptureError.disconnected }
        let data = try JSONEncoder().encode(message)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ScriptureError.invalidData }
        socket.emit("REMOTE", payload)
    }

    func disconnect() {
        generation = UUID()
        socket?.removeAllHandlers()
        socket?.disconnect()
        manager?.disconnect()
        socket = nil
        manager = nil
    }
}
