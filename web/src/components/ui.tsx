// Minimal, unstyled-ish primitives. Visual design comes later — keep styling
// centralized here and in globals.css so it can be swapped in one place.

import Link from "next/link";
import type { ComponentProps, ReactNode } from "react";

export function Card({ className = "", ...props }: ComponentProps<"div">) {
  return <div className={`rounded-2xl border border-[var(--line)] bg-[var(--surface)] p-4 ${className}`} {...props} />;
}

export function SectionTitle({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-2 mt-6 flex items-center justify-between first:mt-0">
      <h2 className="text-sm font-semibold uppercase tracking-wide text-[var(--muted)]">{children}</h2>
      {action}
    </div>
  );
}

type ButtonVariant = "primary" | "secondary" | "danger" | "ghost";
const variants: Record<ButtonVariant, string> = {
  primary: "bg-[var(--brand)] text-white hover:opacity-90",
  secondary: "bg-[var(--surface-2)] text-[var(--fg)] hover:bg-[var(--line)]",
  danger: "bg-[var(--bad)] text-white hover:opacity-90",
  ghost: "text-[var(--brand)] hover:bg-[var(--surface-2)]",
};
const base = "inline-flex items-center justify-center gap-2 rounded-xl px-4 py-2.5 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-40";

export function Button({ variant = "primary", className = "", ...props }: ComponentProps<"button"> & { variant?: ButtonVariant }) {
  return <button className={`${base} ${variants[variant]} ${className}`} {...props} />;
}

export function ButtonLink({ variant = "primary", className = "", ...props }: ComponentProps<typeof Link> & { variant?: ButtonVariant }) {
  return <Link className={`${base} ${variants[variant]} ${className}`} {...props} />;
}

export function Dot({ color, className = "" }: { color: string; className?: string }) {
  return <span className={`inline-block h-2.5 w-2.5 shrink-0 rounded-full ${className}`} style={{ background: color }} />;
}

export function Badge({ children, color }: { children: ReactNode; color?: string }) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium"
      style={{ background: color ? `color-mix(in srgb, ${color} 15%, transparent)` : "var(--surface-2)", color: color ?? "var(--fg)" }}
    >
      {children}
    </span>
  );
}

export function Chip({ active, ...props }: ComponentProps<"button"> & { active?: boolean }) {
  return (
    <button
      className={`shrink-0 rounded-full border px-3 py-1.5 text-sm transition ${
        active ? "border-[var(--brand)] bg-[var(--brand)] text-white" : "border-[var(--line)] bg-[var(--surface)] text-[var(--fg)]"
      }`}
      {...props}
    />
  );
}

/** Horizontal battery bar. */
export function SocBar({ value, target, className = "" }: { value: number; target?: number; className?: string }) {
  const color = value < 20 ? "var(--bad)" : value < 40 ? "var(--warn)" : "var(--ok)";
  return (
    <div className={`relative h-3 w-full overflow-hidden rounded-full bg-[var(--surface-2)] ${className}`}>
      <div className="h-full rounded-full transition-[width] duration-500" style={{ width: `${Math.min(100, value)}%`, background: color }} />
      {target !== undefined && <div className="absolute top-0 h-full w-0.5 bg-[var(--fg)]" style={{ left: `${target}%` }} />}
    </div>
  );
}

export function Stat({ label, value, sub }: { label: string; value: ReactNode; sub?: ReactNode }) {
  return (
    <div>
      <div className="text-xs text-[var(--muted)]">{label}</div>
      <div className="text-lg font-semibold">{value}</div>
      {sub && <div className="text-xs text-[var(--muted)]">{sub}</div>}
    </div>
  );
}

export function Field({ label, children, hint }: { label: string; children: ReactNode; hint?: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-sm font-medium">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-xs text-[var(--muted)]">{hint}</span>}
    </label>
  );
}

export const inputClass =
  "w-full rounded-xl border border-[var(--line)] bg-[var(--surface)] px-3 py-2.5 text-sm outline-none focus:border-[var(--brand)]";

export function PageHeader({ title, subtitle, back }: { title: string; subtitle?: ReactNode; back?: string }) {
  return (
    <div className="mb-4">
      {back && (
        <Link href={back} className="mb-2 inline-block text-sm text-[var(--brand)]">
          ← Atgal
        </Link>
      )}
      <h1 className="text-2xl font-bold">{title}</h1>
      {subtitle && <p className="mt-1 text-sm text-[var(--muted)]">{subtitle}</p>}
    </div>
  );
}

export function Empty({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <Card className="py-10 text-center">
      <div className="font-semibold">{title}</div>
      {children && <div className="mt-2 text-sm text-[var(--muted)]">{children}</div>}
    </Card>
  );
}
