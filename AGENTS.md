# Agent Instructions

## GitHub Synchronization

- Before starting each task, inspect the current branch, working-tree status, configured remotes, and upstream. Always fetch the latest refs from the GitHub remote (`git fetch --prune <remote>`) before making changes.
- Work on the branch selected for the task. Keep it current with its own upstream; do not switch to another branch merely because it has newer commits.
- If the working tree is clean and the current branch has an upstream, run `git pull --ff-only` using that upstream before editing files. Fetching alone updates remote-tracking refs, not the checked-out branch.
- Preserve all local work. If there are uncommitted changes, divergent history, or no upstream, fetch and inspect the difference, then report what prevents safely updating the branch. Do not automatically reset, discard changes, stash, rebase, or create a merge commit to synchronize.
- If fetching or pulling fails because of connectivity, authentication, or permissions, report the failure and do not claim the branch is current. Continue independent work when possible, clearly noting that synchronization is unverified.
