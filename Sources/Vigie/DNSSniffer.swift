import Foundation
import Darwin

/// Analyse les lignes de `tcpdump -n` concernant le DNS.
/// On relie chaque réponse à sa question (même « client:port » + même identifiant) pour savoir
/// quel NOM DE DOMAINE correspond à quelle ADRESSE IP — c'est ce qui permet de dire « à qui » ça part.
struct DNSLineParser {
    struct Event {
        var name: String
        var type: String
        var answers: [String]      // adresses IP renvoyées (vide pour une simple question)
    }

    private var pending: [String: (name: String, type: String)] = [:]
    private var order: [String] = []

    private static let queryRx = try! NSRegularExpression(
        pattern: #"^\S+ IP6? (\S+) > \S+: (\d+)\S* ([A-Za-z0-9]+)\? (\S+?)\.? \("#)
    private static let responseRx = try! NSRegularExpression(
        pattern: #"^\S+ IP6? \S+ > (\S+): (\d+)\S* (?:q: )?(?:[A-Za-z0-9]+\? \S+ )?(\d+)/\d+/\d+ (.*?) \(\d+\)\s*$"#)
    private static let answerRx = try! NSRegularExpression(pattern: #"\b(A|AAAA) ([0-9A-Fa-f:.]+)"#)

    mutating func parse(_ line: String) -> Event? {
        let range = NSRange(line.startIndex..., in: line)
        if let m = Self.queryRx.firstMatch(in: line, range: range) {
            let client = line.sub(m, 1), id = line.sub(m, 2), type = line.sub(m, 3), name = line.sub(m, 4)
            let key = "\(client)#\(id)"
            pending[key] = (name.lowercased(), type)
            order.append(key)
            if order.count > 2000 { for k in order.prefix(1000) { pending[k] = nil }; order.removeFirst(1000) }
            return Event(name: name.lowercased(), type: type, answers: [])
        }
        if let m = Self.responseRx.firstMatch(in: line, range: range) {
            let client = line.sub(m, 1), id = line.sub(m, 2), count = Int(line.sub(m, 3)) ?? 0
            let rest = line.sub(m, 4)
            guard count > 0, let q = pending[ "\(client)#\(id)" ] else { return nil }
            var ips: [String] = []
            let r2 = NSRange(rest.startIndex..., in: rest)
            for a in Self.answerRx.matches(in: rest, range: r2) {
                let ip = rest.sub(a, 2)
                if Net.v4Bytes(ip) != nil || Net.v6Bytes(ip) != nil { ips.append(ip) }
            }
            return ips.isEmpty ? nil : Event(name: q.name, type: q.type, answers: ips)
        }
        return nil
    }
}

private extension String {
    func sub(_ m: NSTextCheckingResult, _ i: Int) -> String {
        guard let r = Range(m.range(at: i), in: self) else { return "" }
        return String(self[r])
    }
}

/// Démarre `tcpdump` avec les droits administrateur (fenêtre officielle de macOS) et lit son résultat
/// à travers un tube nommé appartenant à l'utilisateur. Vigie ne voit jamais le mot de passe.
final class DNSSniffer {
    var onEvent: ((DNSLineParser.Event) -> Void)?
    var onStatus: ((String) -> Void)?
    private var running = false
    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "vigie.dnssniffer")

    static var fifoPath: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vigie")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dns.fifo").path
    }

    func start() {
        guard !running else { return }
        running = true
        let path = Self.fifoPath
        unlink(path)
        guard mkfifo(path, 0o600) == 0 else { running = false; onStatus?("Impossible de préparer le tube de lecture."); return }

        queue.async { [self] in
            // Ouverture non bloquante côté lecture
            fd = open(path, O_RDONLY | O_NONBLOCK)
            guard fd >= 0 else { running = false; return }

            // Demande d'autorisation administrateur (fenêtre macOS) puis lancement en arrière-plan
            let shell = "/usr/sbin/tcpdump -l -n -i any -s 512 'udp port 53 or tcp port 53' > '\(path)' 2>/dev/null < /dev/null &"
            let apple = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", apple]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { fail("Impossible d'ouvrir la demande d'autorisation."); return }
            DispatchQueue.global().async { [self] in
                p.waitUntilExit()
                if p.terminationStatus != 0 { fail("Autorisation refusée : le mode avancé reste désactivé.") }
                else { onStatus?("Écoute des requêtes DNS active.") }
            }
            readLoop()
        }
    }

    func stop() {
        running = false   // la boucle de lecture se ferme ; tcpdump s'arrête tout seul à sa prochaine écriture
    }

    private func fail(_ msg: String) {
        running = false
        onStatus?(msg)
    }

    private func readLoop() {
        var parser = DNSLineParser()
        var buf = [UInt8](repeating: 0, count: 65536)
        var carry = Data()
        while running {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                carry.append(buf, count: n)
                while let nl = carry.firstIndex(of: 0x0A) {
                    let lineData = carry[carry.startIndex..<nl]
                    carry.removeSubrange(carry.startIndex...nl)
                    if let line = String(data: lineData, encoding: .utf8), let ev = parser.parse(line) { onEvent?(ev) }
                }
            } else {
                usleep(250_000)
            }
        }
        close(fd); fd = -1
        unlink(Self.fifoPath)
        onStatus?("Mode avancé arrêté.")
    }
}
