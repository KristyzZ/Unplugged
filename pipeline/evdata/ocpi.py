"""Crawler for the Via Lietuva OCPI 2.3.0 feed (open, no API key).

The feed paginates with `limit`/`offset`, but its `Link: rel="next"` header is
malformed, so we page by offset ourselves until `X-Total-Count` is covered.
Pages are shorter than `limit` because unpublished locations are filtered out.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field

from . import OCPI_BASE
from .http import fetch_json

PAGE = 1000   # the feed accepts limit=1000: the whole country is ~4 requests instead of ~33


@dataclass
class Crawl:
    items: list[dict] = field(default_factory=list)
    expected_total: int = 0
    pages: int = 0
    failed_offsets: list[int] = field(default_factory=list)

    @property
    def complete(self) -> bool:
        return not self.failed_offsets and self.pages > 0


def crawl(endpoint: str, *, pause: float = 0.15, log=lambda msg: None) -> Crawl:
    """Fetch every item of an OCPI list endpoint (`locations` or `tariffs`)."""
    result = Crawl()
    seen: set = set()
    offset = 0
    total = None
    while total is None or offset < total:
        before = len(result.items)
        url = f"{OCPI_BASE}/{endpoint}?limit={PAGE}&offset={offset}"
        try:
            headers, body = fetch_json(url)
        except RuntimeError as error:
            log(f"  offset {offset}: {error}")
            result.failed_offsets.append(offset)
            if total is None:
                break  # cannot even learn the total; give up
            offset += PAGE
            continue
        if total is None:
            total = int(headers.get("x-total-count", "0") or 0)
            result.expected_total = total
        for item in body.get("data") or []:
            key = item.get("id")
            if key in seen:
                continue
            seen.add(key)
            result.items.append(item)
        result.pages += 1
        offset += PAGE
        if not total and len(result.items) == before:
            break  # no count header (e.g. /tariffs, which ignores paging) and nothing new: done
        if not total:
            total = None  # keep going until a page adds nothing
        time.sleep(pause)
    return result


def trim_tariff(tariff: dict) -> dict:
    """The part of an OCPI tariff the app needs: per element whether it is restricted (time, date,
    duration or energy conditions) and its price components. The app resolves it the same way
    `energy_price` does."""
    elements = []
    for element in tariff.get("elements") or []:
        components = []
        for c in element.get("price_components") or []:
            try:
                components.append({"type": c["type"], "price": float(c["price"]), "step": c.get("step_size")})
            except (KeyError, TypeError, ValueError):
                continue
        elements.append({"restricted": bool(element.get("restrictions")), "components": components})
    return {"id": tariff.get("id"), "currency": tariff.get("currency") or "", "elements": elements}


def energy_price(tariff: dict) -> dict:
    """Flatten an OCPI tariff into per-kWh / per-minute / flat prices (EUR).

    The everyday price comes from unrestricted elements; a tariff made only of restricted elements
    uses its first energy element. TIME is per hour in OCPI and is returned per hour."""
    trimmed = trim_tariff(tariff)
    unrestricted = [e for e in trimmed["elements"] if not e["restricted"]]

    def first(kind: str, elements: list) -> float | None:
        return next((c["price"] for e in elements for c in e["components"] if c["type"] == kind), None)

    return {
        "ENERGY": first("ENERGY", unrestricted) if first("ENERGY", unrestricted) is not None else first("ENERGY", trimmed["elements"]),
        "TIME": first("TIME", unrestricted),
        "FLAT": first("FLAT", unrestricted),
        "PARKING_TIME": first("PARKING_TIME", unrestricted),
    }
