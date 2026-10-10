# Agent Instructions

These rules apply to everyone who changes this repository, people and AI agents alike.

## Start Here (every contributor, once per clone)

1. **Tools:** a Mac with **Xcode 26 or newer** (the UI uses iOS 26 Liquid Glass APIs), **Python 3** (standard library only; used by `scripts/` and `pipeline/`), and the GitHub CLI (`gh auth login`).
2. **Register the String Catalog merge driver:** `scripts/setup-git-merge-driver.sh`. Without it, two people adding strings at the same time get conflicts in `Localizable.xcstrings`. Git config is shared by all worktrees of a clone, so this is once per clone, not once per branch.
3. **Prove your setup works:** `scripts/ios.sh all` (builds the app and the widget, runs the unit tests; needs an iPhone simulator, no Apple ID) and `python3 -m unittest discover -s scripts/tests`. If a command cannot run on your machine, say so in your PR; never report it as passed.
4. **Read:** `SPEC.md` (what we are building), epic **#17** (waves, lanes, who owns which files), `ios/BUILD.md` (build/test details) and, for data work, `pipeline/README.md`.
5. **Pick work from the board:** an open issue labelled `agent-ready` that nobody has claimed (see Tasks and Issues). Then create your branch and worktree (see Working Branches).

## GitHub Synchronization

- Before starting each task, inspect the current branch, working-tree status, configured remotes, and upstream. Always fetch the latest refs from the GitHub remote (`git fetch --prune <remote>`) before making changes.
- Work on the branch selected for the task. Keep it current with its own upstream; do not switch to another branch merely because it has newer commits.
- If the working tree is clean and the current branch has an upstream, run `git pull --ff-only` using that upstream before editing files. Fetching alone updates remote-tracking refs, not the checked-out branch.
- Preserve all local work. If there are uncommitted changes, divergent history, or no upstream, fetch and inspect the difference, then report what prevents safely updating the branch. Do not automatically reset, discard changes, stash, rebase, or create a merge commit to synchronize.
- If fetching or pulling fails because of connectivity, authentication, or permissions, report the failure and do not claim the branch is current. Continue independent work when possible, clearly noting that synchronization is unverified.
- **Exception, deliberate and for PR readiness only:** before opening a PR, and again if `main` moved while it is open, bring the latest `main` into your own task branch yourself: commit your work first, then `git fetch --prune && git merge origin/main`, resolve conflicts, and rerun the checks. This is a task step, not automatic synchronization, and it is the only time a merge commit on a task branch is expected. Do it on your machine: GitHub's web "update branch" button does not run our merge driver.

## Working Branches

- Always create a dedicated branch for a new task before editing files or committing changes. Never implement changes or commit directly on `main`.
- Create the task branch from the synchronized base selected for the task. Use a descriptive name (for Codex, `codex/<task-name>`). When continuing the same task, reuse its existing branch rather than creating another one.
- If local changes prevent safely updating the base or switching branches, preserve them and report the issue; do not discard or stash them automatically.
- After a task branch is merged and no longer needed, delete the branch locally and on GitHub. Do not delete branches belonging to unrelated work.
- **Name** task branches `codex/<issue number>-<short-slug>` (for example `codex/33-xcstrings-merge-driver`).
- **Use your own worktree per task**, because a branch alone does not isolate files when several people or agents work at once:
  `git fetch --prune && git worktree add ../Unplugged-<issue> -b codex/<issue>-<slug> origin/main`
  When the PR is merged: `git worktree remove ../Unplugged-<issue>`, then delete the branch locally and on GitHub.
- A branch for work that depends on an unmerged PR may be based on that PR's branch (a "stacked" PR). Say so in the PR description and merge the base PR first.

## Tasks and Issues

- **One issue, one owner, one PR.** Claim an issue before starting (assign yourself, or comment) so nobody duplicates it. Keep the PR limited to that issue; put unrelated findings in a new issue instead.
- Epic **#17** is the plan: milestones are waves (Wave 0 to 3, the parallel Data track, Backlog) and `lane:*` labels say which area an issue belongs to. Stay inside your lane's files (see Shared Code below).
- `agent-ready` means everything it depends on has merged. `blocked` means wait. Do not start a blocked issue; when its prerequisites merge, replace `blocked` with `agent-ready` on the issues you unblocked.
- Issues marked backlog / `priority:P2` are not authorised for the current sprint. A future-work issue is not permission to build that integration now.
- PR body: what changed and why, validation evidence (commands run and results, screenshots for UI), what you could **not** verify, anything reviewers must watch, and `Closes #<issue>`. Never claim another open issue is done.
- After your PR merges, tick your issue in the epic checklist. Do not merge someone else's PR unless asked to.

## Shared Code (who edits what)

- **AppModel** is split by feature: `ios/Unplugged/State/AppModel.swift` (core state, init, simulated clock) plus `AppModel+Session`, `+Queue`, `+Reports`, `+Profile`, `+Language`, `+Banners`, `+Demo`. Edit only your feature's file. Each feature owns its own Codable payload in `Persistence.swift` / its extension, so adding a saved field never edits a shared struct. Saved data from older versions (`unplugged.state.v1`) must keep loading; `./ios/Tests/run-appmodel-persistence-checks.sh` (macOS) checks this and must stay green when you touch persistence.
- **`ios/Unplugged.xcodeproj/project.pbxproj`:** do not edit it to add files. `ios/Unplugged`, `ios/Shared`, `ios/UnpluggedWidgets` and `ios/UnpluggedTests` are synchronized folders: new Swift files are picked up automatically. Edit the project file only for a genuine target or build-setting change, and say so in the PR.
- **`Models/DemoData.swift`** changes in this order: provenance model (#8) first, then real stations (#35). Coordinate before touching it.
- **Tests** go in `ios/UnpluggedTests/`, one file per feature (`PricingTests.swift`, ...), built with `Fixtures`. Never read the real clock in tests: pass fixed dates in (`Fixtures.t0`, `Fixtures.at(minutes:)`); if production code reads `Date()` directly, add an injectable parameter with a default value.
- **Localization catalog and merge workflow:** see the Localization section below.

## Build, Test and Definition of Done

- `scripts/ios.sh build|test|all` is the single build/test entry point for people and CI. If Xcode, the iOS 26 SDK or a simulator is missing, it fails with a specific exit code, which must be reported as "could not run", never as a pass. Details: `ios/BUILD.md`.
- A change is done when: the app **and** the widget build; tests exist for new logic and all tests pass; English and Lithuanian are both present and the catalog check passes; screens you touched were checked at large Dynamic Type and look unchanged at default settings; evidence is in the PR.
- CI: `ios.yml` builds and tests on a macOS runner for `ios/**` changes (macOS minutes cost 10x on private repos, so keep unrelated changes out of `ios/` and do not push needlessly); `localization.yml` is a cheap Linux check for catalog changes. A red check is fixed, not bypassed.

## Design and Accessibility

- Reuse the existing design system instead of inventing styles: `Theme` colors, `glass(in:)` surfaces (they fall back when Reduce Transparency is on), `scaledFont` (never fixed-size text), `StatRow` for stat columns, `minimumTouchTarget()` for small controls (hit area at least 44 pt), `withMotion` / `Motion.pick` for animation (respects Reduce Motion), `tabBarClearance()` and `screenBackdrop()` for scrolling screens.
- Dark glass is the approved direction: change behaviour and content freely, but do not restyle the look without agreement. Add accessibility labels to new icon-only controls.
- `web/` is the old Next.js prototype. It is not maintained; build features in the iOS app.

## Privacy, Security and Demo Honesty

- Never commit credentials, tokens, API keys, `.env` files or personal data. No operator passwords, real payments or real account linking in this sprint; use clearly fictional test values.
- Licence plates and report photos stay out of any public or city-facing view; reports only support human review, and nothing in the UI may imply a real fine or account restriction was imposed.
- Every price, status and result must say whether it is **demo**, **observed** (real data with a source and timestamp) or **predicted**. Do not present simulated results as evidence, and do not claim causal effects from simulations.

## Available Open Data

- The repository includes `EV_IS_2026-10-09.xlsx`, an open-data export of the EV charging infrastructure registry dated 2026-10-09.
- This dataset is available for future work on Unplugged. Its presence alone is not a request to analyze, transform, import, or integrate it; leave it unchanged until a task requires using it.
- The data pipeline in `pipeline/` (see `pipeline/README.md`) reads the workbook (read-only) and the open Via Lietuva OCPI feed. Run it with `python3 pipeline/run.py crawl | load-registry | poll | report | export`. Its database and exports live in `pipeline/data/` or outside the repository and are never committed.
- The data is CC BY 4.0: keep the attribution "Contains data from Via Lietuva (ev.vialietuva.lt)" wherever it is shown.
- Know the data's limits before quoting numbers: `last_updated` has no time zone (local time); the feed contains duplicate charger records (use the deduplicated view); no charger reports the OCPI `BLOCKED` status, so cars parked after charging are not visible in open data; a snapshot of "broken" chargers is inflated when a whole operator goes offline.
- The status poller (`poll`) builds the history that issues #36 to #38 need. It stops when the computer sleeps, so run it with `caffeinate -i`, and say in the team chat who is running it.

## Localization (String Catalogs)

- The app ships English (source) and Lithuanian. Every user-facing string needs both: add the English text as the key and the Lithuanian value in `ios/Unplugged/Localizable.xcstrings`. Use `Text("English literal")` for views and `tr()`/`trKey()` for strings built in code. A literal `%` in a key is written `%%`; interpolations use `%@` (text), `%lld` (integers) and `%lf` (decimals), and Lithuanian must use the same ones.
- **New keys are appended at the end** of the catalog (it is kept in insertion order, not sorted). Do not reformat or re-sort the file, and do not edit it in Xcode's catalog editor (it rewrites the whole file and creates conflicts for everyone). Entries whose text is identical in both languages can be marked `"shouldTranslate": false` instead of repeating the text.
- **One-time setup per clone:** `scripts/setup-git-merge-driver.sh`. It registers a driver (declared in `.gitattributes`) that merges catalogs by key, so two branches that each add strings no longer conflict. A real conflict (the same string changed differently on both sides) is still reported, naming the key; ours is kept in the file until you decide.
- **Update your branch locally before the PR:** `git fetch && git merge origin/main`. GitHub's web "update branch" and merge buttons do not run custom drivers, so a catalog conflict shown there must be resolved by merging `main` on your machine. (The branch you merge into must contain `scripts/`.)
- **Check before you push:** `python3 scripts/check_xcstrings.py` (valid JSON, no duplicate keys, a Lithuanian value for every key, matching format specifiers). The same check runs in CI for pull requests that touch a catalog. Tests for both scripts: `python3 -m unittest discover -s scripts/tests`.

## Where Things Are Documented

`README.md` (screens, getting started) · `SPEC.md` (product scope and rules) · epic #17 (plan, lanes, status) · `ios/BUILD.md` (build, test, CI) · `ios/Tests/README.md` (persistence checks) · `pipeline/README.md` (open data pipeline).
