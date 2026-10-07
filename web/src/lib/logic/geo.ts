import type { LatLng } from "../types";

/** Roads are longer than straight lines; rough Lithuania-wide factor. */
export const ROAD_FACTOR = 1.2;

export function haversineKm(a: LatLng, b: LatLng): number {
  const R = 6371;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

export function roadKm(a: LatLng, b: LatLng): number {
  return haversineKm(a, b) * ROAD_FACTOR;
}

/**
 * Where a point sits along the straight line a→b.
 * `t` is 0 at a and 1 at b; `detourKm` is the extra straight-line distance
 * to pass through p instead of going directly.
 */
export function positionAlong(a: LatLng, b: LatLng, p: LatLng) {
  const direct = haversineKm(a, b);
  const viaP = haversineKm(a, p) + haversineKm(p, b);
  const t = direct === 0 ? 0 : haversineKm(a, p) / (haversineKm(a, p) + haversineKm(p, b));
  return { t, detourKm: viaP - direct };
}
