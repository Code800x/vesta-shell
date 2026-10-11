
"""Provedor MotionBGS para wallpapers animados."""

import re
import unicodedata
from urllib.error import HTTPError
from urllib.parse import quote, urlparse

from core import (
    fetch_page,
    unique_items,
    validate_url,
    wallpaper_item,
)

from providers.search_service import SearchService


class MotionBGS:
    code = "motionbgs"
    name = "MotionBGS"
    download = True

    base = "https://motionbgs.com"
    hosts = ("motionbgs.com",)

    def __init__(self):
        self.search_service = SearchService(
            provider=self.code,
            fetch_page_callback=self.fetch_source_page,
            page_size=12,
            max_source_pages=40,
            cache_ttl=1800,
            filter_results=False,
        )

    @staticmethod
    def normalize_query(query):
        text = unicodedata.normalize(
            "NFKD",
            str(query or "").strip().lower(),
        )

        text = "".join(
            character
            for character in text
            if not unicodedata.combining(character)
        )

        text = re.sub(r"[\s_]+", "-", text)
        text = re.sub(r"[^a-z0-9-]", "", text)
        text = re.sub(r"-+", "-", text)

        return text.strip("-")

    def listing_url(self, query, number):
        term = str(query or "").strip()

        if term:
            slug = self.normalize_query(term)

            if not slug:
                raise ValueError(
                    "Informe um termo de pesquisa válido."
                )

            path = "/tag:" + quote(slug, safe="") + "/"

            if number > 1:
                path += f"{number}/"

            return self.base + path

        if number > 1:
            return f"{self.base}/{number}/"

        return self.base + "/"

    @staticmethod
    def media_id(image_url):
        match = re.search(
            r"/media/(\d+)/",
            image_url or "",
        )

        return match.group(1) if match else None

    @staticmethod
    def page_slug(url):
        return (
            urlparse(url)
            .path
            .strip("/")
            .split("/")[-1]
        )

    @staticmethod
    def image_matches_page(image_url, slug):
        filename = (
            urlparse(image_url)
            .path
            .split("/")[-1]
            .lower()
        )

        slug = slug.lower()

        return (
            filename == slug
            or filename.startswith(slug + ".")
        )

    def fetch_source_page(self, query, number):
        try:
            document = fetch_page(
                self.listing_url(query, number),
                self.hosts,
            )
        except HTTPError as error:
            if error.code == 404 and str(query).strip():
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

            if (
                not path
                or "/" in path
                or path.isdigit()
                or path.lower() in {
                    "4k",
                    "mobile",
                    "gifs",
                }
                or path.startswith((
                    "tag:",
                    "page:",
                    "search",
                ))
                or not self.media_id(thumb)
            ):
                continue

            slug = self.page_slug(url)

            if not self.image_matches_page(
                thumb,
                slug,
            ):
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

        slug = self.page_slug(url)

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

        document = fetch_page(url, self.hosts)

        candidates = []

        for image in document.images:
            image_url = image["url"]

            if self.image_matches_page(
                image_url,
                slug,
            ):
                media_id = self.media_id(image_url)

                if media_id:
                    candidates.append(media_id)

        for key in (
            "og:image",
            "twitter:image",
        ):
            image_url = document.metadata.get(
                key,
                "",
            )

            if self.image_matches_page(
                image_url,
                slug,
            ):
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
