import PhotosUI
import SwiftUI

struct ReportScreen: View {
    var body: some View {
        NavigationStack {
            ReportContent()
        }
    }
}

/// Report form + list of reports. Also shown as a sheet from a station page.
struct ReportContent: View {
    var initialStationId: String? = nil

    @Environment(AppModel.self) private var model
    @State private var stationId = ""
    @State private var plate = ""
    @State private var details = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @FocusState private var focused: Bool

    private var station: Station? { model.stations.first { $0.id == stationId } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Įkrovimo vietą užima nesikraunantis ar ne elektrinis automobilis? Praneškite — patvirtinti pranešimai padeda taikyti įspėjimus ir baudas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                form
                SectionHeader(title: "Pranešimai šalia jūsų")
                VStack(spacing: 8) {
                    ForEach(model.reports) { r in reportCard(r) }
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Pranešti")
        .onAppear {
            if stationId.isEmpty, let initialStationId { stationId = initialStationId }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                let data = try? await item?.loadTransferable(type: Data.self)
                photo = data.flatMap { UIImage(data: $0) }
            }
        }
    }

    private var form: some View {
        CardBox {
            Text("Stotelė").font(.subheadline.weight(.medium))
            Picker("Stotelė", selection: $stationId) {
                Text("Pasirinkite…").tag("")
                ForEach(model.stations) { s in Text("\(s.name) (\(s.city))").tag(s.id) }
            }
            .pickerStyle(.menu)
            .padding(.bottom, 10)

            Text("Automobilio numeris").font(.subheadline.weight(.medium))
            TextField("ABC 123", text: $plate)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(10)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 10)

            Text("Kas vyksta?").font(.subheadline.weight(.medium))
            TextField("Pvz., benzininis automobilis stovi įkrovimo vietoje", text: $details, axis: .vertical)
                .lineLimit(2...4)
                .focused($focused)
                .padding(10)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 10)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(photo == nil ? "Pridėti nuotrauką" : "Pakeisti nuotrauką", systemImage: "camera")
            }
            .buttonStyle(SecondaryButtonStyle())
            Text("Nuotrauka su matomu numeriu labai padidina patikimumą.")
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

            Button("Pranešti") {
                guard let station else { return }
                model.submitReport(station: station, plate: plate, description: details, hasPhoto: photo != nil)
                plate = ""
                details = ""
                photo = nil
                photoItem = nil
                focused = false
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(station == nil || plate.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(station == nil || plate.isEmpty ? 0.5 : 1)
            .padding(.top, 14)
        }
    }

    private func reportCard(_ r: AbuseReport) -> some View {
        let stationName = model.stations.first { $0.id == r.stationId }?.name ?? r.stationId
        let offences = model.confirmedOffences(forPlate: r.plate)
        return CardBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.plate).font(.headline)
                    Text(stationName + (r.byMe ? " · jūsų pranešimas" : "")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Pill(text: r.isConfirmed ? "Patvirtinta" : "Laukia patvirtinimo", color: r.isConfirmed ? Theme.ok : Theme.warn)
            }
            if !r.description.isEmpty {
                Text(r.description).font(.subheadline).padding(.top, 8)
            }
            HStack(spacing: 6) {
                Pill(text: "\(r.hasPhoto ? "✓" : "–") Nuotrauka", color: r.hasPhoto ? Theme.ok : nil)
                Pill(text: "\(r.telemetryMatches ? "✓" : "–") Stotelės duomenys", color: r.telemetryMatches ? Theme.ok : nil)
                Pill(text: "\(r.confirmations) patvirt.", color: r.confirmations > 0 ? Theme.ok : nil)
            }
            .padding(.top, 10)
            HStack(spacing: 8) {
                Text("Patikimumas").font(.caption).foregroundStyle(.secondary)
                SocBar(value: r.confidence * 100, target: Reports.confirmThreshold * 100, height: 8)
            }
            .padding(.top, 10)
            if r.isConfirmed {
                Text("Pažeidimas nr. \(offences) šiam numeriui · taikoma: \(Reports.sanction(forOffence: offences))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else if !r.byMe {
                Button("Matau tą patį — patvirtinti") { model.confirmReport(r.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 10)
            }
        }
    }
}
