import type { Metadata, Viewport } from "next";
import { AppShell } from "@/components/AppShell";
import { StoreProvider } from "@/lib/store";
import "./globals.css";

export const metadata: Metadata = {
  title: "Unplugged — viena EV įkrovimo platforma",
  description: "Visų operatorių įkrovimo stotelės, kelionių planavimas, atsiskaitymas ir atsakingo naudojimo skatinimas vienoje vietoje.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#0f766e",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="lt" className="h-full antialiased">
      <body className="h-full">
        <StoreProvider>
          <AppShell>{children}</AppShell>
        </StoreProvider>
      </body>
    </html>
  );
}
