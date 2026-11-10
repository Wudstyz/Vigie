import Foundation

/// Lit la sortie CSV de `nettop -L 0 -x -n -J bytes_in,bytes_out,state` ligne par ligne.
///
/// Format (une « photo » complète du réseau à chaque intervalle) :
///   ,state,bytes_in,bytes_out,                              <- en-tête (début d'un échantillon)
///   Safari.1234,,1000,2000,                                 <- processus (nom.pid)
///   tcp4 192.168.1.5:5000<->17.1.2.3:443,Established,10,20, <- connexion du processus ci-dessus
struct NettopParser {
    private var current = Sample(date: Date())
    private var columns: [String: Int] = [:]
    private var currentPid: Int32?

    /// Donne une ligne. Si elle ouvre un nouvel échantillon, renvoie le précédent (terminé).
    mutating func feed(line raw: String, now: Date = Date()) -> Sample? {
        let line = raw.trimmingCharacters(in: .newlines)
        if line.isEmpty { return nil }

        // En-tête : commence par une virgule
        if line.hasPrefix(",") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            var map: [String: Int] = [:]
            for (i, f) in fields.enumerated() where !f.isEmpty { map[f] = i }
            columns = map
            let finished = current.isEmpty ? nil : current
            current = Sample(date: now)
            currentPid = nil
            return finished
        }
        guard !columns.isEmpty else { return nil }

        let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func u64(_ key: String) -> UInt64 {
            guard let i = columns[key], i < f.count else { return 0 }
            return UInt64(f[i]) ?? 0
        }
        func str(_ key: String) -> String {
            guard let i = columns[key], i < f.count else { return "" }
            return f[i]
        }
        let head = f[0]

        if let c = Self.parseConnection(head) {
            guard let pid = currentPid else { return nil }
            current.conns.append(ConnSample(
                pid: pid, proto: c.proto, family: c.family,
                localAddr: c.local.addr, localPort: c.local.port,
                remoteAddr: c.remote.addr == "*" ? nil : c.remote.addr, remotePort: c.remote.port,
                state: str("state"), bytesIn: u64("bytes_in"), bytesOut: u64("bytes_out")))
            return nil
        }
        // Sinon : ligne de processus « nom.pid »
        if let dot = head.lastIndex(of: "."), let pid = Int32(head[head.index(after: dot)...]) {
            let name = String(head[..<dot])
            currentPid = pid
            current.procs.append(ProcSample(name: name, pid: pid, bytesIn: u64("bytes_in"), bytesOut: u64("bytes_out")))
        }
        return nil
    }

    /// Termine l'échantillon en cours (utile quand rien n'arrive pendant un moment).
    mutating func flush() -> Sample? {
        guard !current.isEmpty else { return nil }
        let s = current
        current = Sample(date: Date())
        currentPid = nil
        return s
    }

    static func parseConnection(_ head: String) -> (proto: String, family: Int, local: (addr: String, port: Int?), remote: (addr: String, port: Int?))? {
        guard let space = head.firstIndex(of: " ") else { return nil }
        let kind = head[..<space]
        guard kind.hasPrefix("tcp") || kind.hasPrefix("udp") else { return nil }
        let rest = head[head.index(after: space)...]
        guard let r = rest.range(of: "<->") else { return nil }
        let l = String(rest[..<r.lowerBound]), rm = String(rest[r.upperBound...])
        let proto = kind.hasPrefix("tcp") ? "TCP" : "UDP"
        let family = kind.hasSuffix("6") ? 6 : 4
        return (proto, family, Net.splitEndpoint(l), Net.splitEndpoint(rm))
    }
}
