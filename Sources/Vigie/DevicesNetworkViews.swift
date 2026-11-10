import SwiftUI

// MARK: - Appareils du réseau local

struct DevicesView: View {
    @Environment(NetworkStore.self) private var store
    @State private var sort = [KeyPathComparator(\DeviceRow.ipOrder)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Appareils",
                       subtitle: "Les appareils connectés au même réseau que votre Mac (box, téléphones, télés, imprimantes…).") {
                HStack(spacing: 10) {
                    if store.scanning { ProgressView().controlSize(.small) }
                    if let d = store.lastScan { Text("Analysé \(Fmt.ago(d))").font(.system(size: 12)).foregroundStyle(.secondary) }
                    Button { store.scanLAN() } label: { Label("Analyser maintenant", systemImage: "arrow.clockwise") }
                        .disabled(store.scanning).controlSize(.regular)
                }
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)

            if store.devices.isEmpty {
                EmptyHint(symbol: "laptopcomputer.and.iphone",
                          title: store.scanning ? "Analyse du réseau en cours…" : "Aucune analyse pour l'instant",
                          text: "Vigie envoie un tout petit message à chaque adresse de votre réseau local pour voir qui répond. Rien ne sort de votre réseau. macOS peut vous demander l'autorisation d'accéder au réseau local : acceptez pour voir les appareils.")
            } else {
                Table(store.devices.sorted(using: sort), sortOrder: $sort) {
                    TableColumn("Appareil", value: \.displayName) { d in
                        HStack(spacing: 9) {
                            Image(systemName: d.symbol).frame(width: 22).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(d.displayName).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                if d.name != nil { Text(d.ip).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary) }
                            }
                        }
                    }.width(min: 200, ideal: 270)
                    TableColumn("Adresse IP", value: \.ipOrder) { d in Text(d.ip).font(.system(size: 12, design: .monospaced)) }.width(min: 110, ideal: 130)
                    TableColumn("Adresse MAC", value: \.mac) { d in Text(d.mac).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }.width(min: 140, ideal: 160)
                    TableColumn("Rôle") { d in
                        HStack(spacing: 5) {
                            if d.isGateway { Badge(text: "Box / passerelle", color: Theme.accent) }
                            if d.isThisMac { Badge(text: "Ce Mac", color: Theme.ok) }
                            if d.randomMAC { Badge(text: "Adresse privée", color: .purple).help("Cet appareil utilise une adresse MAC aléatoire (fonction de confidentialité Wi-Fi d'Apple, Android…).") }
                        }
                    }.width(min: 150, ideal: 230)
                    TableColumn("Vu la première fois") { d in Text(Fmt.ago(d.firstSeen)).foregroundStyle(.secondary) }.width(min: 110, ideal: 140)
                }
            }
        }
        .background(Theme.page)
        .onAppear { if store.lastScan == nil && !store.scanning { store.scanLAN() } }
    }
}

extension DeviceRow {
    var displayName: String { name ?? (isGateway ? "Box Internet" : "Appareil inconnu") }
    var ipOrder: UInt32 { Net.v4Bytes(ip).map { $0.reduce(0) { $0 << 8 | UInt32($1) } } ?? 0 }
    var symbol: String {
        if isGateway { return "wifi.router" }
        if isThisMac { return "laptopcomputer" }
        let n = (name ?? "").lowercased()
        if n.contains("iphone") || n.contains("ipad") || n.contains("android") { return "iphone" }
        if n.contains("tv") || n.contains("chromecast") || n.contains("diffuseur") { return "tv" }
        if n.contains("imprimante") || n.contains("printer") { return "printer" }
        if n.contains("nas") { return "externaldrive.connected.to.line.below" }
        return "desktopcomputer"
    }
}

// MARK: - Mon réseau

struct NetworkView: View {
    @Environment(NetworkStore.self) private var store

    var body: some View {
        let n = store.network
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Mon réseau", subtitle: "Comment ce Mac est relié au réseau et à Internet.")

                HStack(alignment: .top, spacing: 12) {
                    Card(title: "Connexion principale") {
                        VStack(spacing: 8) {
                            KeyValueRow(key: "Ce Mac", value: n.hostName.isEmpty ? "—" : n.hostName)
                            if let i = n.interfaces.first(where: { $0.isDefault }) ?? n.interfaces.first {
                                KeyValueRow(key: "Interface", value: "\(i.label) (\(i.name))")
                                KeyValueRow(key: "Adresse IP (réseau local)", value: i.ipv4 ?? "—", mono: true)
                                if let v6 = i.ipv6 { KeyValueRow(key: "Adresse IPv6", value: v6, mono: true) }
                            }
                            KeyValueRow(key: "Box / passerelle", value: n.gateway ?? "—", mono: true)
                            KeyValueRow(key: "Serveurs DNS", value: n.dnsServers.isEmpty ? "—" : n.dnsServers.joined(separator: "\n"), mono: true)
                        }
                    }
                    Card(title: "Qualité") {
                        VStack(spacing: 8) {
                            KeyValueRow(key: "Latence vers la box", value: store.latencyGateway.map { String(format: "%.1f ms", $0) } ?? "—")
                            KeyValueRow(key: "Latence vers Internet", value: store.latencyInternet.map { String(format: "%.1f ms", $0) } ?? (Prefs.pingInternet ? "—" : "désactivée"))
                            if let w = n.wifi {
                                Divider()
                                KeyValueRow(key: "Signal Wi-Fi", value: "\(w.rssi) dBm · \(signalWord(w.rssi))")
                                KeyValueRow(key: "Débit négocié", value: String(format: "%.0f Mbit/s", w.txRate))
                                KeyValueRow(key: "Canal", value: "\(w.channel)\(w.band.isEmpty ? "" : " · \(w.band)")")
                                KeyValueRow(key: "Bruit", value: "\(w.noise) dBm")
                            }
                        }
                    }
                }

                Card(title: "Interfaces réseau actives") {
                    if n.interfaces.isEmpty { Text("Aucune interface détectée.").foregroundStyle(.secondary).font(.system(size: 12)) }
                    VStack(spacing: 0) {
                        ForEach(n.interfaces) { i in
                            HStack(spacing: 10) {
                                Image(systemName: i.label.contains("Wi-Fi") ? "wifi" : (i.name.hasPrefix("utun") ? "lock.shield" : "cable.connector"))
                                    .frame(width: 22).foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(i.label).font(.system(size: 12.5, weight: .medium))
                                        Text(i.name).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                        if i.isDefault { Badge(text: "Principale", color: Theme.ok) }
                                    }
                                    Text([i.ipv4, i.ipv6].compactMap { $0 }.joined(separator: "  ·  ")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }.padding(.vertical, 7)
                            Divider()
                        }
                    }
                }

                Card(title: "Ce que fait Vigie (et ne fait pas)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Lit les connexions et les compteurs du système (outil `nettop` de macOS). Aucun mot de passe n'est nécessaire.", systemImage: "eye")
                        Label("Ne voit pas le contenu de vos échanges (pages, messages, mots de passe) et ne modifie ni ne bloque rien.", systemImage: "hand.raised")
                        Label("N'envoie aucune donnée vers un serveur de Vigie : il n'y en a pas. Deux options facultatives contactent un service extérieur (voir Réglages).", systemImage: "network.slash")
                    }
                    .font(.system(size: 12.5)).labelStyle(TopIconLabel())
                }
            }
            .padding(24)
        }
        .background(Theme.page)
    }

    private func signalWord(_ rssi: Int) -> String {
        switch rssi {
        case ..<(-80): return "faible"
        case ..<(-67): return "correct"
        case ..<(-55): return "bon"
        default: return "excellent"
        }
    }
}

struct TopIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(Theme.accent).frame(width: 18)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}
