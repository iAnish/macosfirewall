import Foundation

/// Where rules and history live. The real implementation talks to the filter extension over XPC;
/// the demo implementation keeps everything in a throwaway local database.
protocol FirewallBackend: AnyObject {
    /// Set by the app; shows the Allow / Block prompt and calls back with the user's answer.
    var promptHandler: ((PromptRequest, @escaping (Bool) -> Void) -> Void)? { get set }
    var isDemo: Bool { get }
    /// nil means the backend is unreachable.
    func fetchRules() async -> [AppRule]?
    func fetchHistory() async -> [ConnectionRecord]?
    func setRule(key: String, name: String, action: RuleAction) async
    func removeRule(key: String) async
}

/// Real backend: everything runs inside this app. Data lives in ~/Library/Application Support/ScaleneFirewall.
final class LocalBackend: FirewallBackend {
    var promptHandler: ((PromptRequest, @escaping (Bool) -> Void) -> Void)?
    let isDemo = false
    let monitor: ConnectionMonitor
    private let db: FirewallDatabase
    private let rules: RuleStore

    init?() {
        let dir = NSHomeDirectory() + "/Library/Application Support/ScaleneFirewall"
        guard let db = FirewallDatabase(path: dir + "/firewall.sqlite") else { return nil }
        self.db = db
        rules = RuleStore(db: db)
        monitor = ConnectionMonitor(db: db, rules: rules)
        monitor.ask = { [weak self] request, reply in
            DispatchQueue.main.async {
                if let handler = self?.promptHandler { handler(request, reply) } else { reply(true) }
            }
        }
    }

    func start() { monitor.start() }

    func fetchRules() async -> [AppRule]? { rules.all() }
    func fetchHistory() async -> [ConnectionRecord]? { db.history(limit: 100) }

    func setRule(key: String, name: String, action: RuleAction) async {
        rules.set(AppRule(key: key, name: name, action: action, updatedAt: Date()))
    }

    func removeRule(key: String) async { rules.remove(key: key) }
}

/// Sample data and a simulated first connection, to try the UI without touching real processes (`--demo`).
final class DemoBackend: FirewallBackend {
    var promptHandler: ((PromptRequest, @escaping (Bool) -> Void) -> Void)?
    let isDemo = true
    private let db: FirewallDatabase

    init() {
        let path = NSTemporaryDirectory() + "scalene-firewall-demo.sqlite"
        try? FileManager.default.removeItem(atPath: path)
        db = FirewallDatabase(path: path)!
        seed()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.simulateFirstConnection() }
    }

    func fetchRules() async -> [AppRule]? { db.rules() }
    func fetchHistory() async -> [ConnectionRecord]? { db.history(limit: 100) }

    func setRule(key: String, name: String, action: RuleAction) async {
        db.setRule(AppRule(key: key, name: name, action: action, updatedAt: Date()))
    }

    func removeRule(key: String) async { db.removeRule(key: key) }

    private func seed() {
        let apps = ["Safari", "Terminal", "Mail", "Slack", "Chrome", "Notes", "Maps", "Music", "Zoom", "Spotify",
                    "Calculator", "Preview", "TextEdit", "Stickies", "Chess"]
        for (i, name) in apps.enumerated() {
            db.setRule(AppRule(key: "/Applications/\(name).app", name: name,
                               action: i < 8 ? .allow : .block, updatedAt: Date()))
        }
        let kinds = ["HTTPS", "HTTP", "QUIC", "DNS", "TCP", "UDP"]
        let dests = ["17.253.144.10:443", "[2606:4700:4700::1111]:443", "142.250.80.46:443",
                     "[2a00:1450:4001:82b::200e]:443", "192.168.1.1:53", "140.82.112.3:22"]
        for i in 0..<120 {
            let name = apps[i % apps.count]
            db.record(ConnectionRecord(
                id: 0, appKey: "/Applications/\(name).app", appName: name, kind: kinds[i % kinds.count],
                direction: i % 9 == 0 ? "Incoming" : "Outgoing",
                timestamp: Date().addingTimeInterval(-Double(i) * 240), source: "192.168.1.20:\(52000 + i)",
                destination: dests[i % dests.count], verdict: i % apps.count < 8 ? "Allowed" : "Blocked"))
        }
    }

    private func simulateFirstConnection() {
        let req = PromptRequest(appKey: "/Applications/Notes.app", appName: "Notes", pid: 4242,
                                kind: "HTTPS", direction: "Outgoing", destination: "17.253.144.12:443")
        promptHandler?(req) { [weak self] allow in
            guard let self else { return }
            self.db.setRule(AppRule(key: req.appKey, name: req.appName, action: allow ? .allow : .block, updatedAt: Date()))
            self.db.record(ConnectionRecord(id: 0, appKey: req.appKey, appName: req.appName, kind: req.kind,
                                            direction: req.direction, timestamp: Date(),
                                            source: "192.168.1.20:54000", destination: req.destination,
                                            verdict: allow ? "Allowed" : "Blocked"))
        }
    }
}
