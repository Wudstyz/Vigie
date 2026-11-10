import SwiftUI

struct ContentView: View {
    @Environment(NetworkStore.self) private var store
    @Environment(Nav.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SidebarSection.allCases, selection: $nav.section) { s in
                    Label(s.title, systemImage: s.symbol)
                        .badge(badge(for: s))
                        .tag(s)
                }
                .listStyle(.sidebar)

                SidebarFooter()
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch nav.section {
                case .overview: OverviewView()
                case .apps: AppsView()
                case .destinations: DestinationsView()
                case .connections: ConnectionsView()
                case .ports: PortsView()
                case .dns: DNSView()
                case .devices: DevicesView()
                case .network: NetworkView()
                case .journal: JournalView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if store.isDemo { Badge(text: "MODE DÉMO", color: Theme.warn) }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { store.togglePause() } label: {
                    Label(store.paused ? "Reprendre" : "Pause", systemImage: store.paused ? "play.fill" : "pause.fill")
                }
                .help(store.paused ? "Reprendre le suivi" : "Mettre le suivi en pause")
            }
        }
    }

    private func badge(for s: SidebarSection) -> Int {
        switch s {
        case .apps: return store.apps.filter { $0.rateIn + $0.rateOut >= 1 }.count
        case .connections: return store.connections.filter { $0.scope == .internet || $0.scope == .lan }.count
        case .ports: return store.listeners.filter(\.exposed).count
        case .devices: return store.devices.count
        default: return 0
        }
    }
}

struct SidebarFooter: View {
    @Environment(NetworkStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Circle().fill(store.paused ? Color.gray : Theme.ok).frame(width: 8, height: 8)
                Text(store.paused ? "En pause" : "En direct").font(.system(size: 12, weight: .medium))
            }
            RatePair(down: store.rateDown, up: store.rateUp)
            if let m = store.statusMessage {
                Text(m).font(.system(size: 11)).foregroundStyle(Theme.warn)
            }
            Toggle(isOn: Binding(get: { store.isDemo }, set: { store.setDemo($0) })) {
                Text("Mode démonstration").font(.system(size: 12))
            }
            .toggleStyle(.switch).controlSize(.small)
            .help("Affiche des données fictives, pour essayer l'app ou faire des captures d'écran.")
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }
}
