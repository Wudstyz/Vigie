import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(NetworkStore.self) private var store
    @Environment(Nav.self) private var nav

    private var topSenders: [AppRow] {
        Array(store.apps.filter { $0.totalOut > 0 }.sorted { $0.totalOut > $1.totalOut }.prefix(6))
    }
    private var topDestinations: [DestinationRow] {
        Array(store.destinations.filter { $0.scope == .internet || $0.scope == .lan }.sorted { $0.totalOut > $1.totalOut }.prefix(6))
    }
    private var activeApps: Int { store.apps.filter { $0.rateIn + $0.rateOut >= 1 }.count }
    private var internetDestinations: Int { store.destinations.filter { $0.scope == .internet }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Vue d'ensemble",
                           subtitle: store.isDemo ? "Mode démonstration : toutes les données affichées sont fictives."
                                                  : "Tout ce que votre Mac envoie et reçoit, en direct. Lecture seule : Vigie ne modifie rien.")

                HStack(spacing: 12) {
                    StatCard(title: "Reçu", value: Fmt.rate(store.rateDown), detail: "\(Fmt.bytes(store.totalDown)) depuis l'ouverture",
                             symbol: "arrow.down.circle.fill", color: Theme.down)
                    StatCard(title: "Envoyé", value: Fmt.rate(store.rateUp), detail: "\(Fmt.bytes(store.totalUp)) depuis l'ouverture",
                             symbol: "arrow.up.circle.fill", color: Theme.up)
                    StatCard(title: "Latence", value: store.latencyGateway.map { String(format: "%.0f ms", $0) } ?? "—",
                             detail: latencyDetail, symbol: "timer", color: Theme.accent)
                    StatCard(title: "Applications actives", value: "\(activeApps)",
                             detail: "\(internetDestinations) destinations sur Internet", symbol: "square.grid.2x2.fill", color: Theme.accent)
                }

                Card(title: "Débit en direct", subtitle: "Les 4 dernières minutes, toutes interfaces réseau confondues") {
                    RateChart(points: store.history).frame(height: 190)
                }

                HStack(alignment: .top, spacing: 12) {
                    Card(title: "Qui envoie le plus de données ?", subtitle: "Total envoyé par application depuis l'ouverture") {
                        if topSenders.isEmpty { Text("Rien d'envoyé pour l'instant.").foregroundStyle(.secondary).font(.system(size: 12)) }
                        let maxV = Double(topSenders.first?.totalOut ?? 1)
                        VStack(spacing: 11) {
                            ForEach(topSenders) { a in
                                HStack(spacing: 10) {
                                    AppIconView(path: a.path, system: a.isSystem, size: 26)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(a.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                            Spacer()
                                            SentText(bytes: a.totalOut).font(.system(size: 12.5, weight: .semibold))
                                        }
                                        UsageBar(value: Double(a.totalOut), maxValue: maxV, color: Theme.up)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { nav.selectedApp = a.id; nav.section = .apps }
                            }
                        }
                    }
                    Card(title: "Vers qui partent vos données ?", subtitle: "Destinations qui ont reçu le plus de données de votre part") {
                        if topDestinations.isEmpty { Text("Aucune destination pour l'instant.").foregroundStyle(.secondary).font(.system(size: 12)) }
                        let maxV = Double(topDestinations.first?.totalOut ?? 1)
                        VStack(spacing: 11) {
                            ForEach(topDestinations) { d in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(d.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                        ScopeBadge(scope: d.scope)
                                        Spacer()
                                        SentText(bytes: d.totalOut).font(.system(size: 12.5, weight: .semibold))
                                    }
                                    UsageBar(value: Double(d.totalOut), maxValue: maxV, color: Theme.up)
                                    Text(d.appsText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { nav.selectedDest = d.id; nav.section = .destinations }
                            }
                        }
                    }
                }

                Card(title: "Dernières nouveautés", subtitle: "Nouvelles destinations, ports ouverts, appareils") {
                    if store.events.isEmpty {
                        Text("Rien de nouveau pour l'instant. Les nouveautés apparaîtront ici dès qu'une application contacte une nouvelle adresse.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 8) {
                        ForEach(store.events.prefix(6)) { e in EventLine(event: e) }
                    }
                }
            }
            .padding(24)
        }
        .background(Theme.page)
    }

    private var latencyDetail: String {
        if let i = store.latencyInternet { return String(format: "box · Internet %.0f ms", i) }
        return store.latencyGateway == nil ? "mesure en cours…" : "vers votre box"
    }
}

struct EventLine: View {
    var event: EventRow
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.kind.symbol)
                .foregroundStyle(event.kind == .newListener ? Theme.warn : Theme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(event.detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Fmt.clock.string(from: event.date)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct RateChart: View {
    var points: [RatePoint]

    var body: some View {
        if points.count < 2 {
            EmptyHint(symbol: "waveform.path.ecg", title: "Collecte en cours…", text: "Le graphique apparaît après quelques secondes.")
        } else {
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Heure", p.date), y: .value("Débit", p.down), series: .value("Sens", "Reçu"))
                        .foregroundStyle(Theme.down.opacity(0.18)).interpolationMethod(.monotone)
                    LineMark(x: .value("Heure", p.date), y: .value("Débit", p.down), series: .value("Sens", "Reçu"))
                        .foregroundStyle(Theme.down).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2))
                    AreaMark(x: .value("Heure", p.date), y: .value("Débit", p.up), series: .value("Sens", "Envoyé"))
                        .foregroundStyle(Theme.up.opacity(0.22)).interpolationMethod(.monotone)
                    LineMark(x: .value("Heure", p.date), y: .value("Débit", p.up), series: .value("Sens", "Envoyé"))
                        .foregroundStyle(Theme.up).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.black.opacity(0.1))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.rateShort(d)).font(.system(size: 10)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { v in
                    AxisValueLabel { if let d = v.as(Date.self) { Text(Fmt.clock.string(from: d)).font(.system(size: 10)) } }
                }
            }
            .chartLegend(.hidden)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 14) {
                    Label("Reçu", systemImage: "circle.fill").foregroundStyle(Theme.down)
                    Label("Envoyé", systemImage: "circle.fill").foregroundStyle(Theme.up)
                }
                .labelStyle(LegendDot()).font(.system(size: 11.5, weight: .medium))
            }
        }
    }
}

struct LegendDot: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7))
            configuration.title.foregroundStyle(.primary)
        }
    }
}
