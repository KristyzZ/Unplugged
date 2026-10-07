"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { MapView } from "@/components/MapView";
import { Badge, Button, Card, Field, inputClass, PageHeader, SectionTitle, SocBar, Stat } from "@/components/ui";
import { getOperator } from "@/lib/data/stations";
import { getVehicle, places, vehicles } from "@/lib/data/vehicles";
import { clock, eur, minutes, pct } from "@/lib/format";
import { planTrip, type TripPlan } from "@/lib/logic/tripPlanner";
import { useStore } from "@/lib/store";

export default function PlanPage() {
  const store = useStore();
  const { stations, vehicleId, soc, ready } = store;
  const [originId, setOriginId] = useState("vilnius");
  const [destId, setDestId] = useState("klaipeda");
  const [plan, setPlan] = useState<TripPlan | null>(null);

  const vehicle = getVehicle(vehicleId);
  const origin = places.find((p) => p.id === originId)!;
  const dest = places.find((p) => p.id === destId)!;

  function run() {
    setPlan(planTrip({ vehicle, startSoc: soc, origin, destination: dest, stations, departure: new Date() }));
  }

  const route = useMemo(() => (plan ? [origin, ...plan.stops.map((s) => s.station), dest] : [origin, dest]), [plan, origin, dest]);

  return (
    <div>
      <PageHeader title="Kelionės planavimas" subtitle="Suplanuosime, kur ir kiek krautis, atsižvelgiant į automobilį, maršrutą ir stotelių užimtumą." />

      <Card className="space-y-4">
        <Field label="Automobilis">
          <select className={inputClass} value={vehicleId} onChange={(e) => store.setVehicle(e.target.value)}>
            {vehicles.map((v) => (
              <option key={v.id} value={v.id}>
                {v.name} · {v.batteryKwh} kWh
              </option>
            ))}
          </select>
        </Field>
        <Field label={`Dabartinė baterijos įkrova: ${soc} %`} hint={`≈ ${Math.round(((soc / 100) * vehicle.batteryKwh * 100) / vehicle.consumptionKwhPer100)} km nuvažiuojamo atstumo`}>
          <input type="range" min={5} max={100} value={soc} onChange={(e) => store.setSoc(+e.target.value)} className="w-full" />
          <SocBar value={soc} />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Iš">
            <select className={inputClass} value={originId} onChange={(e) => setOriginId(e.target.value)}>
              {places.map((p) => (
                <option key={p.id} value={p.id}>{p.name}</option>
              ))}
            </select>
          </Field>
          <Field label="Į">
            <select className={inputClass} value={destId} onChange={(e) => setDestId(e.target.value)}>
              {places.map((p) => (
                <option key={p.id} value={p.id}>{p.name}</option>
              ))}
            </select>
          </Field>
        </div>
        <Button className="w-full" onClick={run} disabled={!ready || originId === destId}>
          Planuoti kelionę
        </Button>
      </Card>

      {plan && (
        <>
          <SectionTitle>Planas</SectionTitle>
          {!plan.feasible && (
            <Card className="mb-3 border-[var(--bad)] text-sm">
              <strong>Kelionės suplanuoti nepavyko.</strong> {plan.message}
            </Card>
          )}
          <Card>
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              <Stat label="Atstumas" value={`${plan.totalKm} km`} />
              <Stat label="Kelionės laikas" value={minutes(plan.driveMinutes + plan.chargeMinutes)} sub={`iš jų krovimas ${minutes(plan.chargeMinutes)}`} />
              <Stat label="Atvyksite" value={clock(plan.arriveAt)} sub={`su ${plan.arriveSoc} % baterija`} />
              <Stat label="Įkrovimų kaina" value={eur(plan.costEur)} sub={stopsLabel(plan.stops.length)} />
            </div>
          </Card>

          <div className="mt-3 h-72 overflow-hidden rounded-2xl">
            <MapView className="h-full w-full" stations={stations} stops={plan.stops.map((s) => s.station)} route={route} fit={route} />
          </div>

          <ol className="mt-3 space-y-2">
            <TimelineRow title={origin.name} sub={`Išvykimas ${clock(new Date())} · ${soc} %`} />
            {plan.stops.map((s, i) => (
              <li key={s.station.id}>
                <Card>
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="text-xs text-[var(--muted)]">
                        {i + 1} sustojimas · po {s.distanceFromPrevKm} km · {getOperator(s.station.operatorId).name}
                      </div>
                      <Link href={`/stations/${s.station.id}`} className="font-semibold hover:underline">
                        {s.station.name}
                      </Link>
                      <div className="text-xs text-[var(--muted)]">{s.connector.type} · {s.connector.powerKw} kW</div>
                    </div>
                    <Badge color={s.freeProbability > 0.7 ? "var(--ok)" : s.freeProbability > 0.4 ? "var(--warn)" : "var(--bad)"}>
                      laisva {pct(s.freeProbability)}
                    </Badge>
                  </div>
                  <div className="mt-3 grid grid-cols-3 gap-3 text-sm">
                    <Stat label="Atvykimas" value={clock(s.arriveAt)} sub={`${s.arriveSoc} %`} />
                    <Stat label="Krautis" value={minutes(s.chargeMinutes)} sub={`iki ${s.departSoc} %`} />
                    <Stat label="Kaina" value={eur(s.costEur)} sub={`${s.energyKwh} kWh`} />
                  </div>
                </Card>
              </li>
            ))}
            <TimelineRow title={dest.name} sub={`Atvykimas ${clock(plan.arriveAt)} · ${plan.arriveSoc} %`} />
          </ol>
        </>
      )}
    </div>
  );
}

function TimelineRow({ title, sub }: { title: string; sub: string }) {
  return (
    <li className="flex items-center gap-3 px-2">
      <span className="h-3 w-3 rounded-full bg-[var(--brand)]" />
      <div>
        <div className="font-semibold">{title}</div>
        <div className="text-xs text-[var(--muted)]">{sub}</div>
      </div>
    </li>
  );
}

function stopsLabel(n: number): string {
  if (n === 0) return "be sustojimų";
  if (n % 10 === 1 && n % 100 !== 11) return `${n} sustojimas`;
  if (n % 10 >= 2 && n % 10 <= 9 && (n % 100 < 11 || n % 100 > 19)) return `${n} sustojimai`;
  return `${n} sustojimų`;
}
