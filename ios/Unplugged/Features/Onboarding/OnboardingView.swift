import SwiftUI
import UserNotifications

/// First launch: what Unplugged is, your car, your battery and charge limit,
/// and why it asks for location and notifications. Four short steps; every
/// answer can be changed later in Profile.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationManager.self) private var location
    @State private var step = 0
    @State private var picking = false
    @State private var notificationsAllowed = false

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $step) {
                welcome.tag(0)
                car.tag(1)
                battery.tag(2)
                permissions.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(Motion.pick(.easeInOut(duration: 0.3)), value: step)

            Button {
                if step == lastStep { finish() } else { withMotion(.easeInOut(duration: 0.3)) { step += 1 } }
            } label: {
                if step == lastStep { Text("Start using Unplugged") } else { Text("Continue") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background {
            ZStack {
                Theme.background
                RadialGradient(colors: [Theme.brand.opacity(0.14), .clear], center: UnitPoint(x: 0.5, y: 0.25), startRadius: 0, endRadius: 380)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .sheet(isPresented: $picking) { VehiclePicker() }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = settings.authorizationStatus == .authorized
        }
    }

    private func finish() {
        if location.allowed { location.request() }
        model.completeOnboarding()
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                withMotion(.easeInOut(duration: 0.3)) { step -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 40, height: 40)
                    .glass(in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(step > 0 ? 1 : 0)
            .disabled(step == 0)
            .accessibilityLabel(Text("Back"))

            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Theme.brand : Theme.fill)
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel(Text("Step \(step + 1) of \(lastStep + 1)"))

            Button("Skip") { finish() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 40, minHeight: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Pages

    private var welcome: some View {
        Page {
            ChargeRing(progress: 0.64, limit: 0.8, color: Theme.brand, lineWidth: 12, flowing: true) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.brand)
            }
            .frame(width: 130, height: 130)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            Heading(title: "Charge without the hassle",
                    subtitle: "Every charger in Lithuania in one app, kept free for the people who need them.")

            VStack(alignment: .leading, spacing: 18) {
                Feature(icon: "map.fill", color: Theme.brand, title: "Every charger, one map",
                        text: "Live availability, power and prices from every operator.")
                Feature(icon: "creditcard.fill", color: Theme.ok, title: "Pay in one place",
                        text: "Start and pay without switching between operator apps.")
                Feature(icon: "star.fill", color: Theme.warn, title: "Move on time, earn points",
                        text: "Free the spot when you're done and get discounts for it.")
            }
            .padding(.top, 8)
        }
    }

    private var car: some View {
        let v = model.vehicle
        return Page {
            Heading(title: "What do you drive?",
                    subtitle: "We'll show only chargers that fit, and plan stops around its real charging speed.")
            CardBox {
                HStack(spacing: 14) {
                    IconBadge(systemImage: "car.side.fill").scaleEffect(1.3).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.brand).font(.subheadline).foregroundStyle(Theme.muted)
                        Text(v.title).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                StatRow {
                    StatView(label: "Battery", value: "\(Int(v.batteryKwh.rounded())) kWh")
                    StatView(label: "Fast charging", value: v.dcKw > 0 ? Fmt.kw(v.dcKw) : "–")
                    StatView(label: "Range", value: "≈ " + Fmt.km(v.rangeKm(soc: 100)))
                }
                .padding(.top, 14)
                Button("Choose your car") { picking = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 14)
            }
            Text("\(VehicleCatalog.all.count) models. Car data: \(VehicleCatalog.attribution)")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
    }

    private var battery: some View {
        let socBinding = Binding(get: { model.soc }, set: { model.setSoc($0) })
        return Page {
            Heading(title: "Your battery",
                    subtitle: "Where you are now and where you usually stop. You can change both anytime.")
            ChargeRing(progress: model.soc / 100, limit: model.chargeLimit / 100, color: Theme.brand, lineWidth: 12) {
                VStack(spacing: 0) {
                    Text("\(Int(model.soc)) %")
                        .scaledFont(30, weight: .bold, design: .rounded, relativeTo: .title)
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text("≈ \(Fmt.km(model.vehicle.rangeKm(soc: model.soc)))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 150, height: 150)
            .frame(maxWidth: .infinity)
            CardBox {
                Text("Battery now").font(.subheadline).foregroundStyle(Theme.muted)
                Slider(value: socBinding, in: 1...100, step: 1).tint(Theme.brand)
                ChargeLimitPicker().padding(.top, 10)
            }
        }
    }

    private var permissions: some View {
        Page {
            Heading(title: "Two quick permissions",
                    subtitle: "Both are optional. Here's exactly what they're for.")
            PermissionCard(
                icon: "location.fill",
                title: "Chargers near you",
                text: "Sorts the map and the widget by distance. Your location stays on your phone.",
                allowed: location.allowed
            ) {
                location.request()
            }
            PermissionCard(
                icon: "bell.badge.fill",
                title: "Know when to move",
                text: "Charging done, free time running out, and a spot held for you in the queue.",
                allowed: notificationsAllowed
            ) {
                NotificationManager.shared.requestPermission { granted in
                    Task { @MainActor in notificationsAllowed = granted }
                }
            }
        }
    }
}

// MARK: - Pieces

/// A scrollable page with consistent spacing.
private struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }
}

private struct Heading: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Feature: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemImage: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                Text(text).font(.subheadline).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionCard: View {
    let icon: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    let allowed: Bool
    let allow: () -> Void

    var body: some View {
        CardBox {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemImage: icon)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Theme.text)
                    Text(text).font(.subheadline).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if allowed {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ok)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .padding(.top, 12)
            } else {
                Button("Allow", action: allow)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 12)
            }
        }
    }
}
