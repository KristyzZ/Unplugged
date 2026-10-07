"use client";

import { useMemo, useState } from "react";
import { OccupancyChart } from "@/components/OccupancyChart";
import { Card, PageHeader, SectionTitle, Stat } from "@/components/ui";
import { getOperator, operators } from "@/lib/data/stations";
import { minutes, pct } from "@/lib/format";
import { IDLE_REDUCTION, networkSummary } from "@/lib/logic/analytics";
import { useStore } from "@/lib/store";

export default function OperatorPage() {
  const { stations, ready } = useStore();
  const [city, setCity] = useState("Vilnius");
  const [operator, setOperator] = useState("");
  const [reduction, setReduction] = useState(IDLE_REDUCTION);

  const filtered = useMemo(
    () => stations.filter((s) => (!city || s.city === city) && (!operator || s.operatorId === operator)),
    [stations, city, operator],
  );
  const sum = useMemo(() => (filtered.length ? networkSummary(filtered, reduction) : null), [filtered, reduction]);
  const cities = Array.from(new Set(stations.map((s) => s.city)));
  const top = sum ? [...sum.stations].sort((a, b) => b.avgIdleMin * b.sessionsPerDay - a.avgIdleMin * a.sessionsPerDay) : [];
  const hour = new Date().getHours();

  return (
    <div>
      <PageHeader title="Analitika miestui ir operatoriams" subtitle="Kaip efektyviau išnaudoti jau esamą įkrovimo infrastruktūrą. Demonstraciniai duomenys." />

      <div className="mb-4 flex flex-wrap gap-2">
        <select className="rounded-xl border border-[var(--line)] bg-[var(--surface)] px-3 py-2 text-sm" value={city} onChange={(e) => setCity(e.target.value)}>
          <option value="">Visi miestai</option>
          {cities.map((c) => (
            <option key={c}>{c}</option>
          ))}
        </select>
        <select className="rounded-xl border border-[var(--line)] bg-[var(--surface)] px-3 py-2 text-sm" value={operator} onChange={(e) => setOperator(e.target.value)}>
          <option value="">Visi operatoriai</option>
          {operators.map((o) => (
            <option key={o.id} value={o.id}>{o.name}</option>
          ))}
        </select>
      </div>

      {!ready || !sum ? (
        <div className="h-40 animate-pulse rounded-2xl bg-[var(--surface-2)]" />
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <Card><Stat label="Įkrovimų per dieną" value={sum.sessionsPerDay} sub={`${filtered.length} stotelės`} /></Card>
            <Card><Stat label="Vid. „idle“ laikas" value={minutes(sum.avgIdleMin)} sub={`${Math.round(sum.idleHoursPerDay)} val. per dieną`} /></Card>
            <Card><Stat label="Piktnaudžiavimo atvejai" value={sum.abuseCases7d} sub="per 7 dienas" /></Card>
            <Card className="border-[var(--brand)]"><Stat label="Papildomai aptarnautų vairuotojų" value={`+${sum.extraSessionsPerDay}/d.`} sub="be naujų stotelių" /></Card>
          </div>

          <SectionTitle>Poveikio modelis</SectionTitle>
          <Card>
            <label className="text-sm">
              „Idle“ laiko sumažėjimas dėl grace period, mokesčio ir taškų: <strong>{pct(reduction)}</strong>
            </label>
            <input type="range" min={0.1} max={0.9} step={0.05} value={reduction} onChange={(e) => setReduction(+e.target.value)} className="mt-2 w-full" />
            <div className="mt-4 space-y-2 text-sm">
              <Bar label="Dabar" value={sum.avgIdleMin} max={sum.avgIdleMin} color="var(--bad)" />
              <Bar label="Su Unplugged" value={sum.avgIdleMinAfter} max={sum.avgIdleMin} color="var(--ok)" />
            </div>
            <p className="mt-3 text-xs text-[var(--muted)]">
              Atlaisvinama {Math.round(sum.idleHoursSavedPerDay)} val. stotelių laiko per dieną → ~{sum.extraSessionsPerDay} papildomų įkrovimų iš to paties stotelių skaičiaus.
            </p>
          </Card>

          <SectionTitle>Paklausa pagal valandas</SectionTitle>
          <Card>
            <OccupancyChart values={sum.hourlyDemand} currentHour={hour} />
          </Card>

          <SectionTitle>Stotelės (daugiausia prarasto laiko viršuje)</SectionTitle>
          <Card className="overflow-x-auto p-0">
            <table className="w-full min-w-[640px] text-sm">
              <thead className="text-left text-xs text-[var(--muted)]">
                <tr className="border-b border-[var(--line)]">
                  <th className="px-4 py-2 font-medium">Stotelė</th>
                  <th className="px-2 py-2 font-medium">Operatorius</th>
                  <th className="px-2 py-2 text-right font-medium">Užimtumas</th>
                  <th className="px-2 py-2 text-right font-medium">Įkrovimai/d.</th>
                  <th className="px-2 py-2 text-right font-medium">Vid. krovimas</th>
                  <th className="px-2 py-2 text-right font-medium">Vid. idle</th>
                  <th className="px-4 py-2 text-right font-medium">Pažeidimai 7 d.</th>
                </tr>
              </thead>
              <tbody>
                {top.map((s) => (
                  <tr key={s.station.id} className="border-b border-[var(--line)] last:border-0">
                    <td className="px-4 py-2 font-medium">{s.station.name}</td>
                    <td className="px-2 py-2 text-[var(--muted)]">{getOperator(s.station.operatorId).name}</td>
                    <td className="px-2 py-2 text-right">{pct(s.utilization)}</td>
                    <td className="px-2 py-2 text-right">{s.sessionsPerDay}</td>
                    <td className="px-2 py-2 text-right">{s.avgChargeMin} min.</td>
                    <td className="px-2 py-2 text-right" style={{ color: s.idleShare > 0.3 ? "var(--bad)" : undefined }}>
                      {s.avgIdleMin} min. ({pct(s.idleShare)})
                    </td>
                    <td className="px-4 py-2 text-right">{s.abuseCases7d}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        </>
      )}
    </div>
  );
}

function Bar({ label, value, max, color }: { label: string; value: number; max: number; color: string }) {
  return (
    <div className="flex items-center gap-3">
      <span className="w-28 shrink-0 text-[var(--muted)]">{label}</span>
      <div className="h-6 flex-1 overflow-hidden rounded-lg bg-[var(--surface-2)]">
        <div className="h-full rounded-lg transition-[width]" style={{ width: `${(value / max) * 100}%`, background: color }} />
      </div>
      <span className="w-16 text-right font-semibold">{minutes(value)}</span>
    </div>
  );
}
