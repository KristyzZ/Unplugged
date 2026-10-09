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
