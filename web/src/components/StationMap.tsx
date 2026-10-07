"use client";

// Leaflet map (OpenStreetMap tiles, no API key). Load it through
// MapView (next/dynamic, ssr: false) — Leaflet needs `window`.

import "leaflet/dist/leaflet.css";
import { useEffect } from "react";
import { CircleMarker, MapContainer, Polyline, TileLayer, Tooltip, useMap } from "react-leaflet";
import { availabilityLevel, freeCount, maxPower, workingCount } from "@/lib/logic/availability";
import { levelColor } from "@/lib/format";
import type { LatLng, Station } from "@/lib/types";

export interface StationMapProps {
  stations: Station[];
  selectedId?: string;
  onSelect?: (id: string) => void;
  route?: LatLng[];
  /** Highlighted stops (e.g. trip plan) — drawn bigger, numbered in tooltip. */
  stops?: Station[];
  user?: LatLng;
  center?: LatLng;
  zoom?: number;
  /** Fit the view to these points whenever they change. */
  fit?: LatLng[];
  className?: string;
}

function FitBounds({ points }: { points?: LatLng[] }) {
  const map = useMap();
  const key = points?.map((p) => `${p.lat},${p.lng}`).join("|");
  useEffect(() => {
    if (!points || points.length === 0) return;
    if (points.length === 1) map.setView([points[0].lat, points[0].lng], 14);
    else map.fitBounds(points.map((p) => [p.lat, p.lng] as [number, number]), { padding: [30, 30] });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
  return null;
}

export default function StationMap({
  stations,
  selectedId,
  onSelect,
  route,
  stops,
  user,
  center = { lat: 54.6872, lng: 25.2797 },
  zoom = 12,
  fit,
  className = "",
}: StationMapProps) {
  const stopIds = new Set(stops?.map((s) => s.id));
  return (
    <MapContainer center={[center.lat, center.lng]} zoom={zoom} className={className} scrollWheelZoom zoomControl={false}>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FitBounds points={fit} />
      {route && route.length > 1 && (
        <Polyline positions={route.map((p) => [p.lat, p.lng] as [number, number])} pathOptions={{ color: "#0f766e", weight: 4, opacity: 0.8 }} />
      )}
      {stations.map((s) => {
        const level = availabilityLevel(s);
        const isStop = stopIds.has(s.id);
        const selected = s.id === selectedId;
        return (
          <CircleMarker
            key={s.id}
            center={[s.lat, s.lng]}
            radius={isStop || selected ? 11 : 8}
            pathOptions={{
              color: selected ? "#111827" : "#ffffff",
              weight: selected ? 3 : 2,
              fillColor: levelColor[level].replace(/var\((--\w+)\)/, (_, v) => cssVar(v)),
              fillOpacity: stops && !isStop ? 0.35 : 1,
            }}
            eventHandlers={{ click: () => onSelect?.(s.id) }}
          >
            <Tooltip direction="top" offset={[0, -8]}>
              <strong>{s.name}</strong>
              <br />
              {freeCount(s)}/{workingCount(s)} laisvos · iki {maxPower(s)} kW · {s.pricePerKwh.toFixed(2)} €/kWh
            </Tooltip>
          </CircleMarker>
        );
      })}
      {user && <CircleMarker center={[user.lat, user.lng]} radius={7} pathOptions={{ color: "#fff", weight: 3, fillColor: "#2563eb", fillOpacity: 1 }} />}
    </MapContainer>
  );
}

// Leaflet paints SVG attributes, which don't resolve CSS variables reliably.
function cssVar(name: string): string {
  if (typeof window === "undefined") return "#64748b";
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || "#64748b";
}
