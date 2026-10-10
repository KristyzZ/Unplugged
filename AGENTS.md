# Agent Instructions

## GitHub Synchronization

- Before starting each task, inspect the current branch, working-tree status, configured remotes, and upstream. Always fetch the latest refs from the GitHub remote (`git fetch --prune <remote>`) before making changes.
- Work on the branch selected for the task. Keep it current with its own upstream; do not switch to another branch merely because it has newer commits.
- If the working tree is clean and the current branch has an upstream, run `git pull --ff-only` using that upstream before editing files. Fetching alone updates remote-tracking refs, not the checked-out branch.
- Preserve all local work. If there are uncommitted changes, divergent history, or no upstream, fetch and inspect the difference, then report what prevents safely updating the branch. Do not automatically reset, discard changes, stash, rebase, or create a merge commit to synchronize.
- If fetching or pulling fails because of connectivity, authentication, or permissions, report the failure and do not claim the branch is current. Continue independent work when possible, clearly noting that synchronization is unverified.

## Working Branches

- Always create a dedicated branch for a new task before editing files or committing changes. Never implement changes or commit directly on `main`.
- Create the task branch from the synchronized base selected for the task. Use a descriptive name (for Codex, `codex/<task-name>`). When continuing the same task, reuse its existing branch rather than creating another one.
- If local changes prevent safely updating the base or switching branches, preserve them and report the issue; do not discard or stash them automatically.
- After a task branch is merged and no longer needed, delete the branch locally and on GitHub. Do not delete branches belonging to unrelated work.

## Available Open Data

- The repository includes `EV_IS_2026-10-09.xlsx`, an open-data export of the EV charging infrastructure registry dated 2026-10-09.
- This dataset is available for future work on Unplugged. Its presence alone is not a request to analyze, transform, import, or integrate it; leave it unchanged until a task requires using it.

## Localization (String Catalogs)

- The app ships English (source) and Lithuanian. Every user-facing string needs both: add the English text as the key and the Lithuanian value in `ios/Unplugged/Localizable.xcstrings`. Use `Text("English literal")` for views and `tr()`/`trKey()` for strings built in code. A literal `%` in a key is written `%%`; interpolations use `%@` (text), `%lld` (integers) and `%lf` (decimals), and Lithuanian must use the same ones.
- **New keys are appended at the end** of the catalog (it is kept in insertion order, not sorted). Do not reformat or re-sort the file, and do not edit it in Xcode's catalog editor (it rewrites the whole file and creates conflicts for everyone). Entries whose text is identical in both languages can be marked `"shouldTranslate": false` instead of repeating the text.
- **One-time setup per clone:** `scripts/setup-git-merge-driver.sh`. It registers a driver (declared in `.gitattributes`) that merges catalogs by key, so two branches that each add strings no longer conflict. A real conflict (the same string changed differently on both sides) is still reported, naming the key; ours is kept in the file until you decide.
- **Update your branch locally before the PR:** `git fetch && git merge origin/main`. GitHub's web "update branch" and merge buttons do not run custom drivers, so a catalog conflict shown there must be resolved by merging `main` on your machine. (The branch you merge into must contain `scripts/`.)
- **Check before you push:** `python3 scripts/check_xcstrings.py` (valid JSON, no duplicate keys, a Lithuanian value for every key, matching format specifiers). The same check runs in CI for pull requests that touch a catalog. Tests for both scripts: `python3 -m unittest discover -s scripts/tests`.
