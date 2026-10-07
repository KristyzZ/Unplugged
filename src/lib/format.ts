import type { ConnectorStatus } from "./types";
import type { AvailabilityLevel } from "./logic/availability";

export const eur = (v: number) =>
  new Intl.NumberFormat("lt-LT", { style: "currency", currency: "EUR" }).format(v);

export function minutes(m: number): string {
  const total = Math.max(0, Math.round(m));
  const h = Math.floor(total / 60);
  const min = total % 60;
  if (h === 0) return `${min} min.`;
  return min === 0 ? `${h} val.` : `${h} val. ${min} min.`;
}

export function clock(d: Date | number): string {
  return new Date(d).toLocaleTimeString("lt-LT", { hour: "2-digit", minute: "2-digit" });
}

export function mmss(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export function km(v: number): string {
  return v < 10 ? `${v.toFixed(1)} km` : `${Math.round(v)} km`;
}

export const statusLabel: Record<ConnectorStatus, string> = {
  available: "Laisva",
  charging: "Kraunasi",
  idle: "Baigė, bet stovi",
  blocked: "Užimta nesikraunant",
  offline: "Neveikia",
};

export const statusColor: Record<ConnectorStatus, string> = {
  available: "var(--ok)",
  charging: "var(--info)",
  idle: "var(--warn)",
  blocked: "var(--bad)",
  offline: "var(--muted)",
};

export const levelLabel: Record<AvailabilityLevel, string> = {
  free: "Laisva",
  limited: "Beveik užimta",
  full: "Užimta",
  offline: "Neveikia",
};

export const levelColor: Record<AvailabilityLevel, string> = {
  free: "var(--ok)",
  limited: "var(--warn)",
  full: "var(--bad)",
  offline: "var(--muted)",
};

export const pct = (v: number) => `${Math.round(v * 100)} %`;
