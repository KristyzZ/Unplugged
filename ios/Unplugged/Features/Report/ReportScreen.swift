import PhotosUI
import SwiftUI

/// Report form + reports for one station. Shown as a sheet from the station page.
struct ReportContent: View {
    let stationId: String

    @Environment(AppModel.self) private var model
    @State private var kind: ReportKind = .wrongUsage
    @State private var connectorId = ""
    @State private var plate = ""
    @State private var details = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @FocusState private var focused: Bool

    private var station: Station? { model.stations.first { $0.id == stationId } }

    private var canSubmit: Bool {
        guard station != nil else { return false }
        switch kind {
        case .wrongUsage: return !plate.trimmingCharacters(in: .whitespaces).isEmpty
        case .chargerProblem: return true
        case .other: return !details.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Report a problem at this station. Confirmed reports of wrong use help enforce warnings and fines.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                form
                SectionHeader(title: "Reports for this station")
                let reports = model.reports.filter { $0.stationId == stationId }
                if reports.isEmpty {
                    Text("No reports for this station yet.").font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(spacing: 8) {
                    ForEach(reports) { r in reportCard(r) }
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Report")
        .onChange(of: photoItem) { _, item in
            Task {
                let data = try? await item?.loadTransferable(type: Data.self)
                photo = data.flatMap { UIImage(data: $0) }
            }
        }
    }

    private var form: some View {
        CardBox {
            Text(station?.name ?? "").font(.headline).padding(.bottom, 10)

            Text("What's the problem?").font(.subheadline.weight(.medium))
            Picker("What's the problem?", selection: $kind) {
                ForEach(ReportKind.allCases) { k in Text(k.title).tag(k) }
            }
            .pickerStyle(.menu)
            .padding(.bottom, 6)

            if kind == .chargerProblem, let station {
                Text("Connector").font(.subheadline.weight(.medium))
                Picker("Connector", selection: $connectorId) {
                    Text("Whole station").tag("")
                    ForEach(station.connectors) { c in
                        Text("\(c.type.rawValue) · \(Int(c.powerKw)) kW").tag(c.id)
                    }
                }
                .pickerStyle(.menu)
                .padding(.bottom, 6)
            }

            if kind == .wrongUsage {
                Text("License plate").font(.subheadline.weight(.medium))
                TextField("ABC 123", text: $plate)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(10)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 10)
            }

            Text("What's happening?").font(.subheadline.weight(.medium))
            TextField(kind.placeholder, text: $details, axis: .vertical)
                .lineLimit(2...4)
                .focused($focused)
                .padding(10)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 10)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(photo == nil ? tr("Add photo") : tr("Change photo"), systemImage: "camera")
            }
            .buttonStyle(SecondaryButtonStyle())
            Text(kind.photoHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8)
            }

            Button("Report") {
                guard let station else { return }
                model.submitReport(station: station, kind: kind, connectorId: connectorId.isEmpty ? nil : connectorId, plate: plate, description: details, hasPhoto: photo != nil)
                plate = ""
                connectorId = ""
                details = ""
                photo = nil
                photoItem = nil
                focused = false
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
            .padding(.top, 14)
        }
    }

    private func reportCard(_ r: AbuseReport) -> some View {
        let stationName = model.stations.first { $0.id == r.stationId }?.name ?? r.stationId
        let offences = model.confirmedOffences(forPlate: r.plate)
        return CardBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.category == .wrongUsage ? r.plate : r.category.title).font(.headline)
                    Text(stationName + (r.byMe ? tr(" · your report") : "")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if r.category == .wrongUsage {
                    Pill(text: r.isConfirmed ? "Confirmed" : "Awaiting confirmation", color: r.isConfirmed ? Theme.ok : Theme.warn)
                } else {
                    Pill(text: "Sent to operator", color: Theme.info)
                }
            }
            if !r.description.isEmpty {
                Text(trKey(r.description)).font(.subheadline).padding(.top, 8)
            }
            HStack(spacing: 6) {
                Pill(text: tr("\(r.hasPhoto ? "✓" : "–") Photo"), color: r.hasPhoto ? Theme.ok : nil)
                Pill(text: tr("\(r.telemetryMatches ? "✓" : "–") Station data"), color: r.telemetryMatches ? Theme.ok : nil)
                Pill(text: tr("\(r.confirmations) confirmed"), color: r.confirmations > 0 ? Theme.ok : nil)
            }
            .padding(.top, 10)
            if r.category == .wrongUsage {
                HStack(spacing: 8) {
                    Text("Confidence").font(.caption).foregroundStyle(.secondary)
                    SocBar(value: r.confidence * 100, target: Reports.confirmThreshold * 100, height: 8)
                }
                .padding(.top, 10)
            }
            if r.category == .wrongUsage && r.isConfirmed {
                Text("Offence no. \(offences) for this plate · applied: \(Reports.sanction(forOffence: offences))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else if !r.byMe {
                Button(r.category == .wrongUsage ? "I see it too — confirm" : "Same here") { model.confirmReport(r.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 10)
            }
        }
    }
}
