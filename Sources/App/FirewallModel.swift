import Foundation
import SwiftUI

@MainActor
final class FirewallModel: ObservableObject {
    enum Status { case checking, running, unreachable, demo }

    @Published private(set) var rules: [AppRule] = []
    @Published private(set) var history: [ConnectionRecord] = []
    @Published private(set) var status: Status = .checking

    /// Bumped when a host name lookup finishes so tables redraw.
    @Published private(set) var resolveTick = 0

    let backend: FirewallBackend
    private let resolver = HostResolver()
    private var openWindows = Set<String>()
    private var timer: Timer?

    init(backend: FirewallBackend) {
        self.backend = backend
        resolver.onResolve = { [weak self] in self?.resolveTick += 1 }
        // Polling also keeps the XPC link to the filter alive so it always knows where to send prompts.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    func windowOpened(_ id: String) { openWindows.insert(id); Task { await refresh() } }
    func windowClosed(_ id: String) { openWindows.remove(id) }

    func refresh() async {
        guard let r = await backend.fetchRules() else {
            status = .unreachable
            return
        }
        status = backend.isDemo ? .demo : .running
        rules = r.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if openWindows.contains("history"), let h = await backend.fetchHistory() { history = h }
    }

    func set(_ rule: AppRule, to action: RuleAction) {
        Task {
            await backend.setRule(key: rule.key, name: rule.name, action: action)
            await refresh()
        }
    }

    func forget(_ rule: AppRule) {
        Task {
            await backend.removeRule(key: rule.key)
            await refresh()
        }
    }

    /// IPv4 endpoints are shown as they are. For IPv6 the website name is shown when it can be found
    /// (this Mac's own name for the source side); otherwise the IPv6 address.
    func display(_ endpoint: String, isSource: Bool) -> String {
        guard endpoint.hasPrefix("["), let close = endpoint.firstIndex(of: "]") else { return endpoint }
        let ip = String(endpoint[endpoint.index(after: endpoint.startIndex)..<close])
        let port = String(endpoint[close...].dropFirst())   // ":443"
        if ip.lowercased().hasPrefix("::ffff:"), ip.contains(".") { return String(ip.dropFirst(7)) + port }
        if isSource { return ProcessInfo.processInfo.hostName + port }
        if let name = resolver.name(for: ip) { return name + port }
        return endpoint
    }

    var statusText: String {
        switch status {
        case .checking: return "Firewall: starting…"
        case .running: return "Firewall: active"
        case .demo: return "Firewall: demo mode"
        case .unreachable: return "Firewall: not running"
        }
    }
}
