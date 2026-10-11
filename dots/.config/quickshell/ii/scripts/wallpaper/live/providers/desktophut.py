
"""Provedor DesktopHut."""

from urllib.parse import quote, urlparse

from core import (
    fetch_page,
    has_next_page,
    unique_items,
    validate_url,
    wallpaper_item,
)


class DesktopHut:
    code = "desktophut"
    name = "DesktopHut"
    download = True

    base = "https://www.desktophut.com"
    hosts = ("desktophut.com",)

    def listing_url(self, query, number):
        path = (
            "/search/" + quote(query.strip(), safe="")
            if query.strip()
            else "/"
        )

        suffix = (
            "?page=" + str(number)
            if number > 1
            else ""
        )

        return self.base + path + suffix

    def fetch(self, query, number):
        document = fetch_page(
            self.listing_url(query, number),
            self.hosts,
        )

        items = []

        for link in document.links:
            url = link["url"]

            try:
                validate_url(url, self.hosts)
            except ValueError:
                continue

            path = urlparse(url).path.strip("/")
            title = link["title"]
            thumb = link["thumb"]

            if not path or "/" in path or not thumb:
                continue

            if (
                "wallpaper" not in path.lower()
                and "wallpaper" not in title.lower()
            ):
                continue

            items.append(
                wallpaper_item(
                    self.code, url, title, thumb
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

        for link in document.links:
            source = link["url"]
            path = urlparse(source).path.lower()

            if not path.endswith(
                (".mp4", ".webm", ".zip")
            ):
                continue

            if (
                link["download"]
                or "/files/" in path
            ):
                return validate_url(
                    source, self.hosts
                )

        raise ValueError(
            "Arquivo original não encontrado no DesktopHut."
        )
