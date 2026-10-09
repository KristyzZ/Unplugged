"""Plain-text findings from the database. Also the quickest way to sanity-check a crawl."""
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

VILNIUS_TZ = ZoneInfo("Europe/Vilnius")
BROKEN = ("INOPERATIVE", "OUTOFORDER")


def _age_days(source_last_updated: str | None, now: datetime) -> float | None:
    """`last_updated` is published as local time without a zone."""
    if not source_last_updated:
        return None
    try:
        then = datetime.fromisoformat(source_last_updated[:19]).replace(tzinfo=VILNIUS_TZ)
    except ValueError:
        return None
    return (now - then).total_seconds() / 86400


def build_report(db: sqlite3.Connection) -> str:
    now = datetime.now(timezone.utc)
    q = lambda sql, *a: db.execute(sql, a).fetchall()
    one = lambda sql, *a: db.execute(sql, a).fetchone()[0]
    out: list[str] = []
    add = out.append

    n_loc, n_evse = one("SELECT COUNT(*) FROM locations"), one("SELECT COUNT(*) FROM evses_current")
    n_records = one("SELECT COUNT(*) FROM evses")
    last = q("SELECT * FROM crawl_runs WHERE kind='locations' ORDER BY id DESC LIMIT 1")
    add("== Network snapshot ==")
    if last:
        r = last[0]
        add(f"last crawl {r['finished_at']}: {r['locations']} locations (source reports {r['expected_total']} incl. unpublished), "
            f"complete={bool(r['complete'])}")
    add(f"{n_loc} locations, {n_evse} distinct chargers ({n_records} records in the feed)")
    dup = q("""SELECT evse_id, COUNT(*) n, COUNT(DISTINCT status) s FROM evses GROUP BY evse_id HAVING n > 1""")
    add(f"data quality: {len(dup)} chargers appear more than once; {sum(1 for d in dup if d['s'] > 1)} of those disagree on status")
    for row in q("SELECT status, COUNT(*) n FROM evses_current GROUP BY status ORDER BY n DESC"):
        add(f"  {row['status']:<12} {row['n']:>5}  {100 * row['n'] / max(n_evse, 1):.1f}%")
    blocked = one("SELECT COUNT(*) FROM evses_current WHERE status = ?", "BLOCKED")
    add(f"BLOCKED reported by any charger: {blocked}  (the OCPI status for 'a car is in the way')")

    vil = "l.city LIKE 'Vilnius%'"
    add("\n== Vilnius ==")
    add(f"{one(f'SELECT COUNT(*) FROM locations l WHERE {vil}')} locations, "
        f"{one(f'SELECT COUNT(*) FROM evses_current e JOIN locations l ON l.id=e.location_id WHERE {vil}')} chargers")
    for row in q(f"SELECT e.status, COUNT(*) n FROM evses_current e JOIN locations l ON l.id=e.location_id WHERE {vil} GROUP BY e.status ORDER BY n DESC"):
        add(f"  {row['status']:<12} {row['n']:>5}")

    add("\n== Reliability by operator (chargers out of order / inoperative) ==")
    add(f"{'operator':<28}{'chargers':>9}{'broken':>8}{'%':>6}")
    for row in q("""SELECT COALESCE(o.name, l.party_id) AS op_name, COUNT(*) total,
                    SUM(e.status IN ('INOPERATIVE','OUTOFORDER')) broken
                    FROM evses_current e JOIN locations l ON l.id=e.location_id LEFT JOIN operators o ON o.party_id=l.party_id
                    GROUP BY op_name HAVING total >= 20 ORDER BY 1.0*broken/total DESC"""):
        add(f"{(row['op_name'] or '?')[:27]:<28}{row['total']:>9}{row['broken']:>8}{100 * row['broken'] / row['total']:>6.0f}")

    ages = sorted(a for a in (_age_days(r["last_updated"], now) for r in
                              q("SELECT last_updated FROM evses_current WHERE status IN ('INOPERATIVE','OUTOFORDER')")) if a is not None)
    add("\n== How long have broken chargers been broken? (from the feed's last_updated; verify before quoting) ==")
    if ages:
        add(f"{len(ages)} broken: >1 day {sum(a > 1 for a in ages)}, >7 days {sum(a > 7 for a in ages)}, "
            f">30 days {sum(a > 30 for a in ages)}, >90 days {sum(a > 90 for a in ages)}; median {ages[len(ages) // 2]:.1f} days")

    reg = one("SELECT COUNT(*) FROM registry")
    add("\n== Registry workbook ==")
    if reg:
        joined = one("SELECT COUNT(*) FROM evses_current e JOIN registry r ON r.evse_id=e.evse_id")
        add(f"{reg} access points; {joined}/{n_evse} live chargers matched by evse_id")
        c = lambda col, v=1: one(f"SELECT COUNT(*) FROM registry WHERE {col}=?", v)
        add(f"smart charging: {c('smart_charging')}   two-way (V2G): {c('bidirectional')}   disabled access: {c('disabled_access')}   "
            f"100% renewable: {c('renewable')}")
        no_pay = one("SELECT COUNT(*) FROM registry WHERE payment_methods IS NULL")
        no_hours = one("SELECT COUNT(*) FROM registry WHERE opening_hours IS NULL OR opening_hours = ?", "Nenurodyta")
        add(f"no payment method listed: {no_pay}   opening hours unspecified: {no_hours}")
        add(f"power: <=7 kW {one('SELECT COUNT(*) FROM registry WHERE power_kw<=7')}, 7-22 kW {one('SELECT COUNT(*) FROM registry WHERE power_kw>7 AND power_kw<=22')}, "
            f"22-50 kW {one('SELECT COUNT(*) FROM registry WHERE power_kw>22 AND power_kw<=50')}, >50 kW {one('SELECT COUNT(*) FROM registry WHERE power_kw>50')}")
    else:
        add("not loaded (run: python -m evdata load-registry)")

    ev = one("SELECT COUNT(*) FROM status_events WHERE first_seen=0")
    span = q("SELECT MIN(observed_at) a, MAX(observed_at) b FROM status_events")[0]
    add("\n== History we have collected ==")
    add(f"{ev} status changes observed since first crawl ({span['a']} → {span['b']})")
    return "\n".join(out)
