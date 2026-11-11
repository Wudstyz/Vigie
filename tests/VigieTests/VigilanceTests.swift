import XCTest
@testable import Vigie

final class VigilanceTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Moteur déjà « adulte » (apprentissage terminé).
    func engine(learning: Bool = false) -> VigilanceEngine {
        var b = Baseline()
        b.createdAt = learning ? t0 : t0.addingTimeInterval(-86_400)
        return VigilanceEngine(baseline: b, now: t0.addingTimeInterval(-3600))
    }

    func app(_ key: String = "app1", name: String = "Appli", path: String? = "/Applications/Appli.app", system: Bool = false, net: Bool = true) -> AppObs {
        AppObs(key: key, name: name, path: path, isSystem: system, internetActive: net)
    }

    func tick(_ e: VigilanceEngine, at i: Int, apps: [AppObs], out: UInt64 = 0, in inn: UInt64 = 0, key: String = "app1",
              ips: Set<String> = [], conns: [ConnObs] = [], listeners: [ListenerObs] = []) -> [AlertCandidate] {
        e.evaluate(now: t0.addingTimeInterval(Double(i)), apps: apps, deltas: [key: (out, inn)],
                   newInternetIPs: ips.isEmpty ? [:] : [key: ips], conns: conns, listeners: listeners)
    }

    // MARK: - Envoi massif

    func testMassiveUploadFlagged() {
        let e = engine()
        e.baseline.apps.insert("app1")
        var last: [AlertCandidate] = []
        for i in 0..<60 { last = tick(e, at: i, apps: [app()], out: 1_000_000) }   // 60 Mo en 1 minute
        let a = last.first { $0.key == "upload|app1" }
        XCTAssertNotNil(a); XCTAssertEqual(a?.severity, .attention); XCTAssertFalse(a?.oneShot ?? true)
    }

    func testVeryMassiveUploadIsImportant() {
        let e = engine(); e.baseline.apps.insert("app1")
        var last: [AlertCandidate] = []
        for i in 0..<60 { last = tick(e, at: i, apps: [app()], out: 4_000_000) }   // 240 Mo
        XCTAssertEqual(last.first { $0.key == "upload|app1" }?.severity, .important)
    }

    func testBalancedTrafficNotFlagged() {
        let e = engine(); e.baseline.apps.insert("app1")
        var all: [AlertCandidate] = []
        for i in 0..<60 { all += tick(e, at: i, apps: [app()], out: 1_000_000, in: 1_000_000) }  // envoie autant qu'il reçoit
        XCTAssertFalse(all.contains { $0.key.hasPrefix("upload|") })
    }

    func testSmallUploadNotFlagged() {
        let e = engine(); e.baseline.apps.insert("app1")
        var all: [AlertCandidate] = []
        for i in 0..<60 { all += tick(e, at: i, apps: [app()], out: 100_000) }   // 6 Mo/min
        XCTAssertTrue(all.isEmpty)
    }

    func testSystemAndTrustedAppsExcludedFromUpload() {
        let e = engine(); e.baseline.apps.insert("sys"); e.baseline.apps.insert("app1")
        var all: [AlertCandidate] = []
        for i in 0..<60 { all += tick(e, at: i, apps: [app("sys", name: "backupd", system: true)], out: 5_000_000, key: "sys") }
        XCTAssertTrue(all.isEmpty, "les applications système sont exclues")
        e.trust("app1")
        for i in 0..<60 { all += tick(e, at: i, apps: [app()], out: 5_000_000) }
        XCTAssertTrue(all.isEmpty, "une application de confiance n'est plus signalée")
    }

    func testSensitivityChangesThreshold() {
        let e = engine(); e.baseline.apps.insert("app1")
        e.sensitivity = .high
        var all: [AlertCandidate] = []
        for i in 0..<60 { all += tick(e, at: i, apps: [app()], out: 250_000) }   // 15 Mo/min : > 10 (élevée), < 30 (normale)
        XCTAssertTrue(all.contains { $0.key == "upload|app1" })
        let e2 = engine(); e2.baseline.apps.insert("app1")
        var all2: [AlertCandidate] = []
        for i in 0..<60 { all2 += tick(e2, at: i, apps: [app()], out: 250_000) }
        XCTAssertFalse(all2.contains { $0.key == "upload|app1" })
    }

    // MARK: - Nouvelle application

    func testNewAppSilentDuringLearningThenFlagged() {
        let e = engine(learning: true)
        XCTAssertTrue(e.isLearning(t0))
        XCTAssertTrue(tick(e, at: 1, apps: [app("a")], key: "a").isEmpty, "pas d'alerte pendant l'apprentissage")
        XCTAssertTrue(e.baseline.apps.contains("a"), "mais l'application est apprise")

        // plus tard, une nouvelle application apparaît
        let later = t0.addingTimeInterval(VigilanceEngine.learningDuration + 10)
        let r = e.evaluate(now: later, apps: [app("a"), app("b", name: "Nouvelle")], deltas: [:], newInternetIPs: [:], conns: [], listeners: [])
        XCTAssertEqual(r.map(\.key), ["newapp|b"])
        XCTAssertEqual(r.first?.severity, .info)
        // une seule fois
        let again = e.evaluate(now: later.addingTimeInterval(5), apps: [app("a"), app("b")], deltas: [:], newInternetIPs: [:], conns: [], listeners: [])
        XCTAssertTrue(again.isEmpty)
    }

    func testNewAppWithoutInternetNotFlaggedNorLearned() {
        let e = engine()
        let r = e.evaluate(now: t0, apps: [app("x", net: false)], deltas: [:], newInternetIPs: [:], conns: [], listeners: [])
        XCTAssertTrue(r.isEmpty); XCTAssertFalse(e.baseline.apps.contains("x"))
    }

    func testSystemAppNeverNew() {
        let e = engine()
        XCTAssertTrue(e.evaluate(now: t0, apps: [app("s", system: true)], deltas: [:], newInternetIPs: [:], conns: [], listeners: []).isEmpty)
    }

    // MARK: - Dossier inhabituel + signature

    func testUnusualLocation() {
        XCTAssertTrue(VigilanceEngine.isUnusualLocation("/private/var/folders/ab/T/x"))
        XCTAssertTrue(VigilanceEngine.isUnusualLocation("/tmp/payload"))
        XCTAssertTrue(VigilanceEngine.isUnusualLocation("/Users/jean/Downloads/Setup.app"))
        XCTAssertTrue(VigilanceEngine.isUnusualLocation("/Users/jean/.hidden/agent"))
        XCTAssertFalse(VigilanceEngine.isUnusualLocation("/Applications/Safari.app"))
        XCTAssertFalse(VigilanceEngine.isUnusualLocation("/System/Library/CoreServices/x"))
        XCTAssertFalse(VigilanceEngine.isUnusualLocation("/opt/homebrew/bin/node"))
        XCTAssertFalse(VigilanceEngine.isUnusualLocation("/Users/jean/.nvm/versions/node/v20/bin/node"), "outils de développement courants")
        XCTAssertFalse(VigilanceEngine.isUnusualLocation("/Users/jean/Documents/Projet/build/App"))
    }

    func testUnsignedProgramInTempFlagged() {
        let e = engine(); e.baseline.apps.insert("p")
        e.codeStatus = { _ in .notTrusted }
        let r = e.evaluate(now: t0, apps: [app("p", name: "agent", path: "/private/var/folders/zz/T/agent")], deltas: [:], newInternetIPs: [:], conns: [], listeners: [])
        XCTAssertTrue(r.contains { $0.key == "path|p" && $0.severity == .attention })
    }

    func testSignedProgramInDownloadsNotFlagged() {
        let e = engine(); e.baseline.apps.insert("p")
        e.codeStatus = { _ in .trusted }
        let r = e.evaluate(now: t0, apps: [app("p", path: "/Users/jean/Downloads/Outil.app")], deltas: [:], newInternetIPs: [:], conns: [], listeners: [])
        XCTAssertFalse(r.contains { $0.key.hasPrefix("path|") })
    }

    func testUnsignedInApplicationsNotFlagged() {
        let e = engine(); e.baseline.apps.insert("p")
        e.codeStatus = { _ in .notTrusted }
        let r = e.evaluate(now: t0, apps: [app("p", path: "/Applications/Vigie.app")], deltas: [:], newInternetIPs: [:], conns: [], listeners: [])
        XCTAssertFalse(r.contains { $0.key.hasPrefix("path|") }, "une app ad hoc dans Applications (comme Vigie) n'est pas suspecte")
    }

    func testRealCodeSigningOnSystemApp() {
        // Safari est signée par Apple ; un chemin inexistant n'est pas de confiance.
        let safari = ["/Applications/Safari.app", "/System/Cryptexes/App/System/Applications/Safari.app"].first { FileManager.default.fileExists(atPath: $0) }
        if let safari { XCTAssertEqual(CodeSigning.status(path: safari), .trusted) }
        XCTAssertEqual(CodeSigning.status(path: "/nonexistent/path/agent"), .notTrusted)
    }

    // MARK: - Ports

    func testSuspiciousPortFlagged() {
        let e = engine(); e.baseline.apps.insert("app1")
        let c = ConnObs(appKey: "app1", appName: "Appli", remoteIP: "203.0.113.9", remotePort: 4444, scope: .internet)
        let r = tick(e, at: 0, apps: [app()], conns: [c])
        XCTAssertTrue(r.contains { $0.key == "port|app1|4444" })
        let lan = ConnObs(appKey: "app1", appName: "Appli", remoteIP: "192.168.1.5", remotePort: 4444, scope: .lan)
        XCTAssertFalse(tick(e, at: 1, apps: [app()], conns: [lan]).contains { $0.key.hasPrefix("port|") }, "réseau local : ignoré")
    }

    func testExposedListenerFlaggedOnce() {
        let e = engine(); e.baseline.apps.insert("app1")
        let l = ListenerObs(key: "app1|TCP|8443|true", appKey: "app1", appName: "Appli", port: 8443, exposed: true, isSystem: false)
        XCTAssertTrue(tick(e, at: 0, apps: [app()], listeners: [l]).contains { $0.key.hasPrefix("listen|") })
        XCTAssertFalse(tick(e, at: 1, apps: [app()], listeners: [l]).contains { $0.key.hasPrefix("listen|") })
        let local = ListenerObs(key: "app1|TCP|3000|false", appKey: "app1", appName: "Appli", port: 3000, exposed: false, isSystem: false)
        XCTAssertFalse(tick(e, at: 2, apps: [app()], listeners: [local]).contains { $0.key.hasPrefix("listen|") })
        let sys = ListenerObs(key: "s|UDP|5353|true", appKey: "s", appName: "mDNSResponder", port: 5353, exposed: true, isSystem: true)
        XCTAssertFalse(tick(e, at: 3, apps: [app()], listeners: [sys]).contains { $0.key.hasPrefix("listen|") })
    }

    // MARK: - Rafale d'adresses

    func testBurstOfNewAddresses() {
        let e = engine(); e.baseline.apps.insert("app1")
        let e0 = tick(e, at: 0, apps: [app()], ips: ["198.51.100.1"])    // départ : connexions déjà ouvertes
        XCTAssertTrue(e0.isEmpty)
        var last: [AlertCandidate] = []
        for i in 30..<50 {
            let ips = Set((0..<8).map { "203.0.113.\(($0 + (i - 30) * 8) % 250 + 1)" })
            last = tick(e, at: i + 100, apps: [app()], ips: ips)
        }
        // 20 ticks × 8 adresses distinctes (plus de 120 au total, moins de 250 valeurs possibles)
        XCTAssertTrue(last.contains { $0.key == "burst|app1" })
    }

    func testFewNewAddressesNotFlagged() {
        let e = engine(); e.baseline.apps.insert("app1")
        var all: [AlertCandidate] = []
        for i in 0..<60 { all += tick(e, at: i + 100, apps: [app()], ips: ["203.0.113.\(i % 10 + 1)"]) }
        XCTAssertFalse(all.contains { $0.key.hasPrefix("burst|") })
    }

    // MARK: - Appareils

    func testNewDeviceAndGatewayChange() {
        let e = engine()
        let box = DeviceObs(mac: "00:00:5e:00:53:01", ip: "192.168.1.1", name: nil, randomMAC: false, isThisMac: false)
        // 1re vue de la box : mémorisée, aucune alerte (ni « changement », ni « nouvel appareil » : c'est la box)
        let r1 = e.evaluateDevices(now: t0, devices: [box], gatewayIP: "192.168.1.1")
        XCTAssertTrue(r1.isEmpty)
        // un autre appareil, jamais vu : signalé
        let tv = DeviceObs(mac: "00:00:5e:00:53:45", ip: "192.168.1.45", name: "tv", randomMAC: false, isThisMac: false)
        XCTAssertTrue(e.evaluateDevices(now: t0, devices: [tv], gatewayIP: "192.168.1.1").contains { $0.key.hasPrefix("device|") })
        // la box répond avec une adresse d'un AUTRE fabricant : important
        let fake = DeviceObs(mac: "da:a1:19:00:00:66", ip: "192.168.1.1", name: nil, randomMAC: true, isThisMac: false)
        let r2 = e.evaluateDevices(now: t0.addingTimeInterval(120), devices: [fake], gatewayIP: "192.168.1.1")
        XCTAssertEqual(r2.first { $0.key == "arp|192.168.1.1" }?.severity, .important)
        // ce Mac est ignoré
        let me = DeviceObs(mac: "—", ip: "192.168.1.10", name: "Moi", randomMAC: false, isThisMac: true)
        XCTAssertTrue(e.evaluateDevices(now: t0.addingTimeInterval(240), devices: [me], gatewayIP: "192.168.1.1").isEmpty)
    }

    /// Cas réel : la box répond tantôt avec une adresse, tantôt avec une autre du MÊME fabricant.
    func testGatewaySecondAddressSameVendorIsOnlyInfoAndNeverRepeats() {
        let e = engine()
        func box(_ mac: String) -> DeviceObs { DeviceObs(mac: mac, ip: "192.168.1.1", name: nil, randomMAC: false, isThisMac: false) }
        let a = "00:00:5e:00:53:42", b = "00:00:5e:00:53:27"
        XCTAssertTrue(e.evaluateDevices(now: t0, devices: [box(a)], gatewayIP: "192.168.1.1").isEmpty)
        let r = e.evaluateDevices(now: t0.addingTimeInterval(120), devices: [box(b)], gatewayIP: "192.168.1.1")
        XCTAssertEqual(r.map(\.key), ["arp|192.168.1.1"])
        XCTAssertEqual(r.first?.severity, .info, "même fabricant : simple information")
        XCTAssertFalse(r.contains { $0.key.hasPrefix("device|") }, "ce n'est pas un « nouvel appareil »")
        // allers-retours : plus aucune alerte, les deux adresses sont connues
        for i in 2..<8 {
            let mac = i % 2 == 0 ? a : b
            XCTAssertTrue(e.evaluateDevices(now: t0.addingTimeInterval(Double(i) * 120), devices: [box(mac)], gatewayIP: "192.168.1.1").isEmpty)
        }
        // mais une adresse d'un autre fabricant reste « important »
        let r2 = e.evaluateDevices(now: t0.addingTimeInterval(2000), devices: [box("aa:bb:cc:00:11:22")], gatewayIP: "192.168.1.1")
        XCTAssertEqual(r2.first?.severity, .important)
    }

    /// Ancien fichier d'apprentissage (une seule adresse mémorisée, pas de liste) : il reste compris.
    func testLegacyBaselineWithSingleGatewayAddress() {
        var b = Baseline(); b.createdAt = t0.addingTimeInterval(-86_400)
        b.gateways["192.168.1.1"] = "00:00:5e:00:53:27"; b.gatewayKnown = nil
        let e = VigilanceEngine(baseline: b, now: t0.addingTimeInterval(-3600))
        let box = DeviceObs(mac: "00:00:5e:00:53:42", ip: "192.168.1.1", name: nil, randomMAC: false, isThisMac: false)
        let r = e.evaluateDevices(now: t0, devices: [box], gatewayIP: "192.168.1.1")
        XCTAssertEqual(r.first?.severity, .info)
        XCTAssertEqual(e.baseline.gatewayKnown?["192.168.1.1"]?.count, 2)
        XCTAssertTrue(e.evaluateDevices(now: t0.addingTimeInterval(60), devices: [box], gatewayIP: "192.168.1.1").isEmpty)
    }

    func testOUI() {
        XCTAssertEqual(VigilanceEngine.oui("00:00:5E:00:53:42"), "00:00:5e")
    }

    func testDevicesSilentDuringLearning() {
        let e = engine(learning: true)
        let d = DeviceObs(mac: "00:00:5e:00:53:20", ip: "192.168.1.20", name: nil, randomMAC: false, isThisMac: false)
        XCTAssertTrue(e.evaluateDevices(now: t0, devices: [d], gatewayIP: "192.168.1.1").isEmpty)
        XCTAssertTrue(e.baseline.devices.contains("00:00:5e:00:53:20"))
    }

    // MARK: - Pannes

    func testGatewayDownAfterThreeFailures() {
        let e = engine()
        XCTAssertTrue(e.evaluateHealth(gatewayMs: nil, internetMs: nil, internetEnabled: true, rssi: nil).isEmpty)
        XCTAssertTrue(e.evaluateHealth(gatewayMs: nil, internetMs: nil, internetEnabled: true, rssi: nil).isEmpty)
        let r = e.evaluateHealth(gatewayMs: nil, internetMs: nil, internetEnabled: true, rssi: nil)
        XCTAssertEqual(r.first { $0.key == "health|gateway" }?.severity, .important)
        // reprise
        XCTAssertFalse(e.evaluateHealth(gatewayMs: 4, internetMs: 12, internetEnabled: true, rssi: -50).contains { $0.key == "health|gateway" })
    }

    func testInternetDownWhileGatewayOk() {
        let e = engine()
        var r: [AlertCandidate] = []
        for _ in 0..<3 { r = e.evaluateHealth(gatewayMs: 3, internetMs: nil, internetEnabled: true, rssi: nil) }
        XCTAssertTrue(r.contains { $0.key == "health|internet" })
        XCTAssertFalse(r.contains { $0.key == "health|gateway" })
    }

    func testInternetCheckDisabledNeverAlerts() {
        let e = engine()
        var r: [AlertCandidate] = []
        for _ in 0..<5 { r = e.evaluateHealth(gatewayMs: 3, internetMs: nil, internetEnabled: false, rssi: nil) }
        XCTAssertTrue(r.isEmpty)
    }

    func testSlowNetworkAndWeakWifi() {
        let e = engine()
        var r: [AlertCandidate] = []
        for _ in 0..<3 { r = e.evaluateHealth(gatewayMs: 150, internetMs: 400, internetEnabled: true, rssi: -85) }
        XCTAssertTrue(r.contains { $0.key == "health|slowgw" })
        XCTAssertTrue(r.contains { $0.key == "health|slownet" })
        XCTAssertTrue(r.contains { $0.key == "health|wifi" })
        let ok = e.evaluateHealth(gatewayMs: 5, internetMs: 15, internetEnabled: true, rssi: -50)
        XCTAssertTrue(ok.isEmpty || !ok.contains { $0.key == "health|wifi" })
    }

    func testNormalNetworkNoAlerts() {
        let e = engine()
        for _ in 0..<10 { XCTAssertTrue(e.evaluateHealth(gatewayMs: 4, internetMs: 15, internetEnabled: true, rssi: -55).isEmpty) }
    }

    // MARK: - Persistance et modèle

    func testBaselineRoundTrip() throws {
        var b = Baseline(); b.apps = ["a", "b"]; b.devices = ["m1"]; b.trusted = ["a"]; b.gateways = ["192.168.1.1": "aa:bb"]; b.gatewayKnown = ["192.168.1.1": ["aa:bb", "aa:cc"]]
        b.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-baseline-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        b.save(to: url)
        XCTAssertEqual(Baseline.load(from: url), b)
        XCTAssertNil(Baseline.load(from: url.appendingPathExtension("absent")))
    }

    func testAlertOngoingWindow() {
        let a = AlertRow(id: "k", firstSeen: t0, lastSeen: t0, severity: .attention, title: "t", explanation: "e", appName: nil, appKey: nil, symbol: "x", oneShot: false)
        XCTAssertTrue(a.isOngoing(at: t0.addingTimeInterval(5)))
        XCTAssertFalse(a.isOngoing(at: t0.addingTimeInterval(60)))
        var one = a; one.oneShot = true
        XCTAssertFalse(one.isOngoing(at: t0), "une alerte ponctuelle n'est jamais « en cours »")
    }

    func testSeverityOrdering() {
        XCTAssertTrue(Severity.important > Severity.attention)
        XCTAssertTrue(Severity.attention > Severity.info)
    }
}
