import PhotosUI
import SwiftUI
import UIKit

/// Report form + reports for one station. Shown as a sheet from the station page.
///
/// For a car blocking a charger: take a photo, the phone reads the plate,
/// pick the spot, and the charger's own data is checked. The form says up
/// front whether that's enough to confirm the report straight away.
struct ReportContent: View {
    let stationId: String

    @Environment(AppModel.self) private var model
    @State private var kind: ReportKind = .wrongUsage
    /// "" = not sure (wrong use) or the whole station (charger problem).
    @State private var spotId = ""
    @State private var plate = ""
    @State private var details = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var reading: PlateReading?
    @State private var scanning = false
    @State private var showCamera = false
    @FocusState private var focused: Bool

    private var station: Station? { model.stations.first { $0.id == stationId } }

    /// The entered plate is the one read from the photo.
    private var plateFromPhoto: Bool {
        guard let reading else { return false }
        return Reports.normalizePlate(reading.plate) == Reports.normalizePlate(plate)
    }

    private var evidence: StationEvidence {
        guard let station else { return .unknown }
        if let spot = station.connectors.first(where: { $0.id == spotId }) { return StationEvidence(spot.effectiveStatus()) }
        return StationEvidence(station: station)
    }

    private var canSubmit: Bool {
        guard station != nil else { return false }
        switch kind {
        case .wrongUsage: return !plate.trimmingCharacters(in: .whitespaces).isEmpty
        case .chargerProblem: return true
        case .other: return !details.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Report a problem at this station. Confirmed reports of wrong use lead to warnings and fines.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                form
                if kind == .wrongUsage {
                    evidenceCard
                }
                Button("Send report", action: submit)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)
                reportList
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            Task {
                let data = try? await item?.loadTransferable(type: Data.self)
                if let image = data.flatMap(UIImage.init(data:)) { setPhoto(image) }
            }
        }
        .onChange(of: kind) { spotId = "" }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { setPhoto($0) }.ignoresSafeArea()
        }
    }

    // MARK: Form

    private var form: some View {
        CardBox {
            Text(station?.name ?? "").font(.headline).foregroundStyle(Theme.text)

            label("What's the problem?").padding(.top, 12)
            DropdownField(selection: $kind, options: ReportKind.allCases.map { ($0, $0.title) })
                .padding(.top, 6)

            if kind != .other, let station {
                label(kind == .wrongUsage ? "Which spot?" : "Connector").padding(.top, 14)
                spotPicker(station).padding(.top, 6)
            }

            label(kind == .wrongUsage ? "Photo of the car" : "Photo").padding(.top, 14)
            photoSection.padding(.top, 6)

            if kind == .wrongUsage {
                label("Licence plate").padding(.top, 14)
                HStack(spacing: 8) {
                    TextField("ABC 123", text: $plate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                    if plateFromPhoto {
                        Label("From photo", systemImage: "text.viewfinder")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ok)
                    }
                }
                .padding(12)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 6)
            }

            label(kind == .other ? "What's wrong?" : "Details (optional)").padding(.top, 14)
            TextField(kind.placeholder, text: $details, axis: .vertical)
                .lineLimit(2...4)
                .focused($focused)
                .padding(12)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 6)
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
    }

    /// "Not sure" plus every connector, with its live status colour.
    private func spotPicker(_ station: Station) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: kind == .wrongUsage ? tr("Not sure") : tr("Whole station"), active: spotId.isEmpty) { spotId = "" }
                ForEach(Array(station.connectors.enumerated()), id: \.element.id) { item in
                    let c = item.element
                    Button { spotId = c.id } label: {
                        HStack(spacing: 6) {
                            Circle().fill(c.status.color).frame(width: 8, height: 8)
                            Text("\(item.offset + 1) · \(c.type.label)")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glass(in: Capsule(), tint: spotId == c.id ? Theme.brand.opacity(0.55) : nil)
                        .minimumTouchTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Spot \(item.offset + 1), \(c.type.label), \(c.status.label)"))
                    .accessibilityAddTraits(spotId == c.id ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var photoSection: some View {
        if let photo {
            PlatePhoto(image: photo, reading: reading, scanning: scanning)
            Group {
                if scanning {
                    Label("Reading the plate…", systemImage: "text.viewfinder").foregroundStyle(Theme.muted)
                } else if let reading {
                    Label("Plate read on your phone: \(reading.plate)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                } else if kind == .wrongUsage {
                    Label("No plate found. Type it below, or take a closer photo.", systemImage: "questionmark.circle").foregroundStyle(Theme.warn)
                }
            }
            .font(.caption.weight(.medium))
            .padding(.top, 8)
        }
        HStack(spacing: 10) {
            if cameraAvailable {
                Button { showCamera = true } label: {
                    Label(photo == nil ? tr("Take photo") : tr("Retake"), systemImage: "camera.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(cameraAvailable ? tr("Choose") : (photo == nil ? tr("Add photo") : tr("Change photo")), systemImage: "photo.on.rectangle")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.top, photo == nil ? 0 : 10)
        if photo == nil {
            Text(kind.photoHint)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)
        }
    }

    private func setPhoto(_ image: UIImage) {
        let previous = reading?.plate
        photo = image
        reading = nil
        scanning = true
        Task {
            let found = await PlateReader.read(image)
            withMotion(.spring(duration: 0.45)) {
                reading = found
                scanning = false
            }
            // Fill the field unless the driver typed something else.
            if let found, plate.isEmpty || plate == previous {
                plate = found.plate
            }
        }
    }

    // MARK: Evidence

    /// What backs the report, and whether it will confirm when sent.
    private var evidenceCard: some View {
        let hasPhoto = photo != nil
        let needed = Reports.confirmationsNeeded(hasPhoto: hasPhoto, plateFromPhoto: plateFromPhoto, evidence: evidence)
        return VStack(alignment: .leading, spacing: 8) {
            Text("What backs your report").font(.headline).foregroundStyle(Theme.text)
            ListCard {
                EvidenceRow(state: hasPhoto ? .yes : .no, title: "Photo",
                            detail: hasPhoto ? tr("Added") : tr("Not added"))
                RowDivider()
                EvidenceRow(state: plateFromPhoto ? .yes : .no, title: "Plate read from photo",
                            detail: plateFromPhoto ? (reading?.plate ?? "") : (reading == nil ? tr("No") : tr("Doesn't match the plate entered")))
                RowDivider()
                EvidenceRow(state: evidence.supports ? .yes : (evidence.contradicts ? .against : .no), title: "Charger data",
                            detail: evidence.detail)
                RowDivider()
                verdict(needed)
            }
        }
        .animation(Motion.pick(.easeInOut(duration: 0.25)), value: needed)
    }

    private func verdict(_ needed: Int?) -> some View {
        let (text, color, icon): (String, Color, String) = switch needed {
        case 0?: (tr("Confirmed as soon as you send it"), Theme.ok, "checkmark.seal.fill")
        case let n?: (n == 1 ? tr("Needs 1 more driver to confirm") : tr("Needs \(n) more drivers to confirm"), Theme.warn, "person.2.fill")
        case nil: (tr("The charger shows a car charging there. Check the spot number."), Theme.bad, "exclamationmark.triangle.fill")
        }
        return HStack(spacing: 12) {
            IconBadge(systemImage: icon, color: color)
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Submit

    private func submit() {
        guard let station else { return }
        model.submitReport(
            station: station, kind: kind, connectorId: spotId.isEmpty ? nil : spotId, plate: plate,
            description: details, hasPhoto: photo != nil, plateFromPhoto: plateFromPhoto
        )
        plate = ""
        spotId = ""
        details = ""
        photo = nil
        photoItem = nil
        reading = nil
        focused = false
    }

    // MARK: Reports at this station

    @ViewBuilder
    private var reportList: some View {
        let reports = model.reports.filter { $0.stationId == stationId }
        Text("Reports for this station").font(.headline).foregroundStyle(Theme.text).padding(.top, 8)
        if reports.isEmpty {
            Text("No reports for this station yet.").font(.subheadline).foregroundStyle(Theme.muted)
        }
        ForEach(reports) { r in reportCard(r) }
    }

    private func reportCard(_ r: AbuseReport) -> some View {
        let stationName = model.stations.first { $0.id == r.stationId }?.name ?? r.stationId
        let offences = model.confirmedOffences(forPlate: r.plate)
        return CardBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.category == .wrongUsage ? r.plate : r.category.title).font(.headline)
                    Text(stationName + (r.byMe ? tr(" · your report") : "")).font(.caption).foregroundStyle(Theme.muted)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Pill(text: tr("\(r.hasPhoto ? "✓" : "–") Photo"), color: r.hasPhoto ? Theme.ok : nil)
                    if r.category == .wrongUsage {
                        let read = r.plateFromPhoto ?? false
                        Pill(text: tr("\(read ? "✓" : "–") Plate read"), color: read ? Theme.ok : nil)
                        let e = r.stationEvidence
                        Pill(text: tr("\(e.supports ? "✓" : (e.contradicts ? "✗" : "–")) Charger data"),
                             color: e.supports ? Theme.ok : (e.contradicts ? Theme.bad : nil))
                    } else {
                        Pill(text: tr("\(r.telemetryMatches ? "✓" : "–") Station data"), color: r.telemetryMatches ? Theme.ok : nil)
                    }
                    Pill(text: tr("\(r.confirmations) confirmed"), color: r.confirmations > 0 ? Theme.ok : nil)
                }
            }
            .padding(.top, 10)
            if r.category == .wrongUsage {
                HStack(spacing: 8) {
                    Text("Confidence").font(.caption).foregroundStyle(Theme.muted)
                    SocBar(value: r.confidence * 100, target: Reports.confirmThreshold * 100, height: 8)
                }
                .padding(.top, 10)
            }
            if r.category == .wrongUsage && r.isConfirmed {
                Text("Offence no. \(offences) for this plate · applied: \(Reports.sanction(forOffence: offences))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 8)
            } else if !r.byMe {
                Button(r.category == .wrongUsage ? "I see it too — confirm" : "Same here") { model.confirmReport(r.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 10)
            }
        }
    }
}

// MARK: - Pieces

/// The photo, a scan line while it's being read, then a box around the plate.
private struct PlatePhoto: View {
    let image: UIImage
    let reading: PlateReading?
    let scanning: Bool

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    if scanning && !Motion.reduced {
                        ScanLine().frame(width: geo.size.width, height: geo.size.height)
                    }
                    if let reading {
                        let r = reading.box
                        let box = CGRect(x: r.minX * geo.size.width, y: r.minY * geo.size.height,
                                         width: r.width * geo.size.width, height: r.height * geo.size.height)
                            .insetBy(dx: -6, dy: -6)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Theme.ok, lineWidth: 3)
                            .frame(width: box.width, height: box.height)
                            .position(x: box.midX, y: box.midY)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                            .transition(.scale(scale: 1.3).combined(with: .opacity))
                        Text(reading.plate)
                            .font(.caption.weight(.bold))
                            .monospaced()
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.ok, in: Capsule())
                            .position(x: box.midX, y: max(12, box.minY - 14))
                            .transition(.opacity)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: 260)
            .accessibilityLabel(Text(reading.map { tr("Photo, plate \($0.plate)") } ?? tr("Photo")))
    }
}

/// A soft band sweeping down the photo while the plate is being read.
private struct ScanLine: View {
    @State private var down = false

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, Theme.brand.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 50)
                .offset(y: down ? geo.size.height - 25 : -25)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: down)
                .onAppear { down = true }
        }
        .allowsHitTesting(false)
    }
}

private struct EvidenceRow: View {
    enum Mark { case yes, no, against }

    let state: Mark
    let title: LocalizedStringKey
    let detail: String

    var body: some View {
        let (icon, color): (String, Color) = switch state {
        case .yes: ("checkmark", Theme.ok)
        case .no: ("minus", Theme.muted)
        case .against: ("xmark", Theme.bad)
        }
        HStack(spacing: 12) {
            IconBadge(systemImage: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// The system camera (a blocking car in reports, a charger in host listings).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
