// Demo data. Operator names are real Lithuanian networks, but every station,
// price, connector count and occupancy figure here is made up for the prototype.
// Replace with operator APIs (OCPI) or a backend when available.

import type { Connector, ConnectorStatus, ConnectorType, Operator, Station } from "../types";

export const operators: Operator[] = [
  { id: "ignitis", name: "Ignitis ON", color: "#0f766e" },
  { id: "eleport", name: "Eleport", color: "#7c3aed" },
  { id: "enefit", name: "Enefit Volt", color: "#ea580c" },
  { id: "inbalance", name: "Inbalance grid", color: "#2563eb" },
];

export function getOperator(id: string): Operator {
  return operators.find((o) => o.id === id) ?? { id, name: id, color: "#64748b" };
}

/** Small deterministic PRNG so demo data is stable between renders and builds. */
export function seeded(seed: string) {
  let h = 2166136261;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return () => {
    h += 0x6d2b79f5;
    let t = h;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

type Profile = "mall" | "office" | "residential" | "highway" | "transport";

// Base occupancy shape per hour (0–23) for each location type.
const profiles: Record<Profile, number[]> = {
  mall:        [.05,.03,.02,.02,.02,.05,.1,.2,.35,.5,.65,.75,.8,.8,.78,.8,.85,.9,.9,.8,.6,.4,.2,.1],
  office:      [.05,.05,.05,.05,.05,.1,.25,.6,.9,.95,.95,.9,.85,.9,.9,.85,.7,.45,.25,.15,.1,.08,.05,.05],
  residential: [.7,.75,.75,.75,.7,.6,.45,.3,.2,.15,.15,.15,.2,.2,.2,.25,.35,.55,.7,.8,.85,.85,.8,.75],
  highway:     [.1,.05,.05,.05,.1,.2,.35,.45,.5,.55,.6,.7,.75,.7,.65,.7,.8,.85,.75,.6,.45,.3,.2,.15],
  transport:   [.2,.15,.1,.1,.15,.3,.55,.7,.75,.7,.65,.65,.6,.6,.65,.7,.75,.7,.6,.5,.4,.35,.3,.25],
};

interface Seed {
  id: string;
  name: string;
  address: string;
  city: string;
  lat: number;
  lng: number;
  operatorId: string;
  profile: Profile;
  /** [type, powerKw, count] */
  connectors: [ConnectorType, number, number][];
  amenities?: string[];
}

const seeds: Seed[] = [
  // Vilnius
  { id: "akropolis", name: "Akropolis", address: "Ozo g. 25", city: "Vilnius", lat: 54.7106, lng: 25.2627, operatorId: "ignitis", profile: "mall", connectors: [["CCS2", 150, 2], ["Type2", 22, 4]], amenities: ["Parduotuvės", "Kavinė", "WC"] },
  { id: "ozas", name: "Ozas", address: "Ozo g. 18", city: "Vilnius", lat: 54.7155, lng: 25.279, operatorId: "eleport", profile: "mall", connectors: [["CCS2", 120, 2], ["Type2", 22, 2]], amenities: ["Parduotuvės", "Kavinė"] },
  { id: "europa", name: "Europa", address: "Konstitucijos pr. 7A", city: "Vilnius", lat: 54.6964, lng: 25.2775, operatorId: "enefit", profile: "office", connectors: [["CCS2", 60, 2], ["Type2", 11, 4]], amenities: ["Parduotuvės", "WC"] },
  { id: "panorama", name: "Panorama", address: "Saltoniškių g. 9", city: "Vilnius", lat: 54.699, lng: 25.2585, operatorId: "ignitis", profile: "mall", connectors: [["CCS2", 100, 2], ["Type2", 22, 2]], amenities: ["Parduotuvės", "Kavinė"] },
  { id: "senamiestis", name: "Lukiškių aikštė", address: "Gedimino pr. 40", city: "Vilnius", lat: 54.6895, lng: 25.27, operatorId: "inbalance", profile: "office", connectors: [["Type2", 22, 4]] },
  { id: "oro-uostas", name: "Oro uostas", address: "Rodūnios kl. 10A", city: "Vilnius", lat: 54.639, lng: 25.286, operatorId: "ignitis", profile: "transport", connectors: [["CCS2", 150, 2], ["Type2", 22, 4]], amenities: ["Kavinė", "WC"] },
  { id: "stotis", name: "Geležinkelio stotis", address: "Geležinkelio g. 16", city: "Vilnius", lat: 54.67, lng: 25.284, operatorId: "eleport", profile: "transport", connectors: [["CCS2", 60, 2], ["Type2", 22, 2]] },
  { id: "antakalnis", name: "Antakalnis", address: "Antakalnio g. 54", city: "Vilnius", lat: 54.702, lng: 25.315, operatorId: "enefit", profile: "residential", connectors: [["CCS2", 50, 1], ["Type2", 22, 2]] },
  { id: "zirmunai", name: "Žirmūnai", address: "Žirmūnų g. 64", city: "Vilnius", lat: 54.711, lng: 25.301, operatorId: "inbalance", profile: "residential", connectors: [["CCS2", 50, 1], ["Type2", 11, 3]] },
  { id: "pasilaiciai", name: "Pašilaičiai", address: "Gabijos g. 86", city: "Vilnius", lat: 54.734, lng: 25.224, operatorId: "ignitis", profile: "residential", connectors: [["CCS2", 75, 2], ["Type2", 22, 2]] },
  { id: "ukmerges", name: "Ukmergės verslo centras", address: "Ukmergės g. 280", city: "Vilnius", lat: 54.73, lng: 25.24, operatorId: "eleport", profile: "office", connectors: [["CCS2", 120, 2], ["Type2", 22, 4]] },
  { id: "pilaite", name: "Pilaitė", address: "Pilaitės pr. 16", city: "Vilnius", lat: 54.709, lng: 25.183, operatorId: "enefit", profile: "residential", connectors: [["CCS2", 50, 1], ["Type2", 22, 2]] },
  { id: "lazdynai", name: "Lazdynai", address: "Architektų g. 19", city: "Vilnius", lat: 54.675, lng: 25.208, operatorId: "inbalance", profile: "residential", connectors: [["Type2", 22, 2]] },
  { id: "santariskes", name: "Santariškės", address: "Santariškių g. 2", city: "Vilnius", lat: 54.7395, lng: 25.273, operatorId: "ignitis", profile: "office", connectors: [["CCS2", 60, 2], ["Type2", 22, 4]] },
  { id: "paupys", name: "Paupys", address: "Paupio g. 46", city: "Vilnius", lat: 54.68, lng: 25.3, operatorId: "eleport", profile: "office", connectors: [["CCS2", 100, 1], ["Type2", 22, 2]], amenities: ["Kavinė"] },
  { id: "naujoji-vilnia", name: "Naujoji Vilnia", address: "Parko g. 2", city: "Vilnius", lat: 54.695, lng: 25.41, operatorId: "enefit", profile: "residential", connectors: [["CCS2", 50, 1], ["CHAdeMO", 50, 1]] },
  // Intercity / highway corridors
  { id: "elektrenai", name: "Elektrėnai A1", address: "A1 magistralė, 47 km", city: "Elektrėnai", lat: 54.786, lng: 24.661, operatorId: "ignitis", profile: "highway", connectors: [["CCS2", 300, 4], ["CHAdeMO", 50, 1]], amenities: ["Kavinė", "WC"] },
  { id: "kaunas-centras", name: "Kauno centras", address: "Laisvės al. 100", city: "Kaunas", lat: 54.8985, lng: 23.9036, operatorId: "eleport", profile: "office", connectors: [["CCS2", 100, 2], ["Type2", 22, 4]] },
  { id: "kaunas-mega", name: "Mega", address: "Islandijos pl. 32", city: "Kaunas", lat: 54.93, lng: 23.905, operatorId: "ignitis", profile: "mall", connectors: [["CCS2", 150, 4], ["Type2", 22, 4]], amenities: ["Parduotuvės", "Kavinė", "WC"] },
  { id: "raseiniai", name: "Raseiniai A1", address: "A1 magistralė, 140 km", city: "Raseiniai", lat: 55.374, lng: 23.122, operatorId: "enefit", profile: "highway", connectors: [["CCS2", 150, 2]], amenities: ["Kavinė", "WC"] },
  { id: "klaipeda", name: "Klaipėda Akropolis", address: "Taikos pr. 61", city: "Klaipėda", lat: 55.7033, lng: 21.1443, operatorId: "ignitis", profile: "mall", connectors: [["CCS2", 150, 2], ["Type2", 22, 4]] },
  { id: "palanga", name: "Palanga", address: "Vytauto g. 106", city: "Palanga", lat: 55.9175, lng: 21.0686, operatorId: "eleport", profile: "mall", connectors: [["CCS2", 60, 2], ["Type2", 22, 2]] },
  { id: "ukmerge", name: "Ukmergė A2", address: "A2 magistralė, 75 km", city: "Ukmergė", lat: 55.245, lng: 24.76, operatorId: "inbalance", profile: "highway", connectors: [["CCS2", 120, 2]], amenities: ["Kavinė"] },
  { id: "panevezys", name: "Panevėžys Babilonas", address: "J. Biliūno g. 1", city: "Panevėžys", lat: 55.7348, lng: 24.3575, operatorId: "ignitis", profile: "mall", connectors: [["CCS2", 150, 2], ["Type2", 22, 2]] },
  { id: "siauliai", name: "Šiauliai Saulės miestas", address: "Aido g. 8", city: "Šiauliai", lat: 55.9349, lng: 23.3137, operatorId: "enefit", profile: "mall", connectors: [["CCS2", 100, 2], ["Type2", 22, 2]] },
  { id: "bauska", name: "Bauska (LV)", address: "A7, Bauska", city: "Bauska", lat: 56.408, lng: 24.193, operatorId: "enefit", profile: "highway", connectors: [["CCS2", 150, 2]] },
  { id: "utena", name: "Utena", address: "Utenio a. 1", city: "Utena", lat: 55.4977, lng: 25.5992, operatorId: "inbalance", profile: "residential", connectors: [["CCS2", 50, 1], ["Type2", 22, 2]] },
  { id: "alytus", name: "Alytus", address: "Naujoji g. 2", city: "Alytus", lat: 54.3963, lng: 24.0459, operatorId: "eleport", profile: "mall", connectors: [["CCS2", 60, 2], ["Type2", 22, 2]] },
  { id: "druskininkai", name: "Druskininkai", address: "Vilniaus al. 10", city: "Druskininkai", lat: 54.017, lng: 23.97, operatorId: "ignitis", profile: "mall", connectors: [["CCS2", 100, 2], ["Type2", 22, 2]] },
  { id: "marijampole", name: "Marijampolė Via Baltica", address: "A5, Marijampolė", city: "Marijampolė", lat: 54.559, lng: 23.354, operatorId: "enefit", profile: "highway", connectors: [["CCS2", 150, 2]] },
];

const basePrice: Record<string, number> = { ignitis: 0.49, eleport: 0.45, enefit: 0.47, inbalance: 0.42 };

function buildConnectors(seed: Seed, rand: () => number, occupancyNow: number): Connector[] {
  const out: Connector[] = [];
  for (const [type, powerKw, count] of seed.connectors) {
    for (let i = 0; i < count; i++) {
      const r = rand();
      let status: ConnectorStatus = "available";
      if (r < occupancyNow * 0.75) status = "charging";
      else if (r < occupancyNow * 0.93) status = "idle";
      else if (r < occupancyNow) status = "blocked";
      if (rand() < 0.04) status = "offline";
      out.push({
        id: `${seed.id}-${out.length + 1}`,
        type,
        powerKw,
        status,
        idleMinutes: status === "idle" ? Math.round(3 + rand() * 40) : undefined,
        etaMinutes: status === "charging" ? Math.round(5 + rand() * (powerKw >= 50 ? 35 : 150)) : undefined,
      });
    }
  }
  return out;
}

function buildStation(seed: Seed, hour: number, tick: number): Station {
  const rand = seeded(seed.id);
  const hourlyOccupancy = profiles[seed.profile].map((v) => Math.min(1, Math.max(0, v + (rand() - 0.5) * 0.2)));
  const hasFastDc = seed.connectors.some(([t, p]) => t !== "Type2" && p >= 100);
  const pricePerKwh = Math.round((basePrice[seed.operatorId] + (hasFastDc ? 0.1 : 0) + (rand() - 0.5) * 0.06) * 100) / 100;
  // Connector states depend on the hour and a "tick" so the map changes over time.
  const live = seeded(`${seed.id}:${hour}:${tick}`);
  return {
    id: seed.id,
    name: seed.name,
    address: seed.address,
    city: seed.city,
    lat: seed.lat,
    lng: seed.lng,
    operatorId: seed.operatorId,
    pricePerKwh,
    hourlyOccupancy,
    amenities: seed.amenities,
    connectors: buildConnectors(seed, live, hourlyOccupancy[hour]),
  };
}

/**
 * Returns a snapshot of all stations. `tick` simulates real-time updates
 * (increment it every ~30s to reshuffle statuses).
 */
export function getStations(date: Date = new Date(), tick = 0): Station[] {
  return seeds.map((s) => buildStation(s, date.getHours(), tick));
}

export function getStation(id: string, date: Date = new Date(), tick = 0): Station | undefined {
  const seed = seeds.find((s) => s.id === id);
  return seed ? buildStation(seed, date.getHours(), tick) : undefined;
}

export const stationIds = seeds.map((s) => s.id);
