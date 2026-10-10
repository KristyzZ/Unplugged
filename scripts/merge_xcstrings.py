#!/usr/bin/env python3
"""Three-way merge driver for Xcode String Catalogs (*.xcstrings), by key.

Git cannot merge a big JSON file sensibly: two branches that each add a string
at the end of the catalog conflict on the same lines. This driver merges the
*structure* instead:

  - a key (or a nested field, e.g. one language of one key) changed on one side
    only: that change wins;
  - both sides made the identical change: taken once;
  - both sides added different keys: both are kept (ours first, then theirs);
  - both sides changed the *same* field differently: a real conflict. Ours is
    kept in the file, the exact keys are printed to stderr, and the exit status
    is 1 so git marks the file as conflicted for a human to decide.

Git calls it as:  merge_xcstrings.py BASE OURS THEIRS [PATHNAME]
and expects the result in OURS. Set it up once per clone with
scripts/setup-git-merge-driver.sh. Standard library only.
"""
from __future__ import annotations

import json
import sys

MISSING = object()


class DuplicateKey(ValueError):
    pass


def _no_duplicates(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise DuplicateKey(f"duplicate key {key!r}")
        seen[key] = value
    return seen


def load(path: str):
    """Return (data, raw_text); an empty/absent file is MISSING (e.g. add/add conflicts)."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        return MISSING, ""
    if not text.strip():
        return MISSING, text
    return json.loads(text, object_pairs_hook=_no_duplicates), text


def merge(base, ours, theirs, path, conflicts):
    """Recursive three-way merge. MISSING means 'absent'; returning MISSING deletes the field."""
    if ours == theirs:
        return ours
    if ours == base:
        return theirs
    if theirs == base:
        return ours
    if isinstance(ours, dict) and isinstance(theirs, dict):
        base_dict = base if isinstance(base, dict) else {}
        merged = {}
        for key in ours:                                   # ours' order is preserved...
            value = merge(base_dict.get(key, MISSING), ours[key], theirs.get(key, MISSING), path + [key], conflicts)
            if value is not MISSING:
                merged[key] = value
        for key in theirs:                                 # ...then keys only theirs has
            if key in ours:
                continue
            value = merge(base_dict.get(key, MISSING), MISSING, theirs[key], path + [key], conflicts)
            if value is not MISSING:
                merged[key] = value
        return merged
    conflicts.append((path, base, ours, theirs))
    return ours


def dumps(data, like: str) -> str:
    """Serialise in the same style as the file we are replacing (this repo's catalog is
    Python-style JSON without a trailing newline; Xcode writes `"key" : value`)."""
    separators = (",", " : ") if '" : ' in like else (",", ": ")
    text = json.dumps(data, indent=2, ensure_ascii=False, separators=separators)
    return text + "\n" if like.endswith("\n") else text


def _show(value) -> str:
    if value is MISSING:
        return "(absent)"
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= 160 else text[:157] + "..."


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    base_path, ours_path, theirs_path = argv[1:4]
    name = argv[4] if len(argv) > 4 else ours_path
    try:
        base, _ = load(base_path)
        ours, ours_text = load(ours_path)
        theirs, _ = load(theirs_path)
    except (ValueError, OSError) as error:  # invalid JSON, duplicate keys...
        print(f"merge_xcstrings: cannot parse {name}: {error}", file=sys.stderr)
        return 2
    conflicts: list = []
    merged = merge(base, ours, theirs, [], conflicts)
    if merged is MISSING:  # both deleted it
        return 0
    with open(ours_path, "w", encoding="utf-8") as f:
        f.write(dumps(merged, ours_text))
    if conflicts:
        print(f"merge_xcstrings: {len(conflicts)} conflict(s) in {name}; ours was kept, decide each one:", file=sys.stderr)
        for path, b, o, t in conflicts:
            where = " > ".join(str(p) for p in path[1:] if p != "localizations") or "(file)"
            print(f"  - {where}\n      base:   {_show(b)}\n      ours:   {_show(o)}\n      theirs: {_show(t)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
