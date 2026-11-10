# Notices tierces / Third-party notices

## Dépendances / Dependencies

Vigie n'embarque **aucune bibliothèque tierce** : aucun paquet Swift externe, aucun runtime embarqué.
L'app n'utilise que les frameworks fournis avec macOS.

Vigie bundles **no third-party library**: no external Swift package, no embedded runtime.
It only uses frameworks shipped with macOS.

| Composant / Component | Rôle / Role | Licence / License |
|---|---|---|
| SwiftUI, Charts, AppKit, CoreWLAN, Foundation (macOS) | Interface, graphiques, Wi-Fi | Fournis avec macOS (Apple SDK) |
| Swift (compilateur et runtime système) | Langage | Apache License 2.0 (Swift.org) |
| `nettop`, `arp`, `route`, `scutil`, `networksetup`, `ping` (macOS) ; `tcpdump`, `osascript` (mode avancé facultatif) | Outils système appelés à l'exécution — non redistribués / System tools called at runtime, not redistributed | Fournis avec macOS |

## Services externes facultatifs / Optional external services

- **RDAP** (`https://rdap.org`) : annuaire public des adresses IP, utilisé **uniquement si vous activez**
  « Identifier les propriétaires des adresses ». / Public IP registry, used **only if you enable**
  "Identify address owners".
- **ping 1.1.1.1** : mesure de latence vers Internet (désactivable). / Internet latency measurement (can be disabled).

## Marques / Trademarks

Les noms de produits et marques cités (Apple, macOS, Wi-Fi, AirPlay, Bonjour, Safari, Mail, Time Machine, etc.)
appartiennent à leurs propriétaires respectifs. Vigie est un projet indépendant, **non affilié** à ces sociétés.
Les captures d'écran du mode démonstration n'affichent que des données fictives
(adresses réservées à la documentation 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24 ; noms de domaine en « exemple.* »).

All product names and trademarks mentioned (Apple, macOS, Wi-Fi, AirPlay, Bonjour, Safari, Mail, Time Machine, …)
belong to their respective owners. Vigie is an independent project, **not affiliated** with those companies.
Screenshots of the demo mode only show fictitious data.
