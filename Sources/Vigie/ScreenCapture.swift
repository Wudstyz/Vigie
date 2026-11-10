import AppKit
import SwiftUI

/// Outil interne : `Vigie --capture DOSSIER` ouvre l'app en mode démonstration, parcourt chaque écran
/// et enregistre une capture PNG haute définition de la fenêtre. Sert aux tests et à la documentation.
@MainActor
enum ScreenCapture {
    static func run(into dir: String) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            // Laisser le temps à la fenêtre d'apparaître et aux données de s'accumuler (graphique, journal…)
            let delay = UInt64((Double(ProcessInfo.processInfo.environment["VIGIE_CAPTURE_DELAY"] ?? "") ?? 14) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)

            guard let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) else {
                FileHandle.standardError.write(Data("Aucune fenêtre à capturer\n".utf8)); NSApp.terminate(nil); return
            }
            window.setContentSize(NSSize(width: 1440, height: 900))
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(nanoseconds: 800_000_000)

            let nav = Nav.shared
            let store = NetworkStore.shared
            for section in SidebarSection.allCases {
                nav.section = section
                nav.selectedApp = nil; nav.selectedDest = nil
                if section == .apps { nav.selectedApp = store.apps.first(where: { $0.name == "DocuNuage" })?.id ?? store.apps.first?.id }
                if section == .destinations { nav.selectedDest = store.destinations.first(where: { $0.scope == .internet })?.id }
                // Le scan du réseau local réel prend quelques secondes : on le laisse finir.
                try? await Task.sleep(nanoseconds: section == .devices && !store.isDemo ? 10_000_000_000 : 1_600_000_000)
                save(window: window, name: section.rawValue, dir: dir)
            }
            // Aide aux tests : liste des alertes détectées (VIGIE_DUMP_ALERTS=fichier)
            if let f = ProcessInfo.processInfo.environment["VIGIE_DUMP_ALERTS"], !f.isEmpty {
                let now = store.lastSampleDate ?? Date()
                let lines = store.alerts.map { a in
                    "\(a.severity.label)\t\(a.oneShot ? "ponctuelle" : (a.isOngoing(at: now) ? "en cours" : "terminée"))\t\(a.dismissed ? "ignorée" : "active")\t\(a.id)\t\(a.title)"
                }
                try? lines.joined(separator: "\n").write(toFile: f, atomically: true, encoding: .utf8)
            }
            NSApp.terminate(nil)
        }
    }

    private static func save(window: NSWindow, name: String, dir: String) {
        let id = CGWindowID(window.windowNumber)
        // Capture de la fenêtre elle-même (avec sa barre de titre), sans autorisation d'enregistrement d'écran
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", String(id), "\(dir)/\(name).png"]
        try? task.run(); task.waitUntilExit()
        if !FileManager.default.fileExists(atPath: "\(dir)/\(name).png"), let view = window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }
}
