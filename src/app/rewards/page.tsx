"use client";

import { Button, Card, PageHeader, SectionTitle, SocBar } from "@/components/ui";
import { POINTS, REASON_LABEL, rewards, tierFor } from "@/lib/logic/points";
import { useStore } from "@/lib/store";

export default function RewardsPage() {
  const store = useStore();
  const { points, lifetimePoints, history, ready } = store;
  const { tier, next } = tierFor(lifetimePoints);

  return (
    <div>
      <PageHeader title="Taškai ir privalumai" subtitle="Atsakingai naudodamiesi stotelėmis renkate taškus ir keičiate juos į nuolaidas." />

      <Card>
        <div className="text-sm text-[var(--muted)]">Jūsų taškai</div>
        <div className="text-5xl font-bold">{ready ? points : "—"}</div>
        <div className="mt-3 flex items-center justify-between text-sm">
          <span className="font-medium">{tier.name}</span>
          {next && <span className="text-[var(--muted)]">iki „{next.name}“ liko {next.min - lifetimePoints}</span>}
        </div>
        {next && <SocBar value={((lifetimePoints - tier.min) / (next.min - tier.min)) * 100} className="mt-1" />}
      </Card>

      <SectionTitle>Kaip uždirbti</SectionTitle>
      <Card className="divide-y divide-[var(--line)] p-0">
        {(Object.keys(POINTS) as (keyof typeof POINTS)[]).map((k) => (
          <div key={k} className="flex items-center justify-between px-4 py-3 text-sm">
            <span>{REASON_LABEL[k]}</span>
            <span className="font-semibold text-[var(--ok)]">+{POINTS[k]}</span>
          </div>
        ))}
      </Card>

      <SectionTitle>Iškeisti</SectionTitle>
      <div className="grid gap-2 sm:grid-cols-2">
        {rewards.map((r) => (
          <Card key={r.id} className="flex items-center justify-between gap-3">
            <div>
              <div className="font-semibold">{r.title}</div>
              <div className="text-xs text-[var(--muted)]">{r.partner}</div>
            </div>
            <Button
              variant={points >= r.cost ? "primary" : "secondary"}
              disabled={points < r.cost}
              onClick={() => {
                if (store.spendPoints(r.cost, r.title)) store.notify("Privalumas aktyvuotas", r.title);
              }}
            >
              {r.cost} tšk.
            </Button>
          </Card>
        ))}
      </div>

      <SectionTitle>Istorija</SectionTitle>
      <Card className="divide-y divide-[var(--line)] p-0">
        {history.length === 0 && <div className="px-4 py-3 text-sm text-[var(--muted)]">Kol kas nieko.</div>}
        {history.slice(0, 20).map((h, i) => (
          <div key={i} className="flex items-center justify-between px-4 py-3 text-sm">
            <div>
              <div>{h.note && h.reason === "redeem" ? h.note : REASON_LABEL[h.reason]}</div>
              <div className="text-xs text-[var(--muted)]">
                {ready ? new Date(h.at).toLocaleDateString("lt-LT") : ""}
                {h.note && h.reason !== "redeem" ? ` · ${h.note}` : ""}
              </div>
            </div>
            <span className={`font-semibold ${h.points > 0 ? "text-[var(--ok)]" : ""}`}>
              {h.points > 0 ? "+" : ""}
              {h.points}
            </span>
          </div>
        ))}
      </Card>
    </div>
  );
}
