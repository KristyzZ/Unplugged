import json
import sqlite3
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from evdata import db as store  # noqa: E402
from evdata import ocpi  # noqa: E402
from evdata.export import build_app_feed  # noqa: E402


def tariff(elements, currency="EUR", tid="t1"):
    return {"id": tid, "currency": currency, "party_id": "AAA", "last_updated": "x", "elements": elements}


def element(*components, restrictions=None):
    e = {"price_components": [{"type": t, "price": str(p), "step_size": 1} for t, p in components]}
    if restrictions:
        e["restrictions"] = restrictions
    return e


class TariffResolution(unittest.TestCase):
    def test_unrestricted_element_wins_over_a_restricted_one(self):
        t = tariff([element(("ENERGY", 0.18), restrictions={"start_time": "00:00:00", "end_time": "00:15:00"}),
                    element(("ENERGY", 0.39), ("FLAT", 0.2))])
        p = ocpi.energy_price(t)
        self.assertEqual((p["ENERGY"], p["FLAT"]), (0.39, 0.2))

    def test_only_restricted_elements_use_the_first_energy_element(self):
        t = tariff([element(("FLAT", 0.25), restrictions={"min_kwh": "0.1"}),
                    element(("ENERGY", 0.18), restrictions={"start_time": "00:00:00"})])
        p = ocpi.energy_price(t)
        self.assertEqual(p["ENERGY"], 0.18)
        self.assertIsNone(p["FLAT"], "a restricted FLAT is not a session fee")

    def test_trim_marks_restricted_elements_and_keeps_components(self):
        trimmed = ocpi.trim_tariff(tariff([element(("ENERGY", 0.3), restrictions={"min_duration": 60}), element(("TIME", 0.6))]))
        self.assertEqual([e["restricted"] for e in trimmed["elements"]], [True, False])
        self.assertEqual(trimmed["elements"][1]["components"], [{"type": "TIME", "price": 0.6, "step": 1}])

    def test_malformed_price_is_skipped(self):
        t = tariff([{"price_components": [{"type": "ENERGY", "price": "abc"}, {"type": "FLAT", "price": "0.1"}]}])
        self.assertEqual(ocpi.trim_tariff(t)["elements"][0]["components"][0]["type"], "FLAT")


class Storage(unittest.TestCase):
    def test_time_is_stored_per_minute(self):
        db = store.connect(":memory:")
        store.apply_tariffs(db, [tariff([element(("ENERGY", 0.3), ("TIME", 0.6))])])
        row = db.execute("SELECT energy_eur_kwh, time_eur_min FROM tariffs").fetchone()
        self.assertEqual((row["energy_eur_kwh"], round(row["time_eur_min"], 4)), (0.3, 0.01))

    def test_old_database_without_elements_is_migrated(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            path = str(Path(d, "old.sqlite"))
            old = sqlite3.connect(path)
            old.execute("CREATE TABLE tariffs (id TEXT PRIMARY KEY, party_id TEXT, currency TEXT, energy_eur_kwh REAL, "
                        "time_eur_min REAL, flat_eur REAL, description TEXT, last_updated TEXT)")
            old.commit(); old.close()
            db = store.connect(path)
            self.assertIn("elements", {r["name"] for r in db.execute("PRAGMA table_info(tariffs)")})

    def test_a_record_with_a_bogus_future_date_ranks_last(self):
        db = store.connect(":memory:")
        def loc(uid, status, updated):
            return {"id": 1, "party_id": "AAA", "name": "S", "address": "a", "city": "c", "coordinates": {"latitude": "54", "longitude": "25"},
                    "operator": {"name": "O"}, "evses": [{"uid": uid, "evse_id": "AAA-1", "status": status, "last_updated": updated,
                                                          "connectors": []}]}
        store.apply_locations(db, [loc(1, "AVAILABLE", "2026-10-09T10:00:00")], "2026-10-09T10:00:00Z")
        store.apply_locations(db, [loc(2, "INOPERATIVE", "2031-01-03T14:17:54")], "2026-10-09T10:00:00Z")
        self.assertEqual(db.execute("SELECT status FROM evses_current").fetchone()["status"], "AVAILABLE")


class AppFeed(unittest.TestCase):
    def setUp(self):
        self.db = store.connect(":memory:")
        loc = {"id": 7, "party_id": "IBG", "name": "L3 | Inbalance grid", "address": "Laisvės pr. 3", "city": "Vilnius",
               "coordinates": {"latitude": "54.67", "longitude": "25.22"}, "operator": {"name": "In Balance grid, UAB"},
               "evses": [{"uid": 1, "evse_id": "IBG-1-A", "status": "AVAILABLE", "last_updated": "2026-10-10T00:01:05",
                          "connectors": [{"id": 650306, "standard": "IEC_62196_T2", "max_electric_power": 22000, "tariff_ids": ["t1"]}]}]}
        store.apply_locations(self.db, [loc], "2026-10-10T10:00:00Z")
        store.apply_tariffs(self.db, [tariff([element(("ENERGY", 0.28))], tid="t1"), tariff([element(("ENERGY", 9))], tid="unused"),
                                      tariff([element(("ENERGY", 1))], currency="PLN", tid="pln")])
        self.db.execute("INSERT INTO crawl_runs(finished_at, kind) VALUES ('2026-10-10T10:00:05Z', 'locations')")

    def test_shape_matches_what_the_app_decodes(self):
        feed = build_app_feed(self.db)
        self.assertEqual(feed["generatedAt"], "2026-10-10T10:00:05Z")
        s = feed["stations"][0]
        self.assertEqual((s["id"], s["party"], s["name"], s["lat"], s["lng"]), (7, "IBG", "L3 | Inbalance grid", 54.67, 25.22))
        e = s["evses"][0]
        self.assertEqual((e["id"], e["status"], e["updated"]), ("IBG-1-A", "AVAILABLE", "2026-10-10T00:01:05"))
        self.assertEqual(e["connectors"], [{"id": 650306, "standard": "IEC_62196_T2", "watts": 22000, "tariff": "t1"}])

    def test_only_used_euro_tariffs_are_exported(self):
        self.assertEqual([t["id"] for t in build_app_feed(self.db)["tariffs"]], ["t1"])

    def test_json_round_trips(self):
        json.loads(json.dumps(build_app_feed(self.db)))


class PagingWithoutACountHeader(unittest.TestCase):
    def test_stops_when_a_page_adds_nothing(self):
        calls = []

        def fake(url, **_):
            calls.append(url)
            return {}, {"data": [{"id": "a"}, {"id": "b"}]}   # like /tariffs: ignores paging, no count header

        with mock.patch.object(ocpi, "fetch_json", fake):
            result = ocpi.crawl("tariffs", pause=0)
        self.assertEqual([i["id"] for i in result.items], ["a", "b"])
        self.assertEqual(len(calls), 2)
        self.assertTrue(result.complete)

    def test_pages_by_offset_until_the_total_is_covered(self):
        pages = {0: ["1", "2"], 1000: ["3"]}

        def fake(url, **_):
            offset = int(url.split("offset=")[1])
            return {"x-total-count": "1500"}, {"data": [{"id": i} for i in pages.get(offset, [])]}

        with mock.patch.object(ocpi, "fetch_json", fake):
            result = ocpi.crawl("locations", pause=0)
        self.assertEqual([i["id"] for i in result.items], ["1", "2", "3"])
        self.assertEqual(result.expected_total, 1500)


if __name__ == "__main__":
    unittest.main()
