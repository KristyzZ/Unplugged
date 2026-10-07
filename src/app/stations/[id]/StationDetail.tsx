"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { OccupancyChart } from "@/components/OccupancyChart";
import { Badge, Button, ButtonLink, Card, Dot, Empty, PageHeader, SectionTitle, SocBar, Stat } from "@/components/ui";
import { getOperator } from "@/lib/data/stations";
import { getVehicle } from "@/lib/data/vehicles";
import { clock, eur, levelColor, levelLabel, minutes, pct, statusColor, statusLabel } from "@/lib/format";
import {
  availabilityLevel,
  bestHourAhead,
  countByStatus,
  demandLevel,
  freeCount,
  probabilityFreeAt,
  workingCount,
} from "@/lib/logic/availability";
import { chargeTime, compatible, effectivePeakKw } from "@/lib/logic/charging";
import { FEE_TIERS, gracePeriodMinutes } from "@/lib/logic/idleFee";
import { useStore } from "@/lib/store";
import { useNow } from "@/lib/useNow";
import type { Connector } from "@/lib/types";

export function StationDetail({ id }: { id: string }) {
  const router = useRouter();
  const store = useStore();
  const { stations, vehicleId, soc, session, queue, ready } = store;
  const station = stations.find((s) => s.id === id);
  const [picked, setPicked] = useState<Connector | null>(null);
  const [target, setTarget] = useState(80);
  const now = useNow(30_000);

  if (!ready || now === 0) return <div className="h-40 animate-pulse rounded-2xl bg-[var(--surface-2)]" />;
  if (!station) return <Empty title="Stotelė nerasta" />;

  const vehicle = getVehicle(vehicleId);
  const op = getOperator(station.operatorId);
  const hour = new Date(now).getHours();
  const level = availabilityLevel(station);
  const counts = countByStatus(station);
  const demand = demandLevel(station, hour);
  const grace = gracePeriodMinutes(demand);
  const best = bestHourAhead(station, hour);
  const pNow = probabilityFreeAt(station, hour);
  const busy = session && !session.endedAt;
  const inQueue = queue?.stationId === station.id;
  const estimate = picked ? chargeTime(vehicle, picked, soc, target) : null;

  function start() {
    if (!picked || !estimate || !station) return;
    store.startSession({
      stationId: station.id,
      connectorId: picked.id,
      startSoc: soc,
      targetSoc: target,
      minutesToTarget: Math.max(1, estimate.minutes),
      graceMinutes: grace,
      pricePerKwh: station.pricePerKwh,
    });
    router.push("/session");
  }

  return (
    <div>
      <PageHeader
        back="/"
        title={station.name}
        subtitle={
          <span className="flex items-center gap-1.5">
            <Dot color={op.color} className="h-2 w-2" /> {op.name} · {station.address}, {station.city}
          </span>
        }
      />

      <Card>
        <div className="flex items-start justify-between">
          <div>
            <Badge color={levelColor[level]}>{levelLabel[level]}</Badge>
            <div className="mt-2 text-3xl font-bold">
              {freeCount(station)}
              <span className="text-lg font-medium text-[var(--muted)]">/{workingCount(station)} laisvos</span>
            </div>
          </div>
          <div className="text-right">
            <div className="text-2xl font-bold">{station.pricePerKwh.toFixed(2)} €</div>
            <div className="text-xs text-[var(--muted)]">už kWh</div>
          </div>
        </div>
        <div className="mt-4 grid grid-cols-3 gap-3 border-t border-[var(--line)] pt-3">
          <Stat label="Kraunasi" value={counts.charging} />
          <Stat label="Baigė, stovi" value={counts.idle} />
          <Stat label="Užimta be įkrovimo" value={counts.blocked} />
        </div>
        <div className="mt-4 flex gap-2">
          <ButtonLink
            variant="secondary"
            className="flex-1"
            href={`https://www.google.com/maps/dir/?api=1&destination=${station.lat},${station.lng}`}
            target="_blank"
          >
            Maršrutas
          </ButtonLink>
          <ButtonLink variant="secondary" className="flex-1" href={`/report?station=${station.id}`}>
            Pranešti apie pažeidimą
          </ButtonLink>
        </div>
      </Card>

      {freeCount(station) === 0 && (
        <Card className="mt-3 border-[var(--warn)]">
          <div className="font-semibold">Visos vietos užimtos</div>
          <p className="mt-1 text-sm text-[var(--muted)]">
            Prisijunkite prie virtualios eilės — pranešime, kai atsilaisvins vieta. Artimiausia laisva vieta tikėtina per{" "}
            {minutes(Math.min(...station.connectors.map((c) => c.etaMinutes ?? 60)))}
          </p>
          <div className="mt-3">
            {inQueue ? (
              <div className="flex items-center justify-between">
                <span className="text-sm">Esate eilėje: <strong>{queue.position} vieta</strong></span>
                <Button variant="ghost" onClick={store.leaveQueue}>Palikti eilę</Button>
              </div>
            ) : (
              <Button
                onClick={() => {
                  store.joinQueue(station.id);
                  store.notify("Prisijungėte prie eilės", `${station.name}: pranešime, kai atsilaisvins vieta.`);
                }}
              >
                Stoti į eilę
              </Button>
            )}
          </div>
        </Card>
      )}

      <SectionTitle>Jungtys</SectionTitle>
      <div className="flex flex-col gap-2">
        {station.connectors.map((c) => {
          const ok = compatible(vehicle, c);
          const selectable = ok && c.status === "available" && !busy;
          return (
            <button
              key={c.id}
              disabled={!selectable}
              onClick={() => setPicked(c)}
              className={`flex items-center gap-3 rounded-2xl border bg-[var(--surface)] p-3 text-left disabled:opacity-60 ${
                picked?.id === c.id ? "border-[var(--brand)] ring-2 ring-[var(--brand)]/20" : "border-[var(--line)]"
              }`}
            >
              <Dot color={statusColor[c.status]} />
              <div className="flex-1">
                <div className="font-medium">
                  {c.type} · {c.powerKw} kW
                </div>
                <div className="text-xs text-[var(--muted)]">
                  {statusLabel[c.status]}
                  {c.status === "charging" && c.etaMinutes && ` · atsilaisvins ~${clock(now + c.etaMinutes * 60_000)}`}
                  {c.status === "idle" && c.idleMinutes && ` · stovi jau ${c.idleMinutes} min.`}
                  {!ok && " · netinka jūsų automobiliui"}
                </div>
              </div>
              {ok && <span className="text-xs text-[var(--muted)]">iki {effectivePeakKw(vehicle, c)} kW</span>}
            </button>
          );
        })}
      </div>

      {picked && estimate && (
        <Card className="mt-3">
          <div className="font-semibold">Įkrovimas: {vehicle.name}</div>
          <div className="mt-3 flex items-center justify-between text-sm">
            <span>Dabar {soc} %</span>
            <span>Iki {target} %</span>
          </div>
          <SocBar value={soc} target={target} className="mt-1" />
          <input type="range" min={Math.min(100, soc + 5)} max={100} value={target} onChange={(e) => setTarget(+e.target.value)} className="mt-3 w-full" />
          <div className="mt-3 grid grid-cols-3 gap-3">
            <Stat label="Trukmė" value={minutes(estimate.minutes)} sub={`baigsis ~${clock(now + estimate.minutes * 60_000)}`} />
            <Stat label="Energija" value={`${estimate.kwh} kWh`} />
            <Stat label="Kaina" value={eur(estimate.kwh * station.pricePerKwh)} />
          </div>
          <p className="mt-3 rounded-xl bg-[var(--surface-2)] p-3 text-xs text-[var(--muted)]">
            Baigus įkrovimą turėsite <strong>{grace} min.</strong> patraukti automobilį (dabartinė paklausa {pct(demand)}). Vėliau
            prastovos mokestis didėja: {FEE_TIERS.map((t) => `${t.eurPerMin.toFixed(2)} €`).join(" → ")} per min. Patraukę laiku gausite taškų.
          </p>
          <Button className="mt-3 w-full" onClick={start}>
            Pradėti ir mokėti per Unplugged
          </Button>
        </Card>
      )}
      {busy && (
        <p className="mt-2 text-sm text-[var(--muted)]">
          Jau turite aktyvų įkrovimą. <Link href="/session" className="text-[var(--brand)]">Peržiūrėti</Link>
        </p>
      )}

      <SectionTitle>Užimtumas pagal valandas</SectionTitle>
      <Card>
        <OccupancyChart values={station.hourlyOccupancy} currentHour={hour} highlight={best !== hour ? best : undefined} />
        <div className="mt-3 grid grid-cols-2 gap-3 border-t border-[var(--line)] pt-3">
          <Stat label="Įprastai šiuo metu laisva vieta" value={pct(pNow)} />
          <Stat
            label="Geriausias laikas per 6 val."
            value={`${String(best).padStart(2, "0")}:00`}
            sub={`tikimybė ${pct(probabilityFreeAt(station, best))}`}
          />
        </div>
      </Card>

      {station.amenities && (
        <>
          <SectionTitle>Šalia</SectionTitle>
          <div className="flex flex-wrap gap-2">
            {station.amenities.map((a) => (
              <Badge key={a}>{a}</Badge>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
