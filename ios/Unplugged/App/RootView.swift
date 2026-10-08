import SwiftUI

enum AppTab: Hashable {
    case map, plan, session, rewards, report
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(AppTab.map)
            PlanScreen()
                .tabItem { Label("Trip", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(AppTab.plan)
            SessionScreen(onFindStation: { model.tab = .map })
                .tabItem { Label("Charge", systemImage: "bolt.car") }
                .tag(AppTab.session)
                .badge(model.hasActiveSession ? Text("•") : nil)
            RewardsScreen()
                .tabItem { Label("Points", systemImage: "star") }
                .tag(AppTab.rewards)
            ReportScreen()
                .tabItem { Label("Report", systemImage: "exclamationmark.triangle") }
                .tag(AppTab.report)
        }
        .overlay(alignment: .top) { BannerStack() }
        .onChange(of: model.session?.stationId) { _, newValue in
            // Jump to the session tab when charging starts.
            if newValue != nil { model.tab = .session }
        }
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
                .foregroundStyle(.white)
                .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 8, y: 4)
                .onTapGesture { model.banners.removeAll { $0.id == banner.id } }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.spring(duration: 0.35), value: model.banners)
    }
}
