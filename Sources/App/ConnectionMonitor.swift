import Foundation
import Darwin

/// Watches the system's sockets and enforces the per-app rules.
///
/// - Known app, allowed: connection is logged.
/// - Known app, blocked: its processes are terminated as soon as they hold a connection.
/// - Unknown app: its processes are paused (SIGSTOP) until the user answers Allow or Block.
///
/// This works from user space, so a connection can be open for up to one poll interval before it is seen.
final class ConnectionMonitor {
    /// Called on an arbitrary queue; `reply(true)` = Allow.
    var ask: ((PromptRequest, @escaping (Bool) -> Void) -> Void)?
    /// Limits which processes are watched and acted on. Everything by default; tests narrow it.
    var shouldManage: (pid_t) -> Bool = { _ in true }

    private let db: FirewallDatabase
    private let rules: RuleStore
    private let queue = DispatchQueue(label: "com.ianish.firewall.monitor")
    private var timer: DispatchSourceTimer?
    private var seen = Set<SocketInfo>()
    private var pending: [String: [SocketInfo]] = [:]
    private var stopped = Set<pid_t>()
    private var termSent = Set<pid_t>()
    private let me = getpid()

    init(db: FirewallDatabase, rules: RuleStore) {
        self.db = db
        self.rules = rules
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.2, repeating: 0.5)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    /// Never leave apps frozen when we exit.
    func resumeAll() {
        queue.sync {
            for pid in stopped { kill(pid, SIGCONT) }
            stopped.removeAll()
        }
    }

    // MARK: Polling

    private func poll() {
        let sockets = SocketScanner.scan().filter { !$0.isLoopback && $0.pid != me && shouldManage($0.pid) }
        let current = Set(sockets)
        let fresh = current.subtracting(seen)
        seen = current

        var toKill = Set<String>()
        var identities: [pid_t: AppIdentity] = [:]
        func identity(_ pid: pid_t) -> AppIdentity? {
            if let i = identities[pid] { return i }
            let i = AppIdentity.resolve(pid: pid)
            identities[pid] = i
            return i
        }

        for s in sockets {
            guard let app = identity(s.pid) else { continue }
            let isFresh = fresh.contains(s)
            switch rules.action(for: app.key) {
            case .allow?:
                if isFresh { record(s, app, allowed: true) }
            case .block?:
                if isFresh { record(s, app, allowed: false) }
                toKill.insert(app.key)
            case nil:
                if app.isSystemDaemon {
                    if isFresh { record(s, app, allowed: true) }
                } else if isFresh || pending[app.key] != nil {
                    hold(s, app)
                }
            }
        }
        for key in toKill { terminate(appKey: key) }
        if toKill.isEmpty { termSent.removeAll() }
    }

    // MARK: Unknown apps

    private func hold(_ s: SocketInfo, _ app: AppIdentity) {
        if pending[app.key] != nil {
            if !pending[app.key]!.contains(s) { pending[app.key]!.append(s) }
            return
        }
        pending[app.key] = [s]
        for pid in pids(ofApp: app.key) where kill(pid, SIGSTOP) == 0 { stopped.insert(pid) }

        let request = PromptRequest(appKey: app.key, appName: app.name, pid: s.pid,
                                    kind: TrafficKind.label(proto: s.proto, port: s.remotePort),
                                    direction: s.incoming ? "Incoming" : "Outgoing",
                                    destination: s.destination)
        guard let ask else { answer(app, allow: true, persist: false); return }
        ask(request) { [weak self] allow in
            self?.queue.async { self?.answer(app, allow: allow, persist: true) }
        }
    }

    private func answer(_ app: AppIdentity, allow: Bool, persist: Bool) {
        if persist {
            rules.set(AppRule(key: app.key, name: app.name, action: allow ? .allow : .block, updatedAt: Date()))
        }
        for s in pending.removeValue(forKey: app.key) ?? [] { record(s, app, allowed: allow) }
        for pid in pids(ofApp: app.key) where stopped.contains(pid) {
            kill(pid, SIGCONT)
            stopped.remove(pid)
        }
        if !allow { terminate(appKey: app.key) }
    }

    // MARK: Helpers

    /// SIGTERM first; anything still holding a connection on a later poll gets SIGKILL.
    private func terminate(appKey: String) {
        for pid in pids(ofApp: appKey) {
            if termSent.contains(pid) { kill(pid, SIGKILL) } else { kill(pid, SIGTERM); termSent.insert(pid) }
        }
    }

    private func pids(ofApp key: String) -> [pid_t] {
        SocketScanner.allPids().filter { $0 != me && shouldManage($0) && AppIdentity.resolve(pid: $0)?.key == key }
    }

    private func record(_ s: SocketInfo, _ app: AppIdentity, allowed: Bool) {
        db.record(ConnectionRecord(id: 0, appKey: app.key, appName: app.name,
                                   kind: TrafficKind.label(proto: s.proto, port: s.remotePort),
                                   direction: s.incoming ? "Incoming" : "Outgoing", timestamp: Date(),
                                   source: s.source, destination: s.destination,
                                   verdict: allowed ? "Allowed" : "Blocked"))
    }
}
