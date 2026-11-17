#!/usr/bin/env python3
"""Check local asset/fragment links and verify the downloadable app archive."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import hashlib
import zipfile

root = Path(__file__).resolve().parent.parent / 'docs'
class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.ids, self.downloads = [], set(), []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, f"Duplicate id: {attrs['id']}"
            self.ids.add(attrs['id'])
        for key in ('src', 'href'):
            if attrs.get(key):
                self.links.append(attrs[key])
        if 'download' in attrs:
            self.downloads.append(attrs['href'])

page = Links()
page.feed((root / 'index.html').read_text())
for link in page.links:
    parsed = urlsplit(link)
    if parsed.scheme or parsed.netloc:
        continue
    if parsed.path and parsed.path != './':
        assert (root / unquote(parsed.path)).is_file(), f'Missing file: {link}'
    if parsed.fragment and not parsed.path:
        assert parsed.fragment in page.ids, f'Missing section: {link}'
assert len(page.downloads) >= 2
for download in set(page.downloads):
    archive = root / download
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        assert 'Daymark.app/Contents/MacOS/Daymark' in bundle.namelist()
        assert 'Daymark.app/Contents/Info.plist' in bundle.namelist()
        assert not any(n.startswith('/') or '..' in Path(n).parts for n in bundle.namelist())
    expected = (root / 'downloads/SHA256SUMS.txt').read_text().split()[0]
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == expected, 'Download checksum mismatch'
print('Website links, sections, download archive, and checksum passed.')
