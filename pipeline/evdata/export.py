"""Compact JSON snapshot for the iOS app (offline fallback / bundled demo data)."""
from __future__ import annotations

import json
import sqlite3

from . import ATTRIBUTION
from .db import now_utc

KW = {"IEC_62196_T2": "Type2", "IEC_62196_T2_COMBO": "CCS2", "CHADEMO": "CHAdeMO"}


def build_snapshot(db: sqlite3.Connection, city: str | None = None) -> dict:
    tariffs = {r["id"]: r["energy_eur_kwh"] for r in db.execute("SELECT id, energy_eur_kwh FROM tariffs")}
    registry = {r["evse_id"]: r for r in db.execute("SELECT * FROM registry")}
    operators = {r["party_id"]: r["name"] for r in db.execute("SELECT party_id, name FROM operators")}
    where, args = ("WHERE city LIKE ?", (f"{city}%",)) if city else ("", ())
    stations = []
    for loc in db.execute(f"SELECT * FROM locations {where} ORDER BY id", args):
        evses = []
        for e in db.execute("SELECT * FROM evses_current WHERE location_id=? ORDER BY uid", (loc["id"],)):
            conns = db.execute("SELECT * FROM connectors WHERE evse_uid=?", (e["uid"],)).fetchall()
            price = next((tariffs[t] for c in conns for t in json.loads(c["tariff_ids"] or "[]") if tariffs.get(t) is not None), None)
            reg = registry.get(e["evse_id"])
            if price is None and reg:
                price = reg["avg_price_eur_kwh"]
            evses.append({
                "id": e["evse_id"], "status": e["status"], "updated": e["last_updated"],
                "connectors": [{"type": KW.get(c["standard"], c["standard"]), "kw": (c["max_power_w"] or 0) / 1000} for c in conns],
                "eurPerKwh": price,
                "disabledAccess": bool(reg["disabled_access"]) if reg and reg["disabled_access"] is not None else None,
                "renewable": bool(reg["renewable"]) if reg and reg["renewable"] is not None else None,
            })
        if evses:
            stations.append({"id": loc["id"], "name": loc["name"], "address": loc["address"], "city": loc["city"],
                             "lat": loc["lat"], "lng": loc["lng"], "operator": operators.get(loc["party_id"]) or loc["party_id"],
                             "evses": evses})
    return {"generatedAt": now_utc(), "attribution": ATTRIBUTION, "stations": stations}


def write_snapshot(db: sqlite3.Connection, path: str, city: str | None = None) -> int:
    snapshot = build_snapshot(db, city)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(snapshot, f, ensure_ascii=False, separators=(",", ":"))
    return len(snapshot["stations"])
