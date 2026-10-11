
"""Provedor MoeWalls."""

from urllib.parse import quote, urlparse

from core import (
    fetch_page,
    has_next_page,
    unique_items,
    validate_url,
    wallpaper_item,
)


class MoeWalls:
    code = "moewalls"
    name = "MoeWalls"
    download = True

    base = "https://moewalls.com"
    hosts = ("moewalls.com",)

    def listing_url(self, query, number):
        path = (
            f"/page/{number}/"
            if number > 1
            else "/"
        )

        url = self.base + path

        if query.strip():
            url += "?s=" + quote(query.strip())

        return url

    def fetch(self, query, number):
        document = fetch_page(
            self.listing_url(query, number),
            self.hosts,
        )

        items = []

        for link in document.links:
            url = link["url"]
            thumb = link["thumb"]

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

            # MoeWalls publica os wallpapers em páginas
            # individuais, normalmente com um slug
            # terminado em "live-wallpaper".
            if "wallpaper" not in path.lower():
                continue

            items.append(
                wallpaper_item(
                    self.code,
                    url,
                    link["title"],
                    thumb,
                )
            )

        return unique_items(items)

    def search(self, query, number):
        items = self.fetch(query, number)

        return {
            "items": items,
            "page": number,
            "last_page": (
                number + 1
                if has_next_page(
                    self, query, number, items
                )
                else number
            ),
        }

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
                ".mp4", ".webm", ".zip"
            )):
                candidates.append(source)

        for candidate in candidates:
            try:
                return validate_url(
                    candidate, self.hosts
                )
            except ValueError:
                continue

        raise ValueError(
            "Não foi encontrado um vídeo original "
            "compatível na página do MoeWalls."
        )
