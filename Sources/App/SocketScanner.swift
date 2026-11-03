import Foundation
import Darwin

/// One live TCP or connected-UDP socket owned by a process.
struct SocketInfo: Hashable {
    let pid: pid_t
    let proto: Int32          // 6 = TCP, 17 = UDP
    let localAddr: String
    let localPort: Int
    let remoteAddr: String
    let remotePort: Int
    let incoming: Bool

    var source: String { Self.format(localAddr, localPort) }
    var destination: String { Self.format(remoteAddr, remotePort) }

    var isLoopback: Bool { remoteAddr == "::1" || remoteAddr.hasPrefix("127.") }

    private static func format(_ addr: String, _ port: Int) -> String {
        let host = addr.contains(":") ? "[\(addr)]" : addr
        return "\(host):\(port)"
    }
}

/// Reads every socket the current user's processes have open, using libproc (no special permissions needed).
/// Processes owned by other users (root daemons) are invisible without root.
enum SocketScanner {
    private static let procPidListFds: Int32 = 1       // PROC_PIDLISTFDS
    private static let procPidFdSocketInfo: Int32 = 3  // PROC_PIDFDSOCKETINFO
    private static let fdTypeSocket: UInt32 = 2        // PROX_FDTYPE_SOCKET
    private static let sockinfoIn: Int32 = 1
    private static let sockinfoTcp: Int32 = 2
    private static let tcpListen: Int32 = 1
    private static let tcpSynSent: Int32 = 2
    private static let tcpEstablished: Int32 = 4

    static func allPids() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(n, 0)))).filter { $0 > 1 }
    }

    static func scan() -> [SocketInfo] {
        var out: [SocketInfo] = []
        for pid in allPids() { out.append(contentsOf: sockets(of: pid)) }
        return out
    }

    private static func sockets(of pid: pid_t) -> [SocketInfo] {
        let size = proc_pidinfo(pid, procPidListFds, 0, nil, 0)
        guard size > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size + 4)
        let got = proc_pidinfo(pid, procPidListFds, 0, &fds, Int32(fds.count * MemoryLayout<proc_fdinfo>.size))
        guard got > 0 else { return [] }

        var found: [(proto: Int32, ini: in_sockinfo, state: Int32)] = []
        for fd in fds.prefix(Int(got) / MemoryLayout<proc_fdinfo>.size) where fd.proc_fdtype == fdTypeSocket {
            var info = socket_fdinfo()
            let r = proc_pidfdinfo(pid, fd.proc_fd, procPidFdSocketInfo, &info, Int32(MemoryLayout<socket_fdinfo>.size))
            guard r == Int32(MemoryLayout<socket_fdinfo>.size) else { continue }
            let s = info.psi
            guard s.soi_family == AF_INET || s.soi_family == AF_INET6 else { continue }
            if s.soi_kind == sockinfoTcp {
                found.append((6, s.soi_proto.pri_tcp.tcpsi_ini, s.soi_proto.pri_tcp.tcpsi_state))
            } else if s.soi_kind == sockinfoIn, s.soi_protocol == IPPROTO_UDP {
                found.append((17, s.soi_proto.pri_in, 0))
            }
        }

        // Ports this process listens on: traffic to them is incoming.
        let listening = Set(found.filter { $0.proto == 6 ? $0.state == tcpListen : port($0.ini.insi_fport) == 0 }
            .map { port($0.ini.insi_lport) })

        var out: [SocketInfo] = []
        for f in found {
            let remotePort = port(f.ini.insi_fport)
            guard remotePort != 0 else { continue }
            if f.proto == 6, f.state != tcpEstablished, f.state != tcpSynSent { continue }
            let lport = port(f.ini.insi_lport)
            let v6 = f.ini.insi_vflag & 0x2 != 0
            out.append(SocketInfo(pid: pid, proto: f.proto,
                                  localAddr: address(f.ini.insi_laddr, v6: v6), localPort: lport,
                                  remoteAddr: address(f.ini.insi_faddr, v6: v6), remotePort: remotePort,
                                  incoming: listening.contains(lport)))
        }
        return out
    }

    private static func port(_ raw: Int32) -> Int {
        Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: raw)))
    }

    /// The address union is 16 bytes: an IPv6 address, or an IPv4 address in the last 4 bytes.
    private static func address<T>(_ union: T, v6: Bool) -> String {
        var bytes = withUnsafeBytes(of: union) { Array($0.prefix(16)) }
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if v6 {
            inet_ntop(AF_INET6, &bytes, &buf, socklen_t(buf.count))
        } else {
            var v4 = Array(bytes[12..<16])
            inet_ntop(AF_INET, &v4, &buf, socklen_t(buf.count))
        }
        return String(cString: buf)
    }
}
