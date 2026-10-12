"""Provedor DesktopHut para wallpapers animados."""

from urllib.parse import quote, urlparse

from ..core import (
    fetch_page,
    unique_items,
    validate_url,
    wallpaper_item,
)
from .http_errors import fetch_listing_or_end
from .search_service import SearchService


class DesktopHut:
    code = "desktophut"
    name = "DesktopHut"
    download = True

    base = "https://www.desktophut.com"
    hosts = ("desktophut.com",)

    def __init__(self):
        self.search_service = SearchService(
            provider=self.code,
            fetch_page_callback=self.fetch_source_page,
            page_size=12,
            max_source_pages=40,
            cache_ttl=1800,
            filter_results=True,
        )

    def listing_url(self, query, number):
        term = str(query or "").strip()
        path = "/search/" + quote(term, safe="") if term else "/"
        suffix = f"?page={number}" if number > 1 else ""
        return self.base + path + suffix

    def fetch_source_page(self, query, number):
        url = self.listing_url(query, number)
        document = fetch_listing_or_end(
            fetch_page,
            self.listing_url(query, number),
            self.hosts,
            page=number,
            missing_page_is_end=True,
        )
        if document is None:
            return [], 0

        items = []
        source_urls = set()

        for link in document.links:
            url = link.get("url", "")
            title = link.get("title", "")
            thumb = link.get("thumb", "")

            try:
                validate_url(url, self.hosts)
            except ValueError:
                continue

            path = urlparse(url).path.strip("/")
            if not path or "/" in path or not thumb:
                continue
            if "wallpaper" not in path.lower() and "wallpaper" not in title.lower():
                continue
            if url in source_urls:
                continue

            source_urls.add(url)
            items.append(wallpaper_item(self.code, url, title, thumb))

        return unique_items(items), len(source_urls)

    def fetch(self, query, number):
        """Compatibilidade com a API anterior."""
        items, _ = self.fetch_source_page(query, number)
        return items

    def search(self, query, number):
        return self.search_service.search(query, number)

    def resolve(self, url, item=None):
        validate_url(url, self.hosts)
        document = fetch_page(url, self.hosts)

        for link in document.links:
            source = link["url"]
            path = urlparse(source).path.lower()
            if not path.endswith((".mp4", ".webm", ".zip")):
                continue
            if link["download"] or "/files/" in path:
                return validate_url(source, self.hosts)

        raise ValueError("Arquivo original não encontrado no DesktopHut.")
