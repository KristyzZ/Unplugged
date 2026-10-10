import SwiftUI

// Visual system: dark graphite with a violet accent and Liquid Glass on the
// controls you touch (tab bar, search, chips, sheets, charging tile).
// Colors, glass and the small building blocks below are the single place to
// re-skin the app.

enum Theme {
    static let background = Color(hex: "15151B")
    static let card = Color(hex: "24242D")
    static let fill = Color(hex: "2F2F3A")
    static let line = Color(hex: "3A3A46")
    static let brand = Color(hex: "A78BFA")
    static let text = Color(hex: "F5F5F7")
    static let muted = Color(hex: "A1A1AA")
    /// Dark ink used on top of bright status colors (map pins).
    static let ink = Color(hex: "15151B")

    static let ok = Color(hex: "5BC48A")
    static let warn = Color(hex: "E8B04E")
    static let bad = Color(hex: "E5636A")
    static let info = brand
}

enum Layout {
    /// Space reserved at the bottom of scrolling screens for the floating tab bar.
    static let tabBarClearance: CGFloat = 104
}

// MARK: Glass

/// Liquid Glass on iOS 26+, frosted material before that, and an opaque
/// surface when Reduce Transparency is on (so text keeps its contrast).
struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Theme.card, in: shape)
                .overlay(shape.stroke(Theme.line, lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(makeGlass(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background((tint ?? Color.clear).opacity(0.25), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.8))
        }
    }

    @available(iOS 26.0, *)
    private func makeGlass() -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    func glass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    /// Leaves room for the floating tab bar under scrolling content.
    func tabBarClearance() -> some View {
        contentMargins(.bottom, Layout.tabBarClearance, for: .scrollContent)
    }
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
        case .unknown: tr("Status unknown")
        case .available: tr("Available")
        case .charging: tr("Charging now")
        case .idle: tr("Finished, still parked")
        case .blocked: tr("Occupied, not charging")
        case .offline: tr("Out of service")
        case .reserved: tr("Held for the next driver")
        }
    }

    var color: Color {
        switch self {
        case .unknown: .gray
        case .available: Theme.ok
        case .charging: Theme.info
        case .idle: Theme.warn
        case .blocked: Theme.bad
        case .offline: .gray
        case .reserved: Theme.brand
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
        case .unknown: tr("Status unknown")
        }
    }

    var color: Color {
        switch self {
        case .unknown: .gray
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

    static func kw(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v)) kW" : String(format: "%.1f kW", v)
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
        // Frosted dark card, the same surface as the station card on Explore,
        // so the map backdrop shows through faintly.
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card.opacity(0.72), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(stroke ?? Color.white.opacity(0.08), lineWidth: stroke == nil ? 1 : 1.5)
            }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(trKey(title))
            .font(.headline)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }
}

struct StatView: View {
    let label: String
    let value: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trKey(label)).font(.caption).foregroundStyle(Theme.muted)
            Text(value).font(.headline).foregroundStyle(Theme.text)
            if let sub { Text(trKey(sub)).font(.caption2).foregroundStyle(Theme.muted) }
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
            .foregroundStyle(color ?? Theme.text)
            .background((color ?? Theme.muted).opacity(0.16), in: Capsule())
    }
}

/// Glass filter chip. Active chips get a violet tint.
struct Chip: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(trKey(title))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(active ? Color.white : Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glass(in: Capsule(), tint: active ? Theme.brand.opacity(0.55) : nil)
                .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
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
                    Rectangle().fill(Theme.text).frame(width: 2)
                        .offset(x: geo.size.width * min(1, target / 100) - 1)
                }
            }
        }
        .frame(height: height)
        .animation(Motion.pick(.easeOut(duration: 0.4)), value: value)
    }
}

/// Circular progress ring with a symbol or text in the middle.
struct ProgressRing<Center: View>: View {
    let progress: Double
    var color: Color = Theme.brand
    var lineWidth: CGFloat = 4
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0.001, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.pick(.easeOut(duration: 0.4)), value: progress)
            center
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(Theme.ink)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(Theme.text)
            .glass(in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
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
                Text(trKey(message)).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}

/// Pinned title row for the root of each tab. The charging tile sits on the
/// left whenever a session is running.
struct ScreenHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            ChargingTile(style: .compact)
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background {
            // Solid behind the title so scrolled content never shows through,
            // then a short fade so cards slide under it softly.
            Theme.background
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Theme.background, Theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .offset(y: 16)
                        .allowsHitTesting(false)
                }
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}

/// Bordered dropdown: shows the current choice in a field with a chevron and
/// opens a menu of options. Titles must already be localized.
struct DropdownField<Value: Hashable>: View {
    let selection: Binding<Value>
    let options: [(value: Value, title: String)]

    @Environment(\.dynamicTypeSize) private var typeSize

    private var currentTitle: String {
        options.first { $0.value == selection.wrappedValue }?.title ?? ""
    }

    var body: some View {
        Menu {
            Picker("", selection: selection) {
                ForEach(options.indices, id: \.self) { i in
                    Text(options[i].title).tag(options[i].value)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentTitle)
                    .foregroundStyle(Theme.text)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.brand)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Columns of stats that stack vertically at accessibility text sizes, so
/// labels and values wrap whole instead of breaking mid-word.
struct StatRow<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing ?? 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        layout { content }
    }
}

// MARK: Lists

/// Rounded square with a symbol, used at the start of list rows.
struct IconBadge: View {
    let systemImage: String
    var color: Color = Theme.brand

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// A group of rows on one frosted card. Put `RowDivider()` between rows.
struct ListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 0) { content }
        .background(Theme.card.opacity(0.72), in: shape)
        .background(.ultraThinMaterial, in: shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
    }
}

/// Hairline between rows, inset past the icon.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 58)
    }
}

/// Icon, title, optional value and chevron. Used inside ListCard.
struct ListRow<Trailing: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    var color: Color = Theme.brand
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: systemImage, color: color)
            Text(title).font(.body).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

extension ListRow where Trailing == ListRowValue {
    /// Row that navigates somewhere: shows a value and a chevron.
    init(systemImage: String, title: LocalizedStringKey, value: String? = nil, color: Color = Theme.brand) {
        self.init(systemImage: systemImage, title: title, color: color) { ListRowValue(value: value) }
    }
}

struct ListRowValue: View {
    let value: String?

    var body: some View {
        HStack(spacing: 6) {
            if let value {
                Text(value).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted.opacity(0.7))
        }
    }
}
