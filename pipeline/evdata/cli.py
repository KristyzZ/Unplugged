from __future__ import annotations

import argparse
import random
import sys
import time
from pathlib import Path

from . import db as store
from .ocpi import crawl
from .registry import read_registry
from .report import build_report
from .export import write_snapshot
from .vehicles import import_vehicles

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = str(ROOT / "pipeline/data/ev.sqlite")
DEFAULT_XLSX = str(ROOT / "EV_IS_2026-10-09.xlsx")
DEFAULT_SNAPSHOT = str(ROOT / "pipeline/data/stations.json")
# Bundled with the iOS app, so it's committed (unlike pipeline/data/).
DEFAULT_VEHICLES = str(ROOT / "ios/Unplugged/Data/vehicles.json")


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def crawl_locations(db) -> dict:
    started = store.now_utc()
    result = crawl("locations", log=log)
    summary = store.apply_locations(db, result.items, started)
    db.execute(
        "INSERT INTO crawl_runs(started_at, finished_at, kind, locations, evses, expected_total, complete, status_changes) "
        "VALUES (?,?,?,?,?,?,?,?)",
        (started, store.now_utc(), "locations", summary["locations"], summary["evses"], result.expected_total,
         int(result.complete), summary["status_changes"]),
    )
    db.commit()
    if not result.complete:
        log(f"WARNING: incomplete crawl, failed offsets {result.failed_offsets}")
    return summary | {"expected_total": result.expected_total, "complete": result.complete}


def crawl_tariffs(db) -> int:
    result = crawl("tariffs", log=log)
    n = store.apply_tariffs(db, result.items)
    db.execute("INSERT INTO crawl_runs(started_at, finished_at, kind, locations, expected_total, complete) VALUES (?,?,?,?,?,?)",
               (store.now_utc(), store.now_utc(), "tariffs", n, result.expected_total, int(result.complete)))
    db.commit()
    return n


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="evdata", description=__doc__)
    p.add_argument("--db", default=DEFAULT_DB, help="SQLite file (default: %(default)s)")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("crawl", help="one full crawl of locations + tariffs")
    reg = sub.add_parser("load-registry", help="load the Excel registry workbook")
    reg.add_argument("xlsx", nargs="?", default=DEFAULT_XLSX)
    poll = sub.add_parser("poll", help="crawl repeatedly and record status changes")
    poll.add_argument("--interval", type=int, default=300, help="seconds between crawls (default 300)")
    poll.add_argument("--tariff-every", type=int, default=12, help="refresh tariffs every N crawls (default 12 = hourly)")
    poll.add_argument("--once", action="store_true")
    sub.add_parser("report", help="print findings from the database")
    exp = sub.add_parser("export", help="write a JSON snapshot for the app")
    exp.add_argument("--out", default=DEFAULT_SNAPSHOT)
    exp.add_argument("--city", default=None, help="e.g. Vilnius")
    veh = sub.add_parser("vehicles", help="import electric car models and specs for the app")
    veh.add_argument("--out", default=DEFAULT_VEHICLES)
    veh.add_argument("--src", default=None, help="Open EV Data JSON (URL or file; default: GitHub)")
    args = p.parse_args(argv)

    if args.cmd == "vehicles":  # no database needed
        catalog = import_vehicles(args.out, args.src)
        log(f"wrote {catalog['count']} vehicles from {len({v['brand'] for v in catalog['vehicles']})} brands to {args.out}")
        return 0

    db = store.connect(args.db)
    if args.cmd == "crawl":
        log(f"locations: {crawl_locations(db)}")
        log(f"tariffs: {crawl_tariffs(db)}")
    elif args.cmd == "load-registry":
        log(f"registry rows loaded: {store.apply_registry(db, read_registry(args.xlsx))}")
    elif args.cmd == "poll":
        n = 0
        while True:
            try:
                s = crawl_locations(db)
                if n % args.tariff_every == 0:
                    crawl_tariffs(db)
                log(f"crawl #{n}: {s['locations']} locations, {s['evses']} chargers, {s['status_changes']} status changes, complete={s['complete']}")
            except Exception as error:  # keep the poller alive through network blips
                log(f"crawl #{n} failed: {error}")
            n += 1
            if args.once:
                break
            time.sleep(args.interval + random.uniform(0, 10))
    elif args.cmd == "report":
        print(build_report(db))
    elif args.cmd == "export":
        log(f"wrote {write_snapshot(db, args.out, args.city)} stations to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
