-- SQLite schema (portable to Postgres: INTEGER PRIMARY KEY -> bigint, TEXT -> text/timestamptz,
-- add a PostGIS geography(lat,lng) column on locations for radius queries).
CREATE TABLE IF NOT EXISTS operators (
  party_id TEXT PRIMARY KEY, name TEXT, website TEXT
);
CREATE TABLE IF NOT EXISTS locations (
  id INTEGER PRIMARY KEY, party_id TEXT, name TEXT, address TEXT, city TEXT,
  lat REAL, lng REAL, parking_type TEXT, time_zone TEXT, last_updated TEXT
);
CREATE TABLE IF NOT EXISTS evses (
  uid INTEGER PRIMARY KEY, evse_id TEXT, location_id INTEGER REFERENCES locations(id),
  status TEXT, last_updated TEXT,           -- last_updated is local Lithuanian time without a zone (as published)
  observed_at TEXT                          -- UTC time of the crawl that last saw this EVSE
);
CREATE INDEX IF NOT EXISTS idx_evses_evse_id ON evses(evse_id);
-- The feed contains duplicate records for the same charger (same evse_id, different uid, sometimes
-- with conflicting status). Statistics use the freshest record per evse_id.
CREATE VIEW IF NOT EXISTS evses_current AS
  SELECT * FROM evses e WHERE e.uid = (
    SELECT x.uid FROM evses x WHERE x.evse_id = e.evse_id ORDER BY x.last_updated DESC, x.uid DESC LIMIT 1);
CREATE TABLE IF NOT EXISTS connectors (
  id INTEGER PRIMARY KEY, evse_uid INTEGER REFERENCES evses(uid), standard TEXT, power_type TEXT,
  max_power_w INTEGER, tariff_ids TEXT       -- JSON array of tariff ids
);
CREATE TABLE IF NOT EXISTS tariffs (
  id TEXT PRIMARY KEY, party_id TEXT, currency TEXT, energy_eur_kwh REAL, time_eur_min REAL,
  flat_eur REAL, description TEXT, last_updated TEXT
);
-- Workbook rows, joined to OCPI on evse_id (100% of OCPI EVSEs match).
CREATE TABLE IF NOT EXISTS registry (
  evse_id TEXT PRIMARY KEY, station_code TEXT, opening_hours TEXT, vehicle_class TEXT, owner TEXT, operator TEXT,
  installed_at TEXT, place TEXT, lat REAL, lng REAL, connector_count INTEGER, connector_types TEXT, power_kw REAL,
  current_type TEXT, max_power_kw REAL, payment_methods TEXT, avg_price_eur_kwh REAL, smart_charging INTEGER,
  bidirectional INTEGER, station_power_kw REAL, in_charging_park INTEGER, park_power_kw REAL,
  disabled_access INTEGER, special_needs_access INTEGER, renewable INTEGER
);
-- Append-only history: one row each time an EVSE's status changes (and the first time it is seen).
CREATE TABLE IF NOT EXISTS status_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT, evse_uid INTEGER, evse_id TEXT, status TEXT,
  source_last_updated TEXT, observed_at TEXT, first_seen INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_events_evse ON status_events(evse_uid, observed_at);
CREATE TABLE IF NOT EXISTS crawl_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT, started_at TEXT, finished_at TEXT, kind TEXT,
  locations INTEGER, evses INTEGER, expected_total INTEGER, complete INTEGER, status_changes INTEGER, note TEXT
);
