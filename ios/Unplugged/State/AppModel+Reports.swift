import Foundation

extension AppModel {
    func submitReport(station: Station, kind: ReportKind, connectorId: String?, plate: String, description: String,
                      hasPhoto: Bool, plateFromPhoto: Bool = false) {
        // The charger's own data backs the report, judged from its live state now:
        // wrong use → is that spot occupied without a session? (all spots when
        // the driver isn't sure); charger problem → does it show as out of service?
        let evidence: StationEvidence?
        let telemetry: Bool
        switch kind {
        case .wrongUsage:
            let spot = station.connectors.first { $0.id == connectorId }
            let found = spot.map { StationEvidence($0.status) } ?? StationEvidence(station: station)
            evidence = found
            telemetry = found == .occupiedNoSession
        case .chargerProblem:
            let scope = station.connectors.filter { connectorId == nil || $0.id == connectorId }
            evidence = nil
            telemetry = scope.contains { $0.status == .offline }
        case .other:
            evidence = nil
            telemetry = false
        }
        let report = AbuseReport(
            stationId: station.id,
            plate: kind == .wrongUsage ? Reports.formatPlate(plate) : "",
            description: description,
            hasPhoto: hasPhoto,
            telemetryMatches: telemetry,
            confirmations: 0,
            createdAt: .now,
            byMe: true,
            kind: kind,
            connectorId: kind == .other ? nil : connectorId,
            plateFromPhoto: kind == .wrongUsage ? plateFromPhoto : nil,
            evidence: evidence
        )
        reports.insert(report, at: 0)
        save()
        if kind != .wrongUsage {
            showBanner(tr("Report sent"), tr("Thanks — we'll pass it on to the operator."))
        } else if report.isConfirmed {
            addPoints(.reportConfirmed, note: station.name)
            let why = report.stationEvidence == .occupiedNoSession
                ? tr("The charger confirms the spot is blocked.")
                : tr("Photo, plate and charger data agree.")
            showBanner(tr("Report confirmed"), why + " " + tr("+\(PointsReason.reportConfirmed.points) pts"))
        } else {
            showBanner(tr("Report sent"), tr("Waiting for more confirmations."))
        }
    }

    func confirmReport(_ id: String) {
        guard let i = reports.firstIndex(where: { $0.id == id }) else { return }
        reports[i].confirmations += 1
        guard reports[i].category == .wrongUsage else {
            showBanner(tr("Thanks!"), tr("Your confirmation helps the operator prioritize."))
            return
        }
        let name = stations.first { $0.id == reports[i].stationId }?.name
        addPoints(.confirmReport, note: name)
        showBanner(tr("+\(PointsReason.confirmReport.points) pts"), tr("Thanks for helping to confirm."))
    }

    func confirmedOffences(forPlate plate: String) -> Int {
        let p = Reports.normalizePlate(plate)
        return reports.filter { Reports.normalizePlate($0.plate) == p && $0.isConfirmed }.count
    }

    // MARK: Reports persistence

    private struct ReportsState: Codable {
        var reports: [AbuseReport]
    }

    func saveReports(to snapshot: inout PersistenceSnapshot) throws {
        try snapshot.set(ReportsState(reports: reports), for: "reports")
    }

    func loadReports(from snapshot: PersistenceSnapshot) {
        guard let state: ReportsState = snapshot.value(for: "reports") else { return }
        reports = state.reports
    }
}
