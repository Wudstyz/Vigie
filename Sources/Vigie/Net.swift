import Foundation
import Darwin

// MARK: - Adresses IP

enum Net {
    /// Retire la « zone » IPv6 (ex. fe80::1%en0 -> fe80::1).
    static func stripZone(_ s: String) -> String {
        if let i = s.firstIndex(of: "%") { return String(s[..<i]) }
        return s
    }

    static func v4Bytes(_ s: String) -> [UInt8]? {
        var a = in_addr()
        guard inet_pton(AF_INET, s, &a) == 1 else { return nil }
        return withUnsafeBytes(of: &a) { Array($0) }
    }

    static func v6Bytes(_ s: String) -> [UInt8]? {
        var a = in6_addr()
        guard inet_pton(AF_INET6, stripZone(s), &a) == 1 else { return nil }
        return withUnsafeBytes(of: &a) { Array($0) }
    }

    /// Classe une adresse : Internet, réseau local, ce Mac, diffusion…
    static func scope(of address: String?) -> Scope {
        guard let address, !address.isEmpty, address != "*" else { return .wildcard }
        if let b = v4Bytes(address) { return scopeV4(b) }
        if let b = v6Bytes(address) {
            if b.allSatisfy({ $0 == 0 }) { return .wildcard }
            if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return .loopback }
            if b[0] == 0xff { return .multicast }
            if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return .lan }      // fe80::/10
            if (b[0] & 0xfe) == 0xfc { return .lan }                      // fc00::/7
            if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff {
                return scopeV4(Array(b[12..<16]))                         // ::ffff:a.b.c.d
            }
            return .internet
        }
        return .internet
    }

    private static func scopeV4(_ b: [UInt8]) -> Scope {
        if b[0] == 0 { return .wildcard }
        if b[0] == 127 { return .loopback }
        if b[0] >= 224 && b[0] <= 239 { return .multicast }
        if b == [255, 255, 255, 255] { return .multicast }
        if b[0] == 10 { return .lan }
        if b[0] == 172 && (16...31).contains(b[1]) { return .lan }
        if b[0] == 192 && b[1] == 168 { return .lan }
        if b[0] == 169 && b[1] == 254 { return .lan }
        if b[0] == 100 && (64...127).contains(b[1]) { return .lan }       // CGNAT / Tailscale
        return .internet
    }

    /// Le Mac peut être contacté depuis un autre appareil sur cette adresse d'écoute ?
    static func isExposed(listenAddress a: String) -> Bool {
        let s = scope(of: a)
        return s != .loopback
    }

    // MARK: Adresse « ip:port » telle qu'écrite par nettop

    /// Sépare « 1.2.3.4:443 », « fe80::1%en0.443 », « *:53 », « *.* ».
    static func splitEndpoint(_ s: String) -> (addr: String, port: Int?) {
        let colonCount = s.filter { $0 == ":" }.count
        let sepIndex: String.Index?
        if colonCount == 1 { sepIndex = s.lastIndex(of: ":") }   // IPv4 ou joker
        else { sepIndex = s.lastIndex(of: ".") }                  // IPv6 : le port suit le dernier point
        guard let i = sepIndex else { return (s, nil) }
        let addr = String(s[..<i])
        let portStr = String(s[s.index(after: i)...])
        return (addr, Int(portStr))
    }

    // MARK: Ports connus

    static func service(port: Int?, proto: String) -> String {
        guard let port, port > 0 else { return "—" }
        if port == 443 { return proto == "UDP" ? "HTTPS / QUIC (443)" : "HTTPS (443)" }
        if let n = knownPorts[port] { return "\(n) (\(port))" }
        return "\(port)"
    }

    static let knownPorts: [Int: String] = [
        20: "FTP données", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "Courrier (SMTP)", 53: "DNS", 67: "DHCP", 68: "DHCP",
        80: "Web (HTTP)", 110: "Courrier (POP3)", 123: "Heure (NTP)", 137: "NetBIOS", 138: "NetBIOS", 139: "NetBIOS",
        143: "Courrier (IMAP)", 161: "SNMP", 389: "LDAP", 445: "Partage Windows (SMB)", 465: "Courrier (SMTPS)",
        500: "VPN (IKE)", 514: "Syslog", 548: "Partage Apple (AFP)", 587: "Courrier (envoi)", 631: "Impression (IPP)",
        636: "LDAPS", 853: "DNS chiffré", 993: "Courrier (IMAPS)", 995: "Courrier (POP3S)", 1194: "VPN (OpenVPN)",
        1701: "VPN (L2TP)", 1883: "MQTT", 1900: "Découverte (UPnP)", 3000: "Dév. web", 3283: "Apple Remote Desktop",
        3306: "MySQL", 3478: "Appels (STUN)", 3689: "iTunes (DAAP)", 4500: "VPN (NAT-T)", 5000: "AirPlay / UPnP",
        5060: "Téléphonie (SIP)", 5222: "Messagerie (XMPP)", 5223: "Notifications Apple (APNs)",
        5228: "Notifications Google", 5353: "Bonjour (mDNS)", 5432: "PostgreSQL", 5900: "Partage d'écran (VNC)",
        6379: "Redis", 7000: "AirPlay", 8000: "Web (alt.)", 8080: "Web (alt.)", 8443: "HTTPS (alt.)",
        8883: "MQTT chiffré", 9100: "Imprimante", 27017: "MongoDB", 51820: "VPN (WireGuard)",
    ]

    // MARK: Compteurs des interfaces réseau

    struct IfaceCounters {
        var name: String
        var bytesIn: UInt32
        var bytesOut: UInt32
    }

    /// Compteurs (32 bits) des interfaces physiques actives : Wi-Fi, Ethernet, données mobiles.
    /// Les interfaces VPN/virtuelles sont ignorées pour ne pas compter deux fois le même trafic.
    static func interfaceCounters() -> [IfaceCounters] {
        var result: [IfaceCounters] = []
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0, let first = ptr else { return [] }
        defer { freeifaddrs(ptr) }
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            let ifa = p.pointee
            cur = ifa.ifa_next
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            result.append(IfaceCounters(name: name, bytesIn: d.ifi_ibytes, bytesOut: d.ifi_obytes))
        }
        return result
    }
}

// MARK: - Mise en forme (français)

enum Fmt {
    private static func num(_ x: Double) -> String {
        let s = x >= 100 ? String(format: "%.0f", x) : (x >= 10 ? String(format: "%.1f", x) : String(format: "%.2f", x))
        return s.replacingOccurrences(of: ".", with: ",")
    }

    static func bytes(_ v: UInt64) -> String {
        let d = Double(v)
        if v < 1000 { return "\(v) o" }
        if d < 1e6 { return num(d / 1e3) + " Ko" }
        if d < 1e9 { return num(d / 1e6) + " Mo" }
        if d < 1e12 { return num(d / 1e9) + " Go" }
        return num(d / 1e12) + " To"
    }

    static func rate(_ v: Double) -> String {
        if v < 1 { return "0 o/s" }
        return bytes(UInt64(v)) + "/s"
    }

    /// Version courte pour la barre des menus.
    static func rateShort(_ v: Double) -> String {
        if v < 1000 { return String(format: "%.0f o/s", v) }
        if v < 1e6 { return String(format: "%.0f Ko/s", v / 1e3) }
        return num(v / 1e6) + " Mo/s"
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 3 { return "à l'instant" }
        if s < 60 { return "il y a \(s) s" }
        if s < 3600 { return "il y a \(s / 60) min" }
        if s < 86400 { return "il y a \(s / 3600) h" }
        return "il y a \(s / 86400) j"
    }

    static let clock: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm:ss"; return f
    }()
}
