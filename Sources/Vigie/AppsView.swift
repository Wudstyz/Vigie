import SwiftUI

struct AppsView: View {
    @Environment(NetworkStore.self) private var store
    @Environment(Nav.self) private var nav
    @State private var query = ""
    @State private var onlyActive = false
    @State private var sort = [KeyPathComparator(\AppRow.totalOut, order: .reverse)]

    private var rows: [AppRow] {
        var r = store.apps
        if onlyActive { r = r.filter { $0.sortRate >= 1 } }
        if !query.isEmpty { r = r.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        return r.sorted(using: sort)
    }

    var body: some View {
        @Bindable var nav = nav
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Applications",
                       subtitle: "Chaque application qui utilise le réseau, ce qu'elle envoie et ce qu'elle reçoit.") {
                Toggle("Actives seulement", isOn: $onlyActive).toggleStyle(.switch).controlSize(.small)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)

            Table(rows, selection: $nav.selectedApp, sortOrder: $sort) {
                TableColumn("Application", value: \.name) { a in
                    HStack(spacing: 9) {
                        AppIconView(path: a.path, system: a.isSystem, size: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(a.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(a.kind).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                }.width(min: 170, ideal: 220)
                TableColumn("Envoyé", value: \.totalOut) { a in
                    HStack(spacing: 6) {
                        SentText(bytes: a.totalOut)
                        if a.totalOut > 200_000 && a.totalOut > a.totalIn * 2 {
                            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                                .foregroundStyle(Theme.warn).help("Cette application envoie bien plus de données qu'elle n'en reçoit.")
                        }
                    }
                }.width(min: 90, ideal: 110)
                TableColumn("Reçu", value: \.totalIn) { a in ReceivedText(bytes: a.totalIn) }.width(min: 80, ideal: 95)
                TableColumn("Envoi/s", value: \.rateOut) { a in RateText(value: a.rateOut, color: Theme.up) }.width(min: 80, ideal: 95)
                TableColumn("Réception/s", value: \.rateIn) { a in RateText(value: a.rateIn, color: Theme.down) }.width(min: 90, ideal: 105)
                TableColumn("Connexions", value: \.connectionCount) { a in Text("\(a.connectionCount)").monospacedDigit() }.width(min: 70, ideal: 80)
                TableColumn("Destinations", value: \.destinationCount) { a in Text("\(a.destinationCount)").monospacedDigit() }.width(min: 70, ideal: 85)
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Chercher une application")
        }
        .background(Theme.page)
        .inspector(isPresented: Binding(get: { nav.selectedApp != nil }, set: { if !$0 { nav.selectedApp = nil } })) {
            if let id = nav.selectedApp, let app = store.apps.first(where: { $0.id == id }) {
                AppDetail(app: app).inspectorColumnWidth(min: 300, ideal: 360, max: 460)
            } else {
                EmptyHint(symbol: "square.grid.2x2", title: "Aucune application sélectionnée", text: "").inspectorColumnWidth(min: 300, ideal: 360, max: 460)
            }
        }
    }
}

struct AppDetail: View {
    @Environment(NetworkStore.self) private var store
    @Environment(Nav.self) private var nav
    var app: AppRow

    var body: some View {
        let dests = store.destinations(forApp: app.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    AppIconView(path: app.path, system: app.isSystem, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.system(size: 18, weight: .bold)).lineLimit(2)
                        Text(app.kind).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Card {
                    VStack(spacing: 7) {
                        HStack { Text("Envoyé").foregroundStyle(.secondary); Spacer(); SentText(bytes: app.totalOut).font(.system(size: 15, weight: .bold)) }
                        HStack { Text("Reçu").foregroundStyle(.secondary); Spacer(); ReceivedText(bytes: app.totalIn).font(.system(size: 15, weight: .bold)) }
                        Divider()
                        KeyValueRow(key: "Débit actuel", value: "↓ \(Fmt.rate(app.rateIn))   ↑ \(Fmt.rate(app.rateOut))")
                        KeyValueRow(key: "Connexions ouvertes", value: "\(app.connectionCount)")
                        KeyValueRow(key: "Processus", value: app.pids.prefix(6).map(String.init).joined(separator: ", ") + (app.pids.count > 6 ? "…" : ""))
                    }
                    .font(.system(size: 12.5))
                }
                if app.totalOut > 200_000 && app.totalOut > app.totalIn * 2 {
                    Label("Cette application envoie nettement plus de données qu'elle n'en reçoit (ex. sauvegarde, synchronisation, ou envoi de statistiques).",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.warn)
                        .padding(10).background(Theme.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
                if let p = app.path {
                    Text(p).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("À qui cette application envoie des données").font(.system(size: 13, weight: .semibold))
                if dests.isEmpty {
                    Text("Aucune destination pour l'instant.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(dests) { d in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(d.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                ScopeBadge(scope: d.scope)
                                Spacer()
                            }
                            HStack {
                                if d.host != nil { Text(d.ip).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
                                Spacer()
                                Label(Fmt.bytes(d.totalOut), systemImage: "arrow.up").foregroundStyle(Theme.up)
                                Label(Fmt.bytes(d.totalIn), systemImage: "arrow.down").foregroundStyle(Theme.down)
                            }
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { nav.selectedDest = d.id; nav.section = .destinations }
                        Divider()
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.page)
    }
}
