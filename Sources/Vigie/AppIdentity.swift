import AppKit
import Darwin

/// Retrouve, pour un processus, l'application à laquelle il appartient (nom, icône).
/// Les « helpers » d'un navigateur (ex. Chrome Helper) sont regroupés sous l'app principale.
struct AppIdentity {
    var key: String
    var name: String
    var path: String?
    var isSystem: Bool
}

final class AppIdentityResolver {
    private var cache: [Int32: (procName: String, identity: AppIdentity)] = [:]
    private var iconCache: [String: NSImage] = [:]

    func identity(pid: Int32, procName: String) -> AppIdentity {
        if let c = cache[pid], c.procName == procName { return c.identity }
        let id = resolve(pid: pid, procName: procName)
        cache[pid] = (procName, id)
        return id
    }

    private func resolve(pid: Int32, procName: String) -> AppIdentity {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        let path = n > 0 ? String(cString: buf) : nil

        if let path, let appPath = Self.outerAppPath(path) {
            let name = Self.displayName(appPath: appPath)
            let system = appPath.hasPrefix("/System/") || appPath.hasPrefix("/Library/Apple/")
            return AppIdentity(key: appPath, name: name, path: appPath, isSystem: system)
        }
        let system = path.map { $0.hasPrefix("/System/") || $0.hasPrefix("/usr/") || $0.hasPrefix("/sbin/") || $0.hasPrefix("/bin/") || $0.hasPrefix("/Library/Apple/") } ?? true
        let clean = Self.cleanName(procName)
        return AppIdentity(key: "proc:" + clean, name: clean, path: path, isSystem: system)
    }

    /// Premier composant « .app » du chemin (l'app la plus extérieure).
    static func outerAppPath(_ path: String) -> String? {
        let comps = path.split(separator: "/", omittingEmptySubsequences: true)
        var acc = ""
        for c in comps {
            acc += "/" + c
            if c.hasSuffix(".app") { return acc }
        }
        return nil
    }

    static func displayName(appPath: String) -> String {
        if let b = Bundle(path: appPath) {
            if let n = b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !n.isEmpty { return n }
            if let n = b.object(forInfoDictionaryKey: "CFBundleName") as? String, !n.isEmpty { return n }
        }
        return ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func cleanName(_ s: String) -> String {
        // « com.apple.WebKit.Networking » reste lisible ; on garde tel quel mais sans espace parasite.
        s.trimmingCharacters(in: .whitespaces)
    }

    /// Icône de l'application (ou icône générique pour les processus système).
    func icon(forKey key: String, path: String?) -> NSImage {
        if let i = iconCache[key] { return i }
        let img: NSImage
        if let path, path.hasSuffix(".app") {
            img = NSWorkspace.shared.icon(forFile: path)
        } else {
            img = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) ?? NSImage()
        }
        img.size = NSSize(width: 32, height: 32)
        iconCache[key] = img
        return img
    }
}

/// Cache d'icônes partagé par l'interface (accès depuis le fil principal uniquement).
@MainActor
enum IconProvider {
    private static var cache: [String: NSImage] = [:]
    static func icon(path: String?, system: Bool) -> NSImage {
        let k = path ?? (system ? "§sys" : "§bin")
        if let i = cache[k] { return i }
        let img: NSImage
        if let path, path.hasSuffix(".app") {
            img = NSWorkspace.shared.icon(forFile: path)
        } else {
            img = NSImage(systemSymbolName: system ? "gearshape.2.fill" : "terminal.fill", accessibilityDescription: nil) ?? NSImage()
        }
        cache[k] = img
        return img
    }
}
