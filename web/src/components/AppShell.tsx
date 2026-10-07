"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { useStore } from "@/lib/store";
import { SessionWatcher } from "./SessionWatcher";

const tabs = [
  { href: "/", label: "Žemėlapis", icon: "M12 21s-7-6.2-7-11a7 7 0 1 1 14 0c0 4.8-7 11-7 11Zm0-8a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z" },
  { href: "/plan", label: "Kelionė", icon: "M4 19h4l10-10-4-4L4 15v4Zm10-14 4 4M15 19h5" },
  { href: "/session", label: "Įkrovimas", icon: "M13 2 4 14h7l-1 8 9-12h-7l1-8Z" },
  { href: "/rewards", label: "Taškai", icon: "M12 3l2.6 5.6 6.1.7-4.5 4.2 1.2 6L12 16.6 6.6 19.5l1.2-6L3.3 9.3l6.1-.7L12 3Z" },
  { href: "/report", label: "Pranešti", icon: "M12 9v4m0 4h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z" },
];

function isActive(path: string, href: string) {
  return href === "/" ? path === "/" || path.startsWith("/stations") : path.startsWith(href);
}

export function AppShell({ children }: { children: ReactNode }) {
  const path = usePathname();
  const { points, session, toasts, dismissToast, ready } = useStore();
  const wide = path.startsWith("/operator");
  const charging = session && !session.endedAt;

  return (
    <div className="flex h-full flex-col">
      <header className="sticky top-0 z-20 border-b border-[var(--line)] bg-[var(--surface)]/95 backdrop-blur">
        <div className={`mx-auto flex h-14 items-center justify-between px-4 ${wide ? "max-w-6xl" : "max-w-2xl"}`}>
          <Link href="/" className="text-lg font-bold tracking-tight">
            <span className="text-[var(--brand)]">⚡</span> Unplugged
          </Link>
          <div className="flex items-center gap-3 text-sm">
            <Link href="/operator" className="text-[var(--muted)] hover:text-[var(--fg)]">
              Operatoriams
            </Link>
            <Link href="/rewards" className="rounded-full bg-[var(--surface-2)] px-3 py-1 font-semibold">
              {ready ? points : "—"} tšk.
            </Link>
          </div>
        </div>
      </header>

      {ready && charging && !path.startsWith("/session") && (
        <Link href="/session" className="block bg-[var(--brand)] px-4 py-2 text-center text-sm font-medium text-white">
          {session.doneAt ? "Įkrovimas baigtas — patraukite automobilį" : "Vyksta įkrovimas — žiūrėti"} →
        </Link>
      )}

      <main className={`mx-auto w-full flex-1 px-4 pb-28 pt-4 ${wide ? "max-w-6xl" : "max-w-2xl"}`}>{children}</main>

      <nav className="fixed inset-x-0 bottom-0 z-20 border-t border-[var(--line)] bg-[var(--surface)] pb-[env(safe-area-inset-bottom)]">
        <div className="mx-auto grid max-w-2xl grid-cols-5">
          {tabs.map((t) => {
            const active = isActive(path, t.href);
            return (
              <Link
                key={t.href}
                href={t.href}
                className={`flex flex-col items-center gap-1 py-2 text-[11px] font-medium ${active ? "text-[var(--brand)]" : "text-[var(--muted)]"}`}
              >
                <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
                  <path d={t.icon} />
                </svg>
                {t.label}
              </Link>
            );
          })}
        </div>
      </nav>

      <div className="pointer-events-none fixed inset-x-0 top-16 z-30 mx-auto flex max-w-md flex-col gap-2 px-4">
        {toasts.map((t) => (
          <button
            key={t.id}
            onClick={() => dismissToast(t.id)}
            className="pointer-events-auto rounded-xl bg-[var(--fg)] px-4 py-3 text-left text-sm text-white shadow-lg"
          >
            <div className="font-semibold">{t.title}</div>
            {t.body && <div className="mt-0.5 opacity-80">{t.body}</div>}
          </button>
        ))}
      </div>

      <SessionWatcher />
    </div>
  );
}
