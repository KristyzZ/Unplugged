import Foundation

// Trip planner: given a car, its battery level and a destination, decide where
// to stop, how long to charge and what battery level to expect. Prefers
// stations that are fast and historically less busy at the expected arrival time.

struct TripStop: Identifiable {
    var id: String { station.id }
    let station: Station
    let connector: Connector
    let distanceFromPrevKm: Int
    let arriveAt: Date
    let arriveSoc: Int
    let departSoc: Int
    let chargeMinutes: Int
    let energyKwh: Double
    let costEur: Double
    /// nil when the station has no busy-hour history: shown as nothing, never as "0 %".
    let freeProbability: Double?
}

struct TripPlan {
    let feasible: Bool
    let message: String?
    let totalKm: Int
    let driveMinutes: Int
    let chargeMinutes: Int
    let arriveAt: Date
    let arriveSoc: Int
    let costEur: Double
    let stops: [TripStop]
}

struct TripInput {
    var vehicle: Vehicle
    var startSoc: Double
    var origin: LatLng
    var destination: LatLng
    var stations: [Station]
    var departure: Date
    /// Never plan to arrive anywhere below this (%).
    var reserveSoc: Double = 10
    /// Stop charging at this level unless more is needed (%).
    var maxChargeSoc: Double = 80
    var avgSpeedKmh: Double = 85
}

enum TripPlanner {
    static let maxDetourKm = 20.0
    static let maxStops = 6

    static func plan(_ input: TripInput) -> TripPlan {
        let first = planOnce(input)
        // Small batteries / sparse corridors: allow charging to 100 % before giving up.
        if !first.feasible && input.maxChargeSoc < 100 {
            var full = input
            full.maxChargeSoc = 100
            let second = planOnce(full)
            if second.feasible { return second }
        }
        return first
    }

    private static func bestConnector(_ vehicle: Vehicle, _ station: Station) -> Connector? {
        station.connectors
            .filter { Charging.isCompatible(vehicle, $0) && $0.status != .offline }
            .max { Charging.effectivePeakKw(vehicle, $0) < Charging.effectivePeakKw(vehicle, $1) }
    }

    private struct Candidate {
        let station: Station
        let connector: Connector
        let t: Double
        let detourKm: Double
    }

    private static func planOnce(_ input: TripInput) -> TripPlan {
        let v = input.vehicle
        let socPerKm = (v.consumptionKwhPer100 / 100) / v.batteryKwh * 100
        let totalKm = Geo.roadKm(input.origin, input.destination)

        // Stations near the corridor, ordered by progress along it.
        let candidates: [Candidate] = input.stations.compactMap { (s: Station) -> Candidate? in
            guard let conn = bestConnector(v, s) else { return nil }
            let pos = Geo.positionAlong(input.origin, input.destination, s.latLng)
            guard pos.detourKm <= maxDetourKm, pos.t > 0.02, pos.t < 0.98 else { return nil }
            return Candidate(station: s, connector: conn, t: pos.t, detourKm: pos.detourKm)
        }
        .sorted { $0.t < $1.t }

        var stops: [TripStop] = []
        var pos = input.origin
        var progress = 0.0
        var soc = input.startSoc
        var clock = input.departure
        var driveMin = 0.0

        func summary(_ feasible: Bool, _ arriveSoc: Double, _ message: String? = nil) -> TripPlan {
            TripPlan(
                feasible: feasible,
                message: message,
                totalKm: Int(totalKm.rounded()),
                driveMinutes: Int(driveMin.rounded()),
                chargeMinutes: stops.reduce(0) { $0 + $1.chargeMinutes },
                arriveAt: clock,
                arriveSoc: Int(arriveSoc.rounded()),
                costEur: (stops.reduce(0) { $0 + $1.costEur } * 100).rounded() / 100,
                stops: stops
            )
        }

        for i in 0...maxStops {
            let kmToDest = Geo.roadKm(pos, input.destination)
            let socAtDest = soc - kmToDest * socPerKm
            if socAtDest >= input.reserveSoc {
                let minutes = kmToDest / input.avgSpeedKmh * 60
                driveMin += minutes
                clock = clock.addingTimeInterval(minutes * 60)
                return summary(true, socAtDest)
            }
            if i == maxStops { break }

            // Reachable stations further along the route, scored.
            var best: (c: Candidate, km: Double, arriveSoc: Double, pFree: Double?, score: Double)?
            for c in candidates where c.t > progress + 0.01 {
                let km = Geo.roadKm(pos, c.station.latLng)
                let arriveSoc = soc - km * socPerKm
                guard arriveSoc >= input.reserveSoc else { continue }
                let eta = clock.addingTimeInterval(km / input.avgSpeedKmh * 3600)
                // No usable history means no credit for availability (not a guess).
                let pFreeKnown = c.station.probabilityFree(atHour: Calendar.current.component(.hour, from: eta))
                let pFree = pFreeKnown ?? 0
                let peak = Charging.effectivePeakKw(v, c.connector)
                // Go far, charge fast, avoid busy stations and detours, avoid pointless stops.
                var score = c.t * 100 + min(peak, 150) / 10 + pFree * 15 - c.detourKm * 0.5
                if !c.connector.type.isDC { score -= 30 }
                if arriveSoc > input.maxChargeSoc - 10 { score -= 60 }
                if best == nil || score > best!.score {
                    best = (c, km, arriveSoc, pFreeKnown, score)
                }
            }

            guard let pick = best else {
                return summary(false, socAtDest, stops.isEmpty
                    ? tr("No suitable station along the route is reachable at the current charge level.")
                    : tr("Couldn't find a reachable station further along."))
            }

            // Charge enough to reach the destination if that's within maxChargeSoc
            // (+10 % to avoid a tiny top-up later), otherwise to maxChargeSoc.
            let kmLeft = Geo.roadKm(pick.c.station.latLng, input.destination)
            let needForDest = kmLeft * socPerKm + input.reserveSoc + 3
            let target = min(100, needForDest <= input.maxChargeSoc + 10 ? max(needForDest, pick.arriveSoc) : input.maxChargeSoc)
            let charge = Charging.chargeTime(v, pick.c.connector, from: pick.arriveSoc, to: target)

            let legMinutes = pick.km / input.avgSpeedKmh * 60
            driveMin += legMinutes
            clock = clock.addingTimeInterval(legMinutes * 60)

            stops.append(TripStop(
                station: pick.c.station,
                connector: pick.c.connector,
                distanceFromPrevKm: Int(pick.km.rounded()),
                arriveAt: clock,
                arriveSoc: Int(pick.arriveSoc.rounded()),
                departSoc: Int(target.rounded()),
                chargeMinutes: charge.minutes,
                energyKwh: charge.kwh,
                costEur: (charge.kwh * pick.c.station.pricePerKwh * 100).rounded() / 100,
                freeProbability: pick.pFree
            ))

            clock = clock.addingTimeInterval(Double(charge.minutes) * 60)
            pos = pick.c.station.latLng
            progress = pick.c.t
            soc = target
        }

        return summary(false, soc, tr("Too many stops — check the starting charge level."))
    }
}
