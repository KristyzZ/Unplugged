"""SQLite store. The schema is deliberately plain so it ports to Postgres/PostGIS
(see schema.sql); timestamps are UTC ISO-8601 strings."""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from .ocpi import energy_price

SCHEMA = (Path(__file__).resolve().parent.parent / "schema.sql").read_text()
BROKEN = ("INOPERATIVE", "OUTOFORDER")


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def connect(path: str) -> sqlite3.Connection:
    if path != ":memory:":
        Path(path).parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    db.executescript(SCHEMA)
    return db


def apply_locations(db: sqlite3.Connection, locations: list[dict], observed_at: str) -> dict:
    """Upsert the static graph and record a status event whenever an EVSE's
    status differs from the last one we saw (or on first sight)."""
    changes = 0
    evses = 0
    with db:
        for loc in locations:
            operator = loc.get("operator") or {}
            coords = loc.get("coordinates") or {}
            db.execute(
                "INSERT INTO operators(party_id, name, website) VALUES (?,?,?) "
                "ON CONFLICT(party_id) DO UPDATE SET name=excluded.name, website=excluded.website",
                (loc.get("party_id"), operator.get("name"), operator.get("website")),
            )
            db.execute(
                "INSERT INTO locations(id, party_id, name, address, city, lat, lng, parking_type, time_zone, last_updated) "
                "VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET party_id=excluded.party_id, name=excluded.name, "
                "address=excluded.address, city=excluded.city, lat=excluded.lat, lng=excluded.lng, "
                "parking_type=excluded.parking_type, time_zone=excluded.time_zone, last_updated=excluded.last_updated",
                (loc["id"], loc.get("party_id"), loc.get("name"), loc.get("address"), loc.get("city"),
                 _f(coords.get("latitude")), _f(coords.get("longitude")), loc.get("parking_type"),
                 loc.get("time_zone"), loc.get("last_updated")),
            )
            for evse in loc.get("evses") or []:
                evses += 1
                previous = db.execute("SELECT status FROM evses WHERE uid=?", (evse["uid"],)).fetchone()
                db.execute(
                    "INSERT INTO evses(uid, evse_id, location_id, status, last_updated, observed_at) VALUES (?,?,?,?,?,?) "
                    "ON CONFLICT(uid) DO UPDATE SET evse_id=excluded.evse_id, location_id=excluded.location_id, "
                    "status=excluded.status, last_updated=excluded.last_updated, observed_at=excluded.observed_at",
                    (evse["uid"], evse.get("evse_id"), loc["id"], evse.get("status"), evse.get("last_updated"), observed_at),
                )
                if previous is None or previous["status"] != evse.get("status"):
                    changes += 1
                    db.execute(
                        "INSERT INTO status_events(evse_uid, evse_id, status, source_last_updated, observed_at, first_seen) "
                        "VALUES (?,?,?,?,?,?)",
                        (evse["uid"], evse.get("evse_id"), evse.get("status"), evse.get("last_updated"), observed_at,
                         1 if previous is None else 0),
                    )
                for conn in evse.get("connectors") or []:
                    db.execute(
                        "INSERT INTO connectors(id, evse_uid, standard, power_type, max_power_w, tariff_ids) VALUES (?,?,?,?,?,?) "
                        "ON CONFLICT(id) DO UPDATE SET evse_uid=excluded.evse_uid, standard=excluded.standard, "
                        "power_type=excluded.power_type, max_power_w=excluded.max_power_w, tariff_ids=excluded.tariff_ids",
                        (conn["id"], evse["uid"], conn.get("standard"), conn.get("power_type"),
                         conn.get("max_electric_power"), json.dumps(conn.get("tariff_ids") or [])),
                    )
    return {"locations": len(locations), "evses": evses, "status_changes": changes}


def apply_tariffs(db: sqlite3.Connection, tariffs: list[dict]) -> int:
    with db:
        for t in tariffs:
            p = energy_price(t)
            alt = next((a.get("text") for a in t.get("tariff_alt_text") or [] if a.get("language") == "lt"), None)
            db.execute(
                "INSERT INTO tariffs(id, party_id, currency, energy_eur_kwh, time_eur_min, flat_eur, description, last_updated) "
                "VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET party_id=excluded.party_id, currency=excluded.currency, "
                "energy_eur_kwh=excluded.energy_eur_kwh, time_eur_min=excluded.time_eur_min, flat_eur=excluded.flat_eur, "
                "description=excluded.description, last_updated=excluded.last_updated",
                (t["id"], t.get("party_id"), t.get("currency"), p["ENERGY"], p["TIME"], p["FLAT"], alt, t.get("last_updated")),
            )
    return len(tariffs)


REGISTRY_FIELDS = [
    "evse_id", "station_code", "opening_hours", "vehicle_class", "owner", "operator", "installed_at", "place",
    "lat", "lng", "connector_count", "connector_types", "power_kw", "current_type", "max_power_kw", "payment_methods",
    "avg_price_eur_kwh", "smart_charging", "bidirectional", "station_power_kw", "in_charging_park", "park_power_kw",
    "disabled_access", "special_needs_access", "renewable",
]


def apply_registry(db: sqlite3.Connection, rows: list[dict]) -> int:
    cols = ",".join(REGISTRY_FIELDS)
    marks = ",".join("?" for _ in REGISTRY_FIELDS)
    update = ",".join(f"{c}=excluded.{c}" for c in REGISTRY_FIELDS if c != "evse_id")
    with db:
        for r in rows:
            values = [(int(v) if isinstance(v, bool) else v) for v in (r.get(f) for f in REGISTRY_FIELDS)]
            db.execute(f"INSERT INTO registry({cols}) VALUES ({marks}) ON CONFLICT(evse_id) DO UPDATE SET {update}", values)
    return len(rows)


def _f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None
