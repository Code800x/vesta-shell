
"""Provedor MoeWalls para wallpapers animados."""

from urllib.error import HTTPError
from urllib.parse import quote, urlparse

from ..core import (
    fetch_page,
    unique_items,
    validate_url,
    wallpaper_item,
)

from .search_service import SearchService


class MoeWalls:
    code = "moewalls"
    name = "MoeWalls"
    download = True

    base = "https://moewalls.com"
    hosts = ("moewalls.com",)

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
        path = (
            f"/page/{number}/"
            if number > 1
            else "/"
        )

        url = self.base + path
        term = str(query or "").strip()

        if term:
            url += "?s=" + quote(term)

        return url

    def fetch_source_page(self, query, number):
        try:
            document = fetch_page(
                self.listing_url(query, number),
                self.hosts,
            )
        except HTTPError as error:
            if error.code == 404:
                return [], 0
            raise

        items = []
        source_urls = set()

        for link in document.links:
            url = link.get("url", "")
            thumb = link.get("thumb", "")
            title = link.get("title", "")

            try:
                validate_url(url, self.hosts)
            except ValueError:
                continue

            path = urlparse(url).path.strip("/")

            if not path or not thumb:
                continue

            if path.startswith((
                "page/",
                "category/",
                "tag/",
                "wp-content/",
                "author/",
                "feed/",
            )):
                continue

            if "wallpaper" not in path.lower():
                continue

            if url in source_urls:
                continue

            source_urls.add(url)

            items.append(
                wallpaper_item(
                    self.code,
                    url,
                    title,
                    thumb,
                )
            )

        return unique_items(items), len(source_urls)

    def fetch(self, query, number):
        """Compatibilidade com a API anterior."""
        items, _ = self.fetch_source_page(
            query,
            number,
        )

        return items

    def search(self, query, number):
        return self.search_service.search(
            query,
            number,
        )

    def resolve(self, url, item=None):
        validate_url(url, self.hosts)

        document = fetch_page(url, self.hosts)

        candidates = []

        for source in document.videos:
            path = urlparse(source).path.lower()

            if path.endswith((".mp4", ".webm")):
                candidates.append(source)

        for link in document.links:
            source = link["url"]
            path = urlparse(source).path.lower()

            if path.endswith((
                ".mp4",
                ".webm",
                ".zip",
            )):
                candidates.append(source)

        for candidate in candidates:
            try:
                return validate_url(
                    candidate,
                    self.hosts,
                )
            except ValueError:
                continue

        raise ValueError(
            "Não foi encontrado um vídeo original "
            "compatível na página do MoeWalls."
        )
