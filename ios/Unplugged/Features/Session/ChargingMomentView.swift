import SwiftUI

/// Full-screen moments over the whole app when a session changes state:
/// plugging in, charging done, and the receipt after the car has moved.
/// Each runs for about two seconds and then waits for the driver.
struct ChargingMomentLayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let moment = model.moment, let session = model.session {
                MomentBackdrop(color: color(moment))
                    .transition(.opacity)

                Group {
                    switch moment {
                    case .started:
                        StartedMoment(session: session)
                    case .completed(let stopped):
                        CompletedMoment(session: session, stopped: stopped)
                    case .finished:
                        FinishedMoment(session: session)
                    }
                }
                .id(moment.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97)),
                    removal: .opacity
                ))
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(Motion.pick(.easeInOut(duration: 0.35)), value: model.moment)
    }

    private func color(_ moment: ChargingMoment) -> Color {
        switch moment {
        case .started: Theme.brand
        case .completed, .finished: Theme.ok
        }
    }
}

/// Dark backdrop with a faint glow of the moment's colour behind the ring.
private struct MomentBackdrop: View {
    let color: Color

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [color.opacity(0.16), .clear],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
        .animation(Motion.pick(.easeInOut(duration: 0.6)), value: color)
    }
}

/// Sleeps, but reports cancellation so a moment that was closed stops its script.
private func pause(_ seconds: Double) async -> Bool {
    (try? await Task.sleep(for: .seconds(seconds))) != nil
}

// MARK: - Plug in

/// Station → cable → ring. While connecting the cable is grey and the ring
/// searches; once charging starts the cable flows violet, the plug turns into
/// a bolt, and the ring fills to the current battery level with a pulse.
private struct StartedMoment: View {
    let session: ChargingSession

    @Environment(AppModel.self) private var model
    @State private var connected = false
    @State private var shownSoc: Double = 0
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            stationChip
            EnergyCable(active: connected)
                .frame(width: 4, height: 56)

            ZStack {
                if connected && !Motion.reduced {
                    ForEach(0..<2, id: \.self) { i in
                        Circle()
                            .stroke(Theme.brand.opacity(0.55), lineWidth: 2)
                            .scaleEffect(pulse ? 1.5 : 1)
                            .opacity(pulse ? 0 : 0.8)
                            .animation(.easeOut(duration: 1.4).delay(Double(i) * 0.3), value: pulse)
                    }
                }

                ChargeRing(
                    progress: shownSoc / 100,
                    limit: connected ? session.targetSoc / 100 : nil,
                    color: Theme.brand,
                    lineWidth: 14,
                    flowing: connected
                ) {
                    VStack(spacing: 2) {
                        Image(systemName: connected ? "bolt.fill" : "powerplug.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(connected ? Theme.brand : Theme.muted)
                            .contentTransition(.symbolEffect(.replace))
                        Text("\(Int(shownSoc)) %")
                            .scaledFont(42, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .contentTransition(.numericText(value: shownSoc))
                            .opacity(connected ? 1 : 0)
                    }
                }

                if !connected {
                    SearchingArc(lineWidth: 14)
                }
            }
            .frame(width: 220, height: 220)

            VStack(spacing: 8) {
                Group {
                    if connected { Text("Charging started") } else { Text("Connecting…") }
                }
                .font(.title2.bold())
                .foregroundStyle(Theme.text)
                .contentTransition(.opacity)

                Group {
                    if connected {
                        Text("Charging to \(Int(session.targetSoc)) % · full at \(Fmt.clock(model.realDate(session.scheduledDoneAt)))")
                    } else {
                        Text("Talking to the charger")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            }
            .padding(.top, 30)
            .padding(.horizontal, 32)

            Spacer(minLength: 24)

            Button("Got it") { model.dismissMoment() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 48)
                .padding(.bottom, 24)
                .opacity(connected ? 1 : 0)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: connected)
        .task { await run() }
    }

    private var stationChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connected ? Theme.brand : Theme.muted)
                .frame(width: 8, height: 8)
            Text(session.stationName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text(session.connectorLabel)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .combine)
    }

    private func run() async {
        guard await pause(Motion.reduced ? 0.3 : 1.2) else { return }
        withMotion(.spring(duration: 0.5, bounce: 0.3)) { connected = true }
        withMotion(.easeOut(duration: 1.1)) { shownSoc = session.startSoc.rounded() }
        // The pulse rings appear with `connected`; flip `pulse` a frame later so they animate.
        guard await pause(0.05) else { return }
        pulse = true
        guard await pause(3.4) else { return }
        if model.moment == .started { model.dismissMoment() }
    }
}

/// Dashed line between the station and the ring. Grey and still while
/// connecting; violet with dashes running down once energy flows.
private struct EnergyCable: View {
    var active: Bool

    var body: some View {
        TimelineView(.animation(paused: !active || Motion.reduced)) { context in
            // Wrap to one dash period (5 + 7): a phase built from the raw
            // reference-date seconds is ~1e10 and stalls rendering while it's drawn.
            let phase = (context.date.timeIntervalSinceReferenceDate * 28).truncatingRemainder(dividingBy: 12)
            CableLine()
                .stroke(
                    active ? Theme.brand : Theme.muted.opacity(0.6),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 7], dashPhase: active ? -phase : 0)
                )
        }
        .animation(Motion.pick(.easeInOut(duration: 0.4)), value: active)
        .accessibilityHidden(true)
    }
}

private struct CableLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// A short arc circling the ring while the charger is answering.
private struct SearchingArc: View {
    var lineWidth: CGFloat
    @State private var spin = false

    var body: some View {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: 0.16)
            .stroke(Theme.muted, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(spin ? 270 : -90))
            .animation(Motion.pick(.linear(duration: 0.9).repeatForever(autoreverses: false)), value: spin)
            .onAppear { spin = true }
            .accessibilityHidden(true)
    }
}

// MARK: - Charging done

/// The ring completes and turns green, the bolt becomes a check, sparks fly.
/// Then the one thing to do: move the car while it's still free.
private struct CompletedMoment: View {
    let session: ChargingSession
    let stopped: Bool

    @Environment(AppModel.self) private var model
    @State private var filled = false
    @State private var done = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let snap = SessionSnapshot(session, now: model.simNow())
            let soc = snap.soc.rounded()
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                ZStack {
                    if done && !Motion.reduced {
                        SparkBurst(color: Theme.ok, radius: 110)
                    }
                    ChargeRing(
                        progress: filled ? soc / 100 : max(0, soc / 100 - 0.08),
                        color: done ? Theme.ok : Theme.brand,
                        lineWidth: 14
                    ) {
                        VStack(spacing: 2) {
                            Image(systemName: done ? "checkmark" : "bolt.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(done ? Theme.ok : Theme.brand)
                                .contentTransition(.symbolEffect(.replace))
                            Text("\(Int(soc)) %")
                                .scaledFont(42, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                .frame(width: 220, height: 220)

                VStack(spacing: 8) {
                    Group {
                        if stopped { Text("Charging stopped") } else { Text("Charged to \(Int(soc)) %") }
                    }
                    .font(.title2.bold())
                    .foregroundStyle(Theme.text)

                    message(snap)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 30)
                .padding(.horizontal, 32)

                if snap.phase == .grace {
                    countdown(snap)
                        .padding(.top, 20)
                }

                Spacer(minLength: 24)

                VStack(spacing: 10) {
                    Button("I moved my car") { model.leaveSpot() }
                        .buttonStyle(PrimaryButtonStyle(color: snap.phase == .idle ? Theme.bad : Theme.ok))
                    Button("Later") { model.dismissMoment() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }
        }
        .sensoryFeedback(.success, trigger: done)
        .task {
            guard await pause(0.2) else { return }
            withMotion(.easeInOut(duration: 0.7)) { filled = true }
            guard await pause(Motion.reduced ? 0.1 : 0.75) else { return }
            withMotion(.spring(duration: 0.45, bounce: 0.35)) { done = true }
        }
    }

    @ViewBuilder
    private func message(_ snap: SessionSnapshot) -> some View {
        if snap.phase == .idle {
            Text("The free time is over and the idle fee is running: \(Fmt.eur(snap.idleFee)) so far. Others are waiting for this spot.")
        } else {
            Text("Move your car while it's free. Within 2 min: +\(PointsReason.movedFast.points) pts, within the free time: +\(PointsReason.movedInGrace.points) pts.")
        }
    }

    private func countdown(_ snap: SessionSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
            Text(Fmt.mmss(snap.graceLeft))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            Text("free time left").foregroundStyle(Theme.muted)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.warn)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.warn.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Receipt

/// The check draws itself, the receipt slides in line by line, the points pop.
private struct FinishedMoment: View {
    let session: ChargingSession

    @Environment(AppModel.self) private var model
    @State private var circle = false
    @State private var check = false
    @State private var rows = false
    @State private var shownPoints = 0

    var body: some View {
        let snap = SessionSnapshot(session, now: session.endedAt ?? model.simNow())
        let points = session.pointsEarned ?? 0
        let lines = receiptLines(snap)

        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .inset(by: 3)
                    .trim(from: 0, to: circle ? 1 : 0)
                    .rotation(.degrees(-90))
                    .stroke(Theme.ok, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                CheckShape()
                    .trim(from: 0, to: check ? 1 : 0)
                    .stroke(Theme.ok, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                if check && !Motion.reduced {
                    SparkBurst(color: Theme.ok, radius: 58, count: 12)
                }
            }
            .frame(width: 112, height: 112)
            .accessibilityHidden(true)

            Text("Spot freed. Thanks!")
                .font(.title2.bold())
                .foregroundStyle(Theme.text)
                .padding(.top, 22)
            Text(session.stationName)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)

            ListCard {
                ForEach(Array(lines.enumerated()), id: \.offset) { item in
                    let line = item.element
                    if item.offset > 0 {
                        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 16)
                    }
                    HStack {
                        Text(line.label)
                            .foregroundStyle(line.isTotal ? Theme.text : Theme.muted)
                        Spacer()
                        Text(line.value)
                            .monospacedDigit()
                            .foregroundStyle(line.color ?? Theme.text)
                    }
                    .font(line.isTotal ? .headline : .subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .opacity(rows ? 1 : 0)
                    .offset(y: rows ? 0 : 10)
                    .animation(Motion.pick(.spring(duration: 0.45).delay(Double(item.offset) * 0.06)), value: rows)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .opacity(rows ? 1 : 0)
            .animation(Motion.pick(.easeOut(duration: 0.25)), value: rows)

            pointsLine(points)
                .padding(.top, 18)
                .padding(.horizontal, 32)

            if session.handedOver == true {
                handOffLine
                    .padding(.top, 14)
                    .padding(.horizontal, 32)
                    .opacity(shownPoints > 0 || points == 0 ? 1 : 0)
                    .offset(y: shownPoints > 0 || points == 0 ? 0 : 8)
                    .animation(Motion.pick(.spring(duration: 0.5).delay(0.25)), value: shownPoints)
            }

            Spacer(minLength: 24)

            Button("Done") { model.finishSession() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
        .sensoryFeedback(.success, trigger: check)
        .task {
            withMotion(.easeOut(duration: 0.45)) { circle = true }
            guard await pause(0.35) else { return }
            withMotion(.easeOut(duration: 0.3)) { check = true }
            guard await pause(0.2) else { return }
            rows = true
            guard await pause(0.5) else { return }
            withMotion(.spring(duration: 0.6, bounce: 0.45)) { shownPoints = points }
        }
    }

    /// Someone was waiting: the spot went straight to them.
    private var handOffLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.brand)
                .frame(width: 30, height: 30)
                .background(Theme.brand.opacity(0.16), in: Circle())
            Text("Next driver notified. Your spot is held for them for \(Int(SpotHold.minutes)) min.")
                .font(.footnote)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func pointsLine(_ points: Int) -> some View {
        if points > 0 {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                Text("+\(shownPoints) pts")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(shownPoints)))
            }
            .font(.headline)
            .foregroundStyle(Theme.ok)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.ok.opacity(0.14), in: Capsule())
            .scaleEffect(shownPoints > 0 ? 1 : 0.6)
            .opacity(shownPoints > 0 ? 1 : 0)
            .accessibilityLabel(Text("+\(points) pts"))
        } else {
            Text("No points this time. Move within the free minutes to earn them.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .opacity(rows ? 1 : 0)
        }
    }

    private struct Line {
        let label: LocalizedStringKey
        let value: String
        var color: Color? = nil
        var isTotal = false
    }

    private func receiptLines(_ snap: SessionSnapshot) -> [Line] {
        var lines = [
            Line(label: "Battery", value: "\(Int(session.startSoc.rounded())) → \(Int(snap.soc.rounded())) %"),
            Line(label: "Energy", value: String(format: "%.1f kWh", snap.kwh)),
        ]
        // Sessions priced with frozen terms itemize the charge; older ones are energy only.
        if let charges = snap.pricingCharges {
            lines.append(Line(label: "Energy charge", value: Fmt.eur(charges.energy)))
            if charges.sessionStart > 0 {
                lines.append(Line(label: "Session start fee", value: Fmt.eur(charges.sessionStart)))
            }
            if charges.chargingTime > 0 {
                lines.append(Line(label: "Charging time fee", value: Fmt.eur(charges.chargingTime)))
            }
            if charges.savings > 0 {
                lines.append(Line(label: "Plan saving (already included)", value: Fmt.eur(charges.savings), color: Theme.ok))
            }
        } else {
            lines.append(Line(label: "Charging", value: Fmt.eur(snap.chargingCost)))
        }
        if snap.idleFee > 0 {
            lines.append(Line(label: "Idle fee", value: Fmt.eur(snap.idleFee), color: Theme.bad))
        }
        lines.append(Line(label: "Total", value: Fmt.eur(snap.chargingCost + snap.idleFee), isTotal: true))
        return lines
    }
}
