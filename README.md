# Unplugged

A unified EV charging platform — a native iOS app built with Swift and SwiftUI. Stations across operators, live availability, trip planning, payments in one place, and incentives for responsible use: dynamic grace periods, progressive idle fees, points, and abuse reporting.

Vilnius Hack 2026 · Challenge #13.

> Prototype. The iOS app still uses **demo stations, prices, connector states and occupancy** from `ios/Unplugged/Models/DemoData.swift`. Charging, payments and operator plans are simulated; operator names are illustrative. The separate `pipeline/` reads real open data but is not yet wired into the app on `main` ([#35](https://github.com/KristyzZ/Unplugged/issues/35)).

## Getting Started

Requires a **Mac** with **Xcode 26 or newer and the iOS 26+ SDK**. Liquid Glass APIs require that SDK to compile; the effect appears on iOS 26+, with a frosted fallback on older supported iOS versions. App and widget builds and the 52 unit tests were verified with Xcode 27.0 / iOS SDK 27.0 locally and Xcode 26.6 / iOS SDK 26.5 in [CI run 38037065194](https://github.com/KristyzZ/Unplugged/actions/runs/38037065194), as recorded in [PR #40](https://github.com/KristyzZ/Unplugged/pull/40).

1. `git clone https://github.com/KristyzZ/Unplugged.git`
2. Open `ios/Unplugged.xcodeproj`.
3. Select a simulator at the top (e.g., iPhone 16) and press ▶ (`⌘R`).

**On your iPhone:** connect your phone, then in Xcode open the *Unplugged* project → *Signing & Capabilities* → *Team* and select your Apple ID. Do the same for the *UnpluggedWidgets* target (it shows charging on the Lock Screen). If the Bundle ID is already taken, change `lt.vilniushack.unplugged` to a unique value and set the widget's ID to the same value plus `.widgets`. On your phone, go to *Settings → General → VPN & Device Management* and trust the developer.

To set a location in the simulator, use *Features → Location → Custom Location* (Vilnius: 54.6872, 25.2797).

From the repository root on a Mac, build the app and widget and run the unit tests:

```bash
scripts/ios.sh all
```

See [ios/BUILD.md](ios/BUILD.md) for toolchain selection, simulator overrides, separate build/test commands and CI logs. The iOS workflow also supports manual dispatch in GitHub Actions; documentation-only changes do not trigger its path-filtered runs.

## Screens

| Screen | Features |
|---|---|
| Explore | Full-screen dark map with stations across operators, search, filters (available, ≥ 50 kW, compatible with my vehicle, operator), and a draggable panel with the nearest or selected station and the full list |
| Station | Connector states (available / charging / charging complete but still occupied / occupied without charging / out of service), pricing, hourly occupancy, probability of finding an available space, a virtual queue, charging start and payment, directions, and reporting a problem (wrong use, charger problem, other) |
| Plan | Car from Profile + battery level + destination → where, when, and how much to charge, battery percentage on arrival, cost, and route on the map |
| Charging | Session flow: progress → completion notification → 5–15-minute grace period → progressive fee → receipt and points, plus session history. Time can be accelerated from 1× to 300× for the demo |
| Charging tile | While charging, a tile in the top-left corner of the other tabs (tap to open Charging, × to hide until the next phase). Also shown on the Lock Screen and in the Dynamic Island as a Live Activity |
| Profile | Car, payment methods, operator plans (demo), points and rewards, city/operator analytics, language and demo data reset |

## Project Structure

```text
ios/
  Unplugged.xcodeproj
  Unplugged/
    App/          app entry point, tabs, notification banners
    Models/       domain types and demo data
    Logic/        business rules without UI — change logic here
      IdleFee.swift        demand-based grace periods, fee tiers, cap
      Availability.swift   occupancy, probability of finding an available space
      Charging.swift       charging curve, duration, and kWh
      TripPlanner.swift    trip planning
      Points.swift         points, rewards, levels
      Reports.swift        report confidence, sanctions
      Analytics.swift      operator / city analytics
    State/        AppModel + feature extensions, scoped persistence, notifications, location
    UI/Theme.swift  colors, glass, formatting, shared components — change design here
    Features/     screens
  UnpluggedWidgets/ Lock Screen / Dynamic Island Live Activity
  Shared/         code used by both the app and the widget
  UnpluggedTests/  native unit tests
  Tests/          standalone AppModel persistence checks
  BUILD.md        build and test instructions
pipeline/
  run.py          command-line entry point
  evdata/         OCPI crawler, registry loader, SQLite store, reports, snapshot export
  schema.sql      current records, status_events history, crawl_runs audit
  tests/          Python regression tests
scripts/ios.sh    reproducible app/widget build and test command
.github/workflows/ios.yml  macOS build/test CI
EV_IS_2026-10-09.xlsx  original registry export; read-only input
web/              earlier web prototype (Next.js)
```

## Data

The [EV data pipeline](pipeline/README.md) reads the public [Via Lietuva OCPI locations and tariff feed](https://ev.vialietuva.lt/atviri-duomenys-1) and the repository's `EV_IS_2026-10-09.xlsx` registry export. The workbook is an original, dated input: the loader reads it without modifying it. Live data supplies current statuses; the registry adds fields such as payment methods, accessibility and opening hours. These sources are separate from the app's fictional pricing and demo occupancy.

Python 3.10+ is sufficient; the pipeline uses the standard library. Run these from the repository root (on Windows, use `python` instead of `python3` if needed):

```bash
python3 pipeline/run.py crawl
python3 pipeline/run.py load-registry
python3 pipeline/run.py poll
```

`poll` is a long-running process: it checks approximately every five minutes and records observed status changes in SQLite. Stop it with Ctrl+C. For a persistent poller, choose a database outside the checkout using the global `--db` option documented in [pipeline/README.md](pipeline/README.md). In another terminal, export a snapshot or run the pipeline tests:

```bash
python3 pipeline/run.py export --city Vilnius
python3 -m unittest discover -s pipeline/tests
```

Default outputs are `pipeline/data/ev.sqlite` and `pipeline/data/stations.json` (both git-ignored). On `main`, this is a collector and file exporter, not an HTTP server or an iOS data connection. App wiring remains [#35](https://github.com/KristyzZ/Unplugged/issues/35).

**Attribution:** contains data from **Via Lietuva**, [ev.vialietuva.lt](https://ev.vialietuva.lt/), licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Unplugged normalizes, joins and filters the source data for its database and exports. Preserve the attribution, license link and indication of changes wherever derived data is displayed or distributed; see the publisher's [open-data terms](https://ev.vialietuva.lt/atviri-duomenys-1).

Polling captures sampled status changes, not every charging session. The feed contains duplicate charger records and timestamps without a timezone; use the pipeline's deduplicated current view and its observation history carefully. Open data does not establish whether a car remains parked after charging, provide payment authority or allow remote start/stop. The app's hourly occupancy and operator metrics remain seeded demonstrations, not results derived from this history.

## Parallel contribution workflow

Use the [MVP epic #17](https://github.com/KristyzZ/Unplugged/issues/17) and its [lane/file-ownership tables](https://github.com/KristyzZ/Unplugged/issues/17) to select work. Follow [AGENTS.md](AGENTS.md): one issue owner, a dedicated task branch (`codex/<issue>-<slug>`) and a separate Git worktree per issue, based on freshly fetched `main`. A branch alone does not isolate files. Claim the issue before editing; preserve local changes and synchronize only when safe.

Edit only the issue's owned files and coordinate changes to shared files. AppModel feature methods now live in `ios/Unplugged/State/AppModel+<Feature>.swift`; use the ownership table rather than editing the core for every feature. New Swift files in synchronized source folders are picked up automatically. Open one scoped PR with validation evidence and `Closes #<issue>`; follow the epic's integration order. After merge, remove only that task's worktree and branch when no longer needed.

**Localization tooling pending [#33](https://github.com/KristyzZ/Unplugged/issues/33):** its key-wise String Catalog merge driver and checker have not landed. Until then, keep catalog changes small, preserve existing keys/order and update against `main` before integration. User-facing strings need both English and Lithuanian; use `Text("English literal")` with a catalog entry or `tr()` / `trKey()` for constructed strings. Once #33 lands, follow its one-time driver setup and checker instructions; those scripts are not available on `main` yet.

## Demo status and runbook placeholder

**End-to-end runbook pending [#22](https://github.com/KristyzZ/Unplugged/issues/22).** The ordered scenario in [SPEC.md](SPEC.md#demonstration-scenario) is the acceptance target, not a verified presentation script. Replace this placeholder with the fixed setup, exact actions, reset procedure and expected outcomes when #22 lands, including EN/LT, relaunch and denied-notification checks.

Individual screens and simulated charging can be explored today; **Profile → Settings → Reset demo data** resets saved demo state, and **Charging** offers time acceleration. This does not yet guarantee a deterministic map/recommendation/queue/dashboard scenario. Plan toggles do not change pricing (#9); session release is not connected to map availability (#10); queue position is fixed (#14); report photo evidence is not retained (#15); analytics uses seeded assumptions (#13); routes are approximate (#21). Track their completion in [#17](https://github.com/KristyzZ/Unplugged/issues/17).

The Lock Screen / Dynamic Island Live Activity already mirrors the simulated charging session. System countdowns continue while the app is closed, but phase and fee updates are sent by the running app. APNs push updates and real operator session control are out of scope; lifecycle/background hardening remains [#20](https://github.com/KristyzZ/Unplugged/issues/20).

## Next Steps

- Connect the existing open-data pipeline to the app (#35); real operator account and session-control pilots remain later work
- Actual routing (MKDirections) instead of straight-line distance × 1.2
- Payments (Apple Pay / Stripe) and accounts
