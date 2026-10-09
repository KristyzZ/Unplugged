import CarPlay
import MapKit
import SwiftUI
import UIKit

/// Unplugged on the car's screen, built from the templates Apple allows for
/// EV charging apps:
///   • Nearby — a map of the closest chargers that fit your car, with free
///     spots, power and price; Navigate, or join the queue when it's full.
///   • Charging — the session (battery, time left, free time, cost) with the
///     one action that matters now; or the spot held for you in the queue.
/// Everything comes from the same AppModel the phone uses.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private weak var scene: CPTemplateApplicationScene?
    private var timer: Timer?
    private var nearby: CPPointOfInterestTemplate?
    private var status: CPInformationTemplate?
    private var nearbySignature = ""

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        scene = templateApplicationScene
        MainActor.assumeIsolated {
            let nearby = CPPointOfInterestTemplate(title: tr("Nearby"), pointsOfInterest: [], selectedIndex: NSNotFound)
            nearby.tabTitle = tr("Nearby")
            nearby.tabImage = UIImage(systemName: "mappin.and.ellipse")
            let status = CPInformationTemplate(title: tr("Charging"), layout: .twoColumn, items: [], actions: [])
            status.tabTitle = tr("Charging")
            status.tabImage = UIImage(systemName: "bolt.fill")
            self.nearby = nearby
            self.status = status
            interfaceController.setRootTemplate(CPTabBarTemplate(templates: [nearby, status]), animated: false, completion: nil)
            refresh()
        }
        // Countdowns and availability change while you drive.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        timer?.invalidate()
        timer = nil
        self.interfaceController = nil
        nearby = nil
        status = nil
    }

    // MARK: Refresh

    @MainActor private func refresh() {
        let model = AppModel.shared
        refreshNearby(model)
        refreshStatus(model)
    }

    @MainActor private func refreshNearby(_ model: AppModel) {
        let vehicle = model.vehicle
        let stations = model.stations
            .filter { s in s.connectors.contains { Charging.isCompatible(vehicle, $0) && $0.status != .offline } }
            .map { ($0, Geo.haversineKm(model.origin, $0.latLng)) }
            .sorted { $0.1 < $1.1 }
            .prefix(12) // the template's limit
        // Rebuilding the map resets what the driver selected; only do it on a change.
        let signature = stations.map { "\($0.0.id):\($0.0.freeCount)" }.joined(separator: ",")
        guard signature != nearbySignature, let nearby else { return }
        nearbySignature = signature

        let pois = stations.map { station, km in
            let item = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
            item.name = station.name
            let free = station.freeCount > 0
                ? tr("\(station.freeCount)/\(station.workingCount) free")
                : tr("All taken")
            let poi = CPPointOfInterest(
                location: item,
                title: station.name,
                subtitle: "\(free) · \(Int(station.maxPower)) kW",
                summary: "\(Fmt.km(km)) · \(Fmt.price(station.pricePerKwh))",
                detailTitle: station.name,
                detailSubtitle: station.address,
                detailSummary: "\(free) · \(Int(station.maxPower)) kW · \(Fmt.price(station.pricePerKwh))",
                pinImage: pin(station.availability.color)
            )
            poi.primaryButton = CPTextButton(title: tr("Navigate"), textStyle: .confirm) { [weak self] _ in
                self?.navigate(to: station.coordinate)
            }
            if station.freeCount == 0 {
                poi.secondaryButton = CPTextButton(title: tr("Join queue"), textStyle: .normal) { [weak self] _ in
                    MainActor.assumeIsolated {
                        AppModel.shared.joinQueue(station)
                        self?.refresh()
                    }
                }
            }
            return poi
        }
        nearby.setPointsOfInterest(pois, selectedIndex: NSNotFound)
    }

    @MainActor private func refreshStatus(_ model: AppModel) {
        guard let status else { return }
        var items: [CPInformationItem] = []
        var actions: [CPTextButton] = []

        if let s = model.session {
            let snap = SessionSnapshot(s, now: model.simNow())
            items.append(CPInformationItem(title: tr("Station"), detail: s.stationName))
            items.append(CPInformationItem(title: tr("Battery"), detail: "\(Int(snap.soc.rounded())) %"))
            switch snap.phase {
            case .charging:
                items.append(CPInformationItem(title: tr("Time left"), detail: Fmt.minutes(snap.minutesLeft)))
                items.append(CPInformationItem(title: tr("So far"), detail: Fmt.eur(snap.energyCost)))
                actions.append(button(tr("Stop charging"), style: .cancel) { $0.stopCharging() })
            case .grace:
                items.append(CPInformationItem(title: tr("Free time left"), detail: Fmt.mmss(snap.graceLeft)))
                items.append(CPInformationItem(title: tr("Charging"), detail: Fmt.eur(snap.energyCost)))
                actions.append(button(tr("I moved my car"), style: .confirm) { $0.leaveSpot() })
            case .idle:
                items.append(CPInformationItem(title: tr("Idle fee"), detail: Fmt.eur(snap.idleFee)))
                items.append(CPInformationItem(title: tr("Charging"), detail: Fmt.eur(snap.energyCost)))
                actions.append(button(tr("I moved my car"), style: .confirm) { $0.leaveSpot() })
            case .ended:
                items.append(CPInformationItem(title: tr("Total"), detail: Fmt.eur(snap.energyCost + snap.idleFee)))
                if let points = s.pointsEarned, points > 0 {
                    items.append(CPInformationItem(title: tr("Points"), detail: "+\(points)"))
                }
                actions.append(button(tr("Done"), style: .normal) { $0.finishSession() })
            }
        } else if let hold = model.myHold {
            let left = max(0, hold.until.timeIntervalSince(model.simNow()))
            items.append(CPInformationItem(title: tr("Spot held for you"), detail: hold.stationName))
            items.append(CPInformationItem(title: tr("Time left"), detail: Fmt.mmss(left)))
            items.append(CPInformationItem(title: tr("Connector"), detail: hold.connectorLabel))
            if let station = model.stations.first(where: { $0.id == hold.stationId }) {
                actions.append(CPTextButton(title: tr("Navigate"), textStyle: .confirm) { [weak self] _ in
                    self?.navigate(to: station.coordinate)
                })
            }
            actions.append(button(tr("Release spot"), style: .cancel) { $0.releaseHold() })
        } else if let queue = model.queue, let station = model.stations.first(where: { $0.id == queue.stationId }) {
            items.append(CPInformationItem(title: tr("In the queue"), detail: station.name))
            items.append(CPInformationItem(title: tr("Place in line"), detail: "\(queue.position)"))
            actions.append(button(tr("Leave queue"), style: .cancel) { $0.leaveQueue() })
        } else {
            items.append(CPInformationItem(title: tr("You're not charging"), detail: tr("Pick a charger in Nearby.")))
        }
        status.items = items
        status.actions = actions
    }

    // MARK: Helpers

    @MainActor private func button(_ title: String, style: CPTextButtonStyle, _ action: @escaping @MainActor (AppModel) -> Void) -> CPTextButton {
        CPTextButton(title: title, textStyle: style) { [weak self] _ in
            MainActor.assumeIsolated {
                action(AppModel.shared)
                self?.refresh()
            }
        }
    }

    private func navigate(to coordinate: CLLocationCoordinate2D) {
        guard let url = URL(string: "maps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=d") else { return }
        scene?.open(url, options: nil, completionHandler: nil)
    }

    private func pin(_ color: Color) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        let image = UIImage(systemName: "bolt.circle.fill", withConfiguration: config) ?? UIImage()
        return image.withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
    }
}
