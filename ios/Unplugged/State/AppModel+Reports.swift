import Foundation

extension AppModel {
    func submitReport(station: Station, kind: ReportKind, connectorId: String?, plate: String,
                      description: String, hasPhoto: Bool) {
        let telemetry: Bool
        switch kind {
        case .wrongUsage: telemetry = station.connectors.contains { $0.effectiveStatus() == .blocked }
        case .chargerProblem:
            telemetry = station.connectors.filter { connectorId == nil || $0.id == connectorId }
                .contains { $0.effectiveStatus() == .offline }
        case .other: telemetry = false
        }
        let report = AbuseReport(stationId: station.id, plate: kind == .wrongUsage ? plate.uppercased() : "",
                                 description: description, hasPhoto: hasPhoto, telemetryMatches: telemetry,
                                 confirmations: 0, createdAt: .now, byMe: true, kind: kind,
                                 connectorId: kind == .chargerProblem ? connectorId : nil,
                                 reviewState: .submitted, confirmedByMe: false, reportRewardGranted: false)
        reports.insert(report, at: 0)
        save()
        showBanner(tr("Report saved locally"), tr("Demo only. It has not been sent to an operator."))
    }

    func confirmReport(_ id: String) {
        guard let i = reports.firstIndex(where: { $0.id == id }), reports[i].canConfirm else { return }
        reports[i].confirmedByMe = true
        reports[i].confirmations += 1
        reports[i].reviewState = .pendingReview
        let name = stations.first { $0.id == reports[i].stationId }?.name
        if reports[i].category == .wrongUsage {
            // The persisted local-confirmation flag and points are in the same
            // atomic feature snapshot. Repeated taps/reload cannot farm rewards.
            addPoints(.confirmReport, note: name)
            showBanner(tr("+\(PointsReason.confirmReport.points) pts"), tr("Thanks for helping to confirm."))
        } else {
            save() // Every category persists confirmation state.
            showBanner(tr("Confirmation saved"), tr("This is a local demo confirmation."))
        }
    }

    func queueReportForReview(_ id: String) {
        guard let i = reports.firstIndex(where: { $0.id == id }), reports[i].reviewStatus == .submitted else { return }
        reports[i].reviewState = .pendingReview
        save()
    }

    /// Explicit simulation controls; confidence never automatically becomes moderation.
    func reviewReport(_ id: String, accepted: Bool) {
        guard let i = reports.firstIndex(where: { $0.id == id }), !reports[i].reviewStatus.isReviewed else { return }
        reports[i].reviewState = accepted ? .reviewedAccepted : .reviewedRejected
        reports[i].reviewedAt = .now
        if accepted, reports[i].category == .wrongUsage, reports[i].byMe, reports[i].reportRewardGranted != true {
            reports[i].reportRewardGranted = true
            let name = stations.first { $0.id == reports[i].stationId }?.name
            addPoints(.reportConfirmed, note: name)
        } else { save() }
        showBanner(tr("Demo review recorded"), tr("No real fine or account restriction has been applied."))
    }

    func confirmedOffences(forPlate plate: String) -> Int {
        let p = Reports.normalizePlate(plate)
        guard !p.isEmpty else { return 0 }
        return reports.filter { $0.category == .wrongUsage && Reports.normalizePlate($0.plate) == p && $0.isConfirmed }.count
    }

    private struct ReportsState: Codable { var reports: [AbuseReport] }

    func saveReports(to snapshot: inout PersistenceSnapshot) throws {
        try snapshot.set(ReportsState(reports: reports), for: "reports")
    }

    func loadReports(from snapshot: PersistenceSnapshot) {
        guard let state: ReportsState = snapshot.value(for: "reports") else { return }
        reports = state.reports.map {
            var report = $0
            if report.reviewState == nil {
                // Old submissions could already award a high-confidence report.
                // Preserve that fact without inventing an actual reviewed outcome.
                if report.reportRewardGranted == nil {
                    report.reportRewardGranted = report.byMe && report.category == .wrongUsage
                        && report.confidence >= Reports.confirmThreshold
                }
            }
            return report
        }
    }
}
