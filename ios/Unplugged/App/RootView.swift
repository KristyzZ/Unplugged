import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case map, plan, rewards, report

    var title: LocalizedStringKey {
        switch self {
        case .map: "Map"
        case .plan: "Trip"
        case .rewards: "Points"
        case .report: "Report"
        }
    }

    var icon: String {
        switch self {
        case .map: "mappin.and.ellipse"
        case .plan: "point.topleft.down.to.point.bottomright.curvepath"
        case .rewards: "star.fill"
        case .report: "exclamationmark.triangle.fill"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // All four tabs stay alive (keeps scroll position, map camera and
        // navigation) — only the selected one is visible.
        ZStack {
            Theme.background.ignoresSafeArea()
            tabContent(.map) { MapScreen() }
            tabContent(.plan) { PlanScreen() }
            tabContent(.rewards) { RewardsScreen() }
            tabContent(.report) { ReportScreen() }
        }
        .overlay(alignment: .bottom) {
            GlassTabBar(selection: $model.tab)
                .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .top) { BannerStack() }
        .sheet(isPresented: $model.showSession) {
            SessionSheet()
                .environment(model)
                .environment(\.locale, model.lang.locale)
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let active = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 24)
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
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
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
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.spring(duration: 0.35), value: model.banners)
    }
}
