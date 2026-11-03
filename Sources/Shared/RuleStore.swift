import Foundation

/// In-memory cache over the rules table so the per-flow decision never touches disk.
final class RuleStore {
    private let db: FirewallDatabase
    private var cache: [String: AppRule]
    private let lock = NSLock()

    init(db: FirewallDatabase) {
        self.db = db
        cache = Dictionary(uniqueKeysWithValues: db.rules().map { ($0.key, $0) })
    }

    func action(for key: String) -> RuleAction? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]?.action
    }

    func all() -> [AppRule] {
        lock.lock(); defer { lock.unlock() }
        return Array(cache.values)
    }

    func set(_ rule: AppRule) {
        lock.lock(); cache[rule.key] = rule; lock.unlock()
        db.setRule(rule)
    }

    func remove(key: String) {
        lock.lock(); cache[key] = nil; lock.unlock()
        db.removeRule(key: key)
    }
}
