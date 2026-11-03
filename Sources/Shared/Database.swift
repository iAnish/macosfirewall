import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite store for per-app rules and the connection history (rolling 36 hour window).
final class FirewallDatabase {
    static let retention: TimeInterval = 36 * 3600

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.scaleneintelligence.macosfirewall.db")
    private var writesSincePrune = 0

    private enum Bind { case text(String), int(Int64), real(Double) }

    init?(path: String) {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard sqlite3_open(path, &db) == SQLITE_OK else { return nil }
        run("PRAGMA journal_mode=WAL")
        run("""
            CREATE TABLE IF NOT EXISTS rules (
                app_key TEXT PRIMARY KEY, app_name TEXT NOT NULL,
                action TEXT NOT NULL, updated REAL NOT NULL)
            """)
        run("""
            CREATE TABLE IF NOT EXISTS connections (
                id INTEGER PRIMARY KEY AUTOINCREMENT, app_key TEXT NOT NULL, app_name TEXT NOT NULL,
                kind TEXT NOT NULL, direction TEXT NOT NULL, ts REAL NOT NULL,
                source TEXT NOT NULL, destination TEXT NOT NULL, verdict TEXT NOT NULL)
            """)
        run("CREATE INDEX IF NOT EXISTS idx_connections_ts ON connections(ts)")
        prune()
    }

    deinit { sqlite3_close(db) }

    // MARK: Rules

    func rules() -> [AppRule] {
        queue.sync {
            var out: [AppRule] = []
            run("SELECT app_key, app_name, action, updated FROM rules ORDER BY app_name COLLATE NOCASE") { s in
                out.append(AppRule(key: Self.text(s, 0), name: Self.text(s, 1),
                                   action: RuleAction(rawValue: Self.text(s, 2)) ?? .block,
                                   updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 3))))
            }
            return out
        }
    }

    func setRule(_ rule: AppRule) {
        queue.sync {
            run("INSERT OR REPLACE INTO rules (app_key, app_name, action, updated) VALUES (?,?,?,?)",
                [.text(rule.key), .text(rule.name), .text(rule.action.rawValue),
                 .real(rule.updatedAt.timeIntervalSince1970)])
        }
    }

    func removeRule(key: String) {
        queue.sync { run("DELETE FROM rules WHERE app_key = ?", [.text(key)]) }
    }

    // MARK: History

    /// Asynchronous so the network path never waits on disk.
    func record(_ c: ConnectionRecord) {
        queue.async { [self] in
            run("""
                INSERT INTO connections (app_key, app_name, kind, direction, ts, source, destination, verdict)
                VALUES (?,?,?,?,?,?,?,?)
                """,
                [.text(c.appKey), .text(c.appName), .text(c.kind), .text(c.direction),
                 .real(c.timestamp.timeIntervalSince1970), .text(c.source), .text(c.destination), .text(c.verdict)])
            writesSincePrune += 1
            if writesSincePrune >= 500 { pruneLocked() }
        }
    }

    func history(limit: Int) -> [ConnectionRecord] {
        queue.sync {
            var out: [ConnectionRecord] = []
            let cutoff = Date().addingTimeInterval(-Self.retention).timeIntervalSince1970
            run("""
                SELECT id, app_key, app_name, kind, direction, ts, source, destination, verdict
                FROM connections WHERE ts >= ? ORDER BY ts DESC, id DESC LIMIT ?
                """, [.real(cutoff), .int(Int64(limit))]) { s in
                out.append(ConnectionRecord(
                    id: sqlite3_column_int64(s, 0), appKey: Self.text(s, 1), appName: Self.text(s, 2),
                    kind: Self.text(s, 3), direction: Self.text(s, 4),
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(s, 5)),
                    source: Self.text(s, 6), destination: Self.text(s, 7), verdict: Self.text(s, 8)))
            }
            return out
        }
    }

    func prune() { queue.sync { pruneLocked() } }

    private func pruneLocked() {
        writesSincePrune = 0
        let cutoff = Date().addingTimeInterval(-Self.retention).timeIntervalSince1970
        run("DELETE FROM connections WHERE ts < ?", [.real(cutoff)])
    }

    // MARK: SQLite helpers

    private static func text(_ s: OpaquePointer, _ col: Int32) -> String {
        sqlite3_column_text(s, col).map { String(cString: $0) } ?? ""
    }

    private func run(_ sql: String, _ binds: [Bind] = [], row: ((OpaquePointer) -> Void)? = nil) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch b {
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .real(let v): sqlite3_bind_double(stmt, idx, v)
            }
        }
        while sqlite3_step(stmt) == SQLITE_ROW { row?(stmt) }
    }
}
