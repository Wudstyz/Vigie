<div align="center">

<img src="docs/icon.png" width="128" alt="Vigie icon">

# Vigie

**See everything your Mac sends over the network — and to whom.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0E8A9A?logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-0B4A6B)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)
![MIT License](https://img.shields.io/badge/license-MIT-green)
![No dependencies](https://img.shields.io/badge/dependencies-none-success)

[🇫🇷 Français](README.md) · 🇬🇧 English

<img src="docs/screenshots/overview.png" width="900" alt="Vigie overview (demo mode)">

</div>

---

> **Note:** the app interface is in **French**. This README is a translation of the French one.

## What it does

Vigie is a small Mac app that answers one question: **what is happening on my network?**

- 📤 **What each application sends and receives**, in bytes and live, with its icon.
- 🎯 **Where it goes**: every address contacted, with its domain name, its owner (optional), the volume sent and received, and which apps contact it.
- ⚠️ **Flags apps that send far more than they receive** (backup, sync, telemetry…).
- 🔌 **All open connections** right now, app by app.
- 🚪 **Open ports** on your Mac, and which ones are reachable from the rest of the network.
- 📡 **Local network devices** (router, phones, TVs, printers), flagging "private" (randomized) MAC addresses.
- 📶 **Your connection**: addresses, gateway, DNS, Wi-Fi signal, latency.
- 🛡️ **Vigilance mode**: Vigie spots what is out of the ordinary (massive data upload, suspicious program, new device, open port, connection outage…) and **alerts you**.
- 🧾 **A journal** of changes: new destination, new open port, new device.
- 🔎 **Advanced mode (optional)**: the domain names your apps actually ask for.
- 🧪 **Demo mode**: fully fictitious data, to try the app without exposing anything.

**Read-only**: Vigie observes; it never blocks or changes anything. **Light theme only.**

## Screenshots

All taken in **demo mode** (fictitious data).

| Vigilance | Applications |
|---|---|
| <img src="docs/screenshots/vigilance.png" width="450"> | <img src="docs/screenshots/apps.png" width="450"> |
| **Destinations** | **Connections** |
| <img src="docs/screenshots/destinations.png" width="450"> | <img src="docs/screenshots/connections.png" width="450"> |
| **Open ports** | **Devices** |
| <img src="docs/screenshots/ports.png" width="450"> | <img src="docs/screenshots/devices.png" width="450"> |
| **My network** | **Domain names (advanced mode)** |
| <img src="docs/screenshots/network.png" width="450"> | <img src="docs/screenshots/dns.png" width="450"> |
| **Journal** | |
| <img src="docs/screenshots/journal.png" width="450"> | |


## Installation

**Requirements**: an **Apple Silicon** Mac (M1 or later) running **macOS 14 Sonoma or later**. Nothing else to install (no Homebrew, Python or Node).

1. Download `Vigie-1.1.1.dmg` from the [Releases](../../releases) page and open it.
2. Drag **Vigie** into **Applications**.
3. **First launch** — Vigie is not signed with a paid Apple developer account (so it is not "notarized"). macOS will show a warning. **Right-click Vigie → Open → Open**. Or, in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Vigie.app
   ```
4. Optional: verify the download with the SHA-256 given on the release page (`shasum -a 256 Vigie-1.1.1.dmg`).

## Getting started

1. Open Vigie: the **Overview** fills in within seconds. No password is asked.
2. To try it without exposing anything: switch on **"Mode démonstration"** at the bottom of the sidebar.
3. **Applications** → click a row: the right panel lists *who* the app sends data to.
4. **Destinations** → filter on "Internet" and sort by "Envoyé" (sent).
5. **Appareils** (devices) → macOS may ask permission for **local network** access: accept it to see the list.
6. Settings (⌘ ,): domain names, address owners, latency, speed in the menu bar.

## Vigilance mode

On by default ("Mode vigilance" switch at the bottom of the sidebar). Vigie continuously looks for what is out of the ordinary and explains it in French, with three buttons: **Ignorer** (dismiss), **Faire confiance** (trust this app), **Voir l'application** (view app).

| What Vigie spots | Example |
|---|---|
| **Massive upload** to the Internet (≥ 30 MB in 1 min *and* more than 3× what is received; system apps excluded) | an app sending your files without being asked |
| **Suspicious program**: not signed by an identified developer, run from a temporary, downloads or hidden folder, and using the Internet | an executable dropped in `/tmp` |
| **Risky port**: connection to a port often used by remote-control tools (4444, 31337…) | a backdoor |
| **New application** using the Internet for the first time | good to know, not necessarily bad |
| **Open port**: an app accepts connections coming from the network | a server started by a program |
| **New device** on the local network, or **router MAC address change** (possible spoofing; "important" if the manufacturer changes, just "good to know" if it is the same, which is common with a Wi-Fi repeater or a multi-interface router) | an intruder on your Wi-Fi |
| **Outages**: router or Internet not answering, very slow network, weak Wi-Fi signal | "I have a connection problem" |

- **Learning**: on the very first real use, Vigie observes for **15 minutes** what is usual on your Mac (apps, devices, ports) without flagging anything as "new". What it learns is stored in `~/Library/Application Support/Vigie/baseline.json` (app names, MAC addresses of network devices, ports): it stays on your Mac and is never sent. Settings → "Oublier ce que Vigie a appris" to start over.
- **Sensitivity** (Low / Normal / High): sets the massive-upload threshold (100 / 30 / 10 MB per minute).
- **macOS notifications** for "to check" and "important" alerts (can be turned off in Settings). A red badge on the menu bar icon and a counter in the sidebar show ongoing alerts.
- **This is not an antivirus**: an alert is a signal to check, not proof of a problem, and no alert does not prove everything is fine (a discreet, well-disguised program can slip through).
- **Try the detection**: `tests/anomaly/run.sh` runs a deliberately shady program (unsigned, temp folder, opens a port, sends ~45 MB to Cloudflare's speed-test server) to check Vigie catches it. It asks for confirmation first.

## What Vigie sees… and doesn't

| Vigie sees | Vigie does not see |
|---|---|
| Which app opens a connection | The **content** of exchanges (pages, messages, passwords) |
| To which address and port | What is said *inside* an encrypted connection (nearly all of the web) |
| How many bytes are sent / received | Connections shorter than ~1 second |
| Ports open on your Mac | Other devices' traffic on your network |

This is the same level of information as macOS's built-in `nettop` tool (which Vigie relies on, without administrator rights). Going down to packet contents would require a full capture tool (e.g. Wireshark) with admin rights — out of Vigie's scope.

## Privacy: what leaves your Mac

Vigie has **no server** and sends **no analytics**. Here is *everything* it can cause to be sent:

| Feature | What is sent, and to whom | Setting |
|---|---|---|
| Domain names | Each contacted address is submitted to **your usual DNS server** (router, ISP) | On · can be disabled |
| Address owners | Contacted Internet addresses are sent to **rdap.org** (public registry) | **Off by default** |
| Latency | A "ping" to your router, and to `1.1.1.1` | Internet: on · can be disabled |
| Devices | A small UDP packet to each address on **your local network** (nothing leaves the network) | On demand |
| Vigilance | Nothing sent; local notifications and a learning file kept on your Mac | On · can be disabled |
| Advanced mode | Nothing sent; reads DNS requests via `tcpdump` (admin password entered in the official macOS dialog, **never seen by Vigie**) | Off · on demand |

## Compatibility and known limits

**What was tested** (honestly):
- macOS **26.6.2**, Apple Silicon Mac: build, **45 unit tests**, launch in **real mode** (real connections, domain names, devices, Wi-Fi) and in **demo mode**.
- Launch in a **sandbox with no access to Homebrew** (`tests/smoke_test.sh`), on the same Mac.
- Measured load: about **2% of one core** for the app.
- **Vigilance**: tested live by provoking a real anomaly (an unsigned program in a temporary folder that opens a port and uploads ~45 MB to the Internet): the **4 expected alerts** appeared. On the same Mac at rest, **no false alert** was observed (after learning).

**What was not tested**:
- **Vigilance**: the "risky port", "new device", "router address change" and "outage" rules are covered by unit tests but were **not provoked live**. **macOS notification display** was not visually verified. False alerts were only observed on **a single Mac**: other uses (development, games, VPNs, Docker…) may produce some.
- **macOS 14 and 15**: the minimum (14.0) is verified in the binary from the APIs used, but the app was not run on those versions.
- **Intel Macs**: not supported (arm64 build only).
- **Advanced mode (domain names)**: `tcpdump` line parsing is tested on samples, but the authorization dialog and live capture were **not** tested end to end.
- **Address owners**: the RDAP service response was checked on a public address, but the feature was not observed over time in the app.
- **No test on a corporate network, behind a proxy, or with several VPNs.**

**Known limits**:
- Totals are **"since Vigie was opened"**; nothing is kept after closing.
- Names from reverse DNS are often a host's (e.g. `ec2-…amazonaws.com`) rather than the site visited. Advanced mode gives the real requested name… unless the app uses encrypted DNS.
- Device **manufacturers** are not identified; names only appear if announced on the network (mDNS / DNS).
- The **Wi-Fi network name (SSID)** is not shown (macOS reserves it for apps allowed to use location).
- Counted bytes are *socket* bytes: they exclude network headers, so they differ slightly from your router's counters.

## Build from source

You need Xcode (or the Command Line Tools) with Swift ≥ 5.9. Tested with Swift 6.2.

```bash
./build_app.sh          # builds build/Vigie.app (arm64, ad hoc signature)
```
```bash
./make_dmg.sh           # builds build/Vigie-1.1.1.dmg + its SHA-256
```
```bash
swift test              # 45 unit tests
```
```bash
tests/smoke_test.sh     # launches the app without Homebrew access and checks its 10 screens
```
```bash
tests/anomaly/run.sh    # manual test: provokes an anomaly to check vigilance
```
```bash
scripts/make_icns.sh    # regenerates the icon (icon/icon.icns, docs/icon.png)
```

Documentation screenshots are redone with `build/Vigie.app/Contents/MacOS/Vigie --capture docs/screenshots` (demo mode).

## Code layout

| File | Role |
|---|---|
| `Sources/Vigie/NettopMonitor.swift`, `NettopParser.swift` | One-shot `nettop` snapshot every second, output parsing |
| `Sources/Vigie/NetworkStore.swift` | The "brain": aggregates apps, destinations, connections, ports, journal |
| `Sources/Vigie/Resolvers.swift`, `AppIdentity.swift` | Domain names, owners (RDAP), app identification |
| `Sources/Vigie/LANScanner.swift`, `SystemInfo.swift` | Local devices, interfaces, DNS, Wi-Fi, latency |
| `Sources/Vigie/Vigilance.swift`, `VigilanceView.swift`, `AlertNotifier.swift` | Anomaly detection, screen and notifications |
| `Sources/Vigie/DNSSniffer.swift` | Advanced mode: reading DNS requests |
| `Sources/Vigie/DemoSource.swift` | Demo mode (fictitious data) |
| `Sources/Vigie/*View.swift`, `Components.swift` | SwiftUI interface |
| `icon/`, `scripts/` | Icon generation |
| `tests/` | Unit tests, smoke test, sandbox profile |

## Contributing

Ideas and fixes are welcome: open an *issue* to discuss, or a *pull request* (with a test if possible). Please **never** include real data from your network (addresses, device names): use the documentation ranges (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`).

## License

[MIT](LICENSE) © 2026 Wudstyz. See also [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Product names mentioned belong to their owners; this project is not affiliated with any of them.
