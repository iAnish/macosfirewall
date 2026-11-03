import Foundation

enum RuleAction: String, Codable {
    case allow
    case block
}

/// A remembered decision for one application.
struct AppRule: Codable, Identifiable, Hashable {
    var key: String          // path of the outermost .app bundle (or the executable for command line tools)
    var name: String
    var action: RuleAction
    var updatedAt: Date
    var id: String { key }
}

/// One network connection seen by the filter.
struct ConnectionRecord: Codable, Identifiable, Hashable {
    var id: Int64
    var appKey: String
    var appName: String
    var kind: String         // HTTP, HTTPS, QUIC, DNS, TCP, UDP ...
    var direction: String    // Outgoing / Incoming
    var timestamp: Date
    var source: String
    var destination: String
    var verdict: String      // Allowed / Blocked
}

/// Sent from the filter to the menu bar app when an unknown app opens its first connection.
struct PromptRequest: Codable {
    var appKey: String
    var appName: String
    var pid: Int32
    var kind: String
    var direction: String
    var destination: String
}

enum TrafficKind {
    static func label(proto: Int32, port: Int) -> String {
        switch (proto, port) {
        case (_, 53): return "DNS"
        case (6, 80), (6, 8080): return "HTTP"
        case (6, 443): return "HTTPS"
        case (17, 443): return "QUIC"
        case (6, _): return "TCP"
        case (17, _): return "UDP"
        default: return "IP/\(proto)"
        }
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}
