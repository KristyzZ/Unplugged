import Foundation

extension AppModel {
    func submitReport(station: Station, kind: ReportKind, connectorId: String?, plate: String, description: String, hasPhoto: Bool) {
        // Station telemetry backs the report: a bay occupied without a session
        // (wrong use), or a connector the station already shows as out of service.
        let telemetry: Bool
        switch kind {
        case .wrongUsage:
            telemetry = station.connectors.contains { $0.status == .blocked }
        case .chargerProblem:
            let scope = station.connectors.filter { connectorId == nil || $0.id == connectorId }
            telemetry = scope.contains { $0.status == .offline }
        case .other:
            telemetry = false
        }
        let report = AbuseReport(
            stationId: station.id,
            plate: kind == .wrongUsage ? plate.uppercased() : "",
            description: description,
            hasPhoto: hasPhoto,
            telemetryMatches: telemetry,
            confirmations: 0,
            createdAt: .now,
            byMe: true,
            kind: kind,
            connectorId: kind == .chargerProblem ? connectorId : nil
        )
        reports.insert(report, at: 0)
        save()
        if kind != .wrongUsage {
            showBanner(tr("Report sent"), tr("Thanks — we'll pass it on to the operator."))
        } else if report.isConfirmed {
            addPoints(.reportConfirmed, note: station.name)
            showBanner(tr("Report confirmed"), tr("Station data confirmed the violation. +\(PointsReason.reportConfirmed.points) pts"))
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
