import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline"))

from evdata import vehicles  # noqa: E402

BUNDLED = ROOT / "ios/Unplugged/Data/vehicles.json"


def raw(**overrides):
    record = {
        "id": "11111111-aaaa", "brand": "Hyundai", "model": "IONIQ 5", "variant": "Long Range 2WD",
        "vehicle_type": "car", "release_year": 2021, "usable_battery_size": 74,
        "energy_consumption": {"average_consumption": 18.5},
        "ac_charger": {"ports": ["type2"], "usable_phases": 3, "max_power": 11},
        "dc_charger": {"ports": ["ccs"], "max_power": 233, "is_default_charging_curve": False,
                       "charging_curve": [{"percentage": 10, "power": 220}, {"percentage": 80, "power": 120}]},
    }
    record.update(overrides)
    return record


class CleanVehicle(unittest.TestCase):
    def test_keeps_a_normal_car(self):
        v = vehicles.clean_vehicle(raw())
        self.assertEqual(v["connectors"], ["CCS2", "Type2"])
        self.assertEqual(v["dcKw"], 233)
        self.assertTrue(v["curveMeasured"])

    def test_curve_is_padded_to_cover_0_to_100(self):
        curve = vehicles.clean_vehicle(raw())["curve"]
        self.assertEqual(curve[0], [0, 220])
        self.assertEqual(curve[-1], [100, 120])

    def test_drops_motorbikes_and_scraped_records(self):
        self.assertIsNone(vehicles.clean_vehicle(raw(vehicle_type="motorbike")))
        self.assertIsNone(vehicles.clean_vehicle(raw(_model_hash="abc")))

    def test_drops_implausible_numbers(self):
        self.assertIsNone(vehicles.clean_vehicle(raw(usable_battery_size=0)))
        self.assertIsNone(vehicles.clean_vehicle(raw(energy_consumption={"average_consumption": 80})))

    def test_caps_ac_and_maps_plugs(self):
        v = vehicles.clean_vehicle(raw(
            ac_charger={"ports": ["type1"], "max_power": 39},
            dc_charger={"ports": ["chademo", "tesla_suc"], "max_power": 50, "charging_curve": []},
        ))
        self.assertEqual(v["acKw"], 22)
        self.assertEqual(v["connectors"], ["CHAdeMO", "Type2"])

    def test_tidies_names(self):
        v = vehicles.clean_vehicle(raw(brand="Opel / Vauxhall", model="  Corsa-e. ", variant=""))
        self.assertEqual((v["brand"], v["model"]), ("Opel", "Corsa-e"))


class Catalog(unittest.TestCase):
    def test_merges_case_duplicates_and_writes_valid_json(self):
        source = {"meta": {"updated_at": "2025-01-01"}, "data": [
            raw(id="b58bc94d-1"), raw(id="dup", model="ioniq  5"),
        ]}
        saved = vehicles.LEGACY_ALIASES
        vehicles.LEGACY_ALIASES = {"ioniq5": "b58bc94d"}
        try:
            catalog = vehicles.build_catalog(source)
        finally:
            vehicles.LEGACY_ALIASES = saved
        self.assertEqual(catalog["count"], 1)
        self.assertEqual(catalog["aliases"], {"ioniq5": "b58bc94d-1"})
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "vehicles.json"
            vehicles.write_catalog(catalog, str(out))
            self.assertEqual(json.loads(out.read_text())["vehicles"][0]["id"], "b58bc94d-1")

    def test_bundled_file_is_consistent(self):
        catalog = json.loads(BUNDLED.read_text())
        ids = {v["id"] for v in catalog["vehicles"]}
        self.assertEqual(len(ids), catalog["count"])
        self.assertTrue(set(catalog["aliases"].values()) <= ids)
        for v in catalog["vehicles"]:
            self.assertTrue(v["connectors"])
            if v["dcKw"]:
                self.assertEqual((v["curve"][0][0], v["curve"][-1][0]), (0, 100))


if __name__ == "__main__":
    unittest.main()
