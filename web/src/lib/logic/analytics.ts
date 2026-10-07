// Operator / city analytics derived from (demo) session history.

import { seeded } from "../data/stations";
import type { Station } from "../types";

export interface StationStats {
  station: Station;
  sessionsPerDay: number;
  avgChargeMin: number;
  avgIdleMin: number;
  /** Share of occupied time where the car was not charging. */
  idleShare: number;
  utilization: number;
  abuseCases7d: number;
}

export function stationStats(station: Station): StationStats {
  const r = seeded(`stats:${station.id}`);
  const connectors = station.connectors.length;
  const fast = station.connectors.some((c) => c.powerKw >= 50);
  const utilization = station.hourlyOccupancy.reduce((a, b) => a + b, 0) / 24;
  const avgChargeMin = Math.round(fast ? 28 + r() * 20 : 110 + r() * 80);
  const avgIdleMin = Math.round(fast ? 8 + r() * 14 : 25 + r() * 55);
  const occupiedMinPerDay = utilization * 24 * 60 * connectors;
  const sessionsPerDay = Math.round(occupiedMinPerDay / (avgChargeMin + avgIdleMin));
  return {
    station,
    sessionsPerDay,
    avgChargeMin,
    avgIdleMin,
    idleShare: avgIdleMin / (avgChargeMin + avgIdleMin),
    utilization,
    abuseCases7d: Math.round(r() * (station.city === "Vilnius" ? 9 : 4)),
  };
}

/** Assumed effect of grace period + idle fee + rewards on idle time. */
export const IDLE_REDUCTION = 0.7;

export interface NetworkSummary {
  stations: StationStats[];
  sessionsPerDay: number;
  avgIdleMin: number;
  avgIdleMinAfter: number;
  idleHoursPerDay: number;
  idleHoursSavedPerDay: number;
  extraSessionsPerDay: number;
  abuseCases7d: number;
  hourlyDemand: number[];
}

export function networkSummary(stations: Station[], idleReduction = IDLE_REDUCTION): NetworkSummary {
  const stats = stations.map(stationStats);
  const sessions = stats.reduce((a, s) => a + s.sessionsPerDay, 0);
  const idleMinTotal = stats.reduce((a, s) => a + s.sessionsPerDay * s.avgIdleMin, 0);
  const chargeMinTotal = stats.reduce((a, s) => a + s.sessionsPerDay * s.avgChargeMin, 0);
  const avgIdle = idleMinTotal / Math.max(1, sessions);
  const avgCharge = chargeMinTotal / Math.max(1, sessions);
  const savedMin = idleMinTotal * idleReduction;
  const hourlyDemand = Array.from({ length: 24 }, (_, h) => stations.reduce((a, s) => a + s.hourlyOccupancy[h], 0) / stations.length);
  return {
    stations: stats,
    sessionsPerDay: sessions,
    avgIdleMin: avgIdle,
    avgIdleMinAfter: avgIdle * (1 - idleReduction),
    idleHoursPerDay: idleMinTotal / 60,
    idleHoursSavedPerDay: savedMin / 60,
    // Freed bay-time divided by a typical session (charge + reduced idle).
    extraSessionsPerDay: Math.round(savedMin / (avgCharge + avgIdle * (1 - idleReduction))),
    abuseCases7d: stats.reduce((a, s) => a + s.abuseCases7d, 0),
    hourlyDemand,
  };
}
