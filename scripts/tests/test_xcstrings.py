"""Tests for scripts/merge_xcstrings.py and scripts/check_xcstrings.py.

Run:  python3 -m unittest discover -s scripts/tests -v
The git tests drive a real `git merge` in a throwaway repository, so they exercise the driver exactly
as contributors will.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
ROOT = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

import check_xcstrings as check  # noqa: E402
import merge_xcstrings as merger  # noqa: E402


def entry(lt, en=None):
    loc = {"lt": {"stringUnit": {"state": "translated", "value": lt}}}
    if en is not None:
        loc["en"] = {"stringUnit": {"state": "translated", "value": en}}
    return {"localizations": loc}


def catalog(**strings):
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def dump(data, xcode_style=False, trailing_newline=False):
    text = json.dumps(data, indent=2, ensure_ascii=False, separators=(",", " : ") if xcode_style else (",", ": "))
    return text + ("\n" if trailing_newline else "")


class MergeFunction(unittest.TestCase):
    def merge(self, base, ours, theirs):
        conflicts = []
        return merger.merge(base, ours, theirs, [], conflicts), conflicts

    def test_both_add_different_keys_keeps_both_ours_first(self):
        base = catalog(A=entry("a"))
        merged, conflicts = self.merge(base, catalog(A=entry("a"), B=entry("b")), catalog(A=entry("a"), C=entry("c")))
        self.assertEqual(conflicts, [])
        self.assertEqual(list(merged["strings"]), ["A", "B", "C"])

    def test_identical_change_on_both_sides_is_taken_once(self):
        base = catalog(A=entry("a"))
        side = catalog(A=entry("a"), B=entry("b"))
        merged, conflicts = self.merge(base, side, side)
        self.assertEqual((conflicts, merged), ([], side))

    def test_one_sided_edit_and_one_sided_delete(self):
        base = catalog(A=entry("a"), B=entry("b"))
        merged, conflicts = self.merge(base, catalog(A=entry("A2"), B=entry("b")), catalog(A=entry("a")))
        self.assertEqual(conflicts, [])
        self.assertEqual(merged["strings"], {"A": entry("A2")})

    def test_different_languages_of_the_same_key_merge_deeply(self):
        base = catalog(A=entry("a"))
        ours = catalog(A=entry("a2"))
        theirs = catalog(A={"localizations": {**entry("a")["localizations"], "de": {"stringUnit": {"state": "translated", "value": "ein"}}}})
        merged, conflicts = self.merge(base, ours, theirs)
        self.assertEqual(conflicts, [])
        self.assertEqual(merged["strings"]["A"]["localizations"]["lt"]["stringUnit"]["value"], "a2")
        self.assertEqual(merged["strings"]["A"]["localizations"]["de"]["stringUnit"]["value"], "ein")

    def test_same_field_changed_differently_is_a_conflict_and_keeps_ours(self):
        base = catalog(A=entry("a"))
        merged, conflicts = self.merge(base, catalog(A=entry("ours")), catalog(A=entry("theirs")))
        self.assertEqual(len(conflicts), 1)
        self.assertEqual(conflicts[0][0][-1], "value")
        self.assertEqual(merged["strings"]["A"]["localizations"]["lt"]["stringUnit"]["value"], "ours")

    def test_same_new_key_with_different_text_is_a_conflict(self):
        base = catalog()
        merged, conflicts = self.merge(base, catalog(N=entry("one")), catalog(N=entry("two")))
        self.assertEqual(len(conflicts), 1)

    def test_delete_versus_edit_is_a_conflict(self):
        base = catalog(A=entry("a"))
        _, conflicts = self.merge(base, catalog(), catalog(A=entry("edited")))
        self.assertEqual(len(conflicts), 1)

    def test_duplicate_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d, "x.xcstrings")
            p.write_text('{"strings": {"A": {}, "A": {}}}')
            with self.assertRaises(ValueError):
                merger.load(str(p))


class Formatting(unittest.TestCase):
    def test_style_of_the_destination_file_is_preserved(self):
        data = catalog(A=entry("ą"))
        for xcode, newline in [(False, False), (True, True)]:
            like = dump(data, xcode_style=xcode, trailing_newline=newline)
            self.assertEqual(merger.dumps(data, like), like)


class Checker(unittest.TestCase):
    def check(self, data):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d, "c.xcstrings")
            p.write_text(json.dumps(data, ensure_ascii=False))
            return check.check_file(str(p))

    def test_repository_catalogs_are_valid(self):
        for path in check.default_files():
            self.assertEqual(check.check_file(path), [], path)

    def test_valid_catalog_passes(self):
        self.assertEqual(self.check(catalog(**{"Hello %@": entry("Labas %@"), "Total %lld min": entry("Iš viso %lld min.")})), [])

    def test_missing_lithuanian_is_reported(self):
        self.assertTrue(any("no 'lt' translation" in p for p in self.check(catalog(A={"localizations": {}}))))

    def test_empty_lithuanian_is_reported(self):
        self.assertTrue(any("empty" in p for p in self.check(catalog(A=entry("  ")))))

    def test_should_translate_false_is_allowed(self):
        self.assertEqual(self.check(catalog(**{"CCS2": {"shouldTranslate": False}})), [])

    def test_specifier_mismatch_is_reported(self):
        problems = self.check(catalog(**{"Now %lld %%": entry("Dabar %@ %%")}))
        self.assertTrue(any("format specifiers differ" in p for p in problems), problems)

    def test_missing_specifier_is_reported(self):
        self.assertTrue(self.check(catalog(**{"Hi %@": entry("Labas")})))

    def test_literal_percent_and_positional_specifiers(self):
        self.assertEqual(self.check(catalog(**{"%@ at 50 %%": entry("%1$@ prie 50 %%")})), [])

    def test_explicit_english_localization_is_used_as_the_source(self):
        self.assertEqual(self.check(catalog(NSKey=entry("Vieta %@", en="Place %@"))), [])
        self.assertTrue(self.check(catalog(NSKey=entry("Vieta", en="Place %@"))))

    def test_duplicate_keys_and_bad_json_are_reported(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d, "c.xcstrings")
            p.write_text('{"strings": {"A": {}, "A": {}}}')
            self.assertTrue(any("not valid JSON" in x for x in check.check_file(str(p))))
            p.write_text("{nope")
            self.assertTrue(any("not valid JSON" in x for x in check.check_file(str(p))))


@unittest.skipUnless(subprocess.run(["git", "--version"], capture_output=True).returncode == 0, "git not available")
class GitIntegration(unittest.TestCase):
    """Real merges between two branches of a throwaway repository."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "Test")
        self.git("config", "merge.xcstrings.name", "xcstrings")
        self.git("config", "merge.xcstrings.driver", f'{sys.executable} "{SCRIPTS / "merge_xcstrings.py"}" %O %A %B %P')
        (self.repo / ".gitattributes").write_text("*.xcstrings merge=xcstrings\n")
        self.file = self.repo / "L.xcstrings"
        self.write(catalog(A=entry("a"), B=entry("b")))
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "base")

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args, check=True):
        r = subprocess.run(["git", *args], cwd=self.repo, capture_output=True, text=True)
        if check and r.returncode != 0:
            self.fail(f"git {' '.join(args)} failed: {r.stderr}")
        return r

    def write(self, data):
        self.file.write_text(dump(data))

    def commit_on(self, branch, data, start="main"):
        self.git("checkout", "-q", "-B", branch, start)
        self.write(data)
        self.git("commit", "-q", "-am", branch)

    def test_parallel_additions_at_the_end_merge_cleanly(self):
        # With a plain text merge this is the classic conflict: both append at the same place.
        self.commit_on("feat-1", catalog(A=entry("a"), B=entry("b"), X=entry("x")))
        self.commit_on("feat-2", catalog(A=entry("a"), B=entry("b"), Y=entry("y")))
        self.git("checkout", "-q", "feat-1")
        merge = self.git("merge", "--no-edit", "feat-2", check=False)
        self.assertEqual(merge.returncode, 0, merge.stdout + merge.stderr)
        merged = json.loads(self.file.read_text())
        self.assertEqual(list(merged["strings"]), ["A", "B", "X", "Y"])
        self.assertEqual(check.check_file(str(self.file)), [])

    def test_without_the_driver_the_same_merge_conflicts(self):
        self.commit_on("feat-1", catalog(A=entry("a"), B=entry("b"), X=entry("x")))
        self.commit_on("feat-2", catalog(A=entry("a"), B=entry("b"), Y=entry("y")))
        self.git("checkout", "-q", "feat-1")
        self.git("config", "--unset", "merge.xcstrings.driver")
        self.assertNotEqual(self.git("merge", "--no-edit", "feat-2", check=False).returncode, 0)

    def test_same_key_edited_differently_conflicts_and_names_the_key(self):
        self.commit_on("feat-1", catalog(A=entry("one"), B=entry("b")))
        self.commit_on("feat-2", catalog(A=entry("two"), B=entry("b")))
        self.git("checkout", "-q", "feat-1")
        merge = self.git("merge", "--no-edit", "feat-2", check=False)
        self.assertNotEqual(merge.returncode, 0)
        self.assertIn("CONFLICT", merge.stdout)
        self.assertIn("A", merge.stderr + merge.stdout)
        self.assertEqual(json.loads(self.file.read_text())["strings"]["A"], entry("one"))  # ours kept, valid JSON

    def test_edit_and_addition_elsewhere_merge_cleanly(self):
        self.commit_on("feat-1", catalog(A=entry("a-edited"), B=entry("b")))
        self.commit_on("feat-2", catalog(A=entry("a"), B=entry("b"), Z=entry("z")))
        self.git("checkout", "-q", "feat-1")
        self.assertEqual(self.git("merge", "--no-edit", "feat-2", check=False).returncode, 0)
        strings = json.loads(self.file.read_text())["strings"]
        self.assertEqual(strings["A"], entry("a-edited"))
        self.assertIn("Z", strings)


if __name__ == "__main__":
    unittest.main()
