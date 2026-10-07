import type { ConnectorStatus, Station } from "../types";

export function countByStatus(station: Station): Record<ConnectorStatus, number> {
  const counts: Record<ConnectorStatus, number> = { available: 0, charging: 0, idle: 0, blocked: 0, offline: 0 };
  for (const c of station.connectors) counts[c.status]++;
  return counts;
}

export function freeCount(station: Station): number {
  return countByStatus(station).available;
}

export function workingCount(station: Station): number {
  return station.connectors.filter((c) => c.status !== "offline").length;
}

export function maxPower(station: Station): number {
  return Math.max(...station.connectors.map((c) => c.powerKw));
}

export type AvailabilityLevel = "free" | "limited" | "full" | "offline";

export function availabilityLevel(station: Station): AvailabilityLevel {
  const working = workingCount(station);
  if (working === 0) return "offline";
  const free = freeCount(station);
  if (free === 0) return "full";
  if (free / working < 0.34) return "limited";
  return "free";
}

/**
 * Probability that at least one connector is free at a given hour,
 * from the historical occupancy share. Treats connectors as independent:
 * P(free) = 1 - p^n.
 */
export function probabilityFreeAt(station: Station, hour: number): number {
  const p = station.hourlyOccupancy[((hour % 24) + 24) % 24];
  const n = Math.max(1, workingCount(station));
  return 1 - Math.pow(p, n);
}

/** Current demand (0–1): live occupancy blended with the historical norm for this hour. */
export function demandLevel(station: Station, hour: number): number {
  const working = workingCount(station);
  const live = working === 0 ? 1 : 1 - freeCount(station) / working;
  const hist = station.hourlyOccupancy[hour % 24];
  return Math.min(1, 0.7 * live + 0.3 * hist);
}

/** The hours (0–23) where the station is usually busiest. */
export function peakHours(station: Station, top = 3): number[] {
  return station.hourlyOccupancy
    .map((v, h) => ({ v, h }))
    .sort((a, b) => b.v - a.v)
    .slice(0, top)
    .map((x) => x.h)
    .sort((a, b) => a - b);
}

/** Best hour to come in the next `window` hours. */
export function bestHourAhead(station: Station, fromHour: number, window = 6): number {
  let best = fromHour;
  for (let i = 0; i <= window; i++) {
    const h = (fromHour + i) % 24;
    if (station.hourlyOccupancy[h] < station.hourlyOccupancy[best]) best = h;
  }
  return best;
}
