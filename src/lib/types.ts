// Core domain types for the Unplugged EV charging platform.

export type ConnectorType = "CCS2" | "Type2" | "CHAdeMO";

export type ConnectorStatus =
  | "available" // free and ready
  | "charging" // car plugged in and drawing power
  | "idle" // charging finished, car still occupying the spot
  | "blocked" // spot taken by a car that is not charging / not an EV
  | "offline"; // out of service

export interface Connector {
  id: string;
  type: ConnectorType;
  powerKw: number;
  status: ConnectorStatus;
  /** Minutes the current occupant has been idle (only when status === "idle"). */
  idleMinutes?: number;
  /** Estimated minutes until free (only when status === "charging"). */
  etaMinutes?: number;
}

export interface Operator {
  id: string;
  name: string;
  color: string;
}

export interface Station {
  id: string;
  name: string;
  address: string;
  city: string;
  lat: number;
  lng: number;
  operatorId: string;
  /** Price per kWh in EUR. */
  pricePerKwh: number;
  connectors: Connector[];
  /** Typical occupancy share (0–1) for each hour of the day, index 0 = 00:00. */
  hourlyOccupancy: number[];
  amenities?: string[];
}

export interface Vehicle {
  id: string;
  name: string;
  batteryKwh: number;
  /** Real-world consumption in kWh per 100 km. */
  consumptionKwhPer100: number;
  maxDcKw: number;
  maxAcKw: number;
  connectors: ConnectorType[];
}

export interface Place {
  id: string;
  name: string;
  lat: number;
  lng: number;
}

export interface LatLng {
  lat: number;
  lng: number;
}
