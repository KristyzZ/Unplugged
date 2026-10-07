// 24-hour "usually busy" bar chart from historical occupancy.

export function OccupancyChart({ values, currentHour, highlight }: { values: number[]; currentHour: number; highlight?: number }) {
  return (
    <div>
      <div className="flex h-28 items-end gap-[3px]">
        {values.map((v, h) => {
          const isNow = h === currentHour;
          const isBest = h === highlight;
          const color = isNow ? "var(--brand)" : isBest ? "var(--ok)" : v > 0.75 ? "color-mix(in srgb, var(--bad) 55%, var(--surface-2))" : "color-mix(in srgb, var(--fg) 22%, var(--surface-2))";
          return (
            <div key={h} className="group relative flex h-full flex-1 items-end">
              <div className="w-full rounded-t-sm" style={{ height: `${Math.max(4, v * 100)}%`, background: color }} />
              <div className="pointer-events-none absolute bottom-full left-1/2 mb-1 hidden -translate-x-1/2 whitespace-nowrap rounded bg-[var(--fg)] px-1.5 py-0.5 text-[10px] text-white group-hover:block">
                {String(h).padStart(2, "0")}:00 · {Math.round(v * 100)} %
              </div>
            </div>
          );
        })}
      </div>
      <div className="mt-1 flex justify-between text-[10px] text-[var(--muted)]">
        <span>00</span>
        <span>06</span>
        <span>12</span>
        <span>18</span>
        <span>23</span>
      </div>
    </div>
  );
}
