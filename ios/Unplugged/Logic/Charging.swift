import Foundation

enum Charging {
    /// Share of peak power the battery accepts at a given state of charge (0–100).
    static func taper(_ soc: Double) -> Double {
        if soc < 50 { return 1 }
        if soc < 80 { return 1 - (soc - 50) / 30 * 0.45 } // 1.0 → 0.55
        return 0.55 - (soc - 80) / 20 * 0.4 // 0.55 → 0.15
    }

    static func isCompatible(_ vehicle: Vehicle, _ connector: Connector) -> Bool {
        vehicle.connectors.contains(connector.type)
    }

    /// Peak power the car can actually draw from this connector.
    static func effectivePeakKw(_ vehicle: Vehicle, _ connector: Connector) -> Double {
        let carLimit = connector.type.isDC ? vehicle.maxDcKw : vehicle.maxAcKw
        return min(carLimit, connector.powerKw)
    }

    /// Minutes and kWh to charge from `fromSoc` to `toSoc` (percent), in 1 %
    /// steps. DC follows the car's own charging curve, capped by the charger;
    /// AC is flat.
    static func chargeTime(_ vehicle: Vehicle, _ connector: Connector, from fromSoc: Double, to toSoc: Double) -> (minutes: Int, kwh: Double) {
        guard toSoc > fromSoc else { return (0, 0) }
        let peak = effectivePeakKw(vehicle, connector)
        let kwhPerPct = vehicle.batteryKwh / 100
        var hours = 0.0
        var s = Int(fromSoc.rounded(.down))
        while s < Int(toSoc.rounded(.up)) {
            let kw = connector.type.isDC ? min(connector.powerKw, vehicle.dcPower(atSoc: Double(s))) : peak
            hours += kwhPerPct / max(kw, 1)
            s += 1
        }
        // ~8 % losses between grid and battery.
        let kwh = (toSoc - fromSoc) * kwhPerPct / 0.92
        return (Int((hours * 60).rounded()), (kwh * 10).rounded() / 10)
    }
}

extension Charging {
    /// The charge level reached after about `minutes` of charging, starting at
    /// `fromSoc` (never above 100 %). The inverse of `chargeTime`.
    static func targetSoc(_ vehicle: Vehicle, _ connector: Connector, from fromSoc: Double, minutes: Int) -> Double {
        let start = Int(fromSoc.rounded(.down))
        guard minutes > 0, start < 100 else { return fromSoc }
        for target in (start + 1)...100 where chargeTime(vehicle, connector, from: fromSoc, to: Double(target)).minutes >= minutes {
            return Double(target)
        }
        return 100
    }

    /// Minutes to go from `fromSoc` to a full battery, at least 5.
    static func minutesToFull(_ vehicle: Vehicle, _ connector: Connector, from fromSoc: Double) -> Int {
        max(5, chargeTime(vehicle, connector, from: fromSoc, to: 100).minutes)
    }
}
