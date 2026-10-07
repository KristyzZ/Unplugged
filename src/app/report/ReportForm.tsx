"use client";

import { useSearchParams } from "next/navigation";
import { useState } from "react";
import { Badge, Button, Card, Field, inputClass, PageHeader, SectionTitle, SocBar } from "@/components/ui";
import { POINTS } from "@/lib/logic/points";
import { CONFIRM_THRESHOLD, confidence, normalizePlate, reportStatus, sanctionFor } from "@/lib/logic/reports";
import { useStore } from "@/lib/store";

export function ReportForm() {
  const params = useSearchParams();
  const store = useStore();
  const { stations, reports, ready } = store;
  const [stationId, setStationId] = useState(params.get("station") ?? "");
  const [plate, setPlate] = useState("");
  const [description, setDescription] = useState("");
  const [photo, setPhoto] = useState<string | null>(null);

  const station = stations.find((s) => s.id === stationId);

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!station || !plate) return;
    // Station telemetry: a bay that is occupied without an active session.
    const telemetryMatches = station.connectors.some((c) => c.status === "blocked");
    const report = {
      id: `r-${Date.now()}`,
      stationId: station.id,
      plate: plate.toUpperCase(),
      description,
      hasPhoto: !!photo,
      telemetryMatches,
      confirmations: 0,
      createdAt: Date.now(),
      byMe: true,
    };
    store.addReport(report);
    if (reportStatus(report) === "confirmed") {
      store.addPoints("report_confirmed", POINTS.report_confirmed, station.name);
      store.notify("Pranešimas patvirtintas", `Stotelės duomenys patvirtino pažeidimą. +${POINTS.report_confirmed} tšk.`);
    } else {
      store.notify("Pranešimas išsiųstas", "Laukiame papildomų patvirtinimų.");
    }
    setPlate("");
    setDescription("");
    setPhoto(null);
  }

  return (
    <div>
      <PageHeader
        title="Pranešti apie pažeidimą"
        subtitle="Įkrovimo vietą užima nesikraunantis ar ne elektrinis automobilis? Praneškite — patvirtinti pranešimai padeda taikyti įspėjimus ir baudas."
      />

      <Card>
        <form onSubmit={submit} className="space-y-4">
          <Field label="Stotelė">
            <select className={inputClass} value={stationId} onChange={(e) => setStationId(e.target.value)} required>
              <option value="">Pasirinkite…</option>
              {stations.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name} ({s.city})
                </option>
              ))}
            </select>
          </Field>
          <Field label="Automobilio numeris">
            <input className={inputClass} value={plate} onChange={(e) => setPlate(e.target.value)} placeholder="ABC 123" required />
          </Field>
          <Field label="Kas vyksta?">
            <textarea
              className={inputClass}
              rows={3}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Pvz., benzininis automobilis stovi įkrovimo vietoje"
            />
          </Field>
          <Field label="Nuotrauka" hint="Nuotrauka su matomu numeriu labai padidina patikimumą.">
            <input
              type="file"
              accept="image/*"
              capture="environment"
              className="block w-full text-sm"
              onChange={(e) => {
                const f = e.target.files?.[0];
                setPhoto(f ? URL.createObjectURL(f) : null);
              }}
            />
          </Field>
          {photo && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={photo} alt="Pranešimo nuotrauka" className="h-40 w-full rounded-xl object-cover" />
          )}
          <Button type="submit" className="w-full" disabled={!ready}>
            Pranešti
          </Button>
        </form>
      </Card>

      <SectionTitle>Pranešimai šalia jūsų</SectionTitle>
      <div className="space-y-2">
        {reports.map((r) => {
          const st = stations.find((s) => s.id === r.stationId);
          const conf = confidence(r);
          const status = reportStatus(r);
          const samePlate = reports.filter((x) => normalizePlate(x.plate) === normalizePlate(r.plate) && reportStatus(x) === "confirmed").length;
          return (
            <Card key={r.id}>
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="font-semibold">{r.plate}</div>
                  <div className="text-xs text-[var(--muted)]">{st?.name ?? r.stationId}{r.byMe ? " · jūsų pranešimas" : ""}</div>
                </div>
                <Badge color={status === "confirmed" ? "var(--ok)" : "var(--warn)"}>
                  {status === "confirmed" ? "Patvirtinta" : "Laukia patvirtinimo"}
                </Badge>
              </div>
              {r.description && <p className="mt-2 text-sm">{r.description}</p>}
              <div className="mt-3 flex flex-wrap gap-1.5 text-xs">
                <Badge color={r.hasPhoto ? "var(--ok)" : undefined}>{r.hasPhoto ? "✓" : "–"} Nuotrauka</Badge>
                <Badge color={r.telemetryMatches ? "var(--ok)" : undefined}>{r.telemetryMatches ? "✓" : "–"} Stotelės duomenys</Badge>
                <Badge color={r.confirmations > 0 ? "var(--ok)" : undefined}>{r.confirmations} patvirtinimai</Badge>
              </div>
              <div className="mt-3 flex items-center gap-2 text-xs text-[var(--muted)]">
                <span>Patikimumas</span>
                <SocBar value={conf * 100} target={CONFIRM_THRESHOLD * 100} className="flex-1" />
              </div>
              {status === "confirmed" && <p className="mt-2 text-xs text-[var(--muted)]">Pažeidimas nr. {samePlate} šiam numeriui · taikoma: {sanctionFor(samePlate)}</p>}
              {!r.byMe && status !== "confirmed" && (
                <Button
                  variant="secondary"
                  className="mt-3 w-full"
                  onClick={() => {
                    store.confirmReport(r.id);
                    store.addPoints("confirm_report", POINTS.confirm_report, st?.name);
                    store.notify(`+${POINTS.confirm_report} tšk.`, "Ačiū, kad padėjote patvirtinti.");
                  }}
                >
                  Matau tą patį — patvirtinti
                </Button>
              )}
            </Card>
          );
        })}
      </div>
    </div>
  );
}
