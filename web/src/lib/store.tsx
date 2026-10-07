"use client";

// Client-side app state for the prototype (no backend yet). Persisted to
// localStorage so a page refresh during a demo keeps the session and points.

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { getStations } from "./data/stations";
import type { PointsReason } from "./logic/points";
import type { AbuseReport } from "./logic/reports";
import type { Station } from "./types";

export interface ChargingSession {
  stationId: string;
  connectorId: string;
  startedAt: number; // sim ms
  startSoc: number;
  targetSoc: number;
  minutesToTarget: number;
  graceMinutes: number;
  pricePerKwh: number;
  doneAt?: number; // sim ms when charging finished or was stopped
  endedAt?: number; // sim ms when the car left the spot
  idleFeeEur?: number;
  pointsEarned?: number;
}

export interface PointsEntry {
  reason: PointsReason;
  points: number;
  at: number;
  note?: string;
}

export interface QueueEntry {
  stationId: string;
  joinedAt: number;
  position: number;
}

export interface Toast {
  id: number;
  title: string;
  body?: string;
}

interface PersistedState {
  vehicleId: string;
  soc: number;
  points: number;
  lifetimePoints: number;
  history: PointsEntry[];
  session: ChargingSession | null;
  queue: QueueEntry | null;
  reports: AbuseReport[];
}

const initial: PersistedState = {
  vehicleId: "ioniq5",
  soc: 34,
  points: 120,
  lifetimePoints: 240,
  history: [
    { reason: "moved_fast", points: 30, at: Date.now() - 86_400_000 * 2 },
    { reason: "off_peak", points: 10, at: Date.now() - 86_400_000 * 2 },
  ],
  session: null,
  queue: null,
  reports: [
    { id: "r-demo", stationId: "europa", plate: "KLM 482", description: "Benzininis automobilis stovi įkrovimo vietoje nuo ryto.", hasPhoto: true, telemetryMatches: false, confirmations: 1, createdAt: Date.now() - 3_600_000, byMe: false },
  ],
};

interface Store extends PersistedState {
  /** False during SSR and the first client render. */
  ready: boolean;
  stations: Station[];
  tick: number;
  /** Demo time multiplier for the charging simulation (1 = real time). */
  speed: number;
  simNow: () => number;
  toasts: Toast[];
  setVehicle: (id: string) => void;
  setSoc: (soc: number) => void;
  setSpeed: (s: number) => void;
  addPoints: (reason: PointsReason, points: number, note?: string) => void;
  spendPoints: (cost: number, note: string) => boolean;
  startSession: (s: Omit<ChargingSession, "startedAt">) => void;
  updateSession: (patch: Partial<ChargingSession>) => void;
  clearSession: () => void;
  joinQueue: (stationId: string) => void;
  leaveQueue: () => void;
  addReport: (r: AbuseReport) => void;
  confirmReport: (id: string) => void;
  notify: (title: string, body?: string) => void;
  dismissToast: (id: number) => void;
  reset: () => void;
}

const Ctx = createContext<Store | null>(null);
const KEY = "unplugged:v1";

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<PersistedState>(initial);
  const [loaded, setLoaded] = useState(false);
  const [tick, setTick] = useState(0);
  const [speed, setSpeed] = useState(1);
  const [toasts, setToasts] = useState<Toast[]>([]);

  // Simulated clock: advances `speed` times faster than real time.
  const sim = useRef({ realAnchor: 0, simAnchor: 0, speed: 1 });
  const simNow = useCallback(() => {
    const s = sim.current;
    if (s.realAnchor === 0) return Date.now();
    return s.simAnchor + (Date.now() - s.realAnchor) * s.speed;
  }, []);
  const changeSpeed = useCallback(
    (next: number) => {
      const now = simNow();
      sim.current = { realAnchor: Date.now(), simAnchor: now, speed: next };
      setSpeed(next);
    },
    [simNow],
  );

  useEffect(() => {
    sim.current = { realAnchor: Date.now(), simAnchor: Date.now(), speed: 1 };
    try {
      const raw = localStorage.getItem(KEY);
      // Hydrating from localStorage has to happen after mount (SSR has no storage).
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (raw) setState({ ...initial, ...JSON.parse(raw) });
    } catch {}
    setLoaded(true);
    // "Real-time" station updates every 20 s.
    const id = setInterval(() => setTick((t) => t + 1), 20_000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (!loaded) return;
    try {
      localStorage.setItem(KEY, JSON.stringify(state));
    } catch {}
  }, [state, loaded]);

  // Computed only after mount: station state depends on the local hour, so
  // rendering it on the server would cause hydration mismatches.
  const stations = useMemo(() => (loaded ? getStations(new Date(), tick) : []), [loaded, tick]);

  const notify = useCallback((title: string, body?: string) => {
    const id = Date.now() + Math.random();
    setToasts((t) => [...t, { id, title, body }]);
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 6000);
  }, []);

  const value: Store = {
    ...state,
    ready: loaded,
    stations,
    tick,
    speed,
    simNow,
    toasts,
    setVehicle: (vehicleId) => setState((s) => ({ ...s, vehicleId })),
    setSoc: (soc) => setState((s) => ({ ...s, soc })),
    setSpeed: changeSpeed,
    addPoints: (reason, points, note) =>
      setState((s) => ({
        ...s,
        points: s.points + points,
        lifetimePoints: s.lifetimePoints + points,
        history: [{ reason, points, at: Date.now(), note }, ...s.history],
      })),
    spendPoints: (cost, note) => {
      if (state.points < cost) return false;
      setState((s) => ({
        ...s,
        points: s.points - cost,
        history: [{ reason: "redeem", points: -cost, at: Date.now(), note }, ...s.history],
      }));
      return true;
    },
    startSession: (session) => setState((s) => ({ ...s, session: { ...session, startedAt: simNow() }, queue: null })),
    updateSession: (patch) => setState((s) => (s.session ? { ...s, session: { ...s.session, ...patch } } : s)),
    clearSession: () => setState((s) => ({ ...s, session: null })),
    joinQueue: (stationId) => setState((s) => ({ ...s, queue: { stationId, joinedAt: Date.now(), position: 2 } })),
    leaveQueue: () => setState((s) => ({ ...s, queue: null })),
    addReport: (r) => setState((s) => ({ ...s, reports: [r, ...s.reports] })),
    confirmReport: (id) =>
      setState((s) => ({ ...s, reports: s.reports.map((r) => (r.id === id ? { ...r, confirmations: r.confirmations + 1 } : r)) })),
    notify,
    dismissToast: (id) => setToasts((t) => t.filter((x) => x.id !== id)),
    reset: () => {
      setState(initial);
      changeSpeed(1);
    },
  };

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useStore(): Store {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useStore must be used inside <StoreProvider>");
  return ctx;
}
