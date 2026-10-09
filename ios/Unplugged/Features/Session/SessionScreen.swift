import SwiftUI

struct SessionScreen: View {
    var onFindStation: () -> Void = {}

    @Environment(AppModel.self) private var model
    private let speeds: [Double] = [1, 10, 60, 300]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let session = model.session {
                        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                            let snap = SessionSnapshot(session, now: model.simNow())
                            sessionContent(session, snap)
                        }
                        demoControls
                    } else {
                        EmptyStateCard(
                            title: "Not charging right now",
                            message: "Pick a station on the map and start charging — you'll pay right here.",
                            systemImage: "bolt.car"
                        )
                        Button("Find a station", action: onFindStation)
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, 12)
                    }
                    history
                }
                .padding(16)
            }
            .tabBarClearance()
            .screenBackdrop()
            .navigationTitle("Charging")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Charging") }
        }
    }

    @ViewBuilder
    private func sessionContent(_ s: ChargingSession, _ snap: SessionSnapshot) -> some View {
        Text("\(s.stationName) · \(s.connectorLabel)")
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
            .padding(.bottom, 12)

        CardBox {
            HStack {
                phasePill(snap.phase)
                Spacer()
                Text("started \(Fmt.clock(s.startedAt))").font(.caption).foregroundStyle(Theme.muted)
            }
            Text("\(Int(snap.soc.rounded())) %")
                .scaledFont(56, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                .contentTransition(.numericText())
                .padding(.top, 12)
            SocBar(value: snap.soc, target: s.targetSoc, height: 12).padding(.top, 8)
            HStack {
                Text("\(Int(s.startSoc)) %")
                Spacer()
                Text("target \(Int(s.targetSoc)) %")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .padding(.top, 4)
            Divider().padding(.vertical, 12)
            StatRow {
                StatView(label: "Energy", value: String(format: "%.1f kWh", snap.kwh))
                StatView(label: "Cost", value: Fmt.eur(snap.energyCost))
                if snap.phase == .charging {
                    StatView(label: "Left", value: Fmt.minutes(snap.minutesLeft))
                } else {
                    StatView(label: "Idle fee", value: Fmt.eur(snap.idleFee))
                }
            }
        }

        switch snap.phase {
        case .charging:
            Button("Stop charging") { model.stopCharging() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 16)
        case .grace:
            CardBox(stroke: Theme.warn) {
                VStack(spacing: 6) {
                    Text("Free time to move your car").font(.subheadline).foregroundStyle(Theme.muted)
                    Text(Fmt.mmss(snap.graceLeft))
                        .scaledFont(52, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                        .monospacedDigit()
                    Text("Move within 2 min to earn **\(PointsReason.movedFast.points) pts**, or within the grace period to earn **\(PointsReason.movedInGrace.points) pts**")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 12)
            leaveButton
        case .idle:
            idleCard(snap).padding(.top, 12)
            leaveButton
        case .ended:
            receipt(s, snap).padding(.top, 12)
            Button("Done") { model.finishSession() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 16)
        }
    }

    private var leaveButton: some View {
        Button("I moved my car") { model.leaveSpot() }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 16)
    }

    private func phasePill(_ phase: SessionSnapshot.Phase) -> some View {
        switch phase {
        case .charging: Pill(text: tr("Charging now"), color: Theme.info)
        case .grace: Pill(text: "Finished — move your car", color: Theme.warn)
        case .idle: Pill(text: "Idle fee is running", color: Theme.bad)
        case .ended: Pill(text: "Completed", color: Theme.ok)
        }
    }

    private func idleCard(_ snap: SessionSnapshot) -> some View {
        let rate = IdleFee.currentRate(minutes: snap.idleMinutes)
        return CardBox(stroke: Theme.bad) {
            HStack(alignment: .firstTextBaseline) {
                Text("You've been idle for \(Fmt.minutes(snap.idleMinutes))").font(.headline)
                Spacer()
                Text(String(format: "%.2f €/min", rate)).font(.subheadline).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 6) {
                ForEach(Array(IdleFee.tiers.enumerated()), id: \.offset) { item in
                    let tier = item.element
                    let end = item.offset + 1 < IdleFee.tiers.count ? IdleFee.tiers[item.offset + 1].fromMin : nil
                    let active = rate == tier.eurPerMin
                    VStack(spacing: 2) {
                        Text(String(format: "%.2f €/min", tier.eurPerMin)).font(.caption.weight(.semibold))
                        Text(end.map { "\(Int(tier.fromMin))–\(Int($0)) min" } ?? "\(Int(tier.fromMin))+ min").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(active ? Color.white : Color.primary)
                    .background(active ? Theme.bad : Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.top, 12)
            Text("Maximum fee \(Fmt.eur(IdleFee.capEur)). Other drivers are waiting for this spot.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)
        }
    }

    private func receipt(_ s: ChargingSession, _ snap: SessionSnapshot) -> some View {
        CardBox {
            Text("Receipt").font(.headline).padding(.bottom, 8)
            row(String(format: trKey("Charging (%.1f kWh × %.2f €)"), snap.kwh, s.pricePerKwh), Fmt.eur(snap.energyCost))
            row("Idle fee", Fmt.eur(snap.idleFee))
            Divider().padding(.vertical, 6)
            row("Total", Fmt.eur(snap.energyCost + snap.idleFee), bold: true)
            if let pts = s.pointsEarned, pts > 0 {
                row("Points earned", "+\(pts)")
            }
        }
    }

    private func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(trKey(label)).foregroundStyle(bold ? Theme.text : Theme.muted)
            Spacer()
            Text(value)
        }
        .font(bold ? .subheadline.weight(.semibold) : .subheadline)
        .padding(.vertical, 2)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "History")
            CardBox {
                if model.sessionHistory.isEmpty {
                    Text("No past sessions yet.").font(.subheadline).foregroundStyle(Theme.muted)
                }
                ForEach(Array(model.sessionHistory.enumerated()), id: \.offset) { item in
                    let s = item.element
                    let snap = SessionSnapshot(s, now: s.endedAt ?? s.startedAt)
                    if item.offset > 0 { Divider().padding(.vertical, 8) }
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.stationName).font(.subheadline.weight(.semibold))
                            Text("\(s.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))) · \(String(format: "%.1f kWh", snap.kwh))")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            if snap.idleFee > 0 {
                                Text("Includes idle fee \(Fmt.eur(snap.idleFee))").font(.caption).foregroundStyle(Theme.warn)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.eur(snap.energyCost + snap.idleFee)).font(.subheadline.weight(.semibold))
                            if let pts = s.pointsEarned, pts > 0 {
                                Text("+\(pts) pts").font(.caption).foregroundStyle(Theme.ok)
                            }
                        }
                    }
                }
            }
        }
    }

    private var demoControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Lock Screen")
            CardBox {
                Toggle(isOn: Binding(get: { model.lockScreenEnabled }, set: { model.setLockScreen($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show on Lock Screen").font(.subheadline.weight(.semibold))
                        Text("Progress and countdowns on the Lock Screen and in the Dynamic Island, even with the app closed. You can also swipe it away there.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.brand)
            }
            SectionHeader(title: "Demo: time acceleration")
            HStack(spacing: 8) {
                ForEach(speeds, id: \.self) { s in
                    Chip(title: "\(Int(s))×", active: model.speed == s) { model.setSpeed(s) }
                }
            }
            Text("Speed up time to see the notification, the grace period and the growing fee.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}
