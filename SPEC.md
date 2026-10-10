# Unplugged — Product Specification

Hack4Vilnius · Challenge #13 · Updated 2026-10-10.

This specification is based on our discussion of the challenge and product direction. It is not a copy of the official challenge brief. The current product is a native iOS prototype (Swift / SwiftUI); `web/` contains an earlier Next.js prototype.

## Problem and Goal

EV charging spaces in Vilnius are used inefficiently: vehicles remain parked after charging ends or occupy spaces without charging, queues form at some stations while nearby stations remain available. Separate operator apps make it difficult to compare prices, availability, and existing subscriptions.

**Unplugged helps distribute drivers across existing charging infrastructure and encourages them to free up spaces promptly.** The primary outcome is more available charging spaces and shorter waits. A unified map provides the foundation for this solution.

Product directions:

1. **One place:** operator stations, price comparison, linked accounts, and charging history.
2. **Responsible behavior:** notifications, grace periods, idle fees, points, and reports of blocked spaces.
3. **Network optimization:** occupancy data, predictions, recommendations, and routing drivers to less busy stations.

## Users and Value

| User | Value |
|---|---|
| EV driver | Finds a suitable station based on vehicle compatibility, waiting time, and personal pricing; retains operator plan benefits |
| Charging operator | Gains additional sessions, makes better use of available stations, and sees the results of referrals |
| City | Sees aggregated demand, time spent blocking spaces, and gaps in infrastructure |

## Hackathon MVP

The MVP must demonstrate one complete scenario: **occupied station → better alternative → charging completion notification → vehicle moved → available space and reward**.

| Priority | Feature | Acceptance Criterion |
|---|---|---|
| P0 | Unified map | Demo stations in Vilnius from multiple operators; filters for connector type, power, and availability |
| P0 | Clear connector states | Distinguishes available, charging, charging complete but space occupied, occupied without charging, and out of service; unknown data is not shown as availability |
| P0 | Station recommendation | Compares at least two alternatives by compatibility, travel time, waiting time, and session cost; explains the choice |
| P0 | Session and space release | A demo session progresses through charging completion, a grace period, and idle fees; moving the vehicle makes the space available |
| P0 | Notifications and points | Notifies the driver when charging ends and a fee is approaching; awards points once for moving the vehicle on time |
| P0 | Operator value demonstration | Shows demo referred sessions, their revenue, and time spent blocking spaces; metrics are labeled as simulated |
| P1 | Linked operator plans | A demo plan can be enabled and disabled; personal pricing and recommendations change accordingly |
| P1 | Virtual queue | Notifies a queued driver when a space becomes available; does not guarantee a space without operator confirmation |
| P1 | Report a blocked space | Station, photo, description, and confirmations; review status is visible |
| P2 | Trip planning | Vehicle, battery level, and destination → compatible charging stations, time, cost, and battery level on arrival |

P0 defines the core demonstration scope. P1 is added after P0 is complete; P2 and other existing prototype features remain part of the broader product vision.

### Implementation status (2026-10-10)

The table above is an acceptance target, not a declaration that every criterion is complete. `main` includes the dark-glass Explore / Plan / Charging / Profile UI, EN/LT switching, simulated charging and local notifications, reports, rewards, profile controls, charging tile and Lock Screen / Dynamic Island Live Activity. AppModel is split into feature extensions; native tests and app/widget CI are present (see [build instructions](ios/BUILD.md)).

The separate `pipeline/` collects Via Lietuva open OCPI data, reads the untouched `EV_IS_2026-10-09.xlsx` registry, stores sampled status history and exports snapshots. The iOS app still uses fictional stations, prices and occupancy; connecting these real inputs remains [#35](https://github.com/KristyzZ/Unplugged/issues/35). Payments and operator plans remain simulated.

Explainable recommendations, plan-aware pricing, session-to-map release, real queue notifications, report review/reward integrity and event-derived analytics are still tracked in [epic #17](https://github.com/KristyzZ/Unplugged/issues/17). The deterministic end-to-end scenario and its validated runbook remain [#22](https://github.com/KristyzZ/Unplugged/issues/22). Existing screens and timers do not establish that those issues are complete.

## Recommendations and Data

- Incompatible or out-of-service connectors are excluded first; usable charging power is limited by the vehicle's supported power.
- Remaining alternatives are compared by travel time, expected waiting time, charging duration, and total session cost. Drivers can prioritize time or price.
- Pricing includes known energy, session-start, and time-based charges, plus applicable plan discounts. Potential idle fees are shown separately.
- Recommendations are explained: “This station is farther away, but the demo data indicates a shorter wait and lower cost.” Savings are calculated from the same scenario data.
- Every status and price has a source, update timestamp, and data type: demo, observed, or predicted. Stale data is clearly marked.
- Predicted availability is presented as an estimate with uncertainty. Charging completion alone does not mean the vehicle has left.
- The MVP uses explainable rules and deterministic demo scenarios. A prediction model using historical data is a later stage.

## Session and Responsible Use Rules

Session flow: `charging → charging complete / space occupied → grace period → idle fee → space released → receipt`.

- Demo grace period: 5–15 minutes depending on demand, as in the existing `IdleFee.swift`. The selected period and fee terms are shown before the session and remain unchanged during it.
- After the grace period, demo rates apply: first 10 minutes — €0.10/minute; from 10 to 30 minutes — €0.25/minute; thereafter — €0.50/minute. The total idle fee is capped at €40. This is a configurable prototype policy.
- Notifications cover: selected battery target reached, charging complete, grace period ending soon, idle fees started, and a station the driver is waiting for becoming available.
- Points are awarded for releasing a space within the grace period. One event cannot generate multiple rewards; actual discounts depend on partner agreements.
- Confirming that a space has actually been released requires an appropriate operator or parking-space occupancy signal. In the demo, this is an explicitly simulated event.
- An abuse report provides evidence for review. The existing prototype's confidence score and escalation rules are demonstrative; user reports do not automatically create real financial charges or account restrictions.

## Operator Incentives and Subscriptions

The case for operator participation is additional sessions and better infrastructure utilization. When operator A's station is overcrowded, Unplugged can direct a driver to an available station belonging to operator B. The operator dashboard shows the results of these referrals.

**Bring your own contract:** users link their existing operator accounts and plans. Unplugged compares the prices available to each user while preserving the value of operator subscriptions and loyalty programs. Before a session, the app clearly shows which operator's contract applies and who bills the user.

MVP plans and tariffs are fictional. Real account linking requires an operator-supported authorization method and an agreement; operator passwords are not collected. Without plan integration, the public price is shown and a personal discount is not promised.

| Level | Capabilities | App Behavior |
|---|---|---|
| 1 — Discovery | Location, connectors, power, operator | Station discovery, directions, and a link to the operator's app |
| 2 — Live data | Status, faults, and prices | Displays received data and its freshness |
| 3 — Account integration | Account, plan, and loyalty terms | Calculates personal pricing when confirmed by the integration |
| 4 — Full charging | Session start, stop, and payment | Performs actions within Unplugged according to operator-supported capabilities |

Capabilities are checked for each station. Lower integration levels do not provide session control or reservations. Unified payment is a long-term goal; payments are simulated during the hackathon.

Potential revenue sources include operator analytics subscriptions and an agreed fee for referred sessions. These are hypotheses to validate in a pilot; any fee must be transparent and included in the price shown to the user. Recommendation criteria must be clear, and paid placement must be labeled.

## Operator and City Analytics

The dashboard is intended to show referred and completed sessions, their revenue, charging and blocking duration, queue time, and station utilization by hour. Mismatches between demand and available infrastructure help identify pilot locations and assess expansion needs.

A referred session is recorded separately from an incremental session: whether it would have happened without Unplugged can only be evaluated through a comparative pilot. City views use aggregated data; the public map does not display drivers' license plates or individual histories.

## Technical Foundation and Boundaries

- Primary platform: SwiftUI, MapKit, Swift Charts, local iOS notifications and ActivityKit. Domain rules remain in `ios/Unplugged/Logic/`, state and feature extensions in `ios/Unplugged/State/`, and demo data in `ios/Unplugged/Models/DemoData.swift`. Liquid Glass requires the iOS 26+ SDK to compile; supported older runtimes use the frosted fallback. See [ios/BUILD.md](ios/BUILD.md) for the verified toolchain and build/test commands.
- Existing areas: map, station details, session, trip planning, points, abuse reports, and operator analytics.
- New priorities: recommendation explanations, a network load redistribution scenario, a linked-plan model, and displaying integration capabilities. This specification does not itself implement these features.
- Data models: operator and integration capabilities, station, connector and status timestamp, tariff, linked plan, session, reward event, queue entry, report, and referral event.
- The public Via Lietuva OCPI feed is already consumed by `pipeline/`; its registry loader reads `EV_IS_2026-10-09.xlsx` without changing it. Data is attributed to Via Lietuva under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); normalized/joined exports are derived data. See [README Data](README.md#data) and [pipeline/README.md](pipeline/README.md). This collector does not provide operator account access, remote session control, payment authority or an app-facing HTTP server on `main`. Authorized operator integrations, a hosted backend, authorization and real payments remain later work.
- The current app can run with demo data without operator accounts, real payments or a server; saved demo state can be reset and simulated time accelerated. Reproducibility of the full cross-screen scenario is an acceptance requirement still owned by #22, not a verified property of the current timer-generated station data.
- The shipped Live Activity extension displays the simulated charging session on the Lock Screen and, on supported devices, the Dynamic Island. It mirrors charging, grace, idle-fee and ended phases. Its countdowns use system-rendered wall-clock dates, so they keep ticking while the app is closed; state transitions and fee values are updated locally while the app runs. It requests no push token (`pushType: nil`). APNs push updates and real operator control are out of scope; background/lifecycle hardening remains [#20](https://github.com/KristyzZ/Unplugged/issues/20).
- Reservations with a 10–15-minute arrival window, real charging credits and advanced prediction are later-stage features. Reservations require operator confirmation.

## Demonstration Scenario

**Runbook placeholder — pending [#22](https://github.com/KristyzZ/Unplugged/issues/22).** The sequence below describes the intended integrated demonstration. A fixed fixture, exact presentation actions and expected outcomes will be documented after its dependencies land; the current map refresh, queue and seeded dashboard do not yet implement this complete reproducible sequence. Verify both languages, relaunch, denied notifications and repeated reset before treating it as ready to present.

1. A driver in Vilnius searches for a suitable station. The nearest station is occupied; one charging session has ended, but the vehicle remains parked.
2. Unplugged offers an available alternative and explains the differences in travel time, waiting time, and price. If P1 is implemented, enabling a demo operator plan recalculates personal pricing.
3. The driver whose session has ended receives a notification and sees a grace period countdown. The demo can show both moving the vehicle on time and progressive idle fees.
4. When the vehicle is moved, the connector becomes available, points are awarded, and a queued user is notified of availability.
5. The operator dashboard shows simulated changes in sessions and blocking duration. All amounts and results are clearly labeled as demo data.

## Success Evaluation and Next Decisions

Hackathon success means a reproducible P0 scenario, a clear recommendation explanation, correctly functioning grace periods and fee calculations, and a clear distinction between observed, predicted, and demo data.

Pilot metrics: median time from charging completion to space release, share of sessions where the vehicle is moved within the grace period, average waiting time, recommendation acceptance, and completed referred sessions. Changes are compared with a baseline under similar hours and demand conditions; no percentage improvement is promised before the pilot.

Before a real pilot, confirm access to operator data and session control, application of subscription tariffs, a physical space occupancy signal, payment responsibilities, the report review process, and agreed fee rules. The first practical step is a pilot with one operator and several stations in Vilnius.
