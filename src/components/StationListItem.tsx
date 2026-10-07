import Link from "next/link";
import { getOperator } from "@/lib/data/stations";
import { levelColor, levelLabel, km } from "@/lib/format";
import { availabilityLevel, freeCount, maxPower, workingCount } from "@/lib/logic/availability";
import type { Station } from "@/lib/types";
import { Badge, Dot } from "./ui";

export function StationListItem({ station, distance, selected }: { station: Station; distance?: number; selected?: boolean }) {
  const level = availabilityLevel(station);
  const op = getOperator(station.operatorId);
  return (
    <Link
      href={`/stations/${station.id}`}
      id={`st-${station.id}`}
      className={`flex items-center gap-3 rounded-2xl border bg-[var(--surface)] p-3 transition ${selected ? "border-[var(--brand)]" : "border-[var(--line)]"}`}
    >
      <div className="flex w-12 flex-col items-center">
        <span className="text-lg font-bold leading-none">{maxPower(station)}</span>
        <span className="text-[10px] text-[var(--muted)]">kW</span>
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate font-semibold">{station.name}</div>
        <div className="flex items-center gap-1.5 truncate text-xs text-[var(--muted)]">
          <Dot color={op.color} className="h-2 w-2" />
          {op.name} · {station.address}
        </div>
        <div className="mt-1 flex items-center gap-2 text-xs">
          <Badge color={levelColor[level]}>
            {freeCount(station)}/{workingCount(station)} · {levelLabel[level]}
          </Badge>
          <span className="text-[var(--muted)]">{station.pricePerKwh.toFixed(2)} €/kWh</span>
        </div>
      </div>
      {distance !== undefined && <div className="text-right text-sm font-medium text-[var(--muted)]">{km(distance)}</div>}
    </Link>
  );
}
