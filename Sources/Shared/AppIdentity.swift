import Foundation
import Darwin

/// The application a network flow belongs to. Helper processes inside an app bundle
/// (e.g. "Google Chrome Helper") resolve to the outermost .app so one rule covers the whole app.
struct AppIdentity {
    let key: String
    let name: String
    let isBundle: Bool

    private static let systemPrefixes = ["/usr/libexec/", "/usr/sbin/", "/sbin/", "/System/Library/"]

    /// macOS's own daemons and core apps (mDNSResponder, Dock, Finder, ...) are never prompted for or paused;
    /// freezing or killing them would break the system.
    var isSystemDaemon: Bool {
        Self.systemPrefixes.contains { key.hasPrefix($0) }
    }

    static func resolve(pid: pid_t) -> AppIdentity? {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return from(executablePath: String(cString: buf))
    }

    static func from(executablePath exe: String) -> AppIdentity {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[exe] { return hit }

        var prefix = ""
        var bundlePath: String?
        for comp in URL(fileURLWithPath: exe).pathComponents where comp != "/" {
            prefix += "/" + comp
            if comp.hasSuffix(".app") { bundlePath = prefix; break }
        }

        let identity: AppIdentity
        if let bundlePath {
            let info = Bundle(path: bundlePath)?.infoDictionary
            let fallback = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
            let name = (info?["CFBundleDisplayName"] as? String)
                ?? (info?["CFBundleName"] as? String) ?? fallback
            identity = AppIdentity(key: bundlePath, name: name, isBundle: true)
        } else {
            identity = AppIdentity(key: exe, name: (exe as NSString).lastPathComponent, isBundle: false)
        }
        cache[exe] = identity
        return identity
    }

    private static var cache: [String: AppIdentity] = [:]
    private static let lock = NSLock()
}
