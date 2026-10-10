#!/usr/bin/env python3
"""Validate Xcode String Catalogs (*.xcstrings).

    python3 scripts/check_xcstrings.py            # every catalog under ios/
    python3 scripts/check_xcstrings.py FILE...    # specific files

Fails (exit 1) when a catalog
  - is not valid JSON or has duplicate keys,
  - lacks the top-level `strings` map,
  - has an entry without a non-empty Lithuanian value (`lt`),
    unless the entry is marked `"shouldTranslate": false` (text identical in both languages),
  - uses different format specifiers in English and Lithuanian (%@, %lld, %.1f ... the
    counts and types must match; positional forms like %1$@ are fine).

English is the source language: for most catalogs the key *is* the English text; for
catalogs with an explicit `en` localization (e.g. InfoPlist.xcstrings) that value is used.
Standard library only.
"""
from __future__ import annotations

import glob
import json
import os
import re
import sys

REQUIRED_LANGUAGE = "lt"
# printf-style conversions we use in this app; "%%" (a literal percent) is stripped first.
SPEC = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[dius@fFeEgGxXoc]")


def load(path):
    def no_duplicates(pairs):
        seen = {}
        for key, value in pairs:
            if key in seen:
                raise ValueError(f"duplicate key {key!r}")
            seen[key] = value
        return seen

    with open(path, encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=no_duplicates)


def specifiers(text: str) -> list[str]:
    stripped = text.replace("%%", "")
    return sorted(m.group(0)[-1] for m in SPEC.finditer(stripped))  # the conversion letter: d, f, @ ...


def unit_values(localization: dict) -> list[str]:
    """All string values in a localization, including plural/device variations."""
    values = []
    unit = localization.get("stringUnit")
    if unit is not None:
        values.append(unit.get("value", ""))
    for variation in (localization.get("variations") or {}).values():
        for sub in variation.values():
            values.extend(unit_values(sub))
    return values


def check_file(path: str) -> list[str]:
    try:
        data = load(path)
    except (ValueError, OSError) as error:
        return [f"{path}: not valid JSON ({error})"]
    strings = data.get("strings")
    if not isinstance(strings, dict):
        return [f"{path}: missing top-level 'strings' map"]
    problems = []
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations") or {}
        lt = localizations.get(REQUIRED_LANGUAGE)
        if lt is None:
            problems.append(f"{path}: {key!r}: no '{REQUIRED_LANGUAGE}' translation "
                            f'(add one, or mark the entry "shouldTranslate": false if the text is identical)')
            continue
        values = unit_values(lt)
        if not values or any(not v.strip() for v in values):
            problems.append(f"{path}: {key!r}: empty '{REQUIRED_LANGUAGE}' value")
            continue
        en = unit_values(localizations["en"]) if "en" in localizations else [key]
        want = specifiers(en[0]) if en else []
        for value in values:
            if specifiers(value) != want:
                problems.append(f"{path}: {key!r}: format specifiers differ: English {want} vs Lithuanian {specifiers(value)} ({value!r})")
    return problems


def default_files() -> list[str]:
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ios")
    skip = (os.sep + "build" + os.sep, os.sep + "DerivedData" + os.sep)
    return sorted(p for p in glob.glob(os.path.join(root, "**", "*.xcstrings"), recursive=True) if not any(s in p for s in skip))


def main(argv: list[str]) -> int:
    files = argv[1:] or default_files()
    if not files:
        print("check_xcstrings: no .xcstrings files found", file=sys.stderr)
        return 2
    problems = []
    for path in files:
        found = check_file(path)
        problems += found
        try:
            count = len(load(path).get("strings", {}))
        except (ValueError, OSError):
            count = 0
        print(f"{os.path.relpath(path)}: {count} entries, {len(found)} problem(s)")
    for problem in problems:
        print("  " + problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
