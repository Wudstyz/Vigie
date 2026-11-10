import XCTest
@testable import Vigie

final class VigieTests: XCTestCase {

    // MARK: - nettop

    func testParsesNettopSample() {
        var p = NettopParser()
        let lines = [
            ",state,bytes_in,bytes_out,",
            "Safari.1234,,1000,2000,",
            "tcp4 192.168.1.10:62961<->203.0.113.50:443,Established,308525,732200,",
            "tcp6 2001:db8:1::1.50931<->2001:4860:4840:400::.443,Established,6438,2254,",
            "udp6 *.5353<->*.*,,10240567,4166542,",
            "tcp4 127.0.0.1:8021<->*:*,Listen,,,",
            "Mail Helper.99,,5,6,",
            "udp4 *:62084<->*:*,,0,416,",
            ",state,bytes_in,bytes_out,",
        ]
        var done: Sample?
        for l in lines { if let s = p.feed(line: l) { done = s } }
        guard let s = done else { return XCTFail("échantillon non terminé") }

        XCTAssertEqual(s.procs.count, 2)
        XCTAssertEqual(s.procs[0].name, "Safari"); XCTAssertEqual(s.procs[0].pid, 1234)
        XCTAssertEqual(s.procs[0].bytesIn, 1000); XCTAssertEqual(s.procs[0].bytesOut, 2000)
        XCTAssertEqual(s.procs[1].name, "Mail Helper"); XCTAssertEqual(s.procs[1].pid, 99)

        XCTAssertEqual(s.conns.count, 5)
        let c0 = s.conns[0]
        XCTAssertEqual(c0.pid, 1234); XCTAssertEqual(c0.proto, "TCP")
        XCTAssertEqual(c0.localAddr, "192.168.1.10"); XCTAssertEqual(c0.localPort, 62961)
        XCTAssertEqual(c0.remoteAddr, "203.0.113.50"); XCTAssertEqual(c0.remotePort, 443)
        XCTAssertEqual(c0.bytesIn, 308525); XCTAssertEqual(c0.bytesOut, 732200)
        XCTAssertFalse(c0.isListening)

        let c1 = s.conns[1]
        XCTAssertEqual(c1.remoteAddr, "2001:4860:4840:400::"); XCTAssertEqual(c1.remotePort, 443)

        let udp = s.conns[2]
        XCTAssertEqual(udp.proto, "UDP"); XCTAssertEqual(udp.localPort, 5353); XCTAssertNil(udp.remoteAddr)
        XCTAssertTrue(udp.isListening)

        let listen = s.conns[3]
        XCTAssertTrue(listen.isListening); XCTAssertEqual(listen.localPort, 8021)
        XCTAssertEqual(s.conns[4].pid, 99)   // rattachée au bon processus
    }

    func testEndpointSplitting() {
        XCTAssertEqual(Net.splitEndpoint("1.2.3.4:443").addr, "1.2.3.4")
        XCTAssertEqual(Net.splitEndpoint("1.2.3.4:443").port, 443)
        XCTAssertEqual(Net.splitEndpoint("*:*").addr, "*")
        XCTAssertNil(Net.splitEndpoint("*:*").port)
        XCTAssertEqual(Net.splitEndpoint("::1.8021").addr, "::1")
        XCTAssertEqual(Net.splitEndpoint("::1.8021").port, 8021)
        XCTAssertEqual(Net.splitEndpoint("fe80::1%en0.58060").addr, "fe80::1%en0")
        XCTAssertEqual(Net.splitEndpoint("*.*").addr, "*")
    }

    // MARK: - Portée des adresses

    func testScopes() {
        XCTAssertEqual(Net.scope(of: "127.0.0.1"), .loopback)
        XCTAssertEqual(Net.scope(of: "::1"), .loopback)
        XCTAssertEqual(Net.scope(of: "192.168.1.20"), .lan)
        XCTAssertEqual(Net.scope(of: "10.0.0.5"), .lan)
        XCTAssertEqual(Net.scope(of: "172.20.1.1"), .lan)
        XCTAssertEqual(Net.scope(of: "172.32.1.1"), .internet)
        XCTAssertEqual(Net.scope(of: "169.254.3.4"), .lan)
        XCTAssertEqual(Net.scope(of: "fe80::1%en0"), .lan)
        XCTAssertEqual(Net.scope(of: "fd12:3456::1"), .lan)
        XCTAssertEqual(Net.scope(of: "224.0.0.251"), .multicast)
        XCTAssertEqual(Net.scope(of: "ff02::fb"), .multicast)
        XCTAssertEqual(Net.scope(of: "203.0.113.50"), .internet)
        XCTAssertEqual(Net.scope(of: "2001:4860:4860::8888"), .internet)
        XCTAssertEqual(Net.scope(of: "*"), .wildcard)
        XCTAssertEqual(Net.scope(of: "::ffff:192.168.1.5"), .lan)
    }

    func testExposure() {
        XCTAssertFalse(Net.isExposed(listenAddress: "127.0.0.1"))
        XCTAssertFalse(Net.isExposed(listenAddress: "::1"))
        XCTAssertTrue(Net.isExposed(listenAddress: "*"))
        XCTAssertTrue(Net.isExposed(listenAddress: "192.168.1.23"))
    }

    // MARK: - Mise en forme

    func testFormatting() {
        XCTAssertEqual(Fmt.bytes(0), "0 o")
        XCTAssertEqual(Fmt.bytes(999), "999 o")
        XCTAssertEqual(Fmt.bytes(1500), "1,50 Ko")
        XCTAssertEqual(Fmt.bytes(2_500_000), "2,50 Mo")
        XCTAssertEqual(Fmt.bytes(12_300_000_000), "12,3 Go")
        XCTAssertEqual(Fmt.rate(0), "0 o/s")
        XCTAssertEqual(Fmt.rate(4200), "4,20 Ko/s")
    }

    func testServiceNames() {
        XCTAssertEqual(Net.service(port: 443, proto: "TCP"), "HTTPS (443)")
        XCTAssertEqual(Net.service(port: 443, proto: "UDP"), "HTTPS / QUIC (443)")
        XCTAssertEqual(Net.service(port: 5353, proto: "UDP"), "Bonjour (mDNS) (5353)")
        XCTAssertEqual(Net.service(port: 61234, proto: "TCP"), "61234")
        XCTAssertEqual(Net.service(port: nil, proto: "TCP"), "—")
    }

    // MARK: - Appareils / apps

    func testRandomMAC() {
        XCTAssertTrue(LANScanner.isRandomMAC("da:a1:19:00:00:01"))
        XCTAssertTrue(LANScanner.isRandomMAC("02:00:5e:10:00:02"))
        XCTAssertFalse(LANScanner.isRandomMAC("00:00:5e:00:53:03"))
    }

    func testOuterAppPath() {
        XCTAssertEqual(AppIdentityResolver.outerAppPath("/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helper.app/Contents/MacOS/Helper"),
                       "/Applications/Google Chrome.app")
        XCTAssertNil(AppIdentityResolver.outerAppPath("/usr/libexec/rapportd"))
    }

    // MARK: - DNS (mode avancé)

    func testDNSQueryAndResponseCorrelation() {
        var p = DNSLineParser()
        let q = "12:34:56.789012 IP 192.168.1.10.54321 > 192.168.1.1.53: 12345+ A? www.Exemple.fr. (33)"
        let r = "12:34:56.801000 IP 192.168.1.1.53 > 192.168.1.10.54321: 12345 2/0/1 CNAME cdn.exemple.fr., A 203.0.113.7 (80)"
        let e1 = p.parse(q)
        XCTAssertEqual(e1?.name, "www.exemple.fr"); XCTAssertEqual(e1?.type, "A"); XCTAssertEqual(e1?.answers, [])
        let e2 = p.parse(r)
        XCTAssertEqual(e2?.name, "www.exemple.fr"); XCTAssertEqual(e2?.answers, ["203.0.113.7"])
    }

    func testDNSIPv6Response() {
        var p = DNSLineParser()
        _ = p.parse("01:02:03.000001 IP6 fd00::15.50000 > fd00::1.53: 777+ AAAA? exemple.org. (30)")
        let e = p.parse("01:02:03.010000 IP6 fd00::1.53 > fd00::15.50000: 777 1/0/0 AAAA 2001:db8::7 (58)")
        XCTAssertEqual(e?.answers, ["2001:db8::7"])
    }

    func testDNSUnknownResponseIgnored() {
        var p = DNSLineParser()
        XCTAssertNil(p.parse("01:02:03.010000 IP 10.0.0.1.53 > 10.0.0.2.5000: 9 1/0/0 A 1.2.3.4 (40)"))
        XCTAssertNil(p.parse("n'importe quoi"))
    }

    // MARK: - Propriétaire (RDAP)

    func testRDAPParsing() {
        let json: [String: Any] = [
            "name": "EXEMPLE-NET", "country": "FR",
            "startAddress": "203.0.113.0", "endAddress": "203.0.113.255",
            "entities": [["roles": ["registrant"], "vcardArray": ["vcard", [["version", [:], "text", "4.0"], ["fn", [:], "text", "Exemple Hébergement SA"]]]]],
        ]
        let r = OwnerResolver.parse(json)
        XCTAssertEqual(r.info?.name, "Exemple Hébergement SA")
        XCTAssertEqual(r.info?.country, "FR")
        XCTAssertEqual(r.lo, [203, 0, 113, 0]); XCTAssertEqual(r.hi, [203, 0, 113, 255])
    }

    func testRDAPPrefersRegistrantOverContacts() {
        // Cas réel : le contact technique est listé AVANT le titulaire.
        let json: [String: Any] = [
            "name": "RESEAU-X", "country": "AU", "startAddress": "198.51.100.0", "endAddress": "198.51.100.255",
            "entities": [
                ["roles": ["technical", "administrative"], "vcardArray": ["vcard", [["fn", [:], "text", "Contact technique"]]]],
                ["roles": ["abuse"], "vcardArray": ["vcard", [["fn", [:], "text", "Contact abus"]]]],
                ["roles": ["registrant"], "vcardArray": ["vcard", [["fn", [:], "text", "Société Titulaire"]]]],
            ],
        ]
        XCTAssertEqual(OwnerResolver.parse(json).info?.name, "Société Titulaire")
    }

    // MARK: - Mode démo

    func testDemoSampleIsConsistent() {
        let d = DemoSource()
        let a = d.nextSample(), b = d.nextSample()
        XCTAssertFalse(a.procs.isEmpty); XCTAssertFalse(a.conns.isEmpty)
        // Les compteurs ne diminuent jamais
        for p in b.procs { if let q = a.procs.first(where: { $0.pid == p.pid }) { XCTAssertGreaterThanOrEqual(p.bytesOut, q.bytesOut) } }
        // Adresses fictives uniquement (documentation / réseau local)
        for c in b.conns { if let r = c.remoteAddr { XCTAssertNotEqual(Net.scope(of: r), .wildcard) } }
    }
}
