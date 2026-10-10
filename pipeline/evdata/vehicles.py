"""Electric car models and their charging specs, for the app's car picker,
range estimates and charge-time maths.

Source: Open EV Data (https://github.com/KilowattApp/open-ev-data), MIT licence
with an attribution requirement — keep VEHICLES_ATTRIBUTION visible wherever the
data is used (the app shows it on the car pages).

The upstream file mixes curated entries with scraped ones and has some obvious
data-entry slips, so `build_catalog` cleans it:
  * cars and microcars only (no motorbikes);
  * drops scraped records (they carry `_model_hash` and have broken names such
    as an Audi called "50 quattro");
  * drops implausible rows (battery, consumption, power out of range);
  * caps AC power at 22 kW (a few rows list the DC figure there);
  * maps plugs to what Lithuanian stations offer: CCS2, CHAdeMO, Type 2
    (Type 1 cars charge from Type 2 sockets with their own cable; the old
    Tesla Supercharger-only plug is dropped);
  * merges duplicates that differ only in letter case or spacing.
"""
from __future__ import annotations

import json
import re
import time
from pathlib import Path

from .http import fetch_json

VEHICLES_SOURCE = "https://raw.githubusercontent.com/KilowattApp/open-ev-data/master/data/ev-data.json"
VEHICLES_ATTRIBUTION = "Car data: Open EV Data (https://github.com/KilowattApp/open-ev-data), MIT licence."

BRAND_NAMES = {"Opel / Vauxhall": "Opel", "Mercedes": "Mercedes-Benz"}

# The app's earlier built-in cars, so a saved choice keeps working.
# Values are id prefixes in the source; the build fails if one stops matching.
LEGACY_ALIASES = {
    "model-y": "3012e28f",   # Tesla Model Y Long Range Dual Motor (2022)
    "model-3": "a9461623",   # Tesla Model 3 RWD (2022)
    "id4": "2d7c8848",       # Volkswagen ID.4 Pro Performance (2021)
    "ioniq5": "b58bc94d",    # Hyundai IONIQ 5 Long Range 2WD (2021)
    "ev3": "7a854fa3",       # Kia EV3 Long Range (2024)
    "enyaq": "8c8b6921",     # Skoda Enyaq 85 (2023)
    "leaf": "77028f96",      # Nissan Leaf 40 kWh (2018)
    "dolphin": "352427b1",   # BYD Dolphin 60.5 kWh (2023)
}

AC_PORTS = {"type2": "Type2", "type1": "Type2"}
DC_PORTS = {"ccs": "CCS2", "tesla_ccs": "CCS2", "chademo": "CHAdeMO"}


def _clean(text: str | None) -> str:
    text = re.sub(r"\s+", " ", (text or "").strip())
    return text.rstrip(".").strip()


def _key(*parts) -> str:
    return "|".join(re.sub(r"[\s\-_.]", "", str(p)).lower() for p in parts)


def _curve(dc: dict, max_kw: float) -> list[list[float]]:
    points = {}
    for point in dc.get("charging_curve") or []:
        pct, kw = point.get("percentage"), point.get("power")
        if pct is None or kw is None or not 0 <= pct <= 100 or kw <= 0:
            continue
        points[round(float(pct))] = round(min(float(kw), max_kw), 1)
    if not points:
        return []
    curve = [[pct, points[pct]] for pct in sorted(points)]
    # Make sure the curve covers 0–100 % so the app never extrapolates.
    if curve[0][0] > 0:
        curve.insert(0, [0, curve[0][1]])
    if curve[-1][0] < 100:
        curve.append([100, curve[-1][1]])
    return curve


def clean_vehicle(raw: dict) -> dict | None:
    """One source record → one app record, or None when it isn't usable."""
    if raw.get("vehicle_type", "car") not in ("car", "microcar"):
        return None
    if "_model_hash" in raw:
        return None
    brand = BRAND_NAMES.get(_clean(raw.get("brand")), _clean(raw.get("brand")))
    model = _clean(raw.get("model"))
    variant = _clean(raw.get("variant"))
    if not brand or not model:
        return None

    battery = float(raw.get("usable_battery_size") or 0)
    consumption = float((raw.get("energy_consumption") or {}).get("average_consumption") or 0)
    if not 5 <= battery <= 250 or not 8 <= consumption <= 45:
        return None

    ac = raw.get("ac_charger") or {}
    ac_kw = min(float(ac.get("max_power") or 0), 22.0)
    ac_ports = [AC_PORTS[p] for p in ac.get("ports") or [] if p in AC_PORTS]

    dc = raw.get("dc_charger") or {}
    dc_kw = float(dc.get("max_power") or 0)
    dc_ports = [DC_PORTS[p] for p in dc.get("ports") or [] if p in DC_PORTS]
    if not 20 <= dc_kw <= 500 or not dc_ports:
        dc_kw, dc_ports = 0.0, []

    connectors = list(dict.fromkeys(dc_ports + (ac_ports if ac_kw > 0 else [])))
    if not connectors:
        return None

    year = raw.get("release_year")
    record = {
        "id": raw["id"],
        "brand": brand,
        "model": model,
        "variant": variant,
        "year": int(year) if year else None,
        "batteryKwh": round(battery, 1),
        "consumptionKwhPer100": round(consumption, 1),
        "acKw": round(ac_kw, 1),
        "acPhases": ac.get("usable_phases"),
        "dcKw": round(dc_kw, 1),
        "connectors": connectors,
    }
    if dc_kw:
        record["curve"] = _curve(dc, dc_kw)
        record["curveMeasured"] = not dc.get("is_default_charging_curve", True)
    return record


def build_catalog(source: dict) -> dict:
    vehicles, seen = [], set()
    for raw in source.get("data", []):
        record = clean_vehicle(raw)
        if record is None:
            continue
        key = _key(record["brand"], record["model"], record["variant"], record["year"])
        if key in seen:
            continue
        seen.add(key)
        vehicles.append(record)
    vehicles.sort(key=lambda v: (v["brand"].lower(), v["model"].lower(), v["variant"].lower(), -(v["year"] or 0)))

    aliases = {}
    for legacy, prefix in LEGACY_ALIASES.items():
        matches = [v["id"] for v in vehicles if v["id"].startswith(prefix)]
        if len(matches) != 1:
            raise ValueError(f"alias {legacy!r}: expected one vehicle with id {prefix}…, found {len(matches)}")
        aliases[legacy] = matches[0]

    return {
        "source": VEHICLES_SOURCE,
        "attribution": VEHICLES_ATTRIBUTION,
        "sourceUpdatedAt": (source.get("meta") or {}).get("updated_at"),
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "count": len(vehicles),
        "aliases": aliases,
        "vehicles": vehicles,
    }


def write_catalog(catalog: dict, out: str) -> None:
    """One vehicle per line: small file, readable diffs when the data is refreshed."""
    head = {k: v for k, v in catalog.items() if k != "vehicles"}
    lines = [json.dumps(v, ensure_ascii=False, separators=(",", ":")) for v in catalog["vehicles"]]
    text = json.dumps(head, ensure_ascii=False, indent=1)[:-2] + ',\n "vehicles": [\n  ' + ",\n  ".join(lines) + "\n ]\n}\n"
    json.loads(text)  # never write a file the app can't read
    path = Path(out)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def import_vehicles(out: str, src: str | None = None) -> dict:
    if src and not src.startswith("http"):
        source = json.loads(Path(src).read_text(encoding="utf-8"))
    else:
        _, source = fetch_json(src or VEHICLES_SOURCE)
    catalog = build_catalog(source)
    write_catalog(catalog, out)
    return catalog
