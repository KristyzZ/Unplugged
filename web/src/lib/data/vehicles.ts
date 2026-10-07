import type { Place, Vehicle } from "../types";

// Approximate real-world figures; good enough for planning demos.
export const vehicles: Vehicle[] = [
  { id: "model-y", name: "Tesla Model Y LR", batteryKwh: 75, consumptionKwhPer100: 17, maxDcKw: 250, maxAcKw: 11, connectors: ["CCS2", "Type2"] },
  { id: "model-3", name: "Tesla Model 3 RWD", batteryKwh: 57, consumptionKwhPer100: 15, maxDcKw: 170, maxAcKw: 11, connectors: ["CCS2", "Type2"] },
  { id: "id4", name: "Volkswagen ID.4 Pro", batteryKwh: 77, consumptionKwhPer100: 19, maxDcKw: 135, maxAcKw: 11, connectors: ["CCS2", "Type2"] },
  { id: "ioniq5", name: "Hyundai Ioniq 5 LR", batteryKwh: 77, consumptionKwhPer100: 19, maxDcKw: 230, maxAcKw: 11, connectors: ["CCS2", "Type2"] },
  { id: "ev3", name: "Kia EV3 LR", batteryKwh: 81, consumptionKwhPer100: 16, maxDcKw: 128, maxAcKw: 11, connectors: ["CCS2", "Type2"] },
  { id: "enyaq", name: "Škoda Enyaq 85", batteryKwh: 77, consumptionKwhPer100: 18, maxDcKw: 135, maxAcKw: 11, connectors: ["CCS2", "Type2"] },
  { id: "leaf", name: "Nissan Leaf 40", batteryKwh: 39, consumptionKwhPer100: 17, maxDcKw: 50, maxAcKw: 6.6, connectors: ["CHAdeMO", "Type2"] },
  { id: "dolphin", name: "BYD Dolphin", batteryKwh: 60, consumptionKwhPer100: 16, maxDcKw: 88, maxAcKw: 11, connectors: ["CCS2", "Type2"] },
];

export function getVehicle(id: string): Vehicle {
  return vehicles.find((v) => v.id === id) ?? vehicles[0];
}

export const places: Place[] = [
  { id: "vilnius", name: "Vilnius (centras)", lat: 54.6872, lng: 25.2797 },
  { id: "kaunas", name: "Kaunas", lat: 54.8985, lng: 23.9036 },
  { id: "klaipeda", name: "Klaipėda", lat: 55.7033, lng: 21.1443 },
  { id: "palanga", name: "Palanga", lat: 55.9175, lng: 21.0686 },
  { id: "panevezys", name: "Panevėžys", lat: 55.7348, lng: 24.3575 },
  { id: "siauliai", name: "Šiauliai", lat: 55.9349, lng: 23.3137 },
  { id: "druskininkai", name: "Druskininkai", lat: 54.017, lng: 23.97 },
  { id: "utena", name: "Utena", lat: 55.4977, lng: 25.5992 },
  { id: "marijampole", name: "Marijampolė", lat: 54.559, lng: 23.354 },
  { id: "riga", name: "Ryga (LV)", lat: 56.9496, lng: 24.1052 },
];
