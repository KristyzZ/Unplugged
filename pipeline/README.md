# EV data pipeline

Turns Lithuania's open charging-station data into a local database the Unplugged app and a city dashboard can use.

| Source | What it gives us | License |
|---|---|---|
| Live OCPI 2.3.0 feed `https://ev.vialietuva.lt/ocpi/2.3.0/{locations,tariffs}` | stations, chargers, **live status**, connectors, tariffs | CC BY 4.0 / ODC-BY 1.0 |
| `EV_IS_2026-10-09.xlsx` (repo root, never modified) | payment methods, opening hours, accessibility, renewables, smart/V2G, station power | open data export |

The two join on the charger id (`evse_id`): 5,734 of 5,737 live chargers match.
Please keep the attribution "Contains data from Via Lietuva (ev.vialietuva.lt), CC BY 4.0" wherever the data is shown.

## Quick start (Python 3.10+, standard library only)

```bash
python3 pipeline/run.py crawl            # ~1 min: 33 pages of locations + tariffs -> pipeline/data/ev.sqlite
python3 pipeline/run.py load-registry    # Excel -> registry table
python3 pipeline/run.py report           # findings (reliability, outages, accessibility, data quality)
python3 pipeline/run.py poll             # keep crawling every 5 min and record every status change
python3 pipeline/run.py export --city Vilnius   # compact JSON for the app (pipeline/data/stations.json)
python3 -m unittest discover -s pipeline/tests
```
`--db PATH` (before the command) puts the database somewhere else, e.g. outside the repo so it survives worktree cleanup.

## Why run the poller early
The feed only shows the *current* status. `poll` appends a row to `status_events` whenever a charger changes state, so days of
running gives real busy-hour curves, turnover times and how long chargers stay broken, none of which exist in the open data.

## Tables (`schema.sql`)
`operators`, `locations`, `evses`, `connectors`, `tariffs`, `registry`, `status_events` (history), `crawl_runs` (audit),
and the view `evses_current` (freshest record per charger; use it for statistics).

## Things we learned about the data (read before quoting numbers)
- **Pagination:** `X-Total-Count` is 3,273 but only ~1,984 locations are published; the `Link: rel="next"` header is malformed, so we page by `offset`.
- **Duplicates:** ~95 charger ids appear under several records at the same location, ~18 with conflicting statuses (e.g. one "inoperative since July", one "available"). Always use `evses_current`.
- **`last_updated` has no time zone** and is local Lithuanian time. `date_from` filtering is also read as local time.
- **No `BLOCKED` status:** the OCPI standard defines it for "a car is in the way", but no charger reports it. The feed cannot tell us about cars parked after charging; that signal has to come from drivers/sensors.
- **"Broken for N days" is an estimate** from `last_updated`; confirm with the poller's own history before putting it in a pitch.
- The server gzips responses (~18x smaller); the client asks for it. Default poll interval is 5 min to stay polite.

## Moving to hosted Postgres (e.g. Supabase)
The schema is plain SQL. Create the tables in Postgres (`TEXT`→`text`/`timestamptz`, add `geography(Point)` from `lat,lng` for radius queries),
then point a thin API at it. The crawler functions in `evdata/db.py` are the only SQLite-specific code (the `ON CONFLICT` upserts also work in Postgres).
