"use client";

import dynamic from "next/dynamic";
import type { StationMapProps } from "./StationMap";

const StationMap = dynamic(() => import("./StationMap"), {
  ssr: false,
  loading: () => <div className="h-full w-full animate-pulse rounded-2xl bg-[var(--surface-2)]" />,
});

export function MapView(props: StationMapProps) {
  return <StationMap {...props} />;
}
