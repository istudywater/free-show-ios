import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var connection: ConnectionState = .disconnected
    @Published private(set) var output: OutputState = .unknown
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var checkedAt: Date?
    @Published var selectedSlide: SlideReference?

    private let client: RESTClient
    private var operation: Task<Void, Never>?
    private var generation = UUID()

    init(client: RESTClient = RESTClient()) { self.client = client }

    func connect(host: String, port: String, password: String) {
        guard !isBusy else { return }
        let endpoint: FreeShowEndpoint
        do { endpoint = try RESTClient.endpoint(host: host, port: port) }
        catch { errorMessage = error.localizedDescription; return }
        connection = .connecting
        run {
            try await self.client.connect(to: endpoint, password: password)
            try Task.checkCancellation()
            self.updateOutput()
            self.message = "API ready. Output status was checked."
        }
    }

    func send(_ command: OutputCommand) {
        guard connection == .connected, !isBusy else { return }
        run {
            self.output = .unknown
            self.checkedAt = nil
            try await self.client.send(command)
            try Task.checkCancellation()
            self.message = "\(command.title) request sent. A live output change is not confirmed."
            _ = try await self.client.refreshStatus()
            try Task.checkCancellation()
            self.updateOutput()
        }
    }

    func refresh() {
        guard connection == .connected, !isBusy else { return }
        run {
            _ = try await self.client.refreshStatus()
            try Task.checkCancellation()
            self.updateOutput()
            self.message = "Output status refreshed."
        }
    }

    func disconnect() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        // disconnect has no suspension points in RESTClient, but the protocol is async.
        isBusy = true
        connection = .disconnected
        output = .unknown
        checkedAt = nil
        message = nil
        errorMessage = nil
        let current = generation
        operation = Task {
            guard current == generation else { return }
            await client.disconnect()
            guard current == generation else { return }
            isBusy = false
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        isBusy = true
        errorMessage = nil
        message = nil
        output = .unknown
        checkedAt = nil
        let current = generation
        operation = Task {
            do {
                try await work()
                guard current == generation else { return }
                connection = client.state
            } catch {
                guard current == generation else { return }
                connection = client.state
                output = .unknown
                checkedAt = nil
                if !(error is CancellationError) {
                    if (error as? URLError)?.code == .timedOut {
                        errorMessage = "The request timed out. It may have reached FreeShow. Check the desktop before reconnecting; the command was not retried."
                    } else if error is URLError {
                        errorMessage = "Cannot reach the API. Check Wi-Fi, local-network permission, host, port, and FreeShow API settings. A sent command may still have run; it was not retried."
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            guard current == generation else { return }
            isBusy = false
            operation = nil
        }
    }

    private func updateOutput() {
        guard let status = client.clearedStatus else { return }
        output = status.all ? .cleared : .other(description: "Output is not fully cleared")
        checkedAt = Date()
    }
}
