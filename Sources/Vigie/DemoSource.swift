import Foundation

/// Mode démonstration : trafic entièrement FICTIF, pour essayer l'app sans rien exposer de votre Mac
/// et pour les captures d'écran. Les adresses utilisées sont celles réservées à la documentation
/// (192.0.2.x, 198.51.100.x, 203.0.113.x) et les noms de domaine finissent par « exemple.* ».
final class DemoSource {
    struct Dest {
        var ip: String
        var host: String
        var port: Int
        var proto = "TCP"
        var weightIn = 1.0
        var weightOut = 1.0
    }

    struct DemoApp {
        var pid: Int32
        var name: String
        var paths: [String]
        var system = false
        var dests: [Dest]
        var pool: [Dest] = []          // sites « de passage » qui s'ouvrent et se ferment (navigation)
        var profile: (Int) -> (Double, Double)   // (reçu, envoyé) en octets/s à l'instant t
    }

    private struct Conn {
        var pid: Int32
        var dest: Dest
        var cumIn: UInt64 = 0
        var cumOut: UInt64 = 0
        var local: Int
        var dieAt: Int?
    }

    private var t = 0
    private var apps: [DemoApp] = []
    private var conns: [Conn] = []
    private var procCum: [Int32: (UInt64, UInt64)] = [:]
    private var nextLocalPort = 50000
    private var lastDown: UInt64 = 0, lastUp: UInt64 = 0
    private var identityByPid: [Int32: AppIdentity] = [:]
    private(set) var hostNames: [String: String] = [:]
    private(set) var owners: [String: OwnerInfo] = [:]

    private func firstExisting(_ paths: [String]) -> String? {
        paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func noise(_ amp: Double) -> Double { Double.random(in: 0...amp) }

    init() {
        let bursty: (Int) -> (Double, Double) = { t in
            let burst = (t % 11) < 3 ? 1_400_000.0 : 0
            let i = 25_000 + burst * Double.random(in: 0.4...1.2) + Double.random(in: 0...60_000)
            return (i, i * 0.05 + 800)
        }
        let pool = (1...12).map { n -> Dest in
            let names = ["www.exemple.org", "cdn.exemple-images.net", "actualites.exemple.fr", "video.exemple-stream.com",
                         "api.exemple.io", "boutique.exemple.fr", "forum.exemple.org", "meteo.exemple.fr",
                         "tuiles-carte.exemple.net", "recettes.exemple.fr", "encyclo.exemple.org", "pixel.exemple-pub.com"]
            return Dest(ip: "203.0.113.\(10 + n)", host: names[n - 1], port: 443)
        }
        apps = [
            DemoApp(pid: 1201, name: "Safari", paths: ["/Applications/Safari.app", "/System/Cryptexes/App/System/Applications/Safari.app"],
                    dests: [Dest(ip: "203.0.113.10", host: "moteur-recherche.exemple.fr", port: 443)], pool: pool, profile: bursty),
            DemoApp(pid: 1210, name: "Mail", paths: ["/System/Applications/Mail.app"],
                    dests: [Dest(ip: "198.51.100.21", host: "imap.exemple.fr", port: 993),
                            Dest(ip: "198.51.100.22", host: "smtp.exemple.fr", port: 587, weightIn: 0.1, weightOut: 3)],
                    profile: { t in (4_000 + (t % 20 == 0 ? 220_000 : 0) + Double.random(in: 0...3_000), 900 + (t % 20 == 0 ? 40_000 : 0)) }),
            DemoApp(pid: 1220, name: "Messages", paths: ["/System/Applications/Messages.app"],
                    dests: [Dest(ip: "198.51.100.40", host: "notifications.exemple.net", port: 5223)],
                    profile: { t in (2_000 + (t % 13 == 0 ? 60_000 : 0), 1_500 + (t % 13 == 0 ? 30_000 : 0)) }),
            DemoApp(pid: 1230, name: "Musique", paths: ["/System/Applications/Music.app"],
                    dests: [Dest(ip: "198.51.100.60", host: "audio.exemple-musique.fr", port: 443, weightIn: 6, weightOut: 1),
                            Dest(ip: "198.51.100.61", host: "pochettes.exemple-musique.fr", port: 443)],
                    profile: { _ in (42_000 + Double.random(in: 0...12_000), 1_800) }),
            DemoApp(pid: 1240, name: "Photos", paths: ["/System/Applications/Photos.app"],
                    dests: [Dest(ip: "203.0.113.80", host: "stockage.exemple-cloud.fr", port: 443, weightIn: 0.2, weightOut: 4),
                            Dest(ip: "203.0.113.81", host: "synchro.exemple-cloud.fr", port: 443)],
                    profile: { t in (t % 70 < 35) ? (30_000, 650_000 + Double.random(in: 0...200_000)) : (3_000, 2_000) }),
            DemoApp(pid: 1250, name: "App Store", paths: ["/System/Applications/App Store.app"],
                    dests: [Dest(ip: "198.51.100.90", host: "telechargements.exemple-apps.net", port: 443, weightIn: 8, weightOut: 0.3)],
                    profile: { t in (t % 45 < 12) ? (1_800_000 + Double.random(in: 0...500_000), 40_000) : (1_000, 600) }),
            DemoApp(pid: 1260, name: "DocuNuage", paths: [],
                    dests: [Dest(ip: "192.0.2.77", host: "synchro.docunuage.exemple.com", port: 443, weightIn: 0.3, weightOut: 5),
                            Dest(ip: "192.0.2.78", host: "telemetrie.docunuage.exemple.com", port: 443, weightIn: 0.05, weightOut: 1)],
                    profile: { _ in (9_000 + Double.random(in: 0...4_000), 170_000 + Double.random(in: 0...50_000)) }),
            DemoApp(pid: 1300, name: "softwareupdated", paths: [], system: true,
                    dests: [Dest(ip: "198.51.100.120", host: "mises-a-jour.exemple.net", port: 443, weightIn: 10, weightOut: 0.2)],
                    profile: { t in (t % 100 > 55 && t % 100 < 85) ? (900_000, 12_000) : (600, 300) }),
            DemoApp(pid: 1310, name: "Time Machine", paths: ["/System/Applications/Time Machine.app"], system: true,
                    dests: [Dest(ip: "192.168.1.20", host: "nas-salon.local", port: 445, weightIn: 0.2, weightOut: 6)],
                    profile: { t in (t % 90 < 40) ? (60_000, 2_300_000 + Double.random(in: 0...600_000)) : (500, 300) }),
            DemoApp(pid: 1320, name: "cloudd", paths: [], system: true,
                    dests: [Dest(ip: "198.51.100.150", host: "icloud.exemple.net", port: 443)],
                    profile: { _ in (14_000 + Double.random(in: 0...6_000), 9_000 + Double.random(in: 0...3_000)) }),
            DemoApp(pid: 1330, name: "mDNSResponder", paths: [], system: true,
                    dests: [Dest(ip: "192.168.1.1", host: "box-internet.local", port: 53, proto: "UDP"),
                            Dest(ip: "224.0.0.251", host: "", port: 5353, proto: "UDP")],
                    profile: { _ in (3_000 + Double.random(in: 0...2_000), 1_500 + Double.random(in: 0...800)) }),
        ]

        // Identités (nom + icône) : on réutilise les vraies apps Apple présentes sur le Mac.
        for a in apps {
            let path = firstExisting(a.paths)
            let key = path ?? "proc:\(a.name)"
            identityByPid[a.pid] = AppIdentity(key: key, name: a.name, path: path, isSystem: a.system)
        }
        for (pid, name, path) in [(Int32(1340), "Centre de contrôle", "/System/Library/CoreServices/ControlCenter.app"),
                                  (1350, "smbd", ""), (1360, "node", ""), (1370, "rapportd", "")] {
            let ok = !path.isEmpty && FileManager.default.fileExists(atPath: path)
            identityByPid[pid] = AppIdentity(key: ok ? path : "proc:\(name)", name: name, path: ok ? path : nil, isSystem: name != "node")
        }

        for a in apps {
            for d in a.dests + a.pool where !d.host.isEmpty { hostNames[d.ip] = d.host }
            for d in a.dests + a.pool {
                if d.ip.hasPrefix("203.0.113.") { owners[d.ip] = OwnerInfo(name: "Exemple Hébergement SA", country: "FR") }
                if d.ip.hasPrefix("198.51.100.") { owners[d.ip] = OwnerInfo(name: "Réseau Exemple Télécom", country: "FR") }
                if d.ip.hasPrefix("192.0.2.") { owners[d.ip] = OwnerInfo(name: "DocuNuage Inc.", country: "US") }
            }
        }
        for a in apps { procCum[a.pid] = (UInt64.random(in: 5_000_000...900_000_000), UInt64.random(in: 1_000_000...300_000_000)) }

        // Connexions initiales (permanentes)
        for a in apps {
            for d in a.dests { conns.append(Conn(pid: a.pid, dest: d, local: newPort(), dieAt: nil)) }
        }
    }

    private func newPort() -> Int { nextLocalPort += Int.random(in: 1...9); return nextLocalPort }

    func identity(pid: Int32) -> AppIdentity? { identityByPid[pid] }

    // MARK: - Échantillons

    func nextSample() -> Sample {
        t += 1
        // Navigation : un nouveau site s'ouvre de temps en temps, puis se ferme
        if t % 7 == 3, let safari = apps.first(where: { $0.pid == 1201 }) {
            let open = Set(conns.filter { $0.pid == 1201 }.map { $0.dest.ip })
            if let d = safari.pool.filter({ !open.contains($0.ip) }).randomElement() {
                conns.append(Conn(pid: 1201, dest: d, local: newPort(), dieAt: t + Int.random(in: 18...45)))
            }
        }
        conns.removeAll { $0.dieAt != nil && $0.dieAt! <= t }

        var sample = Sample(date: Date())
        var downTotal: UInt64 = 0, upTotal: UInt64 = 0

        for a in apps {
            var (rin, rout) = a.profile(t)
            rin *= Double.random(in: 0.85...1.15); rout *= Double.random(in: 0.85...1.15)
            let mine = conns.indices.filter { conns[$0].pid == a.pid }
            let wIn = mine.reduce(0) { $0 + conns[$1].dest.weightIn }
            let wOut = mine.reduce(0) { $0 + conns[$1].dest.weightOut }
            var appIn: UInt64 = 0, appOut: UInt64 = 0
            for i in mine {
                let dIn = UInt64(max(0, rin * conns[i].dest.weightIn / max(wIn, 0.0001)))
                let dOut = UInt64(max(0, rout * conns[i].dest.weightOut / max(wOut, 0.0001)))
                conns[i].cumIn += dIn; conns[i].cumOut += dOut
                appIn += dIn; appOut += dOut
            }
            var c = procCum[a.pid] ?? (0, 0)
            c.0 += appIn; c.1 += appOut
            procCum[a.pid] = c
            // Ce qui part vers le réseau local ne passe pas par Internet, mais passe par le Wi-Fi : on le compte aussi.
            downTotal += appIn; upTotal += appOut
            sample.procs.append(ProcSample(name: a.name, pid: a.pid, bytesIn: c.0, bytesOut: c.1))
            for i in mine {
                let cn = conns[i]
                let v6 = cn.dest.ip.contains(":")
                sample.conns.append(ConnSample(
                    pid: cn.pid, proto: cn.dest.proto, family: v6 ? 6 : 4, localAddr: "192.168.1.23", localPort: cn.local,
                    remoteAddr: cn.dest.ip, remotePort: cn.dest.port,
                    state: cn.dest.proto == "TCP" ? "Established" : "", bytesIn: cn.cumIn, bytesOut: cn.cumOut))
            }
        }
        lastDown = downTotal; lastUp = upTotal

        // Ports en écoute (fictifs)
        let listens: [(Int32, String, String, Int)] = [
            (1330, "UDP", "*", 5353), (1340, "TCP", "*", 7000), (1340, "TCP", "*", 5000),
            (1350, "TCP", "*", 445), (1360, "TCP", "127.0.0.1", 3000), (1370, "TCP", "*", 49152),
        ]
        for (pid, proto, addr, port) in listens {
            if !sample.procs.contains(where: { $0.pid == pid }) {
                sample.procs.append(ProcSample(name: identityByPid[pid]?.name ?? "?", pid: pid, bytesIn: 0, bytesOut: 0))
            }
            sample.conns.append(ConnSample(pid: pid, proto: proto, family: 4, localAddr: addr, localPort: port,
                                           remoteAddr: nil, remotePort: nil, state: proto == "TCP" ? "Listen" : "", bytesIn: 0, bytesOut: 0))
        }
        return sample
    }

    func interfaceDeltas(procs: [ProcSample]) -> (UInt64, UInt64) { (lastDown, lastUp) }

    func latency(base: Double) -> Double { base + Double.random(in: -0.8...2.2) }

    func nextDNS() -> DNSLineParser.Event? {
        guard let a = apps.randomElement(), let d = (a.dests + a.pool).filter({ !$0.host.isEmpty && !$0.host.hasSuffix(".local") }).randomElement() else { return nil }
        return DNSLineParser.Event(name: d.host, type: Bool.random() ? "A" : "AAAA", answers: [d.ip])
    }

    // MARK: - Faux réseau

    func network() -> NetworkSnapshot {
        var n = NetworkSnapshot()
        n.hostName = "Mac de démonstration"
        n.gateway = "192.168.1.1"
        n.dnsServers = ["192.168.1.1", "9.9.9.9"]
        n.interfaces = [InterfaceInfo(name: "en0", label: "Wi-Fi", ipv4: "192.168.1.23", ipv6: "2001:db8:1234::23", isDefault: true)]
        n.wifi = WiFiInfo(rssi: -54, noise: -92, txRate: 866, channel: "44", band: "5 GHz")
        return n
    }

    func devices() -> [DeviceRow] {
        let now = Date()
        func d(_ ip: String, _ mac: String, _ name: String?, gw: Bool = false, me: Bool = false, rnd: Bool = false, age: TimeInterval = 3600) -> DeviceRow {
            DeviceRow(id: mac, ip: ip, mac: mac, name: name, isGateway: gw, isThisMac: me, randomMAC: rnd,
                      firstSeen: now.addingTimeInterval(-age), lastSeen: now)
        }
        return [
            d("192.168.1.1", "00:00:5e:00:53:01", "box-internet.local", gw: true),
            d("192.168.1.20", "00:00:5e:00:53:20", "nas-salon.local"),
            d("192.168.1.23", "—", "Mac de démonstration", me: true),
            d("192.168.1.31", "02:00:5e:00:53:31", "iphone-d-alex.local", rnd: true),
            d("192.168.1.40", "00:00:5e:00:53:40", "imprimante-bureau.local"),
            d("192.168.1.45", "00:00:5e:00:53:45", "tv-salon.local"),
            d("192.168.1.52", "00:00:5e:00:53:52", "diffuseur-chambre.local"),
            d("192.168.1.61", "00:00:5e:00:53:61", nil),
            d("192.168.1.77", "06:00:5e:00:53:77", nil, rnd: true, age: 40),
        ]
    }
}
