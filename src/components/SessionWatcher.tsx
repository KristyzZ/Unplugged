"use client";

// Runs on every page: turns the simulated clock into session events
// (charging finished → notification, grace period over → idle fee starts).

import { useEffect, useRef } from "react";
import { useStore } from "@/lib/store";

export function SessionWatcher() {
  const { session, simNow, updateSession, notify } = useStore();
  const graceNotified = useRef<number | null>(null);

  useEffect(() => {
    if (!session || session.endedAt) return;
    const id = setInterval(() => {
      const now = simNow();
      const doneTarget = session.startedAt + session.minutesToTarget * 60_000;
      if (!session.doneAt && now >= doneTarget) {
        updateSession({ doneAt: doneTarget });
        notify(
          "Įkrovimas baigtas",
          `Turite ${session.graceMinutes} min. patraukti automobilį. Po to skaičiuojamas prastovos mokestis.`,
        );
      }
      if (session.doneAt && graceNotified.current !== session.doneAt && now >= session.doneAt + session.graceMinutes * 60_000) {
        graceNotified.current = session.doneAt;
        notify("Pradėtas skaičiuoti prastovos mokestis", "Kuo ilgiau stovite, tuo didesnis tarifas.");
      }
    }, 500);
    return () => clearInterval(id);
  }, [session, simNow, updateSession, notify]);

  return null;
}
