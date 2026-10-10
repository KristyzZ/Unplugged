import SwiftUI

/// The current charging session in one glance (ring, one sentence, one
/// action), plus recent sessions.
struct SessionScreen: View {
    var onFindStation: () -> Void = {}

    @Environment(AppModel.self) private var model
    @State private var showDemo = false
    private let speeds: [Double] = [1, 10, 60, 300]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let reservation = model.myReservation {
                        ReservationSummaryCard(reservation: reservation)
                        Button("View station") { model.openStation(reservation.stationId) }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    if let queue = model.queue {
                        CardBox {
                            Text("You're in the queue").font(.headline)
                            Text(model.stations.first(where: { $0.id == queue.stationId })?.name ?? queue.stationId)
                                .font(.subheadline).padding(.top, 4)
                            Text("Demo queue position: \(queue.position). We'll hold a compatible connector for 10 min when a spot is confirmed free.")
                                .font(.caption).foregroundStyle(Theme.muted).padding(.top, 8)
                            Button("View station") { model.openStation(queue.stationId) }
                                .buttonStyle(PrimaryButtonStyle()).padding(.top, 12)
                            Button("Leave queue") { model.leaveQueue() }
                                .buttonStyle(SecondaryButtonStyle()).padding(.top, 8)
                        }
                    }
                    if let session = model.session {
                        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                            let snap = SessionSnapshot(session, now: model.simNow())
                            activeCard(session, snap)
                        }
                        demoControls
                    } else if model.myReservation == nil && model.queue == nil {
                        idleCard
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

    // MARK: Not charging

    private var idleCard: some View {
        CardBox {
            VStack(spacing: 10) {
                IconBadge(systemImage: "bolt.car.fill").scaleEffect(1.4).padding(.bottom, 6)
                Text("You're not charging").font(.headline).foregroundStyle(Theme.text)
                Text("Pick a station on Explore and start there. Your session shows up here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Button("Find a station", action: onFindStation)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: Charging

    private func activeCard(_ s: ChargingSession, _ snap: SessionSnapshot) -> some View {
        let look = PhaseLook(s, snap, fullAt: Fmt.clock(model.realDate(s.scheduledDoneAt)))
        let charging = snap.phase == .charging
        return CardBox {
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(s.stationName).font(.headline).foregroundStyle(Theme.text)
                    Text(s.connectorLabel).font(.caption).foregroundStyle(Theme.muted)
                }

                ChargeRing(
                    progress: look.progress,
                    limit: charging ? s.targetSoc / 100 : nil,
                    color: look.color,
                    lineWidth: 14,
                    flowing: charging
                ) {
                    VStack(spacing: 2) {
                        Text(look.value)
                            .scaledFont(40, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Theme.text)
                        Text(look.caption)
                            .font(.subheadline)
                            .foregroundStyle(look.color)
                    }
                }
                .frame(width: 200, height: 200)
                .padding(.vertical, 4)

                Text(look.explanation)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                StatRow {
                    if charging {
                        // What the driver feels: range gained, speed, cost so far.
                        let added = model.vehicle.rangeKm(soc: snap.soc) - model.vehicle.rangeKm(soc: s.startSoc)
                        StatView(label: "Range added", value: "+\(Fmt.km(max(0, added)))")
                        StatView(label: "Power", value: "\(Int(s.averageKw.rounded())) kW")
                        StatView(label: "So far", value: Fmt.eur(snap.chargingCost))
                    } else {
                        StatView(label: "Energy", value: String(format: "%.1f kWh", snap.kwh))
                        StatView(label: "Charging", value: Fmt.eur(snap.chargingCost))
                        // Only once it matters, so it doesn't read as a cost while charging.
                        if snap.idleFee > 0 {
                            StatView(label: "Idle fee", value: Fmt.eur(snap.idleFee))
                        }
                    }
                }
                .padding(.top, 4)

                // The frozen contract and its lines (energy, start fee, time), one tap away.
                if let terms = s.pricingTerms, let charges = snap.pricingCharges {
                    DisclosureGroup {
                        PricingBreakdownView(terms: terms, charges: charges).padding(.top, 8)
                    } label: {
                        Text("Price details").font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                    }
                    .tint(Theme.muted)
                }

                action(snap.phase)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func action(_ phase: SessionSnapshot.Phase) -> some View {
        switch phase {
        case .charging:
            Button("Stop charging") { model.stopCharging() }.buttonStyle(SecondaryButtonStyle())
        case .grace, .idle:
            Button("I moved my car") { model.leaveSpot() }.buttonStyle(PrimaryButtonStyle())
        case .ended:
            Button("Done") { model.finishSession() }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private var demoControls: some View {
        CardBox {
            DisclosureGroup(isExpanded: $showDemo) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(speeds, id: \.self) { s in
                            Chip(title: "\(Int(s))×", active: model.speed == s) { model.setSpeed(s) }
                        }
                    }
                    Text("Speeds up time so you can see the finished notice, the free minutes and the idle fee.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 10)
            } label: {
                Text("Demo: speed up time").font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
            }
            .tint(Theme.muted)
        }
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        if !model.sessionHistory.isEmpty {
            Text("Recent").font(.headline).foregroundStyle(Theme.text).padding(.top, 12)
            ListCard {
                ForEach(Array(model.sessionHistory.prefix(10).enumerated()), id: \.offset) { item in
                    if item.offset > 0 { RowDivider() }
                    historyRow(item.element)
                }
            }
        }
    }

    private func historyRow(_ s: ChargingSession) -> some View {
        let snap = SessionSnapshot(s, now: s.endedAt ?? s.startedAt)
        let day = s.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale))
        // Name the plan when one priced the session.
        let date = s.pricingTerms?.plan.map { "\(day) · \($0.name)" } ?? day
        return HStack(spacing: 12) {
            IconBadge(systemImage: "bolt.fill", color: snap.idleFee > 0 ? Theme.warn : Theme.ok)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.stationName).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                Text(snap.idleFee > 0 ? tr("\(date) · idle fee \(Fmt.eur(snap.idleFee))") : date)
                    .font(.caption)
                    .foregroundStyle(snap.idleFee > 0 ? Theme.warn : Theme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.eur(snap.chargingCost + snap.idleFee)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                if let pts = s.pointsEarned, pts > 0 {
                    Text("+\(pts) pts").font(.caption).foregroundStyle(Theme.ok)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// What the ring and the sentence under it say in each phase.
private struct PhaseLook {
    let value: String
    let caption: String
    let explanation: String
    let color: Color
    let progress: Double

    init(_ s: ChargingSession, _ snap: SessionSnapshot, fullAt: String) {
        switch snap.phase {
        case .charging:
            value = "\(Int(snap.soc.rounded())) %"
            caption = snap.minutesLeft < 1 ? tr("Almost done") : tr("\(Fmt.minutes(snap.minutesLeft)) left")
            explanation = tr("Charging to \(Int(s.targetSoc)) % · full at \(fullAt). We'll tell you when it's done.")
            color = Theme.brand
            progress = snap.soc / 100
        case .grace:
            value = Fmt.mmss(snap.graceLeft)
            caption = tr("to move your car")
            explanation = tr("Charging is done. Move within these free minutes to earn \(PointsReason.movedInGrace.points)–\(PointsReason.movedFast.points) points.")
            color = Theme.warn
            progress = snap.graceLeft / max(1, Double(s.graceMinutes) * 60)
        case .idle:
            value = Fmt.eur(snap.idleFee)
            caption = String(format: trKey("%.2f €/min"), IdleFee.currentRate(minutes: snap.idleMinutes))
            explanation = tr("Idle fee is running and goes up the longer the car stays. Others are waiting for this spot.")
            color = Theme.bad
            progress = 1
        case .ended:
            value = Fmt.eur(snap.chargingCost + snap.idleFee)
            caption = tr("total")
            explanation = (s.pointsEarned ?? 0) > 0
                ? tr("Thanks for freeing the spot. You earned \(s.pointsEarned ?? 0) points.")
                : tr("Thanks for freeing the spot.")
            color = Theme.ok
            progress = 1
        }
    }
}
