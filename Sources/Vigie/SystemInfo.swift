import Foundation
import CoreWLAN
import Darwin

struct InterfaceInfo: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var label: String          // « Wi-Fi », « Ethernet »…
    var ipv4: String?
    var ipv6: String?
    var isDefault: Bool
}

struct WiFiInfo: Hashable {
    var rssi: Int
    var noise: Int
    var txRate: Double
    var channel: String
    var band: String
}

struct NetworkSnapshot {
    var interfaces: [InterfaceInfo] = []
    var gateway: String?
    var dnsServers: [String] = []
    var wifi: WiFiInfo?
    var hostName: String = ""
}

enum SystemInfo {
    static func snapshot() -> NetworkSnapshot {
        var snap = NetworkSnapshot()
        snap.hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

        // Noms « humains » des interfaces
        var labels: [String: String] = [:]
        var currentLabel: String?
        for l in Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"]).split(separator: "\n") {
            if l.hasPrefix("Hardware Port:") { currentLabel = l.dropFirst(14).trimmingCharacters(in: .whitespaces) }
            if l.hasPrefix("Device:"), let cl = currentLabel { labels[l.dropFirst(7).trimmingCharacters(in: .whitespaces)] = cl }
        }

        // Interface par défaut + passerelle
        var defaultIface: String?
        for l in Shell.run("/sbin/route", ["-n", "get", "default"]).split(separator: "\n") {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("gateway:") { snap.gateway = t.dropFirst(8).trimmingCharacters(in: .whitespaces) }
            if t.hasPrefix("interface:") { defaultIface = t.dropFirst(10).trimmingCharacters(in: .whitespaces) }
        }

        // Adresses IP par interface
        var v4: [String: String] = [:], v6: [String: String] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ptr) == 0, let first = ptr {
            var cur: UnsafeMutablePointer<ifaddrs>? = first
            while let p = cur {
                let a = p.pointee; cur = a.ifa_next
                guard let sa = a.ifa_addr else { continue }
                let name = String(cString: a.ifa_name)
                let fam = Int32(sa.pointee.sa_family)
                guard fam == AF_INET || fam == AF_INET6, Int32(a.ifa_flags) & IFF_UP != 0 else { continue }
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let s = String(cString: buf)
                    if fam == AF_INET { v4[name] = s }
                    else if Net.scope(of: s) == .internet || (v6[name] == nil && Net.scope(of: s) == .lan) { v6[name] = Net.stripZone(s) }
                }
            }
            freeifaddrs(ptr)
        }
        let names = Set(v4.keys).union(v6.keys).filter { $0 != "lo0" && ($0.hasPrefix("en") || $0.hasPrefix("utun") || $0.hasPrefix("pdp_ip") || $0.hasPrefix("bridge")) }
        // On masque les interfaces sans adresse IPv4 ni IPv6 publique/locale utile
        snap.interfaces = names.sorted().compactMap { n in
            guard v4[n] != nil || v6[n] != nil else { return nil }
            // Les tunnels système de macOS (utun0…) n'ont qu'une adresse « fe80:: » sans intérêt : on les masque.
            if n.hasPrefix("utun"), v4[n] == nil { return nil }
            let label = labels[n] ?? (n.hasPrefix("utun") ? "Tunnel / VPN" : n)
            return InterfaceInfo(name: n, label: label, ipv4: v4[n], ipv6: v6[n], isDefault: n == defaultIface)
        }.sorted { ($0.isDefault ? 0 : 1, $0.name) < ($1.isDefault ? 0 : 1, $1.name) }

        // Serveurs DNS
        var dns: [String] = []
        for l in Shell.run("/usr/sbin/scutil", ["--dns"]).split(separator: "\n") {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("nameserver[") , let r = t.range(of: ": ") {
                let ip = String(t[r.upperBound...])
                if !dns.contains(ip) { dns.append(ip) }
            }
        }
        snap.dnsServers = dns

        // Wi-Fi (signal, débit) — le nom du réseau (SSID) demande l'autorisation de localisation : on ne l'utilise pas.
        if let w = CWWiFiClient.shared().interface(), w.powerOn(), w.rssiValue() != 0 {
            let ch = w.wlanChannel()
            var band = ""
            if let ch { band = ch.channelBand == .band2GHz ? "2,4 GHz" : (ch.channelBand == .band5GHz ? "5 GHz" : "6 GHz") }
            snap.wifi = WiFiInfo(rssi: w.rssiValue(), noise: w.noiseMeasurement(), txRate: w.transmitRate(),
                                 channel: ch.map { "\($0.channelNumber)" } ?? "—", band: band)
        }
        return snap
    }

    /// Latence (ms) vers une adresse via le `ping` du système ; nil si pas de réponse.
    static func ping(_ host: String) -> Double? {
        let out = Shell.run("/sbin/ping", ["-c", "1", "-W", "1500", host], timeout: 4)
        guard let r = out.range(of: "time=") else { return nil }
        let tail = out[r.upperBound...].prefix { $0.isNumber || $0 == "." }
        return Double(tail)
    }
}
