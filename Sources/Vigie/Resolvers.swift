import Foundation
import Darwin

// MARK: - Noms de domaine (DNS inverse)

/// Demande au DNS du Mac « quel est le nom de cette adresse ? ».
/// ⚠️ Cela envoie l'adresse à votre serveur DNS (box, opérateur…). Désactivable dans les réglages.
final class HostResolver {
    private let lock = NSLock()
    private var cache: [String: String?] = [:]      // nil = lookup terminé, pas de nom
    private var pending: Set<String> = []
    private let queue = DispatchQueue(label: "vigie.dns", qos: .utility, attributes: .concurrent)
    private let gate = DispatchSemaphore(value: 4)
    var onResolved: (() -> Void)?

    func cached(_ ip: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[ip] ?? nil
    }

    func request(_ ip: String) {
        lock.lock()
        if cache[ip] != nil || pending.contains(ip) { lock.unlock(); return }
        pending.insert(ip)
        lock.unlock()
        queue.async { [self] in
            gate.wait(); defer { gate.signal() }
            let name = Self.reverse(ip)
            lock.lock()
            cache[ip] = .some(name)
            pending.remove(ip)
            lock.unlock()
            if name != nil { onResolved?() }
        }
    }

    static func reverse(_ ip: String) -> String? {
        let clean = Net.stripZone(ip)
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var rc: Int32 = -1
        if let _ = Net.v4Bytes(clean) {
            var sa = sockaddr_in(); sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); sa.sin_family = sa_family_t(AF_INET)
            inet_pton(AF_INET, clean, &sa.sin_addr)
            rc = withUnsafePointer(to: &sa) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                }
            }
        } else if Net.v6Bytes(clean) != nil {
            var sa = sockaddr_in6(); sa.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size); sa.sin6_family = sa_family_t(AF_INET6)
            inet_pton(AF_INET6, clean, &sa.sin6_addr)
            rc = withUnsafePointer(to: &sa) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in6>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                }
            }
        }
        guard rc == 0 else { return nil }
        let name = String(cString: host)
        return name.isEmpty || name == clean ? nil : name
    }
}

// MARK: - Propriétaire d'une adresse (RDAP, option)

struct OwnerInfo: Hashable {
    var name: String
    var country: String?
}

/// Retrouve « à qui appartient » une adresse Internet (ex. Google, Apple, OVH…).
/// - Apple (17.0.0.0/8) est reconnu hors ligne.
/// - Le reste passe par RDAP (https://rdap.org), un annuaire public des adresses IP.
///   ⚠️ Cette partie envoie les adresses contactées à ce service : désactivée par défaut.
final class OwnerResolver {
    private struct Range { var lo: [UInt8]; var hi: [UInt8]; var info: OwnerInfo }

    private let lock = NSLock()
    private var ranges: [Range] = []
    private var byIP: [String: OwnerInfo?] = [:]
    private var pending: Set<String> = []
    private var requestCount = 0
    private let queue = DispatchQueue(label: "vigie.rdap", qos: .utility)
    private let session: URLSession
    var enabled = false
    var onResolved: (() -> Void)?

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.httpAdditionalHeaders = ["Accept": "application/rdap+json, application/json", "User-Agent": "Vigie"]
        session = URLSession(configuration: cfg)
    }

    func cached(_ ip: String) -> OwnerInfo? {
        if let b = Net.v4Bytes(ip), b[0] == 17 { return OwnerInfo(name: "Apple", country: "US") }
        lock.lock(); defer { lock.unlock() }
        if let v = byIP[ip] { return v }
        if let b = Net.v4Bytes(ip) ?? Net.v6Bytes(ip) {
            for r in ranges where r.lo.count == b.count && r.lo.lexicographicallyPrecedes(b + [0]) && !r.hi.lexicographicallyPrecedes(b) {
                return r.info
            }
        }
        return nil
    }

    func request(_ ip: String) {
        guard enabled, Net.scope(of: ip) == .internet else { return }
        if let b = Net.v4Bytes(ip), b[0] == 17 { return }
        lock.lock()
        if byIP[ip] != nil || pending.contains(ip) || requestCount >= 500 { lock.unlock(); return }
        pending.insert(ip); requestCount += 1
        lock.unlock()
        queue.async { [self] in
            // Une requête à la fois, espacées, pour rester poli avec le service.
            let info = self.fetch(ip)
            lock.lock(); byIP[ip] = .some(info); pending.remove(ip); lock.unlock()
            if info != nil { onResolved?() }
            Thread.sleep(forTimeInterval: 0.35)
        }
    }

    private func fetch(_ ip: String) -> OwnerInfo? {
        guard let url = URL(string: "https://rdap.org/ip/\(Net.stripZone(ip))") else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var result: OwnerInfo?
        let task = session.dataTask(with: url) { [self] data, resp, _ in
            defer { sem.signal() }
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let parsed = Self.parse(j)
            result = parsed.info
            if let info = parsed.info, let lo = parsed.lo, let hi = parsed.hi {
                lock.lock(); ranges.append(Range(lo: lo, hi: hi, info: info)); lock.unlock()
            }
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 12)
        return result
    }

    static func parse(_ j: [String: Any]) -> (info: OwnerInfo?, lo: [UInt8]?, hi: [UInt8]?) {
        var name = j["name"] as? String
        // Préférer le nom lisible de l'organisation déclarée
        if let ents = j["entities"] as? [[String: Any]] {
            // Le titulaire (« registrant ») d'abord, les contacts administratifs/techniques seulement à défaut.
            search: for role in ["registrant", "administrative", "technical"] {
                for e in ents where (e["roles"] as? [String] ?? []).contains(role) {
                    guard let v = e["vcardArray"] as? [Any], v.count > 1, let props = v[1] as? [[Any]] else { continue }
                    for p in props where (p.first as? String) == "fn" {
                        if p.count > 3, let fn = p[3] as? String, !fn.isEmpty { name = fn; break search }
                    }
                }
            }
        }
        guard let n = name else { return (nil, nil, nil) }
        let country = j["country"] as? String
        let lo = (j["startAddress"] as? String).flatMap { Net.v4Bytes($0) ?? Net.v6Bytes($0) }
        let hi = (j["endAddress"] as? String).flatMap { Net.v4Bytes($0) ?? Net.v6Bytes($0) }
        return (OwnerInfo(name: n, country: country), lo, hi)
    }
}
