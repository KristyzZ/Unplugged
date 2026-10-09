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

PAGE = 100


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
        time.sleep(pause)
    return result


def energy_price(tariff: dict) -> dict:
    """Flatten an OCPI tariff into per-kWh / per-minute / flat prices (EUR)."""
    prices = {"ENERGY": None, "TIME": None, "FLAT": None, "PARKING_TIME": None}
    for element in tariff.get("elements") or []:
        for component in element.get("price_components") or []:
            kind = component.get("type")
            if kind in prices and prices[kind] is None:
                try:
                    prices[kind] = float(component["price"])
                except (KeyError, TypeError, ValueError):
                    pass
    return prices
