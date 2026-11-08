import Foundation

struct ConnectionPreferences: Codable, Equatable, Sendable {
    var host = ""
    var port = "5510"
    var autoReconnect = true
    var rememberPassword = false
}

@MainActor
protocol CredentialVault {
    func password(for endpoint: FreeShowEndpoint) throws -> String?
    func save(_ password: String, for endpoint: FreeShowEndpoint) throws
    func remove(for endpoint: FreeShowEndpoint) throws
}

@MainActor
final class MemoryCredentialVault: CredentialVault {
    private var values: [String: String] = [:]
    private func key(_ endpoint: FreeShowEndpoint) -> String { endpoint.host.lowercased() + ":" + String(endpoint.port) }
    func password(for endpoint: FreeShowEndpoint) throws -> String? { values[key(endpoint)] }
    func save(_ password: String, for endpoint: FreeShowEndpoint) throws { values[key(endpoint)] = password }
    func remove(for endpoint: FreeShowEndpoint) throws { values[key(endpoint)] = nil }
}

struct DiscoveredComputer: Identifiable, Equatable {
    let id: String
    let name: String
    let host: String
    let port: UInt16
}

