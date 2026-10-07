import SwiftUI

struct StationDetailView: View {
    let stationId: String

    @Environment(AppModel.self) private var model
    @State private var pickedConnectorId: String?
    @State private var target: Double = 80
    @State private var showReport = false

    var body: some View {
        Group {
            if let station = model.stations.first(where: { $0.id == stationId }) {
                content(station)
            } else {
                ContentUnavailableView("Stotelė nerasta", systemImage: "bolt.slash")
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ station: Station) -> some View {
        let vehicle = model.vehicle
        let op = DemoData.chargeOperator(station.operatorId)
        let hour = Calendar.current.component(.hour, from: .now)
        let demand = station.demandLevel(hour: hour)
        let grace = IdleFee.graceMinutes(demand: demand)
        let best = station.bestHour(from: hour)
        let busy = model.hasActiveSession
        let picked = station.connectors.first { $0.id == pickedConnectorId }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name).font(.largeTitle.bold())
                    HStack(spacing: 6) {
                        Circle().fill(op.color).frame(width: 8, height: 8)
                        Text("\(op.name) · \(station.address), \(station.city)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 16)

                statusCard(station)

                if station.freeCount == 0 {
                    queueCard(station).padding(.top, 12)
                }

                SectionHeader(title: "Jungtys")
                VStack(spacing: 8) {
                    ForEach(station.connectors) { c in
                        connectorRow(c, vehicle: vehicle, selectable: !busy)
                    }
                }

                if let picked, !busy {
                    chargeCard(station, connector: picked, vehicle: vehicle, grace: grace, demand: demand)
                        .padding(.top, 12)
                }
                if busy {
                    Text("Jau turite aktyvų įkrovimą — žr. skirtuką „Įkrovimas“.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                SectionHeader(title: "Užimtumas pagal valandas")
                CardBox {
                    OccupancyChart(values: station.hourlyOccupancy, currentHour: hour, highlight: best != hour ? best : nil)
                    Divider().padding(.vertical, 12)
                    HStack(alignment: .top) {
                        StatView(label: "Įprastai šiuo metu laisva vieta", value: Fmt.pct(station.probabilityFree(atHour: hour)))
                        StatView(
                            label: "Geriausias laikas per 6 val.",
                            value: Fmt.hour(best),
                            sub: "tikimybė \(Fmt.pct(station.probabilityFree(atHour: best)))"
                        )
                    }
                }

                if !station.amenities.isEmpty {
                    SectionHeader(title: "Šalia")
                    HStack {
                        ForEach(station.amenities, id: \.self) { Pill(text: $0) }
                    }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showReport) {
            NavigationStack {
                ReportContent(initialStationId: station.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Uždaryti") { showReport = false }
                        }
                    }
            }
        }
    }

    private func statusCard(_ station: Station) -> some View {
        CardBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Pill(text: station.availability.label, color: station.availability.color)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(station.freeCount)").font(.system(size: 34, weight: .bold))
                        Text("/\(station.workingCount) laisvos").font(.headline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(String(format: "%.2f €", station.pricePerKwh)).font(.title2.bold())
                    Text("už kWh").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider().padding(.vertical, 12)
            HStack(alignment: .top) {
                StatView(label: "Kraunasi", value: "\(station.count(.charging))")
                StatView(label: "Baigė, stovi", value: "\(station.count(.idle))")
                StatView(label: "Užimta be įkrovimo", value: "\(station.count(.blocked))")
            }
            HStack(spacing: 8) {
                if let url = URL(string: "http://maps.apple.com/?daddr=\(station.lat),\(station.lng)") {
                    Link(destination: url) { Label("Maršrutas", systemImage: "arrow.triangle.turn.up.right.diamond") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button { showReport = true } label: { Label("Pranešti", systemImage: "exclamationmark.triangle") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 14)
        }
    }

    private func queueCard(_ station: Station) -> some View {
        let soonest = station.connectors.compactMap(\.etaMinutes).min() ?? 60
        let inQueue = model.queue?.stationId == station.id
        return CardBox(stroke: Theme.warn) {
            Text("Visos vietos užimtos").font(.headline)
            Text("Prisijunkite prie virtualios eilės — pranešime, kai atsilaisvins vieta. Artimiausia laisva vieta tikėtina per \(Fmt.minutes(Double(soonest)))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            if inQueue {
                HStack {
                    Text("Esate eilėje: **\(model.queue?.position ?? 1) vieta**").font(.subheadline)
                    Spacer()
                    Button("Palikti eilę") { model.leaveQueue() }
                }
                .padding(.top, 12)
            } else {
                Button("Stoti į eilę") { model.joinQueue(station) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 12)
            }
        }
    }

    private func connectorRow(_ c: Connector, vehicle: Vehicle, selectable: Bool) -> some View {
        let compatible = Charging.isCompatible(vehicle, c)
        let enabled = selectable && compatible && c.status == .available
        let selected = pickedConnectorId == c.id
        return Button {
            pickedConnectorId = c.id
            target = max(target, min(100, model.soc + 5))
        } label: {
            HStack(spacing: 12) {
                Circle().fill(c.status.color).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(c.type.rawValue) · \(Int(c.powerKw)) kW").font(.body.weight(.medium))
                    Text(detail(c, compatible: compatible)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if compatible {
                    Text("iki \(Int(Charging.effectivePeakKw(vehicle, c))) kW").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.brand : .clear, lineWidth: 2)
            )
            .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func detail(_ c: Connector, compatible: Bool) -> String {
        var text = c.status.label
        if c.status == .charging, let eta = c.etaMinutes {
            text += " · atsilaisvins ~\(Fmt.clock(Date().addingTimeInterval(Double(eta) * 60)))"
        }
        if c.status == .idle, let idle = c.idleMinutes {
            text += " · stovi jau \(idle) min."
        }
        if !compatible { text += " · netinka jūsų automobiliui" }
        return text
    }

    private func chargeCard(_ station: Station, connector: Connector, vehicle: Vehicle, grace: Int, demand: Double) -> some View {
        let estimate = Charging.chargeTime(vehicle, connector, from: model.soc, to: target)
        let minTarget = min(100, model.soc + 5)
        let tiersText = IdleFee.tiers.map { String(format: "%.2f €", $0.eurPerMin) }.joined(separator: " → ")
        let finishText = Fmt.clock(Date().addingTimeInterval(Double(estimate.minutes) * 60))
        return CardBox {
            Text("Įkrovimas: \(vehicle.name)").font(.headline)
            HStack {
                Text("Dabar \(Int(model.soc)) %")
                Spacer()
                Text("Iki \(Int(target)) %")
            }
            .font(.subheadline)
            .padding(.top, 10)
            SocBar(value: model.soc, target: target).padding(.top, 4)
            if minTarget < 100 {
                Slider(value: $target, in: minTarget...100, step: 1).padding(.top, 6)
            }
            HStack(alignment: .top) {
                StatView(label: "Trukmė", value: Fmt.minutes(Double(estimate.minutes)), sub: "baigsis ~\(finishText)")
                StatView(label: "Energija", value: String(format: "%.1f kWh", estimate.kwh))
                StatView(label: "Kaina", value: Fmt.eur(estimate.kwh * station.pricePerKwh))
            }
            .padding(.top, 10)
            Text("Baigus įkrovimą turėsite **\(grace) min.** patraukti automobilį (dabartinė paklausa \(Fmt.pct(demand))). Vėliau prastovos mokestis didėja: \(tiersText) per min. Patraukę laiku gausite taškų.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 12)
            Button("Pradėti ir mokėti per Unplugged") {
                model.startCharging(at: station, connector: connector, targetSoc: target)
                pickedConnectorId = nil
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 12)
        }
    }
}
