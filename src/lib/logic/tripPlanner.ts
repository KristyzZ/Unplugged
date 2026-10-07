// Trip planner: given a car, its battery level and a destination, decide where
// to stop, how long to charge and what battery level to expect. Prefers
// stations that are fast and historically less busy at the expected arrival time.

import type { Connector, LatLng, Station, Vehicle } from "../types";
import { probabilityFreeAt } from "./availability";
import { chargeTime, compatible, effectivePeakKw, isDc } from "./charging";
import { haversineKm, positionAlong, roadKm } from "./geo";

export interface TripInput {
  vehicle: Vehicle;
  startSoc: number; // %
  origin: LatLng & { name: string };
  destination: LatLng & { name: string };
  stations: Station[];
  departure: Date;
  /** Never plan to arrive anywhere below this (%). */
  reserveSoc?: number;
  /** Stop charging at this level unless more is needed (%). */
  maxChargeSoc?: number;
  avgSpeedKmh?: number;
}

export interface TripStop {
  station: Station;
  connector: Connector;
  distanceFromPrevKm: number;
  arriveAt: Date;
  arriveSoc: number;
  departSoc: number;
  chargeMinutes: number;
  energyKwh: number;
  costEur: number;
  freeProbability: number;
}

export interface TripPlan {
  feasible: boolean;
  message?: string;
  totalKm: number;
  driveMinutes: number;
  chargeMinutes: number;
  arriveAt: Date;
  arriveSoc: number;
  costEur: number;
  stops: TripStop[];
}

const MAX_DETOUR_KM = 20;
const MAX_STOPS = 6;

function bestConnector(vehicle: Vehicle, station: Station): Connector | undefined {
  return station.connectors
    .filter((c) => compatible(vehicle, c) && c.status !== "offline")
    .sort((a, b) => effectivePeakKw(vehicle, b) - effectivePeakKw(vehicle, a))[0];
}

export function planTrip(input: TripInput): TripPlan {
  const plan = planOnce(input);
  // Small batteries / sparse corridors: allow charging to 100 % before giving up.
  if (!plan.feasible && (input.maxChargeSoc ?? 80) < 100) {
    const full = planOnce({ ...input, maxChargeSoc: 100 });
    if (full.feasible) return full;
  }
  return plan;
}

function planOnce(input: TripInput): TripPlan {
  const {
    vehicle,
    startSoc,
    origin,
    destination,
    stations,
    departure,
    reserveSoc = 10,
    maxChargeSoc = 80,
    avgSpeedKmh = 85,
  } = input;

  const kwhPerKm = vehicle.consumptionKwhPer100 / 100;
  const socPerKm = (kwhPerKm / vehicle.batteryKwh) * 100;
  const totalKm = roadKm(origin, destination);

  // Stations near the corridor, ordered by progress along it. Only DC (≥ 50 kW)
  // makes sense on a trip; AC is fine as a last resort.
  const candidates = stations
    .map((s) => ({ s, conn: bestConnector(vehicle, s), ...positionAlong(origin, destination, s) }))
    .filter((c): c is typeof c & { conn: Connector } => !!c.conn && c.detourKm <= MAX_DETOUR_KM && c.t > 0.02 && c.t < 0.98)
    .sort((a, b) => a.t - b.t);

  const stops: TripStop[] = [];
  let pos: LatLng = origin;
  let progress = 0;
  let soc = startSoc;
  let clock = departure.getTime();
  let driveMin = 0;

  for (let i = 0; i <= MAX_STOPS; i++) {
    const kmToDest = roadKm(pos, destination);
    const socAtDest = soc - kmToDest * socPerKm;
    if (socAtDest >= reserveSoc) {
      const minutes = (kmToDest / avgSpeedKmh) * 60;
      driveMin += minutes;
      clock += minutes * 60_000;
      return summary(true, socAtDest);
    }
    if (i === MAX_STOPS) break;

    // Reachable stations further along the route.
    const reachable = candidates
      .filter((c) => c.t > progress + 0.01)
      .map((c) => {
        const km = roadKm(pos, c.s);
        const arriveSoc = soc - km * socPerKm;
        const eta = new Date(clock + (km / avgSpeedKmh) * 3_600_000);
        const pFree = probabilityFreeAt(c.s, eta.getHours());
        const peak = effectivePeakKw(vehicle, c.conn);
        // Score: go far, charge fast, avoid busy stations, avoid detours.
        const score = c.t * 100 + Math.min(peak, 150) / 10 + pFree * 15 - c.detourKm * 0.5 - (isDc(c.conn.type) ? 0 : 30) - (arriveSoc > maxChargeSoc - 10 ? 60 : 0);
        return { ...c, km, arriveSoc, eta, pFree, score };
      })
      .filter((c) => c.arriveSoc >= reserveSoc);

    if (reachable.length === 0) {
      return summary(false, socAtDest, stops.length === 0
        ? "Su dabartiniu įkrovos lygiu nepasiekiama nė viena tinkama stotelė pakeliui."
        : "Nepavyko rasti tolesnės pasiekiamos stotelės.");
    }

    const pick = reachable.sort((a, b) => b.score - a.score)[0];

    // Charge just enough for the next useful hop, capped at maxChargeSoc,
    // or enough to reach the destination if that is possible from here.
    const kmLeft = roadKm(pick.s, destination);
    const needForDest = kmLeft * socPerKm + reserveSoc + 3;
    // If the destination is only slightly out of reach at maxChargeSoc, charge a
    // bit more here rather than adding a tiny top-up stop later.
    const target = Math.min(
      100,
      needForDest <= maxChargeSoc + 10 ? Math.max(needForDest, pick.arriveSoc) : maxChargeSoc,
    );
    const { minutes, kwh } = chargeTime(vehicle, pick.conn, pick.arriveSoc, target);

    const legMinutes = (pick.km / avgSpeedKmh) * 60;
    driveMin += legMinutes;
    clock += legMinutes * 60_000;

    stops.push({
      station: pick.s,
      connector: pick.conn,
      distanceFromPrevKm: Math.round(pick.km),
      arriveAt: new Date(clock),
      arriveSoc: Math.round(pick.arriveSoc),
      departSoc: Math.round(target),
      chargeMinutes: minutes,
      energyKwh: kwh,
      costEur: Math.round(kwh * pick.s.pricePerKwh * 100) / 100,
      freeProbability: pick.pFree,
    });

    clock += minutes * 60_000;
    pos = pick.s;
    progress = pick.t;
    soc = target;
  }

  return summary(false, soc, "Per daug sustojimų — patikrinkite pradinį įkrovos lygį.");

  function summary(feasible: boolean, arriveSoc: number, message?: string): TripPlan {
    const chargeMinutes = stops.reduce((s, x) => s + x.chargeMinutes, 0);
    return {
      feasible,
      message,
      totalKm: Math.round(totalKm),
      driveMinutes: Math.round(driveMin),
      chargeMinutes,
      arriveAt: new Date(clock),
      arriveSoc: Math.round(arriveSoc),
      costEur: Math.round(stops.reduce((s, x) => s + x.costEur, 0) * 100) / 100,
      stops,
    };
  }
}

/** Straight-line km, handy for "near me" sorting. */
export function distanceKm(a: LatLng, b: LatLng): number {
  return haversineKm(a, b);
}
