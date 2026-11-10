import SwiftUI

// MARK: - Connexions

struct ConnectionsView: View {
    @Environment(NetworkStore.self) private var store
    @State private var query = ""
    @State private var showLocal = false
    @State private var sort = [KeyPathComparator(\ConnectionRow.bytesOut, order: .reverse)]

    private var rows: [ConnectionRow] {
        var r = store.connections
        if !showLocal { r = r.filter { $0.scope == .internet || $0.scope == .lan } }
        if !query.isEmpty {
            r = r.filter { $0.appName.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query)
                || $0.remote.contains(query) || $0.service.localizedCaseInsensitiveContains(query) }
        }
        return r.sorted(using: sort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Connexions",
                       subtitle: "\(rows.count) connexions ouvertes en ce moment, application par application.") {
                Toggle("Inclure ce Mac et la diffusion", isOn: $showLocal).toggleStyle(.switch).controlSize(.small)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)

            Table(rows, sortOrder: $sort) {
                TableColumn("Application", value: \.appName) { c in Text(c.appName).font(.system(size: 12.5, weight: .medium)).lineLimit(1) }
                    .width(min: 120, ideal: 150)
                TableColumn("Vers", value: \.title) { c in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.title).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                        if c.host != nil { Text(c.remote).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }.width(min: 200, ideal: 280)
                TableColumn("Type", value: \.scopeLabel) { c in ScopeBadge(scope: c.scope) }.width(min: 80, ideal: 95)
                TableColumn("Service", value: \.service) { c in
                    Text("\(c.proto) · \(c.service)").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }.width(min: 120, ideal: 170)
                TableColumn("État", value: \.state) { c in Text(c.state).font(.system(size: 12)).foregroundStyle(.secondary) }.width(min: 70, ideal: 90)
                TableColumn("Envoyé", value: \.bytesOut) { c in SentText(bytes: c.bytesOut) }.width(min: 75, ideal: 90)
                TableColumn("Reçu", value: \.bytesIn) { c in ReceivedText(bytes: c.bytesIn) }.width(min: 75, ideal: 90)
                TableColumn("Envoi/s", value: \.rateOut) { c in RateText(value: c.rateOut, color: Theme.up) }.width(min: 70, ideal: 85)
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Filtrer les connexions")
        }
        .background(Theme.page)
    }
}

extension ConnectionRow { var scopeLabel: String { scope.label } }

// MARK: - Ports ouverts (services à l'écoute sur ce Mac)

struct PortsView: View {
    @Environment(NetworkStore.self) private var store
    @State private var sort = [KeyPathComparator(\ListenerRow.exposure), KeyPathComparator(\ListenerRow.port)]

    private var rows: [ListenerRow] { store.listeners.sorted(using: sort) }
    private var exposedCount: Int { store.listeners.filter(\.exposed).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Ports ouverts",
                       subtitle: "Les « portes » que des applications de votre Mac laissent ouvertes pour recevoir des connexions.") {
                Badge(text: exposedCount == 0 ? "Aucune porte visible depuis le réseau" : "\(exposedCount) visible\(exposedCount > 1 ? "s" : "") depuis le réseau",
                      color: exposedCount == 0 ? Theme.ok : Theme.warn)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)

            Card {
                Text("Un port **visible depuis le réseau** peut être contacté par les autres appareils de votre réseau local (partage de fichiers, AirPlay, Bonjour…). Un port **« Ce Mac uniquement »** n'est joignable que par les applications de ce Mac. Ce n'est pas forcément un problème : c'est simplement l'état des lieux.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.bottom, 12)

            Table(rows, sortOrder: $sort) {
                TableColumn("Application", value: \.appName) { l in Text(l.appName).font(.system(size: 12.5, weight: .medium)).lineLimit(1) }.width(min: 140, ideal: 180)
                TableColumn("Port", value: \.port) { l in Text("\(l.port)").monospacedDigit() }.width(min: 60, ideal: 70)
                TableColumn("Protocole", value: \.proto) { l in Text(l.proto) }.width(min: 70, ideal: 80)
                TableColumn("Usage probable") { l in Text(l.service == "\(l.port)" ? "—" : l.service).font(.system(size: 12)).foregroundStyle(.secondary) }.width(min: 150, ideal: 200)
                TableColumn("Écoute sur", value: \.address) { l in Text(l.address).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }.width(min: 130, ideal: 160)
                TableColumn("Exposition", value: \.exposure) { l in
                    Badge(text: l.exposure, color: l.exposed ? Theme.warn : Theme.ok)
                }.width(min: 150, ideal: 190)
            }
        }
        .background(Theme.page)
    }
}

// MARK: - Noms de domaine (mode avancé)

struct DNSView: View {
    @Environment(NetworkStore.self) private var store
    @State private var query = ""

    private var rows: [DNSQuery] {
        query.isEmpty ? store.dnsQueries : store.dnsQueries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Noms de domaine",
                       subtitle: "Les sites et services que vos applications demandent à joindre, avant même de s'y connecter.") {
                if store.dnsMode == .on && !store.isDemo {
                    Button("Arrêter le mode avancé") { store.disableAdvancedDNS() }.controlSize(.small)
                }
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)

            if store.dnsMode == .off {
                VStack(alignment: .leading, spacing: 12) {
                    Card(title: "Mode avancé (facultatif)") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Par défaut, Vigie voit **qui** parle à **quelle adresse** et **combien** de données passent. Le mode avancé ajoute les **noms de domaine** demandés par vos applications (ex. « www.exemple.fr »), ce qui rend la colonne « Destination » beaucoup plus parlante.")
                            Text("Pour cela, macOS exige votre autorisation administrateur : une fenêtre officielle du système vous demandera votre mot de passe (ou Touch ID). **Vigie ne voit jamais ce mot de passe.** Seules les requêtes DNS (les « demandes d'adresse ») sont lues, jamais le contenu de vos échanges.")
                            Text("Limite : si une application utilise un DNS chiffré (DNS sur HTTPS, relais privé iCloud…), ses requêtes ne sont pas visibles ici.")
                                .foregroundStyle(.secondary)
                            HStack {
                                Button { store.enableAdvancedDNS() } label: { Label("Activer le mode avancé…", systemImage: "lock.open") }
                                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                                if let s = store.dnsStatus { Text(s).font(.system(size: 12)).foregroundStyle(.secondary) }
                            }
                        }.font(.system(size: 12.5))
                    }
                }.padding(.horizontal, 24)
                Spacer()
            } else if store.dnsMode == .starting {
                EmptyHint(symbol: "lock.shield", title: "En attente de votre autorisation…", text: "Une fenêtre de macOS devrait s'afficher.")
            } else {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.ok)
                    Text(store.dnsStatus ?? "Écoute active").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.bottom, 8)
                if rows.isEmpty {
                    EmptyHint(symbol: "text.magnifyingglass", title: "En attente de requêtes…", text: "Les noms de domaine apparaîtront ici dès qu'une application en demandera un.")
                } else {
                    Table(rows) {
                        TableColumn("Heure") { q in Text(Fmt.clock.string(from: q.date)).monospacedDigit().foregroundStyle(.secondary) }.width(70)
                        TableColumn("Nom demandé") { q in Text(q.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle) }.width(min: 220, ideal: 320)
                        TableColumn("Type") { q in Text(q.type).font(.system(size: 11.5)).foregroundStyle(.secondary) }.width(55)
                        TableColumn("Adresse obtenue") { q in
                            Text(q.answers.isEmpty ? "…" : q.answers.prefix(2).joined(separator: ", "))
                                .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        }.width(min: 160, ideal: 240)
                    }
                    .searchable(text: $query, placement: .toolbar, prompt: "Filtrer les noms")
                }
            }
        }
        .background(Theme.page)
    }
}

// MARK: - Journal

struct JournalView: View {
    @Environment(NetworkStore.self) private var store
    @State private var kind: EventKind?

    private var rows: [EventRow] { kind == nil ? store.events : store.events.filter { $0.kind == kind } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Journal", subtitle: "Ce qui change sur votre réseau, dans l'ordre. Conservé tant que Vigie est ouvert.") {
                Picker("", selection: $kind) {
                    Text("Tout").tag(EventKind?.none)
                    Text("Destinations").tag(EventKind?.some(.newDestination))
                    Text("Ports").tag(EventKind?.some(.newListener))
                    Text("Appareils").tag(EventKind?.some(.newDevice))
                }.pickerStyle(.segmented).frame(width: 330).labelsHidden()
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)

            if rows.isEmpty {
                EmptyHint(symbol: "list.bullet.rectangle", title: "Rien à signaler pour l'instant",
                          text: "Chaque nouvelle destination, nouveau port ouvert ou nouvel appareil sera noté ici.")
            } else {
                List(rows) { e in
                    HStack(spacing: 12) {
                        Image(systemName: e.kind.symbol).foregroundStyle(e.kind == .newListener ? Theme.warn : Theme.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Text(e.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(Fmt.clock.string(from: e.date)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.page)
    }
}
