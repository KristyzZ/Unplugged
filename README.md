# Unplugged

A unified EV charging platform — a native iOS app built with Swift and SwiftUI. Stations across operators, live availability, trip planning, payments in one place, and incentives for responsible use: dynamic grace periods, progressive idle fees, points, and abuse reporting.

Vilnius Hack 2026 · Challenge #13.

> Prototype. All station, pricing, and occupancy data is **demo data** (`ios/Unplugged/Models/DemoData.swift`). Operator names are used for illustration only.

## Getting Started

Requires a **Mac** with **Xcode 26** or later (available free on the App Store). Liquid Glass shows on iOS 26+; older iOS versions get a frosted fallback.

1. `git clone https://github.com/KristyzZ/Unplugged.git`
2. Open `ios/Unplugged.xcodeproj`.
3. Select a simulator at the top (e.g., iPhone 16) and press ▶ (`⌘R`).

**On your iPhone:** connect your phone, then in Xcode open the *Unplugged* project → *Signing & Capabilities* → *Team* and select your Apple ID. Do the same for the *UnpluggedWidgets* target (it shows charging on the Lock Screen). If the Bundle ID is already taken, change `lt.vilniushack.unplugged` to a unique value and set the widget's ID to the same value plus `.widgets`. On your phone, go to *Settings → General → VPN & Device Management* and trust the developer.

To set a location in the simulator, use *Features → Location → Custom Location* (Vilnius: 54.6872, 25.2797).

## Screens

| Screen | Features |
|---|---|
| Map | Full-screen dark map with stations across operators, search, filters (available, ≥ 50 kW, compatible with my vehicle, operator), and a draggable panel with the nearest or selected station and the full list |
| Station | Connector states (available / charging / charging complete but still occupied / occupied without charging / out of service), pricing, hourly occupancy (Swift Charts), probability of finding an available space, a virtual queue, charging start and payment, and Apple Maps directions |
| Charging tile | Not a tab: a tile in the top-left corner while charging (tap for details, × to hide until the next phase). Session flow: progress → completion notification → 5–15-minute grace period → progressive fee → receipt and points. Also shown on the Lock Screen and in the Dynamic Island as a Live Activity. Time can be accelerated from 1× to 300× for the demo |
| Trip | Vehicle + battery level + destination → where, when, and how much to charge, battery percentage on arrival, cost, and route on the map |
| Points | Balance, levels, ways to earn points, reward redemption, history. The ••• menu has operator analytics, language and demo data reset |
| Report | License plate + photo → confidence based on the photo, station data, and other users' confirmations → escalating sanctions |

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
    State/        AppModel (persisted state), notifications, location
    UI/Theme.swift  colors, glass, formatting, shared components — change design here
    Features/     screens
  UnpluggedWidgets/ Lock Screen / Dynamic Island Live Activity
  Shared/         code used by both the app and the widget
web/              earlier web prototype (Next.js)
```

## Next Steps

- Real data: operator APIs (OCPI) or a backend
- Actual routing (MKDirections) instead of straight-line distance × 1.2
- Payments (Apple Pay / Stripe) and accounts
