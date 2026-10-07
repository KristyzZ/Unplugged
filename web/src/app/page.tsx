"use client";

import { useMemo, useState } from "react";
import { MapView } from "@/components/MapView";
import { StationListItem } from "@/components/StationListItem";
import { Chip } from "@/components/ui";
import { operators } from "@/lib/data/stations";
import { getVehicle } from "@/lib/data/vehicles";
import { freeCount, maxPower } from "@/lib/logic/availability";
import { compatible } from "@/lib/logic/charging";
import { haversineKm } from "@/lib/logic/geo";
import { useStore } from "@/lib/store";
import type { LatLng } from "@/lib/types";

const VILNIUS: LatLng = { lat: 54.6872, lng: 25.2797 };

export default function MapPage() {
  const { stations, vehicleId, ready } = useStore();
  const [onlyFree, setOnlyFree] = useState(false);
  const [fastOnly, setFastOnly] = useState(false);
  const [myCarOnly, setMyCarOnly] = useState(true);
  const [operator, setOperator] = useState<string | null>(null);
  const [selected, setSelected] = useState<string>();
  const [user, setUser] = useState<LatLng>(VILNIUS);
  const [located, setLocated] = useState(false);
  const vehicle = getVehicle(vehicleId);

  const list = useMemo(() => {
    return stations
      .filter((s) => !onlyFree || freeCount(s) > 0)
      .filter((s) => !fastOnly || maxPower(s) >= 50)
      .filter((s) => !operator || s.operatorId === operator)
      .filter((s) => !myCarOnly || s.connectors.some((c) => compatible(vehicle, c)))
      .map((s) => ({ s, d: haversineKm(user, s) }))
      .sort((a, b) => a.d - b.d);
  }, [stations, onlyFree, fastOnly, operator, myCarOnly, vehicle, user]);

  function locate() {
    navigator.geolocation?.getCurrentPosition(
      (p) => {
        setUser({ lat: p.coords.latitude, lng: p.coords.longitude });
        setLocated(true);
      },
      () => setLocated(false),
    );
  }

  function select(id: string) {
    setSelected(id);
    document.getElementById(`st-${id}`)?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  return (
    <div className="-mx-4 -mt-4">
      <div className="relative h-[48vh] min-h-72">
        {ready && <MapView className="h-full w-full" stations={list.map((x) => x.s)} selectedId={selected} onSelect={select} user={user} fit={located ? [user] : undefined} />}
        <button
          onClick={locate}
          className="absolute bottom-3 right-3 z-[400] rounded-full bg-[var(--surface)] px-3 py-2 text-sm font-medium shadow"
        >
          ◎ Mano vieta
        </button>
      </div>

      <div className="no-scrollbar flex gap-2 overflow-x-auto px-4 py-3">
        <Chip active={onlyFree} onClick={() => setOnlyFree(!onlyFree)}>Tik laisvos</Chip>
        <Chip active={fastOnly} onClick={() => setFastOnly(!fastOnly)}>Greitos ≥ 50 kW</Chip>
        <Chip active={myCarOnly} onClick={() => setMyCarOnly(!myCarOnly)}>Tinka mano automobiliui</Chip>
        {operators.map((o) => (
          <Chip key={o.id} active={operator === o.id} onClick={() => setOperator(operator === o.id ? null : o.id)}>
            {o.name}
          </Chip>
        ))}
      </div>

      <div className="flex flex-col gap-2 px-4">
        <div className="text-xs text-[var(--muted)]">
          {ready ? `${list.length} stotelės · visų operatorių` : "Kraunama…"}
        </div>
        {list.map(({ s, d }) => (
          <StationListItem key={s.id} station={s} distance={d} selected={s.id === selected} />
        ))}
      </div>
    </div>
  );
}
