import SwiftUI
import WidgetKit

// Home-screen and Lock Screen widget: the nearest fast charger with a free
// spot that fits your car. Data comes from the app (NearbySnapshot in the
// shared App Group); tapping opens that station in the app.

struct NearbyEntry: TimelineEntry {
    let date: Date
    let snapshot: NearbySnapshot?
}

struct NearbyProvider: TimelineProvider {
    func placeholder(in context: Context) -> NearbyEntry {
        NearbyEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NearbyEntry) -> Void) {
        completion(NearbyEntry(date: .now, snapshot: NearbySnapshot.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearbyEntry>) -> Void) {
        // The app asks for a reload when availability changes; this is the fallback.
        let entry = NearbyEntry(date: .now, snapshot: NearbySnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct NearbyChargerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: NearbySnapshot.widgetKind, provider: NearbyProvider()) { entry in
            NearbyWidgetView(entry: entry)
                .containerBackground(for: .widget) { NTheme.background }
        }
        .configurationDisplayName("Nearest free charger")
        .description("The closest fast charger with a free spot for your car.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

/// Same palette as the app.
private enum NTheme {
    static let background = Color(red: 0x15 / 255, green: 0x15 / 255, blue: 0x1B / 255)
    static let card = Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x2D / 255)
    static let violet = Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255)
    static let green = Color(red: 0x5B / 255, green: 0xC4 / 255, blue: 0x8A / 255)
    static let red = Color(red: 0xE5 / 255, green: 0x63 / 255, blue: 0x6A / 255)
    static let text = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
    static let muted = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xAA / 255)
}

private struct NearbyWidgetView: View {
    let entry: NearbyEntry
    @Environment(\.widgetFamily) private var family

    private var lt: Bool { entry.snapshot?.lang == "lt" }
    private func t(_ en: String, _ ltText: String) -> String { lt ? ltText : en }

    var body: some View {
        if let snapshot = entry.snapshot, let first = snapshot.chargers.first {
            switch family {
            case .systemMedium: medium(snapshot)
            case .accessoryRectangular: rectangular(first, anyFree: snapshot.anyFree)
            default: small(first, snapshot: snapshot)
            }
        } else {
            empty
        }
    }

    // MARK: Small

    private func small(_ c: NearbySnapshot.Charger, snapshot: NearbySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                Text(snapshot.anyFree ? t("Free nearby", "Laisva netoli") : t("All busy", "Visos užimtos"))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(snapshot.anyFree ? NTheme.violet : NTheme.red)

            Spacer(minLength: 4)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(c.maxKw))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(NTheme.text)
                Text("kW").font(.caption.weight(.semibold)).foregroundStyle(NTheme.muted)
            }
            Text(c.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                Text(free(c)).foregroundStyle(c.freeCount > 0 ? NTheme.green : NTheme.red)
                Text("· " + km(c.distanceKm)).foregroundStyle(NTheme.muted)
            }
            .font(.caption.weight(.medium))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(NearbySnapshot.url(station: c.id))
    }

    // MARK: Medium

    private func medium(_ snapshot: NearbySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(snapshot.anyFree ? t("Free fast chargers nearby", "Laisvos greitosios stotelės") : t("Fast chargers nearby are busy", "Greitosios stotelės užimtos"),
                      systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.anyFree ? NTheme.violet : NTheme.red)
                Spacer()
                Text(snapshot.generatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(NTheme.muted)
            }
            ForEach(snapshot.chargers.prefix(3)) { c in
                Link(destination: NearbySnapshot.url(station: c.id)) {
                    HStack(spacing: 10) {
                        Text("\(Int(c.maxKw))")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(NTheme.text)
                            .frame(width: 44, height: 28)
                            .background(NTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.name).font(.subheadline.weight(.semibold)).foregroundStyle(NTheme.text).lineLimit(1)
                            Text(String(format: "%.2f €/kWh", c.pricePerKwh)).font(.caption2).foregroundStyle(NTheme.muted)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(free(c)).font(.caption.weight(.semibold))
                                .foregroundStyle(c.freeCount > 0 ? NTheme.green : NTheme.red)
                            Text(km(c.distanceKm)).font(.caption2).foregroundStyle(NTheme.muted)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Lock Screen

    private func rectangular(_ c: NearbySnapshot.Charger, anyFree: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("\(Int(c.maxKw)) kW · \(km(c.distanceKm))", systemImage: "bolt.fill")
                .font(.headline)
            Text(c.name).lineLimit(1)
            Text(free(c)).foregroundStyle(.secondary)
        }
        .widgetURL(NearbySnapshot.url(station: c.id))
    }

    // MARK: Empty

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "bolt.car.fill")
                .font(.title2)
                .foregroundStyle(NTheme.violet)
            Text(t("Open Unplugged to see chargers near you", "Atidarykite Unplugged ir pamatysite stoteles šalia"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(NTheme.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func free(_ c: NearbySnapshot.Charger) -> String {
        c.freeCount > 0 ? t("\(c.freeCount)/\(c.workingCount) free", "\(c.freeCount)/\(c.workingCount) laisvos") : t("Full", "Užimta")
    }

    private func km(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f km", v) : "\(Int(v.rounded())) km"
    }
}

private extension NearbySnapshot {
    static let sample = NearbySnapshot(
        generatedAt: .now,
        chargers: [
            .init(id: "akropolis", name: "Akropolis", address: "Ozo g. 25", freeCount: 2, workingCount: 4, maxKw: 150, pricePerKwh: 0.59, distanceKm: 1.2),
            .init(id: "ozas", name: "Ozas", address: "Ozo g. 18", freeCount: 1, workingCount: 3, maxKw: 120, pricePerKwh: 0.55, distanceKm: 1.6),
            .init(id: "europa", name: "Europa", address: "Konstitucijos pr. 7A", freeCount: 3, workingCount: 6, maxKw: 50, pricePerKwh: 0.49, distanceKm: 2.1),
        ],
        anyFree: true,
        carName: "Hyundai IONIQ 5",
        lang: "en"
    )
}

#Preview("Small", as: .systemSmall) {
    NearbyChargerWidget()
} timeline: {
    NearbyEntry(date: .now, snapshot: .sample)
}
