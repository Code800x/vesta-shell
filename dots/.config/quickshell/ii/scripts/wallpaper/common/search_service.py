
"""Serviços compartilhados de pesquisa da Vesta Shell.

Fornece cache persistente e deduplicação para
provedores que utilizam APIs JSON com paginação nativa.
"""

import hashlib
import json

from live.providers.search_service import SearchCache


class CachedApiSearch:
    """Executa consultas de API com cache persistente."""

    def __init__(self, ttl=1800):
        self.cache = SearchCache(ttl=ttl)

    @staticmethod
    def make_key(provider, parameters):
        """Cria uma chave estável para a consulta."""
        serialized = json.dumps(
            {
                "provider": provider,
                "parameters": parameters,
            },
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )

        digest = hashlib.sha256(
            serialized.encode("utf-8")
        ).hexdigest()

        return f"static-api:v1:{provider}:{digest}"

    def request(
        self,
        provider,
        parameters,
        callback,
        use_cache=True,
    ):
        """Obtém resposta do cache ou executa callback."""
        if not use_cache:
            return callback()

        key = self.make_key(provider, parameters)
        cached = self.cache.get(key)

        if cached is not None:
            return cached

        result = callback()

        self.cache.set(key, result)

        return result


def unique_wallpapers(items):
    """Remove duplicatas por ID e URL dentro de um provedor."""
    seen_ids = set()
    seen_urls = set()
    result = []

    for item in items:
        if not isinstance(item, dict):
            continue

        provider = str(item.get("provider", ""))
        image_id = str(item.get("id", "")).strip()
        image_url = str(item.get("url", "")).strip()

        if not image_id or not image_url:
            continue

        id_key = (provider, image_id)
        url_key = (provider, image_url)

        if id_key in seen_ids or url_key in seen_urls:
            continue

        seen_ids.add(id_key)
        seen_urls.add(url_key)
        result.append(item)

    return result


def pagination_result(items, page, has_more=False, last_page=None):
    """Padroniza o resultado sem alterar o contrato do QML."""
    page = int(page)

    if page < 1:
        raise ValueError("Número de página inválido.")

    if last_page is None:
        last_page = page + 1 if has_more else page

    return {
        "items": unique_wallpapers(items),
        "last_page": max(page, int(last_page)),
    }
