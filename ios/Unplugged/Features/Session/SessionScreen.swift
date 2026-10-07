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
                            title: "Šiuo metu nesikraunate",
                            message: "Pasirinkite stotelę žemėlapyje ir pradėkite įkrovimą — atsiskaitysite čia pat.",
                            systemImage: "bolt.car"
                        )
                        Button("Rasti stotelę", action: onFindStation)
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, 12)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Įkrovimas")
        }
    }

    @ViewBuilder
    private func sessionContent(_ s: ChargingSession, _ snap: SessionSnapshot) -> some View {
        Text("\(s.stationName) · \(s.connectorLabel)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 12)

        CardBox {
            HStack {
                phasePill(snap.phase)
                Spacer()
                Text("pradėta \(Fmt.clock(s.startedAt))").font(.caption).foregroundStyle(.secondary)
            }
            Text("\(Int(snap.soc.rounded())) %")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .padding(.top, 12)
            SocBar(value: snap.soc, target: s.targetSoc, height: 12).padding(.top, 8)
            HStack {
                Text("\(Int(s.startSoc)) %")
                Spacer()
                Text("tikslas \(Int(s.targetSoc)) %")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            Divider().padding(.vertical, 12)
            HStack(alignment: .top) {
                StatView(label: "Energija", value: String(format: "%.1f kWh", snap.kwh))
                StatView(label: "Kaina", value: Fmt.eur(snap.energyCost))
                if snap.phase == .charging {
                    StatView(label: "Liko", value: Fmt.minutes(snap.minutesLeft))
                } else {
                    StatView(label: "Prastovos mokestis", value: Fmt.eur(snap.idleFee))
                }
            }
        }

        switch snap.phase {
        case .charging:
            Button("Sustabdyti įkrovimą") { model.stopCharging() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 16)
        case .grace:
            CardBox(stroke: Theme.warn) {
                VStack(spacing: 6) {
                    Text("Nemokamas laikas patraukti automobilį").font(.subheadline).foregroundStyle(.secondary)
                    Text(Fmt.mmss(snap.graceLeft))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Patraukite per 2 min. ir gausite **\(PointsReason.movedFast.points) tšk.**, per „grace period“ — **\(PointsReason.movedInGrace.points) tšk.**")
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
            Button("Baigti") { model.finishSession() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 16)
        }
    }

    private var leaveButton: some View {
        Button("Patraukiau automobilį") { model.leaveSpot() }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 16)
    }

    private func phasePill(_ phase: SessionSnapshot.Phase) -> some View {
        switch phase {
        case .charging: Pill(text: "Kraunasi", color: Theme.info)
        case .grace: Pill(text: "Baigta — patraukite automobilį", color: Theme.warn)
        case .idle: Pill(text: "Skaičiuojamas prastovos mokestis", color: Theme.bad)
        case .ended: Pill(text: "Užbaigta", color: Theme.ok)
        }
    }

    private func idleCard(_ snap: SessionSnapshot) -> some View {
        let rate = IdleFee.currentRate(minutes: snap.idleMinutes)
        return CardBox(stroke: Theme.bad) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stovite be reikalo \(Fmt.minutes(snap.idleMinutes))").font(.headline)
                Spacer()
                Text(String(format: "%.2f €/min.", rate)).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(Array(IdleFee.tiers.enumerated()), id: \.offset) { item in
                    let tier = item.element
                    let end = item.offset + 1 < IdleFee.tiers.count ? IdleFee.tiers[item.offset + 1].fromMin : nil
                    let active = rate == tier.eurPerMin
                    VStack(spacing: 2) {
                        Text(String(format: "%.2f €/min.", tier.eurPerMin)).font(.caption.weight(.semibold))
                        Text(end.map { "\(Int(tier.fromMin))–\(Int($0)) min." } ?? "\(Int(tier.fromMin))+ min.").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(active ? Color.white : Color.primary)
                    .background(active ? Theme.bad : Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.top, 12)
            Text("Maksimalus mokestis \(Fmt.eur(IdleFee.capEur)). Kiti vairuotojai laukia šios vietos.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func receipt(_ s: ChargingSession, _ snap: SessionSnapshot) -> some View {
        CardBox {
            Text("Kvitas").font(.headline).padding(.bottom, 8)
            row(String(format: "Įkrovimas (%.1f kWh × %.2f €)", snap.kwh, s.pricePerKwh), Fmt.eur(snap.energyCost))
            row("Prastovos mokestis", Fmt.eur(snap.idleFee))
            Divider().padding(.vertical, 6)
            row("Iš viso", Fmt.eur(snap.energyCost + snap.idleFee), bold: true)
            if let pts = s.pointsEarned, pts > 0 {
                row("Gauta taškų", "+\(pts)")
            }
        }
    }

    private func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(value)
        }
        .font(bold ? .subheadline.weight(.semibold) : .subheadline)
        .padding(.vertical, 2)
    }

    private var demoControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Demo: laiko pagreitis")
            HStack(spacing: 8) {
                ForEach(speeds, id: \.self) { s in
                    Chip(title: "\(Int(s))×", active: model.speed == s) { model.setSpeed(s) }
                }
            }
            Text("Pagreitinkite laiką, kad pamatytumėte pranešimą, „grace period“ ir didėjantį mokestį.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
