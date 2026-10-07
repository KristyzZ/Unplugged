"use client";

import { Badge, Button, ButtonLink, Card, Chip, Empty, PageHeader, SectionTitle, SocBar, Stat } from "@/components/ui";
import { getVehicle } from "@/lib/data/vehicles";
import { clock, eur, minutes, mmss } from "@/lib/format";
import { currentRate, FEE_CAP_EUR, FEE_TIERS, idleFee } from "@/lib/logic/idleFee";
import { pointsForMove, REASON_LABEL } from "@/lib/logic/points";
import { useStore } from "@/lib/store";
import { useNow } from "@/lib/useNow";

const SPEEDS = [1, 10, 60, 300];

export default function SessionPage() {
  const store = useStore();
  const { session, stations, simNow, speed, ready } = store;
  const now = useNow(250, simNow);

  if (!ready || now === 0) return <div className="h-40 animate-pulse rounded-2xl bg-[var(--surface-2)]" />;

  if (!session) {
    return (
      <div>
        <PageHeader title="Įkrovimas" />
        <Empty title="Šiuo metu nesikraunate">Pasirinkite stotelę žemėlapyje ir pradėkite įkrovimą — atsiskaitysite čia pat.</Empty>
        <ButtonLink href="/" className="mt-4 w-full">Rasti stotelę</ButtonLink>
      </div>
    );
  }

  const s = session;
  const station = stations.find((x) => x.id === s.stationId);
  const connector = station?.connectors.find((c) => c.id === s.connectorId);
  const vehicle = getVehicle(store.vehicleId);

  const chargeEnd = s.doneAt ?? Math.min(now, s.startedAt + s.minutesToTarget * 60_000);
  const progress = Math.max(0, Math.min(1, (chargeEnd - s.startedAt) / (s.minutesToTarget * 60_000)));
  const soc = s.startSoc + (s.targetSoc - s.startSoc) * progress;
  const kwh = (((soc - s.startSoc) / 100) * vehicle.batteryKwh) / 0.92;
  const energyCost = kwh * s.pricePerKwh;

  const ref = s.endedAt ?? now;
  const sinceDone = s.doneAt ? ref - s.doneAt : 0;
  const graceMs = s.graceMinutes * 60_000;
  const inGrace = !!s.doneAt && sinceDone < graceMs;
  const idleMin = s.doneAt ? Math.max(0, (sinceDone - graceMs) / 60_000) : 0;
  const fee = s.idleFeeEur ?? idleFee(idleMin);

  const phase = s.endedAt ? "ended" : !s.doneAt ? "charging" : inGrace ? "grace" : "idle";

  function stop() {
    store.updateSession({ doneAt: simNow() });
    store.notify("Įkrovimas sustabdytas", `Turite ${s.graceMinutes} min. patraukti automobilį.`);
  }

  function leave() {
    const t = simNow();
    const doneAt = s.doneAt ?? t;
    const minsAfter = (t - doneAt) / 60_000;
    const idle = Math.max(0, minsAfter - s.graceMinutes);
    const { points, reason } = pointsForMove(minsAfter, s.graceMinutes);
    store.updateSession({ doneAt, endedAt: t, idleFeeEur: idleFee(idle), pointsEarned: points });
    store.setSoc(Math.round(soc));
    if (reason) {
      store.addPoints(reason, points, station?.name);
      store.notify(`+${points} tšk.`, REASON_LABEL[reason]);
    }
  }

  return (
    <div>
      <PageHeader title="Įkrovimas" subtitle={`${station?.name ?? s.stationId} · ${connector?.type ?? ""} ${connector?.powerKw ?? ""} kW`} />

      <Card>
        <div className="flex items-center justify-between">
          {phase === "charging" && <Badge color="var(--info)">Kraunasi</Badge>}
          {phase === "grace" && <Badge color="var(--warn)">Baigta — patraukite automobilį</Badge>}
          {phase === "idle" && <Badge color="var(--bad)">Skaičiuojamas prastovos mokestis</Badge>}
          {phase === "ended" && <Badge color="var(--ok)">Užbaigta</Badge>}
          <span className="text-sm text-[var(--muted)]">pradėta {clock(s.startedAt)}</span>
        </div>

        <div className="mt-4 text-5xl font-bold">{Math.round(soc)} %</div>
        <SocBar value={soc} target={s.targetSoc} className="mt-3" />
        <div className="mt-1 flex justify-between text-xs text-[var(--muted)]">
          <span>{s.startSoc} %</span>
          <span>tikslas {s.targetSoc} %</span>
        </div>

        <div className="mt-4 grid grid-cols-3 gap-3 border-t border-[var(--line)] pt-3">
          <Stat label="Energija" value={`${kwh.toFixed(1)} kWh`} />
          <Stat label="Kaina" value={eur(energyCost)} />
          {phase === "charging" ? (
            <Stat label="Liko" value={minutes((s.startedAt + s.minutesToTarget * 60_000 - now) / 60_000)} />
          ) : (
            <Stat label="Prastovos mokestis" value={eur(fee)} />
          )}
        </div>
      </Card>

      {phase === "grace" && (
        <Card className="mt-3 border-[var(--warn)] text-center">
          <div className="text-sm text-[var(--muted)]">Nemokamas laikas patraukti automobilį</div>
          <div className="my-2 text-5xl font-bold tabular-nums">{mmss(graceMs - sinceDone)}</div>
          <div className="text-sm">Patraukite per 2 min. ir gausite <strong>30 tšk.</strong>, per „grace period“ — <strong>20 tšk.</strong></div>
        </Card>
      )}

      {phase === "idle" && (
        <Card className="mt-3 border-[var(--bad)]">
          <div className="flex items-baseline justify-between">
            <span className="font-semibold">Stovite be reikalo {minutes(idleMin)}</span>
            <span className="text-sm text-[var(--muted)]">{currentRate(idleMin).toFixed(2)} €/min.</span>
          </div>
          <div className="mt-3 flex gap-1">
            {FEE_TIERS.map((t, i) => {
              const active = currentRate(idleMin) === t.eurPerMin;
              const end = FEE_TIERS[i + 1]?.fromMin;
              return (
                <div key={t.fromMin} className={`flex-1 rounded-lg p-2 text-center text-xs ${active ? "bg-[var(--bad)] text-white" : "bg-[var(--surface-2)]"}`}>
                  <div className="font-semibold">{t.eurPerMin.toFixed(2)} €/min.</div>
                  <div className="opacity-80">{end ? `${t.fromMin}–${end} min.` : `${t.fromMin}+ min.`}</div>
                </div>
              );
            })}
          </div>
          <p className="mt-2 text-xs text-[var(--muted)]">Maksimalus mokestis {eur(FEE_CAP_EUR)}. Kiti vairuotojai laukia šios vietos.</p>
        </Card>
      )}

      {phase === "ended" && (
        <Card className="mt-3">
          <div className="font-semibold">Kvitas</div>
          <div className="mt-2 space-y-1 text-sm">
            <Row label={`Įkrovimas (${kwh.toFixed(1)} kWh × ${s.pricePerKwh.toFixed(2)} €)`} value={eur(energyCost)} />
            <Row label="Prastovos mokestis" value={eur(fee)} />
            <div className="border-t border-[var(--line)] pt-1">
              <Row label={<strong>Iš viso</strong>} value={<strong>{eur(energyCost + fee)}</strong>} />
            </div>
            {!!s.pointsEarned && <Row label="Gauta taškų" value={`+${s.pointsEarned}`} />}
          </div>
        </Card>
      )}

      <div className="mt-4 flex flex-col gap-2">
        {phase === "charging" && (
          <Button variant="secondary" onClick={stop}>Sustabdyti įkrovimą</Button>
        )}
        {(phase === "grace" || phase === "idle") && <Button onClick={leave}>Patraukiau automobilį</Button>}
        {phase === "ended" && <Button onClick={store.clearSession}>Baigti</Button>}
      </div>

      <SectionTitle>Demo: laiko pagreitis</SectionTitle>
      <div className="flex gap-2">
        {SPEEDS.map((x) => (
          <Chip key={x} active={speed === x} onClick={() => store.setSpeed(x)}>
            {x}×
          </Chip>
        ))}
      </div>
      <p className="mt-2 text-xs text-[var(--muted)]">Pagreitinkite laiką, kad pamatytumėte pranešimą, „grace period“ ir didėjantį mokestį.</p>
    </div>
  );
}

function Row({ label, value }: { label: React.ReactNode; value: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-4">
      <span className="text-[var(--muted)]">{label}</span>
      <span>{value}</span>
    </div>
  );
}
