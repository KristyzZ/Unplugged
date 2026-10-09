import gzip
import json
import os
import ssl
import time
import urllib.error
import urllib.request

USER_AGENT = "unplugged-hackathon/0.1 (open-data research)"
# python.org builds of Python on macOS ship without CA certificates; fall back to the system bundle.
_SYSTEM_CA = "/etc/ssl/cert.pem"


def _open(url: str, timeout: float, context: ssl.SSLContext | None):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json", "Accept-Encoding": "gzip"})
    return urllib.request.urlopen(request, timeout=timeout, context=context)


def fetch(url: str, timeout: float = 60, retries: int = 3) -> tuple[dict[str, str], bytes]:
    """GET with retries. Returns (lower-cased headers, body)."""
    context: ssl.SSLContext | None = None
    last: Exception | None = None
    for attempt in range(retries):
        try:
            with _open(url, timeout, context) as response:
                headers = {k.lower(): v for k, v in response.headers.items()}
                body = response.read()
                if headers.get("content-encoding") == "gzip":
                    body = gzip.decompress(body)  # ~18x smaller on the wire
                return headers, body
        except urllib.error.URLError as error:
            last = error
            if isinstance(error.reason, ssl.SSLCertVerificationError) and context is None and os.path.exists(_SYSTEM_CA):
                context = ssl.create_default_context(cafile=_SYSTEM_CA)
                continue
        except (TimeoutError, ConnectionError, OSError) as error:
            last = error
        time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"GET {url} failed after {retries} attempts: {last}")


def fetch_json(url: str, **kwargs) -> tuple[dict[str, str], dict]:
    headers, body = fetch(url, **kwargs)
    return headers, json.loads(body)
