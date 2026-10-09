import SwiftUI

// Placeholder visual system until the real design lands. Colors, fonts and the
// small building blocks below are the single place to re-skin the app.

enum Theme {
    static let brand = Color(hex: "0F766E")
    static let ok = Color(hex: "16A34A")
    static let info = Color(hex: "2563EB")
    static let warn = Color(hex: "D97706")
    static let bad = Color(hex: "DC2626")
    static let muted = Color.secondary
    static let card = Color(.secondarySystemGroupedBackground)
    static let background = Color(.systemGroupedBackground)
    static let fill = Color(.tertiarySystemFill)
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: Labels & colors for domain values

extension ConnectorStatus {
    var label: String {
        switch self {
        case .available: tr("Available")
        case .charging: tr("Charging now")
        case .idle: tr("Finished, still parked")
        case .blocked: tr("Occupied, not charging")
        case .offline: tr("Out of service")
        }
    }

    var color: Color {
        switch self {
        case .available: Theme.ok
        case .charging: Theme.info
        case .idle: Theme.warn
        case .blocked: Theme.bad
        case .offline: .gray
        }
    }
}

extension AvailabilityLevel {
    var label: String {
        switch self {
        case .free: tr("Available")
        case .limited: tr("Nearly full")
        case .full: tr("Full")
        case .offline: tr("Out of service")
        }
    }

    var color: Color {
        switch self {
        case .free: Theme.ok
        case .limited: Theme.warn
        case .full: Theme.bad
        case .offline: .gray
        }
    }
}

extension ChargeOperator {
    var color: Color { Color(hex: colorHex) }
}

// MARK: Formatting

enum Fmt {
    static var locale: Locale { L10n.locale }

    static func eur(_ v: Double) -> String {
        v.formatted(.currency(code: "EUR").locale(locale))
    }

    static func minutes(_ m: Double) -> String {
        let total = max(0, Int(m.rounded()))
        let h = total / 60
        let min = total % 60
        if h == 0 { return tr("\(min) min") }
        return min == 0 ? tr("\(h) h") : tr("\(h) h \(min) min")
    }

    static func clock(_ d: Date) -> String {
        d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    static func mmss(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func km(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f km", v) : "\(Int(v.rounded())) km"
    }

    static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    static func price(_ v: Double) -> String { String(format: "%.2f €/kWh", v) }

    static func hour(_ h: Int) -> String { String(format: "%02d:00", h) }

    static func stops(_ n: Int) -> String {
        if L10n.current == .en {
            return n == 0 ? "no stops" : n == 1 ? "1 stop" : "\(n) stops"
        }
        if n == 0 { return "be sustojimų" }
        if n % 10 == 1 && n % 100 != 11 { return "\(n) sustojimas" }
        if (2...9).contains(n % 10) && !(11...19).contains(n % 100) { return "\(n) sustojimai" }
        return "\(n) sustojimų"
    }
}

// MARK: Building blocks

struct CardBox<Content: View>: View {
    var stroke: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if let stroke {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(stroke, lineWidth: 1.5)
                }
            }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(trKey(title).uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }
}

struct StatView: View {
    let label: String
    let value: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trKey(label)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
            if let sub { Text(trKey(sub)).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Pill: View {
    let text: String
    var color: Color? = nil

    var body: some View {
        Text(trKey(text))
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color ?? .primary)
            .background((color ?? .gray).opacity(0.15), in: Capsule())
    }
}

struct Chip: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(trKey(title))
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(active ? Color.white : Color.primary)
                .background(active ? Theme.brand : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(active ? .clear : Color(.separator), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal battery bar with optional target marker.
struct SocBar: View {
    let value: Double
    var target: Double? = nil
    var height: CGFloat = 10

    private var color: Color { value < 20 ? Theme.bad : value < 40 ? Theme.warn : Theme.ok }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, value / 100)))
                if let target {
                    Rectangle().fill(Color.primary).frame(width: 2)
                        .offset(x: geo.size.width * min(1, target / 100) - 1)
                }
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.primary)
            .background(Theme.fill.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        CardBox {
            VStack(spacing: 8) {
                Image(systemName: systemImage).font(.largeTitle).foregroundStyle(Theme.brand)
                Text(trKey(title)).font(.headline)
                Text(trKey(message)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}
