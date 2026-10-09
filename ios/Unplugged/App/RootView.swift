import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case explore, plan, charging, profile

    var title: LocalizedStringKey {
        switch self {
        case .explore: "Explore"
        case .plan: "Plan"
        case .charging: "Charging"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .explore: "mappin.and.ellipse"
        case .plan: "point.topleft.down.to.point.bottomright.curvepath"
        case .charging: "bolt.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        // All four tabs stay alive (keeps scroll position, map camera and
        // navigation) — only the selected one is visible.
        ZStack {
            Theme.background.ignoresSafeArea()
            tabContent(.explore) { MapScreen() }
            tabContent(.plan) { PlanScreen() }
            tabContent(.charging) { SessionScreen(onFindStation: { model.tab = .explore }) }
            tabContent(.profile) { ProfileScreen() }
        }
        .overlay(alignment: .bottom) {
            GlassTabBar(selection: $model.tab, chargingActive: model.hasActiveSession)
                .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .top) { BannerStack() }
        // Plug-in, charging done and receipt animations, above everything.
        .overlay { ChargingMomentLayer() }
        .onChange(of: model.session?.stationId) { _, newValue in
            // Jump to the session tab when charging starts.
            if newValue != nil { model.tab = .charging }
        }
        .onChange(of: scenePhase) { _, phase in
            // "I moved my car" pressed on the Lock Screen before the app was running.
            if phase == .active { model.takePendingAction() }
        }
    }

    private func tabContent<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let selected = model.tab == tab
        return content()
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
    }
}

/// Floating Liquid Glass tab bar.
struct GlassTabBar: View {
    @Binding var selection: AppTab
    var chargingActive = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let active = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .scaledFont(19, weight: .semibold, relativeTo: .body)
                            .frame(height: 24)
                            .overlay(alignment: .topTrailing) {
                                if tab == .charging && chargingActive {
                                    Circle().fill(Theme.brand).frame(width: 8, height: 8).offset(x: 6, y: -1)
                                }
                            }
                        Text(tab.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(active ? Theme.brand : Theme.text.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab == .charging && chargingActive ? Text("Charging, session in progress") : Text(tab.title))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 6)
        .glass(in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// In-app notifications shown on top of every screen.
struct BannerStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.banners) { banner in
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title).font(.subheadline.weight(.semibold))
                    if let text = banner.body {
                        Text(text).font(.footnote).opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .foregroundStyle(Theme.text)
                .background(Theme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .glass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                .onTapGesture { model.banners.removeAll { $0.id == banner.id } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Double-tap to dismiss"))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(Motion.pick(.spring(duration: 0.35)), value: model.banners)
    }
}
