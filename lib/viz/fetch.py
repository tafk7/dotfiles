"""Downloads for bundling (web fonts, pinned CDN files), cached by URL so a republish needs no network.

With VIZ_FETCH_FIXTURES set, responses come from that directory instead, one file per URL named
urllib.parse.quote(URL, safe=''), and the network is never touched (the tests run this way).
"""
import hashlib
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# Google Fonts answers with woff2 only to a browser it recognises.
BROWSER_UA = ('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/124.0.0.0 Safari/537.36')
LIMIT = 50 * 1024 * 1024   # bytes per download
CACHE = Path('~/.cache/viz').expanduser()


class FetchError(Exception):
    pass


def _download(url):
    fixtures = os.environ.get('VIZ_FETCH_FIXTURES')
    if fixtures:
        path = Path(fixtures) / urllib.parse.quote(url, safe='')
        if not path.is_file():
            raise FetchError(f'no recorded response for {url}')
        return path.read_bytes()
    if not url.startswith('https://'):
        raise FetchError(f'{url}: only https downloads')
    request = urllib.request.Request(url, headers={'User-Agent': BROWSER_UA})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(LIMIT + 1)
    except (urllib.error.URLError, OSError) as error:
        raise FetchError(f'{url}: {getattr(error, "reason", error)}') from None
    if len(data) > LIMIT:
        raise FetchError(f'{url}: larger than {LIMIT // 1024 // 1024} MB')
    return data


def fetch(url, kind):
    """URL's bytes, from the cache under CACHE/KIND/ when an earlier run downloaded it."""
    cached = CACHE / kind / hashlib.sha256(url.encode()).hexdigest()
    try:
        return cached.read_bytes()
    except FileNotFoundError:
        pass
    data = _download(url)
    cached.parent.mkdir(parents=True, exist_ok=True)
    tmp = cached.with_name(f'.{cached.name}.{os.getpid()}')
    tmp.write_bytes(data)
    tmp.replace(cached)
    return data


def sha256(data):
    return hashlib.sha256(data).hexdigest()
