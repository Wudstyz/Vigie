import SwiftUI

extension Severity {
    var color: Color {
        switch self {
        case .info: return Theme.accent
        case .attention: return Theme.warn
        case .important: return Color(red: 0.84, green: 0.18, blue: 0.2)
        }
    }
}

// MARK: - Bandeau d'état (Vue d'ensemble)

struct VigilanceBanner: View {
    @Environment(NetworkStore.self) private var store
    @Environment(Nav.self) private var nav
    @AppStorage("vigilance") private var vigilance = true

    var body: some View {
        let active = store.activeAlerts
        Group {
            if !vigilance {
                banner(symbol: "shield.slash", color: .gray, title: "La vigilance est désactivée",
                       text: "Vigie n'est pas en train de chercher ce qui sort de l'ordinaire.") {
                    Button("Activer") { vigilance = true }.buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                }
            } else if let top = store.topSeverity {
                banner(symbol: top.symbol, color: top.color,
                       title: top >= .attention
                           ? (store.attentionAlertCount == 1 ? "1 point à vérifier" : "\(store.attentionAlertCount) points à vérifier")
                           : (active.count == 1 ? "1 nouveauté à savoir" : "\(active.count) nouveautés à savoir"),
                       text: active.prefix(2).map(\.title).joined(separator: " · ")) {
                    Button("Voir") { nav.section = .vigilance }.buttonStyle(.borderedProminent).tint(top.color).controlSize(.small)
                }
            } else if let end = store.learningEnds {
                let mins = max(1, Int(end.timeIntervalSinceNow / 60) + 1)
                banner(symbol: "graduationcap.fill", color: Theme.accent, title: "Vigie apprend ce qui est habituel sur ce Mac",
                       text: "Encore environ \(mins) min : pendant ce temps, les nouveautés (applications, appareils) ne sont pas signalées. Les envois massifs et les pannes le sont déjà.") { EmptyView() }
            } else {
                banner(symbol: "checkmark.shield.fill", color: Theme.ok, title: "Tout semble normal",
                       text: "Vigie surveille les envois massifs, les nouvelles applications, les nouveaux appareils, les ports ouverts et les pannes de connexion.") {
                    Button("Détails") { nav.section = .vigilance }.controlSize(.small)
                }
            }
        }
    }

    private func banner<T: View>(symbol: String, color: Color, title: String, text: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(color).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            trailing()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.35)))
    }
}

// MARK: - Écran Vigilance

struct VigilanceView: View {
    @Environment(NetworkStore.self) private var store
    @Environment(Nav.self) private var nav
    @AppStorage("vigilance") private var vigilance = true
    @AppStorage("sensitivity") private var sensitivity = Sensitivity.normal.rawValue
    @State private var showHistory = false

    var body: some View {
        let active = store.activeAlerts.sorted { ($0.severity, $0.lastSeen) > ($1.severity, $1.lastSeen) }
        let past = store.alerts.filter { a in !active.contains(where: { $0.id == a.id }) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Vigilance",
                           subtitle: "Vigie repère ce qui sort de l'ordinaire sur votre réseau et vous prévient.") {
                    VStack(alignment: .trailing, spacing: 8) {
                        Toggle("Mode vigilance", isOn: $vigilance).toggleStyle(.switch)
                        HStack(spacing: 6) {
                            Text("Sensibilité").font(.system(size: 12)).foregroundStyle(.secondary)
                            Picker("", selection: $sensitivity) {
                                ForEach(Sensitivity.allCases) { Text($0.label).tag($0.rawValue) }
                            }.pickerStyle(.segmented).frame(width: 210).labelsHidden()
                        }.disabled(!vigilance)
                    }
                }

                VigilanceBanner()

                if vigilance {
                    if active.isEmpty {
                        Card {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.ok)
                                Text("Aucune alerte en cours.").font(.system(size: 13.5, weight: .medium))
                                Spacer()
                            }
                        }
                    }
                    ForEach(active) { a in AlertCard(alert: a) }

                    if !past.isEmpty {
                        DisclosureGroup(isExpanded: $showHistory) {
                            VStack(spacing: 8) {
                                ForEach(past.prefix(30)) { a in AlertCard(alert: a, compact: true) }
                            }.padding(.top, 8)
                        } label: {
                            Text("Terminées ou ignorées (\(past.count))").font(.system(size: 13, weight: .semibold))
                        }
                    }
                }

                WatchedRulesCard()
            }
            .padding(24)
        }
        .background(Theme.page)
    }
}

struct AlertCard: View {
    @Environment(NetworkStore.self) private var store
    @Environment(Nav.self) private var nav
    var alert: AlertRow
    var compact = false

    var body: some View {
        let now = store.lastSampleDate ?? Date()
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.symbol)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(alert.severity.color.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Badge(text: alert.severity.label, color: alert.severity.color)
                    if !alert.oneShot { Badge(text: alert.isOngoing(at: now) ? "En cours" : "Terminée", color: alert.isOngoing(at: now) ? Theme.warn : .gray) }
                    if alert.dismissed { Badge(text: "Ignorée", color: .gray) }
                    Spacer()
                    Text(Fmt.ago(alert.firstSeen, now: now)).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Text(alert.title).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                if !compact {
                    Text(alert.explanation).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if alert.dismissed {
                            Button("Réafficher") { store.restore(alert.id) }
                        } else {
                            Button("Ignorer") { store.dismiss(alert.id) }
                        }
                        if let key = alert.appKey, let name = alert.appName, !store.isTrusted(appKey: key) {
                            Button("Faire confiance à \(name)") { store.trust(appKey: key) }
                                .help("Vigie ne signalera plus rien au sujet de cette application.")
                            Button("Voir l'application") { nav.selectedApp = key; nav.section = .apps }
                        }
                    }.controlSize(.small).padding(.top, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(alert.dismissed ? Theme.line : alert.severity.color.opacity(0.35)))
        .opacity(alert.dismissed ? 0.65 : 1)
    }
}

struct WatchedRulesCard: View {
    @Environment(NetworkStore.self) private var store
    var body: some View {
        Card(title: "Ce que Vigie surveille", subtitle: "Tout se passe sur votre Mac : aucune alerte n'est envoyée à qui que ce soit.") {
            VStack(alignment: .leading, spacing: 9) {
                rule("arrow.up.circle.fill", "Envois massifs", "une application qui envoie beaucoup plus de données sur Internet qu'elle n'en reçoit (applications système exclues).")
                rule("sparkles", "Nouvelles applications", "une application qui utilise Internet pour la première fois.")
                rule("folder.badge.questionmark", "Programmes suspects", "un programme non signé, lancé depuis un dossier temporaire, de téléchargements ou caché, qui utilise Internet.")
                rule("network.badge.shield.half.filled", "Ports à risque", "une connexion vers un port souvent utilisé par des outils de prise de contrôle à distance.")
                rule("door.left.hand.open", "Ports ouverts", "une application qui accepte des connexions venant du réseau.")
                rule("laptopcomputer.and.iphone", "Appareils", "un appareil jamais vu sur votre réseau, ou une box dont l'adresse matérielle change.")
                rule("wifi.exclamationmark", "Pannes", "box ou Internet qui ne répondent plus, réseau très lent, signal Wi-Fi faible.")
            }
            Divider().padding(.vertical, 2)
            HStack {
                Text("Limite : Vigie voit qui parle à qui et combien, pas le contenu des échanges. Une alerte est un signal à vérifier, pas la preuve d'un problème.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if store.trustedCount > 0 {
                    Button("Ne plus faire confiance à \(store.trustedCount) app\(store.trustedCount > 1 ? "s" : "")") { store.untrustAll() }.controlSize(.small)
                }
            }
        }
    }

    private func rule(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 20)
            (Text(title).fontWeight(.semibold) + Text(" — " + text)).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
