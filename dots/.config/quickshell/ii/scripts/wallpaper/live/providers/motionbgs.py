
"""Provedor MotionBGS para wallpapers animados."""

import re
from urllib.parse import quote, urlparse

from core import (
    fetch_page,
    has_next_page,
    unique_items,
    validate_url,
    wallpaper_item,
)


class MotionBGS:
    code = "motionbgs"
    name = "MotionBGS"
    download = True

    base = "https://motionbgs.com"
    hosts = ("motionbgs.com",)

    def listing_url(self, query, number):
        path = (
            f"/{number}/"
            if number > 1
            else "/"
        )

        url = self.base + path

        if query.strip():
            url += "?s=" + quote(query.strip())

        return url

    @staticmethod
    def media_id(image_url):
        match = re.search(
            r"/media/(\d+)/",
            image_url or "",
        )

        return match.group(1) if match else None

    @staticmethod
    def page_slug(url):
        return urlparse(url).path.strip("/").split("/")[-1]

    @staticmethod
    def image_matches_page(image_url, slug):
        filename = urlparse(image_url).path.split("/")[-1].lower()
        slug = slug.lower()

        return (
            filename == slug
            or filename.startswith(slug + ".")
        )

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

            if (
                not path
                or "/" in path
                or path.isdigit()
                or path.lower() in {
                    "4k", "mobile", "gifs"
                }
                or path.startswith((
                    "tag:", "page:", "search"
                ))
                or not self.media_id(thumb)
            ):
                continue

            # Evita associar um card a uma miniatura
            # pertencente a outro wallpaper.
            slug = self.page_slug(url)

            if not self.image_matches_page(thumb, slug):
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

        slug = self.page_slug(url)

        # Prioridade 1: miniatura do próprio card.
        if item:
            thumb = item.get("thumb", "")

            if self.image_matches_page(thumb, slug):
                media_id = self.media_id(thumb)

                if media_id:
                    return (
                        self.base
                        + "/dl/4k/"
                        + media_id
                    )

        # Prioridade 2: imagem principal identificada
        # pelo slug na página individual.
        document = fetch_page(url, self.hosts)

        candidates = []

        for image in document.images:
            image_url = image["url"]

            if self.image_matches_page(image_url, slug):
                media_id = self.media_id(image_url)

                if media_id:
                    candidates.append(media_id)

        # Metadados sociais frequentemente apontam
        # para a imagem principal do wallpaper.
        for key in (
            "og:image",
            "twitter:image",
        ):
            image_url = document.metadata.get(key, "")

            if self.image_matches_page(image_url, slug):
                media_id = self.media_id(image_url)

                if media_id:
                    candidates.append(media_id)

        if candidates:
            return (
                self.base
                + "/dl/4k/"
                + candidates[0]
            )

        raise ValueError(
            "Não foi possível identificar com segurança "
            "o ID do vídeo correspondente a este wallpaper."
        )
