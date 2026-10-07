import type { Connector, ConnectorType, Vehicle } from "../types";

/** Share of peak power the battery accepts at a given state of charge (0–100). */
export function taper(soc: number): number {
  if (soc < 50) return 1;
  if (soc < 80) return 1 - ((soc - 50) / 30) * 0.45; // 1.0 → 0.55
  return 0.55 - ((soc - 80) / 20) * 0.4; // 0.55 → 0.15
}

export function isDc(type: ConnectorType): boolean {
  return type !== "Type2";
}

/** Peak power the car can actually draw from this connector. */
export function effectivePeakKw(vehicle: Vehicle, connector: Pick<Connector, "type" | "powerKw">): number {
  const carLimit = isDc(connector.type) ? vehicle.maxDcKw : vehicle.maxAcKw;
  return Math.min(carLimit, connector.powerKw);
}

/**
 * Minutes and kWh to charge from `fromSoc` to `toSoc` (percent), integrating
 * the taper curve in 1 % steps. AC charging is flat (no taper).
 */
export function chargeTime(
  vehicle: Vehicle,
  connector: Pick<Connector, "type" | "powerKw">,
  fromSoc: number,
  toSoc: number,
): { minutes: number; kwh: number } {
  if (toSoc <= fromSoc) return { minutes: 0, kwh: 0 };
  const peak = effectivePeakKw(vehicle, connector);
  const kwhPerPct = vehicle.batteryKwh / 100;
  let hours = 0;
  for (let s = Math.floor(fromSoc); s < Math.ceil(toSoc); s++) {
    const kw = isDc(connector.type) ? peak * taper(s) : peak;
    hours += kwhPerPct / Math.max(kw, 1);
  }
  // ~8 % losses between grid and battery.
  const kwh = ((toSoc - fromSoc) * kwhPerPct) / 0.92;
  return { minutes: Math.round(hours * 60), kwh: Math.round(kwh * 10) / 10 };
}

export function compatible(vehicle: Vehicle, connector: Pick<Connector, "type">): boolean {
  return vehicle.connectors.includes(connector.type);
}
