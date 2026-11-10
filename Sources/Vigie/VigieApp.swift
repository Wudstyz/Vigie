import SwiftUI
import AppKit

extension NetworkStore {
    static let shared = NetworkStore()
}

@main
struct VigieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("showMenuBar") private var showMenuBar = true
    private let store = NetworkStore.shared

    var body: some Scene {
        WindowGroup("Vigie", id: "main") {
            ContentView()
                .environment(NetworkStore.shared)
                .environment(Nav.shared)
                .frame(minWidth: 1060, minHeight: 680)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Suivi") {
                Button("Pause / Reprendre") { NetworkStore.shared.togglePause() }.keyboardShortcut("p", modifiers: [.command])
                Button("Analyser le réseau local") { NetworkStore.shared.scanLAN() }.keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarContent()
                .environment(NetworkStore.shared)
                .preferredColorScheme(.light)
        } label: {
            MenuBarLabel().environment(NetworkStore.shared)
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Thème clair uniquement
        NSApp.appearance = NSAppearance(named: .aqua)
        let args = CommandLine.arguments
        let captureDir = args.firstIndex(of: "--capture").flatMap { i in i + 1 < args.count ? args[i + 1] : nil }
        let demo = args.contains("--demo") || (captureDir != nil && !args.contains("--real"))
        Task { @MainActor in
            NetworkStore.shared.start(demo: demo)
            if let dir = captureDir { ScreenCapture.run(into: dir) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { NetworkStore.shared.shutdown() }
    }
}

// MARK: - Barre des menus

struct MenuBarLabel: View {
    @Environment(NetworkStore.self) private var store
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: store.attentionAlertCount > 0 ? "exclamationmark.shield.fill" : "dot.radiowaves.left.and.right")
            Text("↓\(Fmt.rateShort(store.rateDown))  ↑\(Fmt.rateShort(store.rateUp))").monospacedDigit()
        }
    }
}

struct MenuBarContent: View {
    @Environment(NetworkStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let top = Array(store.apps.sorted { $0.rateIn + $0.rateOut > $1.rateIn + $1.rateOut }.prefix(5))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Vigie").font(.system(size: 14, weight: .bold))
                Spacer()
                if store.isDemo { Badge(text: "DÉMO", color: Theme.warn) }
            }
            RatePair(down: store.rateDown, up: store.rateUp)
            if let top = store.topSeverity, top >= .attention {
                Label("\(store.attentionAlertCount) point\(store.attentionAlertCount > 1 ? "s" : "") à vérifier", systemImage: top.symbol)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(top.color)
            }
            Divider()
            Text("En ce moment").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if top.allSatisfy({ $0.rateIn + $0.rateOut < 1 }) {
                Text("Pas d'activité notable.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(top.filter { $0.rateIn + $0.rateOut >= 1 }) { a in
                HStack(spacing: 8) {
                    AppIconView(path: a.path, system: a.isSystem, size: 18)
                    Text(a.name).font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    Text("↓\(Fmt.rateShort(a.rateIn))").foregroundStyle(Theme.down)
                    Text("↑\(Fmt.rateShort(a.rateOut))").foregroundStyle(Theme.up)
                }.font(.system(size: 11.5).monospacedDigit())
            }
            Divider()
            HStack {
                Button("Ouvrir Vigie") {
                    NSApp.activate(ignoringOtherApps: true)
                    if NSApp.windows.contains(where: { $0.canBecomeMain }) {
                        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                    } else { openWindow(id: "main") }
                }
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }
            }.controlSize(.small)
        }
        .padding(14).frame(width: 330)
    }
}
