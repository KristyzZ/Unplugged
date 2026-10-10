# Building and testing the iOS app

One script does everything, locally and in CI, so "works on my machine" and "passes in CI" mean the same thing:

```bash
scripts/ios.sh build   # compile the app AND the widget extension
scripts/ios.sh test    # run the unit tests (UnpluggedTests)
scripts/ios.sh all     # both (default)
```

## Requirements
- macOS with **Xcode 26 or newer** (the UI uses Liquid Glass APIs from the iOS 26 SDK). Checked with Xcode 27.0 / iOS SDK 27.0.
- At least one **iPhone simulator**. The script picks the first available one; override with `IOS_SIM_UDID=<udid> scripts/ios.sh test` (`xcrun simctl list devices available`).
- No Apple ID, signing team or credentials: builds use `CODE_SIGNING_ALLOWED=NO`. (Installing on a physical iPhone does need a team; see the README.)
- Optional: `IOS_DERIVED=<path>` changes the derived-data folder (default `ios/build/DerivedData`, git-ignored). Logs and the `.xcresult` bundle land in `ios/build/`.

## A runner that cannot run the checks fails loudly
The script never skips silently. If the toolchain is missing it stops with a specific message and exit code, so an unavailable runner cannot look like a pass:

| Exit | Meaning |
|---|---|
| 0 | built / tested OK |
| 1 | build or test failure |
| 2 | `xcodebuild` not found |
| 3 | iOS Simulator SDK missing or older than 26 |
| 4 | no iPhone simulator available |

## Xcode project facts
- Shared schemes (committed, so everyone and CI use the same): **`Unplugged`** (app + unit tests) and **`UnpluggedWidgets`** (Live Activity extension). Building `Unplugged` also builds and embeds the widget; the script additionally builds the widget scheme alone.
- Targets: `Unplugged` (app), `UnpluggedWidgets`, `UnpluggedTests` (hosted XCTest bundle).
- Source folders `ios/Unplugged`, `ios/Shared`, `ios/UnpluggedWidgets` and `ios/UnpluggedTests` are *synchronized groups*: **new Swift files are picked up automatically; do not edit `project.pbxproj`** just to add files.
- When the app hosts the tests it skips the notification prompt and UI (`UnpluggedApp.isRunningTests`), so tests are fast and need no permissions.

## Writing tests (for #8–#15 and everyone else)
- Put tests in `ios/UnpluggedTests/`; `import XCTest` and `@testable import Unplugged`.
- Build inputs with `Fixtures` (`Fixtures.vehicle(...)`, `.connector(...)`, `.station(...)`, `.corridor(...)`, `.session(...)`). Add new builders next to it rather than copying setup.
- **Never read the real clock.** Pass times in: use `Fixtures.t0` and `Fixtures.at(minutes:)`, and pass `now:` to logic such as `SessionSnapshot`. If production code reads `Date()`/`Calendar.current` directly, give it an injectable parameter with a default value (a small change) instead of sleeping or comparing against the current time.
- Keep tests for *your* feature in your own file (e.g. `PricingTests.swift`) so parallel PRs do not conflict. Existing files cover shared rules: `IdleFeeTests`, `ChargingTests`, `TripPlannerTests`, `SessionTimelineTests`.
- Run one suite quickly: `cd ios && xcodebuild test -project Unplugged.xcodeproj -scheme Unplugged -destination "id=<udid>" -only-testing:UnpluggedTests/IdleFeeTests CODE_SIGNING_ALLOWED=NO`.

## CI (`.github/workflows/ios.yml`)
Runs `scripts/ios.sh build` then `scripts/ios.sh test` on `macos-26` for pull requests and pushes to `main` that touch `ios/**`, the script or the workflow; it can also be started by hand (Actions > iOS > Run workflow). Logs and the `.xcresult` are uploaded as an artifact.
**Cost:** macOS runner minutes are billed at 10x on private repositories and a full run takes several minutes, so the workflow is path-filtered and cancels superseded runs. Watch the Actions usage quota.
