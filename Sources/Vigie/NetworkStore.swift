import Foundation
import Observation

/// Réglages (mêmes clés que les @AppStorage de l'interface).
enum Prefs {
    static var resolveNames: Bool { UserDefaults.standard.object(forKey: "resolveNames") as? Bool ?? true }
    static var ownerLookup: Bool { UserDefaults.standard.object(forKey: "ownerLookup") as? Bool ?? false }
    static var pingInternet: Bool { UserDefaults.standard.object(forKey: "pingInternet") as? Bool ?? true }
    static var showMenuBar: Bool { UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true }
    static var vigilance: Bool { UserDefaults.standard.object(forKey: "vigilance") as? Bool ?? true }
    static var notify: Bool { UserDefaults.standard.object(forKey: "notify") as? Bool ?? true }
    static var sensitivity: Sensitivity { Sensitivity(rawValue: UserDefaults.standard.string(forKey: "sensitivity") ?? "") ?? .normal }
}

enum DNSMode { case off, starting, on }

@MainActor
@Observable
final class NetworkStore {
    // MARK: - État affiché par l'interface
    var apps: [AppRow] = []
    var destinations: [DestinationRow] = []
    var connections: [ConnectionRow] = []
    var listeners: [ListenerRow] = []
    var devices: [DeviceRow] = []
    var events: [EventRow] = []
    var dnsQueries: [DNSQuery] = []
    var history: [RatePoint] = []

    var rateDown: Double = 0
    var rateUp: Double = 0
    var totalDown: UInt64 = 0
    var totalUp: UInt64 = 0
    var network = NetworkSnapshot()
    var latencyGateway: Double?
    var latencyInternet: Double?
    var paused = false
    var isDemo = false
    var statusMessage: String?
    var scanning = false
    var lastScan: Date?
    var dnsMode: DNSMode = .off
    var dnsStatus: String?
    var sessionStart = Date()
    var lastSampleDate: Date?
    var alerts: [AlertRow] = []
    /// Non nil tant que Vigie apprend ce qui est « habituel » (première utilisation) : aucune « nouveauté » n'est signalée.
    var learningEnds: Date?

    // MARK: - Moteur interne
    @ObservationIgnored private let monitor = NettopMonitor()
    @ObservationIgnored private let identities = AppIdentityResolver()
    @ObservationIgnored private let hostResolver = HostResolver()
    @ObservationIgnored private let ownerResolver = OwnerResolver()
    @ObservationIgnored private let sniffer = DNSSniffer()
    @ObservationIgnored private var demo: DemoSource?
    @ObservationIgnored private var demoTimer: Timer?
    @ObservationIgnored private var slowTimer: Timer?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var engine: VigilanceEngine
    @ObservationIgnored private var lastNotified: [String: Date] = [:]

    init() {
        engine = VigilanceEngine(baseline: Baseline.load() ?? Baseline())
    }

    /// Moteur « réel » : reprend ce que Vigie a appris ; au tout premier usage réel, l'apprentissage commence maintenant.
    private func makeRealEngine() -> VigilanceEngine {
        if let b = Baseline.load() { return VigilanceEngine(baseline: b) }
        let e = VigilanceEngine(baseline: Baseline())
        e.baseline.save()
        return e
    }

    private struct AppAcc {
        var key: String, name: String
        var path: String?
        var isSystem: Bool
        var pids: Set<Int32> = []
        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        var rateIn = 0.0, rateOut = 0.0
        var conns = 0
        var lastActive = Date.distantPast
        var dests: [String: (totalIn: UInt64, totalOut: UInt64, last: Date)] = [:]
    }
    private struct DestAcc {
        var ip: String
        var scope: Scope
        var ports: Set<Int> = []
        var protos: Set<String> = []
        var apps: Set<String> = []
        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        var rateIn = 0.0, rateOut = 0.0
        var conns = 0
        var firstSeen: Date, lastSeen: Date
    }

    @ObservationIgnored private var appAcc: [String: AppAcc] = [:]
    @ObservationIgnored private var destAcc: [String: DestAcc] = [:]
    @ObservationIgnored private var prevProc: [Int32: (UInt64, UInt64)] = [:]
    @ObservationIgnored private var prevConn: [String: (UInt64, UInt64)] = [:]
    @ObservationIgnored private var knownListeners: Set<String> = []
    @ObservationIgnored private var prevIfaces: [String: Net.IfaceCounters] = [:]
    @ObservationIgnored private var hasBaseline = false
    @ObservationIgnored private var lastDate: Date?
    @ObservationIgnored private var dnsNames: [String: String] = [:]
    @ObservationIgnored private var lastConnRows: [ConnectionRow] = []
    @ObservationIgnored private var rebuildScheduled = false
    @ObservationIgnored private var lastScanNet: LANScanner.LocalNet?

    // MARK: - Démarrage / arrêt

    func start(demo wantDemo: Bool) {
        guard !started else { return }
        started = true
        hostResolver.onResolved = { [weak self] in Task { @MainActor in self?.scheduleRebuild() } }
        ownerResolver.onResolved = { [weak self] in Task { @MainActor in self?.scheduleRebuild() } }
        monitor.onSample = { [weak self] s in Task { @MainActor in self?.ingest(s) } }
        monitor.onProblem = { [weak self] m in Task { @MainActor in self?.statusMessage = m } }
        sniffer.onEvent = { [weak self] e in Task { @MainActor in self?.handleDNS(e) } }
        sniffer.onStatus = { [weak self] m in Task { @MainActor in self?.handleDNSStatus(m) } }
        setDemo(wantDemo)
    }

    func shutdown() {
        saveBaselineIfNeeded()
        monitor.stop()
        sniffer.stop()
        demoTimer?.invalidate()
        slowTimer?.invalidate()
    }

    func setDemo(_ on: Bool) {
        isDemo = on
        monitor.stop()
        demoTimer?.invalidate(); slowTimer?.invalidate()
        resetAll()
        statusMessage = nil
        if on {
            let d = DemoSource()
            demo = d
            engine = VigilanceEngine(baseline: d.baseline())     // en démo : rien n'est lu ni écrit sur le disque
            network = d.network()
            devices = d.devices()
            lastScan = Date()
            checkDevices(now: Date(), gatewayIP: "192.168.1.1")
            demoTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let d = self.demo else { return }
                    self.ingest(d.nextSample())
                    self.latencyGateway = d.latency(base: 2.5)
                    self.latencyInternet = d.latency(base: 14)
                    if Int.random(in: 0..<6) == 0, let q = d.nextDNS() { self.handleDNS(q) }
                }
            }
            let warm = 70
            for i in 0..<warm {   // chauffe : graphique, journal et alertes ont déjà du contenu à l'ouverture
                var s = d.nextSample()
                s.date = Date().addingTimeInterval(Double(i - warm))
                ingest(s)
            }
            dnsMode = .on
            dnsStatus = "Mode démonstration : requêtes DNS fictives."
        } else {
            demo = nil
            engine = makeRealEngine()
            if dnsMode == .on { dnsMode = .off; dnsStatus = nil }
            monitor.start()
            refreshNetwork()
            slowTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.slowTick() }
            }
        }
    }

    private func resetAll() {
        apps = []; destinations = []; connections = []; listeners = []; devices = []; events = []
        dnsQueries = []; history = []; dnsNames = [:]; alerts = []; learningEnds = nil; lastNotified = [:]
        appAcc = [:]; destAcc = [:]; prevProc = [:]; prevConn = [:]; knownListeners = []; prevIfaces = [:]
        hasBaseline = false; lastDate = nil
        rateDown = 0; rateUp = 0; totalDown = 0; totalUp = 0
        latencyGateway = nil; latencyInternet = nil
        sessionStart = Date()
        lastScan = nil
    }

    func togglePause() {
        paused.toggle()
        if !paused {   // on repart d'une base propre : ce qui s'est passé pendant la pause n'est pas compté
            prevProc = [:]; prevConn = [:]; hasBaseline = false; lastDate = nil; prevIfaces = [:]
        }
    }

    // MARK: - Tâches lentes (réseau local, latence)

    private var slowCount = 0
    private func slowTick() {
        slowCount += 1
        let gw = network.gateway
        let wantInternet = Prefs.pingInternet
        Task.detached(priority: .utility) { [store = self] in
            let g = gw.flatMap { SystemInfo.ping($0) }
            let i = wantInternet ? SystemInfo.ping("1.1.1.1") : nil
            await MainActor.run { store.latencyGateway = g; store.latencyInternet = i; store.runHealth() }
        }
        saveBaselineIfNeeded()
        if slowCount % 5 == 0 { refreshNetwork() }
        if slowCount % 20 == 0, lastScan != nil { scanLAN() }   // re-scan toutes les ~2 min une fois lancé
    }

    func refreshNetwork() {
        Task.detached(priority: .utility) { [store = self] in
            let snap = SystemInfo.snapshot()
            await MainActor.run { store.network = snap }
        }
    }

    // MARK: - Appareils du réseau local

    func scanLAN() {
        guard !scanning else { return }
        if isDemo { lastScan = Date(); return }
        guard let net = LANScanner.localNet() else { statusMessage = "Pas de réseau local détecté."; return }
        scanning = true
        lastScanNet = net
        LANScanner.scan(net: net) { [weak self] found in
            Task { @MainActor in self?.mergeDevices(found, net: net) }
        }
    }

    private func mergeDevices(_ found: [LANScanner.Found], net: LANScanner.LocalNet) {
        let now = Date()
        let firstScan = lastScan == nil
        var byMac = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        // Ce Mac figure souvent dans sa propre table ARP : on le traite à part pour ne l'afficher qu'une fois.
        let selfEntry = found.first { $0.ip == net.ip }
        let found = found.filter { $0.ip != net.ip }
        for f in found {
            if var d = byMac[f.mac] {
                d.ip = f.ip; d.lastSeen = now
                if let n = f.name { d.name = n }
                d.isGateway = f.ip == net.gateway; d.isThisMac = f.ip == net.ip
                byMac[f.mac] = d
            } else {
                let d = DeviceRow(id: f.mac, ip: f.ip, mac: f.mac, name: f.name, isGateway: f.ip == net.gateway,
                                  isThisMac: f.ip == net.ip, randomMAC: LANScanner.isRandomMAC(f.mac), firstSeen: now, lastSeen: now)
                byMac[f.mac] = d
                if !firstScan { addEvent(.newDevice, "Nouvel appareil sur le réseau", "\(f.name ?? f.ip) · \(f.mac)") }
            }
        }
        let selfID = "self"
        let selfMAC = selfEntry?.mac ?? "—"
        byMac[selfID] = DeviceRow(id: selfID, ip: net.ip, mac: selfMAC, name: network.hostName, isGateway: false, isThisMac: true,
                                  randomMAC: selfEntry.map { LANScanner.isRandomMAC($0.mac) } ?? false,
                                  firstSeen: byMac[selfID]?.firstSeen ?? now, lastSeen: now)
        devices = byMac.values.sorted { Self.ipOrder($0.ip) < Self.ipOrder($1.ip) }
        lastScan = now
        scanning = false
        checkDevices(now: now, gatewayIP: net.gateway)
    }

    private func checkDevices(now: Date, gatewayIP: String?) {
        let obs = devices.map { DeviceObs(mac: $0.mac, ip: $0.ip, name: $0.name, randomMAC: $0.randomMAC, isThisMac: $0.isThisMac) }
        absorb(engine.evaluateDevices(now: now, devices: obs, gatewayIP: gatewayIP), now: now)
    }

    private static func ipOrder(_ ip: String) -> UInt32 {
        guard let b = Net.v4Bytes(ip) else { return 0 }
        return b.reduce(0) { $0 << 8 | UInt32($1) }
    }

    // MARK: - DNS (mode avancé)

    func enableAdvancedDNS() {
        guard !isDemo, dnsMode == .off else { return }
        dnsMode = .starting
        dnsStatus = "En attente de votre autorisation…"
        sniffer.start()
    }

    func disableAdvancedDNS() {
        sniffer.stop()
        dnsMode = .off
        dnsStatus = nil
    }

    private func handleDNSStatus(_ m: String) {
        dnsStatus = m
        if m.hasPrefix("Écoute") { dnsMode = .on }
        else if m.hasPrefix("Autorisation refusée") || m.hasPrefix("Impossible") || m.hasPrefix("Mode avancé arrêté") { dnsMode = .off }
    }

    private func handleDNS(_ e: DNSLineParser.Event) {
        if e.answers.isEmpty {
            dnsQueries.insert(DNSQuery(date: Date(), name: e.name, type: e.type, answers: []), at: 0)
        } else {
            for ip in e.answers { dnsNames[Net.stripZone(ip)] = e.name }
            if let i = dnsQueries.firstIndex(where: { $0.name == e.name && $0.answers.isEmpty }) {
                dnsQueries[i].answers = e.answers
            } else {
                dnsQueries.insert(DNSQuery(date: Date(), name: e.name, type: e.type, answers: e.answers), at: 0)
            }
        }
        if dnsQueries.count > 600 { dnsQueries.removeLast(dnsQueries.count - 600) }
        scheduleRebuild()
    }

    // MARK: - Ingestion d'un échantillon

    private func hostName(_ ip: String) -> String? {
        if let d = demo { return d.hostNames[ip] }
        return dnsNames[ip] ?? hostResolver.cached(ip)
    }
    private func owner(_ ip: String) -> OwnerInfo? {
        if let d = demo { return d.owners[ip] }
        return ownerResolver.cached(ip)
    }

    private func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rebuildScheduled = false
                self.rebuildOutputs()
            }
        }
    }

    func addEvent(_ kind: EventKind, _ title: String, _ detail: String) {
        events.insert(EventRow(date: Date(), kind: kind, title: title, detail: detail), at: 0)
        if events.count > 500 { events.removeLast(events.count - 500) }
    }

    private func identity(pid: Int32, name: String) -> AppIdentity {
        if let d = demo, let i = d.identity(pid: pid) { return i }
        return identities.identity(pid: pid, procName: name)
    }

    private func ingest(_ s: Sample) {
        if paused { return }
        let now = s.date
        lastSampleDate = now
        let dt = min(5, max(0.3, lastDate.map { now.timeIntervalSince($0) } ?? 1))
        lastDate = now
        let first = !hasBaseline
        hasBaseline = true
        statusMessage = nil

        for k in appAcc.keys { appAcc[k]!.rateIn = 0; appAcc[k]!.rateOut = 0; appAcc[k]!.conns = 0; appAcc[k]!.pids = [] }
        for k in destAcc.keys { destAcc[k]!.rateIn = 0; destAcc[k]!.rateOut = 0; destAcc[k]!.conns = 0 }

        // 1) Processus -> applications
        var pidName: [Int32: String] = [:]
        var newPrevProc: [Int32: (UInt64, UInt64)] = [:]
        for p in s.procs {
            pidName[p.pid] = p.name
            let id = identity(pid: p.pid, name: p.name)
            var a = appAcc[id.key] ?? AppAcc(key: id.key, name: id.name, path: id.path, isSystem: id.isSystem)
            var dIn: UInt64 = 0, dOut: UInt64 = 0
            if let prev = prevProc[p.pid] {
                dIn = p.bytesIn >= prev.0 ? p.bytesIn - prev.0 : 0
                dOut = p.bytesOut >= prev.1 ? p.bytesOut - prev.1 : 0
            } else if !first {
                dIn = p.bytesIn; dOut = p.bytesOut
            }
            a.totalIn += dIn; a.totalOut += dOut
            a.rateIn += Double(dIn) / dt; a.rateOut += Double(dOut) / dt
            a.pids.insert(p.pid)
            if dIn + dOut > 0 { a.lastActive = now }
            appAcc[id.key] = a
            newPrevProc[p.pid] = (p.bytesIn, p.bytesOut)
        }
        prevProc = newPrevProc

        // 2) Connexions -> destinations, ports en écoute
        var newPrevConn: [String: (UInt64, UInt64)] = [:]
        var connRows: [ConnectionRow] = []
        var listenRows: [String: ListenerRow] = [:]
        let resolveNames = Prefs.resolveNames
        ownerResolver.enabled = Prefs.ownerLookup && !isDemo
        // Pour la vigilance : trafic Internet par application, nouvelles adresses, ports à surveiller
        var inetDelta: [String: (out: UInt64, in: UInt64)] = [:]
        var inetIPs: [String: Set<String>] = [:]
        var inetConns: [String: Int] = [:]
        var connObs: [ConnObs] = []
        var listenObs: [ListenerObs] = []

        for c in s.conns {
            let pname = pidName[c.pid] ?? "?"
            let id = identity(pid: c.pid, name: pname)

            if c.isListening, let lp = c.localPort {
                // Les ports UDP « temporaires » (≥ 49152) sont ceux qu'ouvrent les applications clientes (DNS, QUIC…) :
                // ce ne sont pas des services qui attendent des connexions.
                if c.proto == "UDP" && lp >= 49152 { continue }
                let exposed = Net.isExposed(listenAddress: c.localAddr)
                let key = "\(id.key)|\(c.proto)|\(lp)|\(exposed)"
                if listenRows[key] == nil {
                    listenRows[key] = ListenerRow(
                        id: key, appName: id.name, pid: c.pid, proto: c.proto,
                        address: c.localAddr == "*" ? "toutes les interfaces" : c.localAddr, port: lp,
                        service: Net.service(port: lp, proto: c.proto), exposed: exposed)
                    listenObs.append(ListenerObs(key: key, appKey: id.key, appName: id.name, port: lp, exposed: exposed, isSystem: id.isSystem))
                    if !first && !knownListeners.contains(key) {
                        addEvent(.newListener, "\(id.name) ouvre le port \(lp)",
                                 "\(c.proto) · \(exposed ? "visible depuis le réseau" : "accessible depuis ce Mac uniquement")")
                    }
                    knownListeners.insert(key)
                }
                continue
            }
            guard let remote = c.remoteAddr else { continue }
            let ip = Net.stripZone(remote)
            let scope = Net.scope(of: ip)
            if scope == .wildcard { continue }

            let ck = c.key
            var dIn: UInt64 = 0, dOut: UInt64 = 0
            if let prev = prevConn[ck] {
                dIn = c.bytesIn >= prev.0 ? c.bytesIn - prev.0 : 0
                dOut = c.bytesOut >= prev.1 ? c.bytesOut - prev.1 : 0
            } else if !first {
                dIn = c.bytesIn; dOut = c.bytesOut
            }
            newPrevConn[ck] = (c.bytesIn, c.bytesOut)
            if scope == .internet {
                var t = inetDelta[id.key] ?? (0, 0)
                t.out += dOut; t.in += dIn
                inetDelta[id.key] = t
                inetIPs[id.key, default: []].insert(ip)
                inetConns[id.key, default: 0] += 1
                if let rp = c.remotePort, VigilanceEngine.suspiciousPorts.contains(rp) {
                    connObs.append(ConnObs(appKey: id.key, appName: id.name, remoteIP: ip, remotePort: rp, scope: scope))
                }
            }

            // destination
            var d = destAcc[ip] ?? DestAcc(ip: ip, scope: scope, firstSeen: now, lastSeen: now)
            let isNewDest = destAcc[ip] == nil
            d.ports.insert(c.remotePort ?? 0); d.protos.insert(c.proto); d.apps.insert(id.name)
            d.totalIn += dIn; d.totalOut += dOut
            d.rateIn += Double(dIn) / dt; d.rateOut += Double(dOut) / dt
            d.conns += 1; d.lastSeen = now
            destAcc[ip] = d
            if isNewDest, !first, scope == .internet || scope == .lan {
                let who = hostName(ip) ?? ip
                addEvent(.newDestination, "\(id.name) → \(who)", "\(Net.service(port: c.remotePort, proto: c.proto)) · \(scope.label)")
            }
            if resolveNames && (scope == .internet || scope == .lan) && !isDemo { hostResolver.request(ip) }
            if scope == .internet && !isDemo { ownerResolver.request(ip) }

            // application
            if var a = appAcc[id.key] {
                a.conns += 1
                var e = a.dests[ip] ?? (0, 0, now)
                e.totalIn += dIn; e.totalOut += dOut; e.last = now
                a.dests[ip] = e
                appAcc[id.key] = a
            }

            let remoteText = Self.endpoint(ip, c.remotePort)
            connRows.append(ConnectionRow(
                id: ck, pid: c.pid, appName: id.name, appKey: id.key, proto: c.proto,
                local: Self.endpoint(c.localAddr, c.localPort), remote: remoteText, remoteIP: ip, remotePort: c.remotePort,
                host: nil, service: Net.service(port: c.remotePort, proto: c.proto), scope: scope,
                state: Self.stateLabel(c.state, proto: c.proto), bytesIn: c.bytesIn, bytesOut: c.bytesOut,
                rateIn: Double(dIn) / dt, rateOut: Double(dOut) / dt))
        }
        prevConn = newPrevConn
        lastConnRows = connRows
        listeners = listenRows.values.sorted { ($0.exposed ? 0 : 1, $0.port) < ($1.exposed ? 0 : 1, $1.port) }

        // 3) Compteurs globaux des interfaces (débit réel du Mac, sans doublons)
        var dDown: UInt64 = 0, dUp: UInt64 = 0
        if isDemo, let d = demo {
            (dDown, dUp) = d.interfaceDeltas(procs: s.procs)
        } else {
            var cur: [String: Net.IfaceCounters] = [:]
            for i in Net.interfaceCounters() { cur[i.name] = i }
            for (n, i) in cur {
                if let p = prevIfaces[n] {
                    dDown += UInt64(i.bytesIn &- p.bytesIn); dUp += UInt64(i.bytesOut &- p.bytesOut)
                }
            }
            prevIfaces = cur
        }
        if !first {
            rateDown = Double(dDown) / dt; rateUp = Double(dUp) / dt
            totalDown += dDown; totalUp += dUp
            history.append(RatePoint(date: now, down: rateDown, up: rateUp))
            if history.count > 240 { history.removeFirst(history.count - 240) }
        }

        // 3 bis) Vigilance : repérer ce qui sort de l'ordinaire
        engine.sensitivity = Prefs.sensitivity
        let obs = appAcc.values.map { AppObs(key: $0.key, name: $0.name, path: $0.path, isSystem: $0.isSystem, internetActive: (inetConns[$0.key] ?? 0) > 0) }
        absorb(engine.evaluate(now: now, apps: obs, deltas: inetDelta, newInternetIPs: inetIPs, conns: connObs, listeners: listenObs), now: now)

        // 4) Nettoyage
        if destAcc.count > 3000 {
            let old = destAcc.values.filter { $0.conns == 0 }.sorted { $0.lastSeen < $1.lastSeen }.prefix(destAcc.count - 2500)
            for o in old { destAcc[o.ip] = nil }
        }
        rebuildOutputs()
    }

    // MARK: - Fabrication des tableaux pour l'interface

    private func rebuildOutputs() {
        let now = lastSampleDate ?? Date()
        apps = appAcc.values.compactMap { a -> AppRow? in
            guard a.conns > 0 || a.totalIn + a.totalOut > 0 else { return nil }
            return AppRow(id: a.key, name: a.name, path: a.path, isSystem: a.isSystem, pids: a.pids.sorted(),
                          rateIn: a.rateIn, rateOut: a.rateOut, totalIn: a.totalIn, totalOut: a.totalOut,
                          connectionCount: a.conns, destinationCount: a.dests.count, lastActive: a.lastActive == .distantPast ? now : a.lastActive)
        }.sorted { ($0.sortRate, $0.totalAll) > ($1.sortRate, $1.totalAll) }

        destinations = destAcc.values.map { d in
            let o = owner(d.ip)
            return DestinationRow(
                id: d.ip, ip: d.ip, scope: d.scope, host: hostName(d.ip), owner: o?.name, country: o?.country,
                ports: d.ports.filter { $0 > 0 }.sorted(), protocols: d.protos.sorted(), appNames: d.apps.sorted(),
                rateIn: d.rateIn, rateOut: d.rateOut, totalIn: d.totalIn, totalOut: d.totalOut,
                connectionCount: d.conns, firstSeen: d.firstSeen, lastSeen: d.lastSeen)
        }.sorted { ($0.sortRate, $0.totalOut + $0.totalIn) > ($1.sortRate, $1.totalOut + $1.totalIn) }

        connections = lastConnRows.map { r in
            var r = r
            if let ip = r.remoteIP { r.host = hostName(ip) }
            return r
        }.sorted { ($0.rateIn + $0.rateOut, $0.bytesIn + $0.bytesOut) > ($1.rateIn + $1.rateOut, $1.bytesIn + $1.bytesOut) }
    }

    /// Destinations contactées par une application, les plus gros volumes envoyés d'abord.
    func destinations(forApp key: String) -> [AppDestination] {
        guard let a = appAcc[key] else { return [] }
        return a.dests.map { ip, v in
            AppDestination(id: ip, ip: ip, host: hostName(ip), scope: Net.scope(of: ip), totalIn: v.totalIn, totalOut: v.totalOut, lastSeen: v.last)
        }.sorted { ($0.totalOut, $0.totalIn) > ($1.totalOut, $1.totalIn) }
    }

    // MARK: - Vigilance

    /// Alertes à afficher : non ignorées, et (ponctuelles ou encore en cours).
    var activeAlerts: [AlertRow] {
        let now = lastSampleDate ?? Date()
        return alerts.filter { !$0.dismissed && ($0.oneShot || $0.isOngoing(at: now)) }
    }
    var activeAlertCount: Int { activeAlerts.count }
    /// Alertes qui demandent vraiment un coup d'œil (les simples « à savoir » ne comptent pas).
    var attentionAlertCount: Int { activeAlerts.filter { $0.severity >= .attention }.count }
    var topSeverity: Severity? { activeAlerts.map(\.severity).max() }

    func runHealth() {
        let c = engine.evaluateHealth(gatewayMs: latencyGateway, internetMs: latencyInternet,
                                      internetEnabled: Prefs.pingInternet, rssi: network.wifi?.rssi)
        absorb(c, now: Date())
    }

    private func absorb(_ cands: [AlertCandidate], now: Date) {
        learningEnds = (!isDemo && engine.isLearning(now)) ? engine.learningEnds : nil
        guard Prefs.vigilance else { return }
        for c in cands {
            if let i = alerts.firstIndex(where: { $0.id == c.key }) {
                // Une situation qui avait cessé puis revient redevient une alerte visible
                let wasStale = !c.oneShot && now.timeIntervalSince(alerts[i].lastSeen) >= AlertRow.ongoingWindow
                alerts[i].lastSeen = now
                alerts[i].count += 1
                alerts[i].title = c.title
                alerts[i].explanation = c.explanation
                if c.severity > alerts[i].severity { alerts[i].severity = c.severity; alerts[i].dismissed = false; notify(c, now: now) }
                if wasStale { alerts[i].dismissed = false; notify(c, now: now) }
            } else {
                alerts.insert(AlertRow(id: c.key, firstSeen: now, lastSeen: now, severity: c.severity, title: c.title,
                                       explanation: c.explanation, appName: c.appName, appKey: c.appKey, symbol: c.symbol, oneShot: c.oneShot), at: 0)
                if let nm = c.appName { addEvent(.info, "Vigilance : \(c.title)", nm) } else { addEvent(.info, "Vigilance : \(c.title)", c.severity.label) }
                notify(c, now: now)
            }
        }
        if alerts.count > 200 { alerts.removeLast(alerts.count - 200) }
    }

    private func notify(_ c: AlertCandidate, now: Date) {
        guard Prefs.notify, !isDemo, c.severity >= .attention else { return }
        if let last = lastNotified[c.key], now.timeIntervalSince(last) < 600 { return }
        lastNotified[c.key] = now
        AlertNotifier.post(title: c.severity == .important ? "⚠️ Vigie : \(c.title)" : "Vigie : \(c.title)", body: c.explanation, id: c.key)
    }

    func dismiss(_ id: String) {
        if let i = alerts.firstIndex(where: { $0.id == id }) { alerts[i].dismissed = true }
    }

    func restore(_ id: String) {
        if let i = alerts.firstIndex(where: { $0.id == id }) { alerts[i].dismissed = false }
    }

    /// « Faire confiance » : Vigie ne signalera plus cette application.
    func trust(appKey: String) {
        engine.trust(appKey)
        for i in alerts.indices where alerts[i].appKey == appKey { alerts[i].dismissed = true }
        saveBaselineIfNeeded()
    }
    func isTrusted(appKey: String) -> Bool { engine.isTrusted(appKey) }

    func untrustAll() {
        engine.baseline.trusted = []
        saveBaselineIfNeeded(force: true)
    }

    /// Oublie ce que Vigie a appris et recommence l'apprentissage.
    func resetLearning() {
        engine = VigilanceEngine(baseline: Baseline())
        alerts = []
        saveBaselineIfNeeded(force: true)
    }

    var trustedCount: Int { engine.baseline.trusted.count }

    private func saveBaselineIfNeeded(force: Bool = false) {
        guard !isDemo, force || engine.dirty else { return }
        engine.baseline.save()
        engine.markClean()
    }

    // MARK: - Mise en forme

    static func endpoint(_ addr: String, _ port: Int?) -> String {
        let a = addr == "*" ? "*" : addr
        guard let port else { return a }
        return a.contains(":") ? "[\(a)]:\(port)" : "\(a):\(port)"
    }

    static func stateLabel(_ s: String, proto: String) -> String {
        switch s.lowercased() {
        case "established": return "Connectée"
        case "listen": return "En écoute"
        case "syn_sent": return "Connexion…"
        case "syn_received": return "Connexion…"
        case "time_wait": return "Se termine"
        case "close_wait", "closing", "last_ack", "fin_wait_1", "fin_wait_2": return "Se termine"
        case "closed": return "Fermée"
        case "": return proto == "UDP" ? "Sans connexion" : "—"
        default: return s
        }
    }
}
