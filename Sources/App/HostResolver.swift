import Foundation
import Darwin

/// Reverse-DNS lookups for IP addresses, done off the main thread and cached.
final class HostResolver {
    /// Called on the main queue whenever a lookup finishes.
    var onResolve: (() -> Void)?

    private var names: [String: String] = [:]
    private var attempted = Set<String>()
    private let lock = NSLock()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .utility
        return q
    }()

    /// The cached name for `ip`, or nil. A first call for an unknown address starts a lookup.
    func name(for ip: String) -> String? {
        lock.lock()
        if let hit = names[ip] { lock.unlock(); return hit }
        let first = attempted.insert(ip).inserted
        lock.unlock()
        if first {
            queue.addOperation { [weak self] in
                guard let self, let name = Self.lookup(ip) else { return }
                self.lock.lock(); self.names[ip] = name; self.lock.unlock()
                DispatchQueue.main.async { self.onResolve?() }
            }
        }
        return nil
    }

    private static func lookup(_ ip: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints, &res) == 0, let ai = res else { return nil }
        defer { freeaddrinfo(res) }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(ai.pointee.ai_addr, ai.pointee.ai_addrlen, &host, socklen_t(host.count),
                          nil, 0, NI_NAMEREQD) == 0 else { return nil }
        return String(cString: host)
    }
}
