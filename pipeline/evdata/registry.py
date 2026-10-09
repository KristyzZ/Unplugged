"""Reader for the registry workbook (EV_IS_*.xlsx) using only the standard library.

The sheet's headers are Lithuanian; we map columns to English field names and
check a keyword from each header so a changed export layout fails loudly.
The workbook itself is read-only input and is never modified.
"""
from __future__ import annotations

import re
import zipfile
import xml.etree.ElementTree as ET

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}

# column letter -> (field, header keyword expected, converter)
def _yes(v): return None if v in (None, "") else v.strip().lower() == "taip"
def _text(v): return None if v in (None, "") else v.strip()
def _num(v):
    try: return float(str(v).replace(",", "."))
    except (TypeError, ValueError): return None
def _int(v):
    n = _num(v)
    return None if n is None else int(n)
def _price(v):
    m = re.search(r"[\d.,]+", v or "")
    return _num(m.group(0)) if m else None
def _lines(v): return None if v in (None, "") else ", ".join(p.strip() for p in v.splitlines() if p.strip())

COLUMNS = {
    "B": ("station_code", "stotelės identifikacinis", _text),
    "C": ("evse_id", "prieigos identifikacinis", _text),
    "D": ("opening_hours", "darbo laikas", _lines),
    "E": ("vehicle_class", "lengvajam", _text),
    "F": ("owner", "savininkas", _text),
    "G": ("operator", "operatorius", _text),
    "H": ("installed_at", "įrengimo data", _text),
    "J": ("place", "vieta", _text),
    "L": ("lat", "X koordinatės", _num),
    "M": ("lng", "Y koordinatės", _num),
    "N": ("connector_count", "jungčių skaičius", _int),
    "O": ("connector_types", "jungčių tipas", _lines),
    "P": ("power_kw", "individuali atiduodama galia", _num),
    "Q": ("current_type", "srovės rūšis", _lines),
    "S": ("max_power_kw", "maksimali atiduodamoji galia", _num),
    "T": ("payment_methods", "Atsiskaitymo", _lines),
    "U": ("avg_price_eur_kwh", "Vidutinė įkrovimo kaina", _price),
    "W": ("smart_charging", "išmanusis įkrovimas", _yes),
    "X": ("bidirectional", "abikryptis", _yes),
    "Y": ("station_power_kw", "Suminė", _num),
    "Z": ("in_charging_park", "įkrovimo parke", _yes),
    "AA": ("park_power_kw", "parko atiduodamąją galią", _num),
    "AB": ("disabled_access", "asmenims su negalia", _yes),
    "AC": ("special_needs_access", "specialiųjų poreikių", _yes),
    "AD": ("renewable", "atsinaujinančių", _yes),
}


def _shared_strings(z: zipfile.ZipFile) -> list[str]:
    root = ET.fromstring(z.read("xl/sharedStrings.xml"))
    return ["".join(t.text or "" for t in si.iter(f"{{{NS['m']}}}t")) for si in root.findall("m:si", NS)]


def read_registry(path: str) -> list[dict]:
    """Return one dict per access point (row), keyed by English field names."""
    with zipfile.ZipFile(path) as z:
        strings = _shared_strings(z)
        sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
    rows: list[dict[str, str]] = []
    for row in sheet.iter(f"{{{NS['m']}}}row"):
        cells: dict[str, str] = {}
        for c in row.findall("m:c", NS):
            v = c.find("m:v", NS)
            if v is None or v.text is None:
                continue
            col = re.match(r"[A-Z]+", c.get("r")).group(0)
            cells[col] = strings[int(v.text)] if c.get("t") == "s" else v.text
        rows.append(cells)
    if not rows:
        raise ValueError("empty workbook")
    header, body = rows[0], rows[1:]
    for col, (field, keyword, _) in COLUMNS.items():
        if keyword.lower() not in (header.get(col, "")).lower():
            raise ValueError(f"column {col} ({field}): expected header containing '{keyword}', got {header.get(col)!r}")
    out = []
    for cells in body:
        record = {field: conv(cells.get(col)) for col, (field, _, conv) in COLUMNS.items()}
        if record["evse_id"]:
            out.append(record)
    return out
