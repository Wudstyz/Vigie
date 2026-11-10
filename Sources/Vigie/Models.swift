import Foundation

// MARK: - Échantillons bruts (venant de nettop, du mode démo…)

/// Compteurs cumulés d'un processus.
struct ProcSample: Equatable {
    var name: String
    var pid: Int32
    var bytesIn: UInt64
    var bytesOut: UInt64
}

/// Une connexion ou un « socket » ouvert par un processus.
struct ConnSample: Equatable {
    var pid: Int32
    var proto: String          // "TCP" ou "UDP"
    var family: Int            // 4 ou 6
    var localAddr: String
    var localPort: Int?
    var remoteAddr: String?    // nil = pas de correspondant (écoute…)
    var remotePort: Int?
    var state: String          // "Established", "Listen", "" (UDP)…
    var bytesIn: UInt64
    var bytesOut: UInt64

    var key: String { "\(pid)|\(proto)|\(localAddr):\(localPort ?? 0)|\(remoteAddr ?? "*"):\(remotePort ?? 0)" }
    var isListening: Bool { state.lowercased() == "listen" || (proto == "UDP" && remoteAddr == nil && localPort != nil) }
}

struct Sample {
    var date: Date
    var procs: [ProcSample] = []
    var conns: [ConnSample] = []
    var isEmpty: Bool { procs.isEmpty && conns.isEmpty }
}

// MARK: - Portée d'une adresse

enum Scope: String, CaseIterable, Identifiable {
    case internet, lan, loopback, multicast, wildcard
    var id: String { rawValue }
    var label: String {
        switch self {
        case .internet: return "Internet"
        case .lan: return "Réseau local"
        case .loopback: return "Ce Mac"
        case .multicast: return "Diffusion"
        case .wildcard: return "—"
        }
    }
}

// MARK: - Données agrégées affichées par l'interface

struct AppRow: Identifiable, Hashable {
    var id: String            // clé : chemin du .app ou nom du processus
    var name: String
    var path: String?
    var isSystem: Bool
    var pids: [Int32]
    var rateIn: Double
    var rateOut: Double
    var totalIn: UInt64
    var totalOut: UInt64
    var connectionCount: Int
    var destinationCount: Int
    var lastActive: Date

    // Valeurs « à plat » pour le tri des tableaux
    var sortRate: Double { rateIn + rateOut }
    var totalAll: UInt64 { totalIn + totalOut }
    var kind: String { isSystem ? "Système" : "Application" }
}

struct DestinationRow: Identifiable, Hashable {
    var id: String            // adresse IP distante
    var ip: String
    var scope: Scope
    var host: String?         // nom de domaine, s'il est connu
    var owner: String?        // propriétaire du réseau (option)
    var country: String?
    var ports: [Int]
    var protocols: [String]
    var appNames: [String]
    var rateIn: Double
    var rateOut: Double
    var totalIn: UInt64
    var totalOut: UInt64
    var connectionCount: Int
    var firstSeen: Date
    var lastSeen: Date

    var title: String { host ?? ip }
    var sortRate: Double { rateIn + rateOut }
    var ownerText: String { [owner, country].compactMap { $0 }.joined(separator: " · ") }
    var appsText: String { appNames.joined(separator: ", ") }
    var isActive: Bool { connectionCount > 0 }
}

/// Part d'une destination dans l'activité d'une application.
struct AppDestination: Identifiable, Hashable {
    var id: String            // IP
    var ip: String
    var host: String?
    var scope: Scope
    var totalIn: UInt64
    var totalOut: UInt64
    var lastSeen: Date
    var title: String { host ?? ip }
}

struct ConnectionRow: Identifiable, Hashable {
    var id: String
    var pid: Int32
    var appName: String
    var appKey: String
    var proto: String
    var local: String
    var remote: String
    var remoteIP: String?
    var remotePort: Int?
    var host: String?
    var service: String
    var scope: Scope
    var state: String
    var bytesIn: UInt64
    var bytesOut: UInt64
    var rateIn: Double
    var rateOut: Double
    var title: String { host ?? remote }
}

struct ListenerRow: Identifiable, Hashable {
    var id: String
    var appName: String
    var pid: Int32
    var proto: String
    var address: String
    var port: Int
    var service: String
    /// Vrai si le port est joignable depuis d'autres appareils (pas seulement depuis ce Mac).
    var exposed: Bool
    var exposure: String { exposed ? "Visible depuis le réseau" : "Ce Mac uniquement" }
}

struct DeviceRow: Identifiable, Hashable {
    var id: String            // adresse MAC (ou IP)
    var ip: String
    var mac: String
    var name: String?
    var isGateway: Bool
    var isThisMac: Bool
    var randomMAC: Bool
    var firstSeen: Date
    var lastSeen: Date
}

struct RatePoint: Identifiable {
    var id: Date { date }
    var date: Date
    var down: Double
    var up: Double
}

enum EventKind: String {
    case newDestination, newListener, newDevice, info
    var symbol: String {
        switch self {
        case .newDestination: return "arrow.up.right.circle.fill"
        case .newListener: return "door.left.hand.open"
        case .newDevice: return "laptopcomputer.and.iphone"
        case .info: return "info.circle.fill"
        }
    }
    var label: String {
        switch self {
        case .newDestination: return "Nouvelle destination"
        case .newListener: return "Port ouvert"
        case .newDevice: return "Nouvel appareil"
        case .info: return "Info"
        }
    }
}

struct EventRow: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var kind: EventKind
    var title: String
    var detail: String
}

struct DNSQuery: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var name: String
    var type: String
    var answers: [String]
}
