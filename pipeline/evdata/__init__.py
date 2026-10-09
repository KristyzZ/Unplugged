"""Open EV-charging data for Unplugged: crawl the Via Lietuva OCPI feed, load the
registry workbook, keep a status history in SQLite and export app snapshots."""

SOURCE_BASE = "https://ev.vialietuva.lt"
OCPI_BASE = f"{SOURCE_BASE}/ocpi/2.3.0"
ATTRIBUTION = "Contains data from Via Lietuva (ev.vialietuva.lt), licensed CC BY 4.0."
