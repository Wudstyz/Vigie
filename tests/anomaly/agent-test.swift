// Programme de TEST de la vigilance de Vigie : volontairement « louche » (non signé, dossier temporaire).
//  1) ouvre un port TCP visible depuis le réseau ;
//  2) envoie ~45 Mo vers le serveur public de test de débit de Cloudflare (speed.cloudflare.com).
import Foundation
import Darwin

// 1) port en écoute sur toutes les interfaces
let ls = socket(AF_INET, SOCK_STREAM, 0)
var yes: Int32 = 1
setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
var addr = sockaddr_in()
addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); addr.sin_family = sa_family_t(AF_INET)
addr.sin_port = UInt16(48650).bigEndian; addr.sin_addr.s_addr = INADDR_ANY
_ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(ls, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
listen(ls, 4)
print("écoute sur le port 48650")

// 2) envoi massif, en 5 morceaux de 9 Mo
let chunk = Data(count: 9_000_000)
var req = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!)
req.httpMethod = "POST"
let sem = DispatchSemaphore(value: 0)
var sent = 0
func next() {
    if sent >= 5 { sem.signal(); return }
    URLSession.shared.uploadTask(with: req, from: chunk) { _, r, e in
        sent += 1
        print("morceau \(sent)/5 envoyé", (r as? HTTPURLResponse)?.statusCode ?? -1, e?.localizedDescription ?? "")
        next()
    }.resume()
}
next()
_ = sem.wait(timeout: .now() + 90)
// on garde le port ouvert encore un moment
sleep(40)
print("fin")
