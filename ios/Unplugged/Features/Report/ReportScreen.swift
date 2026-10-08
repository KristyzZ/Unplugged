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
                Text("Is a car that isn't charging, or isn't electric, blocking a charging spot? Report it — confirmed reports help enforce warnings and fines.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                form
                SectionHeader(title: "Reports near you")
                VStack(spacing: 8) {
                    ForEach(model.reports) { r in reportCard(r) }
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Report")
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
            Text("Station").font(.subheadline.weight(.medium))
            Picker("Station", selection: $stationId) {
                Text("Select…").tag("")
                ForEach(model.stations) { s in Text("\(s.name) (\(s.city))").tag(s.id) }
            }
            .pickerStyle(.menu)
            .padding(.bottom, 10)

            Text("License plate").font(.subheadline.weight(.medium))
            TextField("ABC 123", text: $plate)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(10)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 10)

            Text("What's happening?").font(.subheadline.weight(.medium))
            TextField("E.g., a petrol car is parked in the charging spot", text: $details, axis: .vertical)
                .lineLimit(2...4)
                .focused($focused)
                .padding(10)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 10)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(photo == nil ? tr("Add photo") : tr("Change photo"), systemImage: "camera")
            }
            .buttonStyle(SecondaryButtonStyle())
            Text("A photo with a visible plate greatly increases credibility.")
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
                    Text(stationName + (r.byMe ? tr(" · your report") : "")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Pill(text: r.isConfirmed ? "Confirmed" : "Awaiting confirmation", color: r.isConfirmed ? Theme.ok : Theme.warn)
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
            HStack(spacing: 8) {
                Text("Confidence").font(.caption).foregroundStyle(.secondary)
                SocBar(value: r.confidence * 100, target: Reports.confirmThreshold * 100, height: 8)
            }
            .padding(.top, 10)
            if r.isConfirmed {
                Text("Offence no. \(offences) for this plate · applied: \(Reports.sanction(forOffence: offences))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else if !r.byMe {
                Button("I see it too — confirm") { model.confirmReport(r.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 10)
            }
        }
    }
}
