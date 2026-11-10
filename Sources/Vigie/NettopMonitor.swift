import Foundation

/// Interroge l'outil système `nettop` (présent sur tous les Mac) une fois par intervalle et transforme
/// sa sortie en échantillons. Aucun mot de passe administrateur n'est nécessaire.
///
/// Pourquoi des relevés ponctuels (`-L 1`) plutôt que le flux continu (`-L 0`) ? Mesuré sur un Mac réel :
/// le flux continu occupe ~120 % d'un cœur en permanence, alors qu'un relevé ponctuel ne coûte que
/// ~0,015 s (soit ~1,5 % à un relevé par seconde).
final class NettopMonitor {
    private let queue = DispatchQueue(label: "vigie.nettop", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var busy = false
    private var stopped = true
    private var failures = 0
    private let interval: TimeInterval
    var onSample: ((Sample) -> Void)?
    var onProblem: ((String) -> Void)?

    init(interval: TimeInterval = 1) { self.interval = interval }

    func start() {
        queue.async { [self] in
            guard stopped else { return }
            stopped = false
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
            t.setEventHandler { [weak self] in self?.poll() }
            timer = t
            t.resume()
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            timer?.cancel()
            timer = nil
        }
    }

    private func poll() {
        guard !stopped, !busy else { return }
        busy = true
        defer { busy = false }

        let started = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        p.arguments = ["-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out,state"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch {
            failures += 1
            if failures == 3 { onProblem?("Impossible de lancer nettop : \(error.localizedDescription)") }
            return
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()

        var parser = NettopParser()
        let text = String(decoding: data, as: UTF8.self)
        var result: Sample?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let done = parser.feed(line: String(line), now: started) { result = done }
        }
        if let last = parser.flush() { result = last }
        if let s = result, !s.isEmpty {
            failures = 0
            onSample?(s)
        } else {
            failures += 1
            if failures == 3 { onProblem?("Le suivi réseau ne répond pas, nouvelle tentative…") }
        }
    }
}
