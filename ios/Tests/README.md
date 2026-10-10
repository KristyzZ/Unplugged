# AppModel persistence regression checks

Run on a Mac with Xcode selected:

```sh
./ios/Tests/run-appmodel-persistence-checks.sh
```

The harness compiles the actual AppModel feature extensions, persistence,
charging, and domain logic. Only the notification and Live Activity adapters
and the UI tab enum are replaced, so no system notification or activity is
created. It restores any UserDefaults values it temporarily uses.

Checks cover legacy v1 saves (including older optional-field defaults), v2
round trips and precedence, session completion and rewards, report submission,
queue state, language changes, redemption, and reset. This does not replace
building the iOS app/widget or simulator UI verification. A native XCTest
project target/CI remains issue #19's responsibility; this harness requires no
project-file changes.
