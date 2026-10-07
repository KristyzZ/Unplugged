// Rewards: responsible behaviour earns points that convert into discounts.

export type PointsReason =
  | "moved_fast" // moved within 2 min of the "charging finished" notification
  | "moved_in_grace" // moved before the grace period ended
  | "off_peak" // charged in a low-demand hour
  | "report_confirmed" // abuse report verified
  | "confirm_report" // helped verify someone else's report
  | "redeem";

export const POINTS: Record<Exclude<PointsReason, "redeem">, number> = {
  moved_fast: 30,
  moved_in_grace: 20,
  off_peak: 10,
  report_confirmed: 15,
  confirm_report: 5,
};

export const REASON_LABEL: Record<PointsReason, string> = {
  moved_fast: "Automobilis patrauktas per 2 min.",
  moved_in_grace: "Automobilis patrauktas per „grace period“",
  off_peak: "Įkrovimas ne piko metu",
  report_confirmed: "Patvirtintas pranešimas",
  confirm_report: "Padėjote patvirtinti pranešimą",
  redeem: "Iškeista į privalumą",
};

/** Points for leaving the spot `minutesAfterDone` minutes after charging finished. */
export function pointsForMove(minutesAfterDone: number, graceMinutes: number): { points: number; reason?: PointsReason } {
  if (minutesAfterDone <= 2) return { points: POINTS.moved_fast, reason: "moved_fast" };
  if (minutesAfterDone <= graceMinutes) return { points: POINTS.moved_in_grace, reason: "moved_in_grace" };
  return { points: 0 };
}

export interface Reward {
  id: string;
  title: string;
  partner: string;
  cost: number;
}

export const rewards: Reward[] = [
  { id: "coffee", title: "Nemokama kava", partner: "Partnerio kavinė", cost: 80 },
  { id: "kwh-5", title: "−5 % kitam įkrovimui", partner: "Unplugged", cost: 100 },
  { id: "eur-2", title: "2 € įkrovimo nuolaida", partner: "Unplugged", cost: 200 },
  { id: "wash", title: "−50 % automobilio plovimui", partner: "Partnerio plovykla", cost: 250 },
  { id: "kwh-20", title: "−20 % visiems įkrovimams savaitę", partner: "Unplugged", cost: 600 },
];

export type Tier = { name: string; min: number };
export const tiers: Tier[] = [
  { name: "Bronza", min: 0 },
  { name: "Sidabras", min: 300 },
  { name: "Auksas", min: 1000 },
];

export function tierFor(lifetimePoints: number): { tier: Tier; next?: Tier } {
  let idx = 0;
  tiers.forEach((t, i) => {
    if (lifetimePoints >= t.min) idx = i;
  });
  return { tier: tiers[idx], next: tiers[idx + 1] };
}
