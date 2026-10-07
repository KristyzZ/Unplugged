// Abuse reports: a car occupying a charging spot without charging.
// Evidence from several sources builds a confidence score; once it is high
// enough the report is confirmed and a sanction from the ladder applies.

export type ReportStatus = "pending" | "confirmed" | "rejected";

export interface AbuseReport {
  id: string;
  stationId: string;
  plate: string;
  description: string;
  hasPhoto: boolean;
  /** Station telemetry says the bay is occupied but no session is running. */
  telemetryMatches: boolean;
  confirmations: number;
  createdAt: number;
  byMe: boolean;
}

export const CONFIRM_THRESHOLD = 0.7;

export function confidence(r: Pick<AbuseReport, "hasPhoto" | "telemetryMatches" | "confirmations">): number {
  let score = 0.1; // the report itself
  if (r.hasPhoto) score += 0.3;
  if (r.telemetryMatches) score += 0.4;
  score += Math.min(3, r.confirmations) * 0.15;
  return Math.min(1, score);
}

export function reportStatus(r: AbuseReport): ReportStatus {
  return confidence(r) >= CONFIRM_THRESHOLD ? "confirmed" : "pending";
}

/** Sanction for the n-th confirmed offence of the same plate. */
export function sanctionFor(offenceCount: number): string {
  if (offenceCount <= 1) return "Įspėjimas";
  if (offenceCount === 2) return "Bauda 20 €";
  return "Laikinas paskyros apribojimas (7 d.)";
}

/** Light normalisation for Lithuanian plates (e.g. "abc 123" → "ABC123"). */
export function normalizePlate(plate: string): string {
  return plate.toUpperCase().replace(/[^A-Z0-9]/g, "");
}
