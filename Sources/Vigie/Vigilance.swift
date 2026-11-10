import Foundation
import Security

// MARK: - Gravité, alertes

enum Severity: Int, Comparable, Codable {
    case info = 0, attention = 1, important = 2
    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    var label: String {
        switch self {
        case .info: return "À savoir"
        case .attention: return "À vérifier"
        case .important: return "Important"
        }
    }
    var symbol: String {
        switch self {
        case .info: return "info.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .important: return "exclamationmark.octagon.fill"
        }
    }
}

/// Ce qu'une règle de détection produit.
struct AlertCandidate: Equatable {
    var key: String                 // identifiant stable : une même situation = une seule alerte
    var severity: Severity
    var title: String
    var explanation: String
    var appName: String?
    var appKey: String?
    var symbol: String
    /// Vrai pour un événement ponctuel (nouvelle app, nouvel appareil…) ; faux pour une situation qui dure.
    var oneShot: Bool
}

struct AlertRow: Identifiable, Hashable {
    var id: String                  // = key
    var firstSeen: Date
    var lastSeen: Date
    var severity: Severity
    var title: String
    var explanation: String
    var appName: String?
    var appKey: String?
    var symbol: String
    var oneShot: Bool
    var count: Int = 1
    var dismissed = false

    /// Une situation qui dure est « en cours » tant que la règle l'a signalée récemment.
    static let ongoingWindow: TimeInterval = 20
    func isOngoing(at now: Date) -> Bool { !oneShot && now.timeIntervalSince(lastSeen) < Self.ongoingWindow }
}

// MARK: - Sensibilité

enum Sensitivity: String, CaseIterable, Identifiable {
    case low, normal, high
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: return "Faible"
        case .normal: return "Normale"
        case .high: return "Élevée"
        }
    }
    /// Octets envoyés vers Internet en 1 minute au-delà desquels on prévient.
    var uploadPerMinute: UInt64 {
        switch self {
        case .low: return 100_000_000
        case .normal: return 30_000_000
        case .high: return 10_000_000
        }
    }
    /// Nombre de nouvelles adresses Internet différentes contactées en 1 minute par une même application.
    var newAddressesPerMinute: Int {
        switch self {
        case .low: return 200
        case .normal: return 120
        case .high: return 60
        }
    }
}

// MARK: - Ce que Vigie a « appris » (persisté)

struct Baseline: Codable, Equatable {
    var createdAt: Date = Date()
    var apps: Set<String> = []          // applications déjà vues sur Internet
    var devices: Set<String> = []       // adresses MAC déjà vues sur le réseau local
    var listeners: Set<String> = []     // ports ouverts (visibles du réseau) déjà vus
    var gateways: [String: String] = [:] // IP de la box -> adresse MAC attendue
    var trusted: Set<String> = []       // applications auxquelles l'utilisateur fait confiance

    static var fileURL: URL {
        // Variable réservée aux tests : évite de toucher à la vraie configuration de l'utilisateur.
        if let p = ProcessInfo.processInfo.environment["VIGIE_BASELINE"], !p.isEmpty { return URL(fileURLWithPath: p) }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vigie")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("baseline.json")
    }

    static func load(from url: URL = Baseline.fileURL) -> Baseline? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Baseline.self, from: d)
    }

    func save(to url: URL = Baseline.fileURL) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(self) { try? d.write(to: url, options: .atomic) }
    }
}

// MARK: - Signature du code

enum CodeStatus { case trusted, notTrusted }

enum CodeSigning {
    /// « Digne de confiance » = signé par Apple, par un développeur identifié ou via le Mac App Store
    /// (chaîne de certificats Apple). Une signature « ad hoc », absente ou invalide n'est pas de confiance.
    static func status(path: String) -> CodeStatus {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return .notTrusted }
        var req: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &req) == errSecSuccess, let req else { return .notTrusted }
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess ? .trusted : .notTrusted
    }
}

// MARK: - Observations transmises au moteur

struct AppObs {
    var key: String
    var name: String
    var path: String?
    var isSystem: Bool
    var internetActive: Bool        // a au moins une connexion vers Internet en ce moment
}

struct ConnObs {
    var appKey: String
    var appName: String
    var remoteIP: String
    var remotePort: Int
    var scope: Scope
}

struct ListenerObs {
    var key: String
    var appKey: String
    var appName: String
    var port: Int
    var exposed: Bool
    var isSystem: Bool
}

struct DeviceObs {
    var mac: String
    var ip: String
    var name: String?
    var randomMAC: Bool
    var isThisMac: Bool
}

// MARK: - Le moteur

final class VigilanceEngine {
    var baseline: Baseline
    var sensitivity: Sensitivity = .normal
    /// Durée pendant laquelle Vigie apprend ce qui est « habituel » sans rien signaler (première utilisation seulement).
    static let learningDuration: TimeInterval = 15 * 60
    private(set) var dirty = false
    var codeStatus: (String) -> CodeStatus = CodeSigning.status(path:)

    private let started: Date
    private var window: [String: [(date: Date, out: UInt64, in: UInt64)]] = [:]
    private var firstSeenIP: [String: [String: Date]] = [:]
    private var codeCache: [String: CodeStatus] = [:]
    private var failGateway = 0, failInternet = 0, weakWifi = 0
    private var gatewayMs: [Double] = [], internetMs: [Double] = []

    /// Ports souvent associés à des outils de prise de contrôle à distance ou à des logiciels malveillants.
    static let suspiciousPorts: Set<Int> = [23, 2323, 4444, 5555, 6667, 12345, 31337, 1337, 9001, 9030]

    init(baseline: Baseline, now: Date = Date()) {
        self.baseline = baseline
        self.started = now
    }

    var learningEnds: Date { baseline.createdAt.addingTimeInterval(Self.learningDuration) }
    func isLearning(_ now: Date = Date()) -> Bool { now < learningEnds }
    func markClean() { dirty = false }

    func trust(_ appKey: String) { baseline.trusted.insert(appKey); dirty = true }
    func isTrusted(_ appKey: String) -> Bool { baseline.trusted.contains(appKey) }

    // MARK: Règles liées au trafic

    func evaluate(now: Date, apps: [AppObs], deltas: [String: (out: UInt64, in: UInt64)],
                  newInternetIPs: [String: Set<String>], conns: [ConnObs], listeners: [ListenerObs]) -> [AlertCandidate] {
        var out: [AlertCandidate] = []
        let learning = isLearning(now)

        // Fenêtre glissante de 60 s du trafic Internet de chaque application
        for (k, d) in deltas { window[k, default: []].append((now, d.out, d.in)) }
        for k in Array(window.keys) {
            window[k]!.removeAll { now.timeIntervalSince($0.date) > 60 }
            if window[k]!.isEmpty { window[k] = nil }
        }

        for app in apps where !isTrusted(app.key) {
            // 1) Envoi massif vers Internet
            if !app.isSystem, let w = window[app.key] {
                let sent = w.reduce(UInt64(0)) { $0 + $1.out }, recv = w.reduce(UInt64(0)) { $0 + $1.in }
                let limit = sensitivity.uploadPerMinute
                if sent >= limit && sent > recv &* 3 {
                    let big = sent >= limit &* 5
                    out.append(AlertCandidate(
                        key: "upload|\(app.key)", severity: big ? .important : .attention,
                        title: "\(app.name) envoie beaucoup de données sur Internet",
                        explanation: "\(Fmt.bytes(sent)) envoyés en 1 minute (pour \(Fmt.bytes(recv)) reçus). C'est normal pour une sauvegarde ou un envoi de fichiers que vous avez lancé. Sinon, vérifiez ce que fait cette application.",
                        appName: app.name, appKey: app.key, symbol: "arrow.up.circle.fill", oneShot: false))
                }
            }

            // 2) Nouvelle application sur le réseau
            if app.internetActive && !app.isSystem && !baseline.apps.contains(app.key) {
                baseline.apps.insert(app.key); dirty = true
                if !learning {
                    out.append(AlertCandidate(
                        key: "newapp|\(app.key)", severity: .info,
                        title: "Nouvelle application sur le réseau : \(app.name)",
                        explanation: "Cette application n'avait encore jamais utilisé Internet depuis que Vigie vous surveille. C'est normal juste après une installation ou une mise à jour ; sinon, vérifiez qu'elle est légitime.",
                        appName: app.name, appKey: app.key, symbol: "sparkles", oneShot: true))
                }
            }

            // 3) Programme non signé, lancé depuis un dossier inhabituel, qui utilise Internet
            if app.internetActive && !app.isSystem, let path = app.path, Self.isUnusualLocation(path) {
                let st = codeCache[path] ?? { let s = codeStatus(path); codeCache[path] = s; return s }()
                if st == .notTrusted {
                    out.append(AlertCandidate(
                        key: "path|\(app.key)", severity: .attention,
                        title: "\(app.name) tourne depuis un dossier inhabituel",
                        explanation: "Ce programme n'est pas signé par un développeur identifié et se trouve dans un dossier temporaire, de téléchargements ou caché (\(Self.shortPath(path))). Les logiciels légitimes s'installent plutôt dans « Applications ». Si vous ne le reconnaissez pas, méfiez-vous.",
                        appName: app.name, appKey: app.key, symbol: "folder.badge.questionmark", oneShot: false))
                }
            }

            // 4) Beaucoup de nouvelles adresses contactées d'un coup
            if let ips = newInternetIPs[app.key] {
                var seen = firstSeenIP[app.key] ?? [:]
                for ip in ips where seen[ip] == nil {
                    // Pendant les 20 premières secondes, les connexions déjà ouvertes ne comptent pas comme « nouvelles ».
                    seen[ip] = now.timeIntervalSince(started) > 20 ? now : now.addingTimeInterval(-3600)
                }
                seen = seen.filter { now.timeIntervalSince($0.value) < 120 }
                firstSeenIP[app.key] = seen
                let recent = seen.values.filter { now.timeIntervalSince($0) < 60 }.count
                if recent >= sensitivity.newAddressesPerMinute {
                    out.append(AlertCandidate(
                        key: "burst|\(app.key)", severity: .attention,
                        title: "\(app.name) contacte énormément d'adresses différentes",
                        explanation: "\(recent) nouvelles adresses Internet en 1 minute. Un navigateur sur un site chargé peut en contacter beaucoup, mais ce comportement peut aussi être celui d'un programme qui cherche des machines à joindre.",
                        appName: app.name, appKey: app.key, symbol: "point.3.connected.trianglepath.dotted", oneShot: false))
                }
            }
        }

        // 5) Connexion vers un port souvent utilisé par des outils de prise de contrôle à distance
        var seenPort = Set<String>()
        for c in conns where c.scope == .internet && Self.suspiciousPorts.contains(c.remotePort) && !isTrusted(c.appKey) {
            let key = "port|\(c.appKey)|\(c.remotePort)"
            guard seenPort.insert(key).inserted else { continue }
            out.append(AlertCandidate(
                key: key, severity: .attention,
                title: "\(c.appName) se connecte au port \(c.remotePort) d'un serveur sur Internet",
                explanation: "Le port \(c.remotePort) est souvent utilisé par des outils de prise de contrôle à distance ou des logiciels malveillants (mais aussi par des outils légitimes : développement, Tor…). Adresse : \(c.remoteIP).",
                appName: c.appName, appKey: c.appKey, symbol: "network.badge.shield.half.filled", oneShot: false))
        }

        // 6) Nouveau port ouvert, visible depuis le réseau, par une application non système
        for l in listeners where l.exposed && !l.isSystem && !isTrusted(l.appKey) && !baseline.listeners.contains(l.key) {
            baseline.listeners.insert(l.key); dirty = true
            if !learning {
                out.append(AlertCandidate(
                    key: "listen|\(l.key)", severity: .attention,
                    title: "\(l.appName) accepte des connexions venant du réseau (port \(l.port))",
                    explanation: "Cette application a ouvert le port \(l.port), joignable par les autres appareils de votre réseau. C'est normal pour un partage ou un serveur que vous avez lancé ; sinon, vérifiez-la.",
                    appName: l.appName, appKey: l.appKey, symbol: "door.left.hand.open", oneShot: true))
            }
        }
        return out
    }

    // MARK: Règles liées au réseau local

    func evaluateDevices(now: Date, devices: [DeviceObs], gatewayIP: String?) -> [AlertCandidate] {
        var out: [AlertCandidate] = []
        let learning = isLearning(now)
        for d in devices where !d.isThisMac && d.mac != "—" {
            // Usurpation possible : l'adresse matérielle de la box a changé
            if let gw = gatewayIP, d.ip == gw {
                if let expected = baseline.gateways[gw], expected != d.mac {
                    out.append(AlertCandidate(
                        key: "arp|\(gw)", severity: .important,
                        title: "L'adresse matérielle de votre box a changé",
                        explanation: "La box (\(gw)) répondait avec l'adresse \(expected) ; elle répond maintenant avec \(d.mac). C'est normal si vous avez changé de box ou de réseau. Sinon, quelqu'un peut se faire passer pour elle sur votre réseau : évitez les sites sensibles et vérifiez vos appareils.",
                        appName: nil, appKey: nil, symbol: "exclamationmark.shield.fill", oneShot: true))
                }
                if baseline.gateways[gw] != d.mac { baseline.gateways[gw] = d.mac; dirty = true }
            }
            // Nouvel appareil
            if !baseline.devices.contains(d.mac) {
                baseline.devices.insert(d.mac); dirty = true
                if !learning {
                    out.append(AlertCandidate(
                        key: "device|\(d.mac)", severity: .attention,
                        title: "Nouvel appareil sur votre réseau : \(d.name ?? d.ip)",
                        explanation: "Un appareil jamais vu auparavant est apparu (\(d.ip), \(d.mac))\(d.randomMAC ? ", avec une adresse « privée » : téléphones et ordinateurs récents en utilisent" : ""). C'est normal si quelqu'un a connecté un appareil ; sinon, changez le mot de passe de votre Wi-Fi.",
                        appName: nil, appKey: nil, symbol: "laptopcomputer.and.iphone", oneShot: true))
                }
            }
        }
        return out
    }

    // MARK: Règles « problèmes de connexion »

    func evaluateHealth(gatewayMs gw: Double?, internetMs inet: Double?, internetEnabled: Bool, rssi: Int?) -> [AlertCandidate] {
        var out: [AlertCandidate] = []

        if gw == nil { failGateway += 1 } else { failGateway = 0; gatewayMs.append(gw!); gatewayMs = Array(gatewayMs.suffix(3)) }
        if failGateway >= 3 {
            out.append(AlertCandidate(key: "health|gateway", severity: .important,
                title: "Votre box ne répond plus",
                explanation: "Plus de réponse de la box depuis une vingtaine de secondes : le Wi-Fi est peut-être coupé ou la box est éteinte ou en panne.",
                appName: nil, appKey: nil, symbol: "wifi.exclamationmark", oneShot: false))
        }

        if internetEnabled {
            if inet == nil && failGateway == 0 { failInternet += 1 } else if inet != nil { failInternet = 0; internetMs.append(inet!); internetMs = Array(internetMs.suffix(3)) }
            if failInternet >= 3 {
                out.append(AlertCandidate(key: "health|internet", severity: .important,
                    title: "Internet ne répond plus",
                    explanation: "La box répond, mais plus rien ne revient d'Internet. Panne de l'opérateur ou de la box : essayez de la redémarrer.",
                    appName: nil, appKey: nil, symbol: "globe.badge.chevron.backward", oneShot: false))
            }
        }

        if gatewayMs.count == 3, gatewayMs.reduce(0, +) / 3 > 100 {
            out.append(AlertCandidate(key: "health|slowgw", severity: .attention,
                title: "Le réseau local est lent",
                explanation: "Les échanges avec votre box mettent plus de 100 ms. Signal Wi-Fi faible, réseau saturé ou interférences.",
                appName: nil, appKey: nil, symbol: "tortoise.fill", oneShot: false))
        }
        if internetEnabled, internetMs.count == 3, internetMs.reduce(0, +) / 3 > 300 {
            out.append(AlertCandidate(key: "health|slownet", severity: .attention,
                title: "Internet est très lent à répondre",
                explanation: "Les échanges avec Internet mettent plus de 300 ms. Quelqu'un télécharge peut-être beaucoup, ou la connexion de l'opérateur est dégradée.",
                appName: nil, appKey: nil, symbol: "tortoise.fill", oneShot: false))
        }

        if let r = rssi, r < -80 { weakWifi += 1 } else { weakWifi = 0 }
        if weakWifi >= 3, let r = rssi {
            out.append(AlertCandidate(key: "health|wifi", severity: .info,
                title: "Signal Wi-Fi faible",
                explanation: "Le signal est à \(r) dBm (en dessous de -80, la connexion devient instable). Rapprochez-vous de la box.",
                appName: nil, appKey: nil, symbol: "wifi", oneShot: false))
        }
        return out
    }

    // MARK: Aides

    /// Dossiers où un logiciel légitime ne s'installe normalement pas.
    static func isUnusualLocation(_ path: String) -> Bool {
        let p = path.lowercased()
        if p.hasPrefix("/applications/") || p.hasPrefix("/system/") || p.hasPrefix("/usr/") || p.hasPrefix("/library/") || p.hasPrefix("/opt/homebrew/") { return false }
        if p.contains("/tmp/") || p.hasPrefix("/private/var/folders/") || p.hasPrefix("/var/tmp/") || p.hasPrefix("/private/tmp/") { return true }
        if p.contains("/downloads/") || p.hasPrefix("/users/shared/") || p.contains("/library/caches/") { return true }
        // dossier caché (commence par un point) hors outils de développement courants
        let comps = p.split(separator: "/")
        let devDirs: Set<String> = [".nvm", ".cargo", ".rustup", ".pyenv", ".rbenv", ".volta", ".bun", ".deno", ".local", ".swiftpm", ".npm", ".sdkman", ".asdf", ".docker", ".ollama"]
        if comps.contains(where: { $0.hasPrefix(".") && !devDirs.contains(String($0)) && $0 != "." && $0 != ".." }) { return true }
        return false
    }

    static func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
