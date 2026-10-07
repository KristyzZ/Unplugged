import { describe, expect, it } from "vitest";
import { getStations } from "../data/stations";
import { getVehicle, places } from "../data/vehicles";
import { chargeTime } from "./charging";
import { gracePeriodMinutes, idleFee } from "./idleFee";
import { pointsForMove } from "./points";
import { confidence } from "./reports";
import { planTrip } from "./tripPlanner";

describe("grace period", () => {
  it("is 15 min at low demand and 5 min at high demand", () => {
    expect(gracePeriodMinutes(0.1)).toBe(15);
    expect(gracePeriodMinutes(0.95)).toBe(5);
    expect(gracePeriodMinutes(0.65)).toBe(10);
  });
});

describe("idle fee", () => {
  it("grows progressively", () => {
    expect(idleFee(0)).toBe(0);
    expect(idleFee(10)).toBe(1); // 10 × 0.10
    expect(idleFee(30)).toBe(6); // 1 + 20 × 0.25
    expect(idleFee(40)).toBe(11); // 6 + 10 × 0.50
    expect(idleFee(10_000)).toBe(40); // cap
  });
});

describe("points", () => {
  it("rewards moving quickly", () => {
    expect(pointsForMove(1, 10).points).toBe(30);
    expect(pointsForMove(8, 10).points).toBe(20);
    expect(pointsForMove(12, 10).points).toBe(0);
  });
});

describe("reports", () => {
  it("needs several kinds of evidence", () => {
    expect(confidence({ hasPhoto: true, telemetryMatches: false, confirmations: 0 })).toBeLessThan(0.7);
    expect(confidence({ hasPhoto: true, telemetryMatches: true, confirmations: 0 })).toBeGreaterThanOrEqual(0.7);
  });
});

describe("charging", () => {
  it("takes longer above 80 %", () => {
    const car = getVehicle("ioniq5");
    const c = { type: "CCS2" as const, powerKw: 150 };
    const low = chargeTime(car, c, 10, 50).minutes / 40;
    const high = chargeTime(car, c, 80, 100).minutes / 20;
    expect(high).toBeGreaterThan(low * 2);
  });
});

describe("trip planner", () => {
  const stations = getStations(new Date("2026-10-07T09:00:00"));
  const vilnius = places.find((p) => p.id === "vilnius")!;
  const klaipeda = places.find((p) => p.id === "klaipeda")!;
  const kaunas = places.find((p) => p.id === "kaunas")!;

  it("needs no stop for a short trip with a full battery", () => {
    const plan = planTrip({ vehicle: getVehicle("ioniq5"), startSoc: 90, origin: vilnius, destination: kaunas, stations, departure: new Date() });
    expect(plan.feasible).toBe(true);
    expect(plan.stops).toHaveLength(0);
  });

  it("adds a charging stop Vilnius → Klaipėda with a low battery", () => {
    const plan = planTrip({ vehicle: getVehicle("id4"), startSoc: 40, origin: vilnius, destination: klaipeda, stations, departure: new Date() });
    expect(plan.feasible).toBe(true);
    expect(plan.stops.length).toBeGreaterThan(0);
    expect(plan.arriveSoc).toBeGreaterThanOrEqual(10);
    for (const s of plan.stops) expect(s.arriveSoc).toBeGreaterThanOrEqual(10);
  });

  it("uses CHAdeMO for a Nissan Leaf", () => {
    const plan = planTrip({ vehicle: getVehicle("leaf"), startSoc: 50, origin: vilnius, destination: kaunas, stations, departure: new Date() });
    expect(plan.feasible).toBe(true);
    expect(plan.stops[0].connector.type).toBe("CHAdeMO");
  });

  it("reports an infeasible trip instead of crashing", () => {
    const plan = planTrip({ vehicle: getVehicle("leaf"), startSoc: 12, origin: vilnius, destination: klaipeda, stations, departure: new Date() });
    expect(plan.feasible).toBe(false);
    expect(plan.message).toBeTruthy();
  });
});
