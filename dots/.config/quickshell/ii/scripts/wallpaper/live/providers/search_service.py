
"""Serviço compartilhado de pesquisa de live wallpapers."""

import hashlib
import json
import os
import re
import tempfile
import time
import unicodedata
from pathlib import Path
from common.cache import SearchCache, CACHE_DIR
from urllib.parse import urlsplit, urlunsplit




def normalize_text(value):
    """Normaliza acentos, maiúsculas e pontuação."""
    value = unicodedata.normalize(
        "NFKD",
        str(value or "").casefold(),
    )

    value = "".join(
        char
        for char in value
        if not unicodedata.combining(char)
    )

    return re.sub(
        r"[^a-z0-9]+",
        " ",
        value,
    ).strip()


def matches_query(title, url, query):
    """Confere se todos os termos aparecem no título ou slug."""
    words = normalize_text(query).split()

    if not words:
        return True

    slug = urlsplit(url).path.strip("/").split("/")[-1]
    haystack = normalize_text(f"{title} {slug}")
    available = set(haystack.split())

    return all(word in available for word in words)


def canonical_url(url):
    """Remove fragmentos e parâmetros de rastreamento."""
    parsed = urlsplit(str(url or ""))

    return urlunsplit((
        parsed.scheme.lower(),
        parsed.netloc.lower(),
        parsed.path.rstrip("/"),
        parsed.query,
        "",
    ))


def item_key(item):
    """Identificador estável para eliminar duplicatas."""
    url = item.get("url") or item.get("page_url")

    if url:
        return canonical_url(url)

    identifier = item.get("id")

    if identifier:
        return str(identifier)

    return json.dumps(
        item,
        sort_keys=True,
        ensure_ascii=False,
    )



class SearchService:
    """
    Pesquisa paginada sobre páginas de origem.

    fetch_page_callback(query, page) deve retornar:
        (items, source_count)

    items:
        lista de dicionários de wallpapers.

    source_count:
        quantidade de cards válidos antes do filtro.

    O serviço mantém um cache independente por
    provedor, termo e página de origem.
    """

    def __init__(
        self,
        provider,
        fetch_page_callback,
        page_size=12,
        max_source_pages=40,
        cache_ttl=1800,
        filter_results=True,
        enrich_item=None,
        filtered_max_source_pages=None,
        max_enrichments=None,
    ):
        self.provider = provider
        self.fetch_page_callback = fetch_page_callback
        self.page_size = page_size
        self.max_source_pages = max_source_pages
        self.filter_results = filter_results
        self.enrich_item = enrich_item
        self.filtered_max_source_pages = filtered_max_source_pages
        self.max_enrichments = max_enrichments
        self.cache = SearchCache(ttl=cache_ttl)

    def _cache_key(self, query, source_page):
        normalized = normalize_text(query)

        return (
            f"v1:{self.provider}:"
            f"{normalized}:{source_page}"
        )

    def source_page(self, query, number):
        """Lê a página de origem do cache ou da rede."""
        key = self._cache_key(query, number)

        cached = self.cache.get(key)

        if cached is not None:
            return (
                cached["items"],
                cached["source_count"],
            )

        items, source_count = self.fetch_page_callback(
            query,
            number,
        )

        # Não armazenamos objetos de rede ou HTML:
        # somente dados JSON já extraídos.
        self.cache.set(
            key,
            {
                "items": items,
                "source_count": source_count,
            },
        )

        return items, source_count

    @staticmethod
    def matches_resolution(item, resolution):
        if not resolution:
            return True
        minimums = {
            "1920x1080": (1920, 1080),
            "2560x1440": (2560, 1440),
            "3840x2160": (3840, 2160),
        }
        minimum = minimums.get(resolution)
        if minimum is None:
            raise ValueError("Filtro de resolução inválido.")
        width = item.get("width")
        height = item.get("height")
        if width is None or height is None:
            return False
        # Accept portrait videos using their equivalent long/short edges.
        long_edge, short_edge = sorted((int(width), int(height)), reverse=True)
        return long_edge >= minimum[0] and short_edge >= minimum[1]

    def search(self, query, number, resolution=""):
        """Monta uma página virtual de resultados únicos."""
        if not 1 <= number <= 100:
            raise ValueError(
                "A página deve estar entre 1 e 100."
            )

        query = str(query or "").strip()

        start = (number - 1) * self.page_size
        end = start + self.page_size

        # Um item extra determina se existe
        # uma próxima página virtual.
        required = end + 1

        collected = []
        seen_items = set()
        seen_source_signatures = set()

        source_limit = self.max_source_pages
        if resolution and self.filtered_max_source_pages is not None:
            source_limit = min(source_limit, self.filtered_max_source_pages)
        enrichment_count = 0

        for source_number in range(1, source_limit + 1):
            items, source_count = self.source_page(
                query,
                source_number,
            )

            if source_count == 0:
                break

            # Evita percorrer indefinidamente um site
            # que devolve os mesmos cards em todas
            # as páginas, ignorando a paginação.
            signature = tuple(
                item_key(item)
                for item in items
            )

            if signature and signature in seen_source_signatures:
                break

            if signature:
                seen_source_signatures.add(signature)

            for item in items:
                if self.filter_results and not matches_query(
                    item.get("title", "")
                    or item.get("name", ""),
                    item.get("url", ""),
                    query,
                ):
                    continue

                if resolution and self.enrich_item and (
                    item.get("width") is None or item.get("height") is None
                ):
                    if (self.max_enrichments is None or
                            enrichment_count < self.max_enrichments):
                        enrichment_count += 1
                        try:
                            item = self.enrich_item(item)
                        except (OSError, ValueError, TimeoutError) as error:
                            # A detail page failing must not abort the gallery.
                            print(f"[MoeWalls] Metadados indisponíveis: {error}",
                                  file=__import__("sys").stderr)

                if not self.matches_resolution(item, resolution):
                    continue

                key = item_key(item)

                if key in seen_items:
                    continue

                seen_items.add(key)
                collected.append(item)

                if len(collected) >= required:
                    break

            if len(collected) >= required:
                break

        has_more = len(collected) > end

        return {
            "items": collected[start:end],
            "page": number,
            "last_page": (
                number + 1
                if has_more
                else number
            ),
        }
