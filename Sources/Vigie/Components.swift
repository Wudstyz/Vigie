import SwiftUI
import AppKit

// MARK: - Couleurs (thème clair)

enum Theme {
    static let accent = Color(red: 0.055, green: 0.54, blue: 0.60)       // bleu-vert Vigie
    static let down = Color(red: 0.13, green: 0.50, blue: 0.92)           // reçu : bleu
    static let up = Color(red: 0.95, green: 0.52, blue: 0.10)             // envoyé : ambre
    static let ok = Color(red: 0.16, green: 0.66, blue: 0.36)
    static let warn = Color(red: 0.90, green: 0.42, blue: 0.10)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let page = Color(nsColor: .windowBackgroundColor)
    static let line = Color.black.opacity(0.08)
}

// MARK: - Navigation (partagée pour pouvoir piloter les captures d'écran)

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview, apps, destinations, connections, ports, dns, devices, network, journal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Vue d'ensemble"
        case .apps: return "Applications"
        case .destinations: return "Destinations"
        case .connections: return "Connexions"
        case .ports: return "Ports ouverts"
        case .dns: return "Noms de domaine"
        case .devices: return "Appareils"
        case .network: return "Mon réseau"
        case .journal: return "Journal"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .apps: return "square.grid.2x2"
        case .destinations: return "paperplane"
        case .connections: return "arrow.left.arrow.right"
        case .ports: return "door.left.hand.open"
        case .dns: return "text.magnifyingglass"
        case .devices: return "laptopcomputer.and.iphone"
        case .network: return "wifi"
        case .journal: return "list.bullet.rectangle"
        }
    }
}

@MainActor
@Observable
final class Nav {
    static let shared = Nav()
    var section: SidebarSection = .overview
    var selectedApp: String?
    var selectedDest: String?
}

// MARK: - Petites vues

struct AppIconView: View {
    var path: String?
    var system: Bool
    var size: CGFloat = 24
    var body: some View {
        Image(nsImage: IconProvider.icon(path: path, system: system))
            .resizable().interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(system ? Color.secondary : Theme.accent)
    }
}

struct Badge: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.13), in: Capsule())
            .lineLimit(1)
    }
}

extension Scope {
    var color: Color {
        switch self {
        case .internet: return Theme.accent
        case .lan: return .purple
        case .loopback: return .gray
        case .multicast: return .gray
        case .wildcard: return .gray
        }
    }
}

struct ScopeBadge: View {
    var scope: Scope
    var body: some View { Badge(text: scope.label, color: scope.color) }
}

/// « ↓ 1,2 Mo/s  ↑ 80 Ko/s » avec les couleurs reçu / envoyé.
struct RatePair: View {
    var down: Double
    var up: Double
    var body: some View {
        HStack(spacing: 10) {
            Label(Fmt.rate(down), systemImage: "arrow.down").foregroundStyle(down > 0 ? Theme.down : .secondary)
            Label(Fmt.rate(up), systemImage: "arrow.up").foregroundStyle(up > 0 ? Theme.up : .secondary)
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: 12, weight: .medium).monospacedDigit())
    }
}

struct SentText: View {
    var bytes: UInt64
    var body: some View {
        Text(Fmt.bytes(bytes)).monospacedDigit().foregroundStyle(bytes > 0 ? Theme.up : .secondary)
    }
}
struct ReceivedText: View {
    var bytes: UInt64
    var body: some View {
        Text(Fmt.bytes(bytes)).monospacedDigit().foregroundStyle(bytes > 0 ? Theme.down : .secondary)
    }
}
struct RateText: View {
    var value: Double
    var color: Color
    var body: some View {
        Text(value < 1 ? "—" : Fmt.rate(value)).monospacedDigit().foregroundStyle(value >= 1 ? color : .secondary)
    }
}

struct UsageBar: View {
    var value: Double
    var maxValue: Double
    var color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.06))
                Capsule().fill(color.gradient)
                    .frame(width: max(value > 0 ? 4 : 0, g.size.width * CGFloat(maxValue > 0 ? value / maxValue : 0)))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Cartes et en-têtes

struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
    }
}

struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 24, weight: .bold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

struct StatCard: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(color).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 26, weight: .bold).monospacedDigit()).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
    }
}

struct KeyValueRow: View {
    var key: String
    var value: String
    var mono = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary).font(.system(size: 12))
            Spacer(minLength: 12)
            Text(value).font(.system(size: 12, design: mono ? .monospaced : .default)).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

struct EmptyHint: View {
    var symbol: String
    var title: String
    var text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func copyToPasteboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
