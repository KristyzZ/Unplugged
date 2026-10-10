#!/usr/bin/env bash
# One-time, per clone: register the String Catalog merge driver named in .gitattributes.
# (Git config is shared by all worktrees of the clone, so run it once.)
set -euo pipefail
cd "$(dirname "$0")/.."
git config merge.xcstrings.name "Xcode String Catalog (3-way merge by key)"
git config merge.xcstrings.driver "python3 scripts/merge_xcstrings.py %O %A %B %P"
echo "xcstrings merge driver registered for $(git rev-parse --show-toplevel)"
