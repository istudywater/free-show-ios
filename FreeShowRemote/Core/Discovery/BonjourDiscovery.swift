import Foundation
import Combine

/// NetService callbacks are scheduled on the main run loop by the browser/service.
@MainActor
final class BonjourDiscovery: NSObject, ObservableObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    @Published private(set) var computers: [DiscoveredComputer] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    private let browser = NetServiceBrowser()
    private var services: [String: NetService] = [:]

    override init() { super.init(); browser.delegate = self }
    func start() {
        stop(); computers = []; errorMessage = nil; isSearching = true
        browser.searchForServices(ofType: "_freeshow._udp.", inDomain: "local.")
    }
    func stop() {
        browser.stop()
        for service in services.values { service.stop() }
        services.removeAll(); isSearching = false
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.name.uppercased().hasPrefix("FREESHOW-REMOTE-") else { return }
        let key = service.name + "@" + service.domain
        services[key] = service
        service.delegate = self
        service.resolve(withTimeout: 8)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let key = service.name + "@" + service.domain
        services[key]?.stop(); services[key] = nil
        computers.removeAll { $0.id == key }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        isSearching = false
        errorMessage = "Discovery is unavailable. Check local-network access in Settings or enter the computer address manually."
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = sender.name + "@" + sender.domain
        guard services[key] === sender, let host = sender.hostName, sender.port > 0, sender.port <= 65535 else { return }
        let hostName = host.hasSuffix(".") ? String(host.dropLast()) : host
        let computer = DiscoveredComputer(id: key, name: hostName, host: hostName, port: UInt16(sender.port))
        computers.removeAll { $0.id == key }; computers.append(computer)
        computers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        errorMessage = "A FreeShow advertisement could not be resolved. Manual connection is still available."
    }
}
