import SwiftUI

struct DestinationsView: View {
    @Environment(NetworkStore.self) private var store
    @Environment(Nav.self) private var nav
    @State private var query = ""
    @State private var filter: Filter = .internet
    @State private var onlyActive = false
    @State private var sort = [KeyPathComparator(\DestinationRow.totalOut, order: .reverse)]

    enum Filter: String, CaseIterable, Identifiable {
        case internet = "Internet", lan = "Réseau local", all = "Tout"
        var id: String { rawValue }
    }

    private var rows: [DestinationRow] {
        var r = store.destinations
        switch filter {
        case .internet: r = r.filter { $0.scope == .internet }
        case .lan: r = r.filter { $0.scope == .lan }
        case .all: break
        }
        if onlyActive { r = r.filter { $0.isActive } }
        if !query.isEmpty {
            r = r.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.ip.contains(query)
                || $0.appsText.localizedCaseInsensitiveContains(query) || $0.ownerText.localizedCaseInsensitiveContains(query) }
        }
        return r.sorted(using: sort)
    }

    var body: some View {
        @Bindable var nav = nav
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Destinations",
                       subtitle: "Toutes les adresses avec lesquelles votre Mac communique : qui les contacte, et combien de données y sont envoyées.") {
                HStack(spacing: 14) {
                    Picker("", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).frame(width: 260).labelsHidden()
                    Toggle("En cours", isOn: $onlyActive).toggleStyle(.switch).controlSize(.small)
                }
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)

            if !Prefs.resolveNames && !store.isDemo {
                Text("Les noms de domaine sont désactivés dans les réglages : seules les adresses IP sont affichées.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 8)
            }

            Table(rows, selection: $nav.selectedDest, sortOrder: $sort) {
                TableColumn("Destination", value: \.title) { d in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Circle().fill(d.isActive ? Theme.ok : Color.gray.opacity(0.4)).frame(width: 7, height: 7)
                            Text(d.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        }
                        if d.host != nil { Text(d.ip).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary).padding(.leading, 13) }
                    }
                }.width(min: 200, ideal: 270)
                TableColumn("Propriétaire", value: \.ownerText) { d in
                    Text(d.ownerText.isEmpty ? "—" : d.ownerText).font(.system(size: 12)).foregroundStyle(d.ownerText.isEmpty ? .secondary : .primary).lineLimit(1)
                }.width(min: 120, ideal: 170)
                TableColumn("Applications", value: \.appsText) { d in
                    Text(d.appsText).font(.system(size: 12)).lineLimit(1)
                }.width(min: 120, ideal: 160)
                TableColumn("Envoyé", value: \.totalOut) { d in SentText(bytes: d.totalOut) }.width(min: 80, ideal: 90)
                TableColumn("Reçu", value: \.totalIn) { d in ReceivedText(bytes: d.totalIn) }.width(min: 80, ideal: 90)
                TableColumn("Envoi/s", value: \.rateOut) { d in RateText(value: d.rateOut, color: Theme.up) }.width(min: 75, ideal: 90)
                TableColumn("Service") { d in
                    Text(d.ports.prefix(3).map { Net.service(port: $0, proto: d.protocols.first ?? "TCP") }.joined(separator: ", "))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }.width(min: 90, ideal: 130)
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Chercher une adresse, un nom, une app")
        }
        .background(Theme.page)
        .inspector(isPresented: Binding(get: { nav.selectedDest != nil }, set: { if !$0 { nav.selectedDest = nil } })) {
            if let id = nav.selectedDest, let d = store.destinations.first(where: { $0.id == id }) {
                DestinationDetail(dest: d).inspectorColumnWidth(min: 300, ideal: 350, max: 460)
            } else {
                EmptyHint(symbol: "paperplane", title: "Aucune destination sélectionnée", text: "").inspectorColumnWidth(min: 300, ideal: 350, max: 460)
            }
        }
    }
}

struct DestinationDetail: View {
    @Environment(NetworkStore.self) private var store
    @Environment(Nav.self) private var nav
    var dest: DestinationRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        ScopeBadge(scope: dest.scope)
                        if dest.isActive { Badge(text: "En cours", color: Theme.ok) } else { Badge(text: "Terminée", color: .gray) }
                    }
                    Text(dest.title).font(.system(size: 17, weight: .bold)).textSelection(.enabled).lineLimit(3)
                    if dest.host != nil { Text(dest.ip).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                Card {
                    VStack(spacing: 7) {
                        HStack { Text("Données envoyées").foregroundStyle(.secondary); Spacer(); SentText(bytes: dest.totalOut).font(.system(size: 15, weight: .bold)) }
                        HStack { Text("Données reçues").foregroundStyle(.secondary); Spacer(); ReceivedText(bytes: dest.totalIn).font(.system(size: 15, weight: .bold)) }
                        Divider()
                        KeyValueRow(key: "Propriétaire", value: dest.ownerText.isEmpty ? "inconnu" : dest.ownerText)
                        KeyValueRow(key: "Ports", value: dest.ports.isEmpty ? "—" : dest.ports.prefix(6).map(String.init).joined(separator: ", "))
                        KeyValueRow(key: "Protocoles", value: dest.protocols.joined(separator: ", "))
                        KeyValueRow(key: "Connexions", value: "\(dest.connectionCount)")
                        KeyValueRow(key: "Première vue", value: Fmt.ago(dest.firstSeen))
                        KeyValueRow(key: "Dernière activité", value: Fmt.ago(dest.lastSeen))
                    }.font(.system(size: 12.5))
                }
                if dest.ownerText.isEmpty && dest.scope == .internet && !Prefs.ownerLookup && !store.isDemo {
                    Text("Pour savoir à qui appartient cette adresse, activez « Identifier les propriétaires » dans les réglages (⌘,). Attention : cela envoie les adresses contactées à un annuaire public.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .padding(10).background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
                Text("Applications qui la contactent").font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(dest.appNames, id: \.self) { n in
                        let a = store.apps.first { $0.name == n }
                        HStack(spacing: 8) {
                            AppIconView(path: a?.path, system: a?.isSystem ?? true, size: 22)
                            Text(n).font(.system(size: 12.5))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if let a { nav.selectedApp = a.id; nav.section = .apps } }
                    }
                }
                HStack {
                    Button("Copier l'adresse") { copyToPasteboard(dest.ip) }
                    if dest.host != nil { Button("Copier le nom") { copyToPasteboard(dest.title) } }
                }.controlSize(.small)
            }
            .padding(16)
        }
        .background(Theme.page)
    }
}
