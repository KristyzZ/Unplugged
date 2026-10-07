"use client";

import { useEffect, useState } from "react";

/**
 * Current time as state, refreshed every `intervalMs`. Returns 0 until
 * mounted so server and client renders match. Pass `source` to read a
 * simulated clock instead of Date.now.
 */
export function useNow(intervalMs = 1000, source: () => number = Date.now): number {
  const [now, setNow] = useState(0);
  useEffect(() => {
    const tick = () => setNow(source());
    const first = setTimeout(tick, 0);
    const id = setInterval(tick, intervalMs);
    return () => {
      clearTimeout(first);
      clearInterval(id);
    };
  }, [intervalMs, source]);
  return now;
}
