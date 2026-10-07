// Idle-fee rules: after charging ends the driver gets a grace period, then a
// progressively growing per-minute fee. All values are tunable policy knobs.

export const GRACE_MIN = 5;
export const GRACE_MAX = 15;

/**
 * Dynamic grace period. Low demand → 15 min, high demand → 5 min.
 * `demand` is 0–1 (see availability.demandLevel).
 */
export function gracePeriodMinutes(demand: number): number {
  const d = Math.min(1, Math.max(0, demand));
  if (d <= 0.4) return GRACE_MAX;
  if (d >= 0.9) return GRACE_MIN;
  const t = (d - 0.4) / 0.5;
  return Math.round(GRACE_MAX - t * (GRACE_MAX - GRACE_MIN));
}

export interface FeeTier {
  /** Tier starts this many minutes after the grace period ends. */
  fromMin: number;
  eurPerMin: number;
}

export const FEE_TIERS: FeeTier[] = [
  { fromMin: 0, eurPerMin: 0.1 },
  { fromMin: 10, eurPerMin: 0.25 },
  { fromMin: 30, eurPerMin: 0.5 },
];

export const FEE_CAP_EUR = 40;

/** Total idle fee for `minutes` spent idle after the grace period ended. */
export function idleFee(minutes: number, tiers: FeeTier[] = FEE_TIERS): number {
  if (minutes <= 0) return 0;
  let total = 0;
  for (let i = 0; i < tiers.length; i++) {
    const start = tiers[i].fromMin;
    const end = i + 1 < tiers.length ? tiers[i + 1].fromMin : Infinity;
    if (minutes <= start) break;
    total += (Math.min(minutes, end) - start) * tiers[i].eurPerMin;
  }
  return Math.min(FEE_CAP_EUR, Math.round(total * 100) / 100);
}

export function currentRate(minutes: number, tiers: FeeTier[] = FEE_TIERS): number {
  let rate = 0;
  for (const t of tiers) if (minutes >= t.fromMin) rate = t.eurPerMin;
  return rate;
}
