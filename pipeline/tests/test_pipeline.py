import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline"))

from evdata import db as store  # noqa: E402
from evdata.export import build_snapshot  # noqa: E402
from evdata.ocpi import energy_price  # noqa: E402
from evdata.registry import read_registry  # noqa: E402
from evdata.report import build_report  # noqa: E402

WORKBOOK = ROOT / "EV_IS_2026-10-09.xlsx"


def location(status="AVAILABLE", extra_evse=None):
    evses = [{
        "uid": 1, "evse_id": "AAA-E-0001-A", "status": status, "last_updated": "2026-10-09T10:00:00",
        "connectors": [{"id": 11, "standard": "IEC_62196_T2_COMBO", "power_type": "DC", "max_electric_power": 50000, "tariff_ids": ["t1"]}],
    }]
    if extra_evse:
        evses.append(extra_evse)
    return {
        "id": 100, "party_id": "AAA", "name": "Test station", "address": "Gedimino pr. 1", "city": "Vilnius",
        "coordinates": {"latitude": "54.68", "longitude": "25.28"}, "time_zone": "Europe/Vilnius",
        "operator": {"name": "Test Operator", "website": "example.lt"}, "evses": evses,
    }


class StatusHistory(unittest.TestCase):
    def setUp(self):
        self.db = store.connect(":memory:")

    def test_first_sight_then_only_changes_are_recorded(self):
        first = store.apply_locations(self.db, [location()], "2026-10-09T10:00:00Z")
        self.assertEqual(first["status_changes"], 1)  # first observation
        same = store.apply_locations(self.db, [location()], "2026-10-09T10:05:00Z")
        self.assertEqual(same["status_changes"], 0)
        changed = store.apply_locations(self.db, [location("CHARGING")], "2026-10-09T10:10:00Z")
        self.assertEqual(changed["status_changes"], 1)
        rows = self.db.execute("SELECT status, first_seen FROM status_events ORDER BY id").fetchall()
        self.assertEqual([(r["status"], r["first_seen"]) for r in rows], [("AVAILABLE", 1), ("CHARGING", 0)])

    def test_duplicate_records_use_the_freshest(self):
        ghost = {"uid": 2, "evse_id": "AAA-E-0001-A", "status": "INOPERATIVE", "last_updated": "2026-07-29T09:00:00", "connectors": []}
        store.apply_locations(self.db, [location(extra_evse=ghost)], "2026-10-09T10:00:00Z")
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM evses").fetchone()[0], 2)
        current = self.db.execute("SELECT uid, status FROM evses_current").fetchall()
        self.assertEqual([(r["uid"], r["status"]) for r in current], [(1, "AVAILABLE")])


class Tariffs(unittest.TestCase):
    def test_energy_price_components(self):
        tariff = {"elements": [{"price_components": [{"type": "ENERGY", "price": "0.3800"}, {"type": "TIME", "price": "0.1"}]}]}
        p = energy_price(tariff)
        self.assertEqual((p["ENERGY"], p["TIME"], p["FLAT"]), (0.38, 0.1, None))


class Export(unittest.TestCase):
    def test_snapshot_uses_tariff_price_and_city_filter(self):
        db = store.connect(":memory:")
        store.apply_locations(db, [location()], "2026-10-09T10:00:00Z")
        store.apply_tariffs(db, [{"id": "t1", "party_id": "AAA", "currency": "EUR", "last_updated": "x",
                                  "elements": [{"price_components": [{"type": "ENERGY", "price": "0.41"}]}]}])
        snap = build_snapshot(db, "Vilnius")
        self.assertEqual(len(snap["stations"]), 1)
        evse = snap["stations"][0]["evses"][0]
        self.assertEqual((evse["eurPerKwh"], evse["connectors"][0]["type"], evse["connectors"][0]["kw"]), (0.41, "CCS2", 50.0))
        self.assertEqual(build_snapshot(db, "Kaunas")["stations"], [])
        self.assertIn("CC BY 4.0", snap["attribution"])

    def test_report_runs_on_a_small_database(self):
        db = store.connect(":memory:")
        store.apply_locations(db, [location("OUTOFORDER")], "2026-10-09T10:00:00Z")
        self.assertIn("Reliability by operator", build_report(db))


@unittest.skipUnless(WORKBOOK.exists(), "registry workbook not present")
class Registry(unittest.TestCase):
    def test_workbook_parses(self):
        rows = read_registry(str(WORKBOOK))
        self.assertGreater(len(rows), 5000)
        self.assertTrue(all(r["evse_id"] for r in rows))
        first = rows[0]
        self.assertIsInstance(first["power_kw"], float)
        self.assertIsInstance(first["avg_price_eur_kwh"], float)
        self.assertIn(first["smart_charging"], (True, False))
        self.assertTrue(54 < first["lat"] < 57 and 20 < first["lng"] < 27)  # Lithuania


if __name__ == "__main__":
    unittest.main()
