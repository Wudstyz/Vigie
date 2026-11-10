import Foundation
import Darwin

/// Découvre les appareils du réseau local : envoie un tout petit paquet UDP à chaque adresse du
/// réseau (/24 au maximum) pour que le Mac interroge ARP, puis lit la table ARP du système.
/// Rien n'est envoyé hors du réseau local.
final class LANScanner {
    struct Found {
        var ip: String
        var mac: String
        var name: String?
    }

    struct LocalNet {
        var interface: String
        var ip: String
        var maskPrefix: Int
        var gateway: String?
    }

    /// Réseau local principal : interface de la route par défaut.
    static func localNet() -> LocalNet? {
        let route = Shell.run("/sbin/route", ["-n", "get", "default"])
        var gw: String?, iface: String?
        for l in route.split(separator: "\n") {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("gateway:") { gw = t.dropFirst(8).trimmingCharacters(in: .whitespaces) }
            if t.hasPrefix("interface:") { iface = t.dropFirst(10).trimmingCharacters(in: .whitespaces) }
        }
        guard let iface else { return nil }
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0, let first = ptr else { return nil }
        defer { freeifaddrs(ptr) }
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            let a = p.pointee; cur = a.ifa_next
            guard String(cString: a.ifa_name) == iface, let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  let mask = a.ifa_netmask else { continue }
            let ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let m = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var ipc = ip, ipbuf = [CChar](repeating: 0, count: 64)
            inet_ntop(AF_INET, &ipc, &ipbuf, 64)
            let prefix = UInt32(bigEndian: m.s_addr).nonzeroBitCount
            return LocalNet(interface: iface, ip: String(cString: ipbuf), maskPrefix: prefix, gateway: gw)
        }
        return nil
    }

    /// Adresses à sonder (limité au /24 qui contient le Mac, pour rester léger et poli).
    static func hosts(of net: LocalNet) -> [String] {
        guard let b = Net.v4Bytes(net.ip) else { return [] }
        return (1...254).map { "\(b[0]).\(b[1]).\(b[2]).\($0)" }
    }

    static func scan(net: LocalNet, completion: @escaping ([Found]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            // 1) Réveiller ARP : un datagramme UDP vers chaque adresse (port 9 « discard »)
            let s = socket(AF_INET, SOCK_DGRAM, 0)
            if s >= 0 {
                var payload: UInt8 = 0
                for host in hosts(of: net) {
                    var sa = sockaddr_in()
                    sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                    sa.sin_family = sa_family_t(AF_INET)
                    sa.sin_port = UInt16(9).bigEndian
                    inet_pton(AF_INET, host, &sa.sin_addr)
                    _ = withUnsafePointer(to: &sa) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(s, &payload, 1, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                    usleep(2000)
                }
                close(s)
            }
            Thread.sleep(forTimeInterval: 1.8)

            // 2) Lire la table ARP
            var found = readARP(interface: net.interface)

            // 3) Noms (mDNS / DNS inverse), en parallèle
            let group = DispatchGroup()
            let lock = NSLock()
            for i in found.indices {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    let n = HostResolver.reverse(found[i].ip)
                    lock.lock(); found[i].name = n; lock.unlock()
                    group.leave()
                }
            }
            _ = group.wait(timeout: .now() + 4)
            completion(found)
        }
    }

    static func readARP(interface: String) -> [Found] {
        var out: [Found] = []
        for l in Shell.run("/usr/sbin/arp", ["-an"]).split(separator: "\n") {
            // ? (192.168.1.10) at 0:0:5e:0:53:1 on en0 ifscope permanent [ethernet]
            guard let o = l.firstIndex(of: "("), let c = l.firstIndex(of: ")"), o < c else { continue }
            let ip = String(l[l.index(after: o)..<c])
            let rest = l[l.index(after: c)...].split(separator: " ").map(String.init)
            guard rest.count >= 4, rest[0] == "at", rest[2] == "on", rest[3] == interface else { continue }
            let macRaw = rest[1]
            guard macRaw != "(incomplete)", Net.scope(of: ip) == .lan else { continue }
            let mac = macRaw.split(separator: ":").map { $0.count == 1 ? "0\($0)" : String($0) }.joined(separator: ":")
            if mac == "ff:ff:ff:ff:ff:ff" { continue }
            out.append(Found(ip: ip, mac: mac, name: nil))
        }
        return out
    }

    /// Une adresse MAC « aléatoire » (confidentialité Wi-Fi d'Apple, Android…) a le bit 0x02 du 1er octet.
    static func isRandomMAC(_ mac: String) -> Bool {
        guard let first = mac.split(separator: ":").first, let v = UInt8(first, radix: 16) else { return false }
        return v & 0x02 != 0
    }
}

// MARK: - Petit utilitaire pour lancer une commande système

enum Shell {
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 8) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
