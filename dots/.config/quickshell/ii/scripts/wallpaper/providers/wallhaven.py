
"""Provedor Wallhaven para wallpapers estáticos."""

import os
from urllib.parse import urlencode

from core.http import request_json
from common.search_service import (
    CachedApiSearch,
    pagination_result,
)

API = "https://wallhaven.cc/api/v1/search"
SUPPORTED_PURITY = ("100",)

search_cache = CachedApiSearch(ttl=1800)


def search(args):
    api_key = os.environ.get(
        "WALLHAVEN_API_KEY", ""
    ).strip()

    if args.purity != "100" and not api_key:
        raise ValueError(
            "O Wallhaven exige autenticação para classificações "
            "restritas. Selecione Konachan ou Yande.re para "
            "pesquisar sem chave de API."
        )

    params = {
        "q": args.query,
        "categories": args.categories,
        "purity": args.purity,
        "sorting": args.sorting,
        "page": args.page,
    }

    if args.resolutions:
        params["atleast"] = args.resolutions

    if api_key:
        params["apikey"] = api_key

    # Não incluímos a chave de API em texto claro
    # nos arquivos de cache ou na chave de pesquisa.
    cache_params = {
        key: value
        for key, value in params.items()
        if key != "apikey"
    }
    cache_params["authenticated"] = bool(api_key)

    def fetch():
        payload = request_json(
            API + "?" + urlencode(params)
        )

        if not isinstance(payload, dict):
            raise ValueError(
                "Resposta inesperada do Wallhaven."
            )

        return payload

    payload = search_cache.request(
        provider="wallhaven",
        parameters=cache_params,
        callback=fetch,
        use_cache=args.sorting != "random",
    )

    entries = payload.get("data") or []

    if not isinstance(entries, list):
        raise ValueError(
            "Lista de wallpapers inválida no Wallhaven."
        )

    items = []

    for entry in entries:
        if not isinstance(entry, dict):
            continue

        thumbs = entry.get("thumbs") or {}

        if not isinstance(thumbs, dict):
            thumbs = {}

        image_id = str(entry.get("id") or "")
        image_url = str(entry.get("path") or "")
        thumb_url = str(
            thumbs.get("large")
            or thumbs.get("original")
            or ""
        )

        if not image_id or not image_url or not thumb_url:
            continue

        items.append({
            "id": image_id,
            "provider": "wallhaven",
            "thumb": thumb_url,
            "url": image_url,
            "resolution": str(
                entry.get("resolution") or ""
            ),
            "purity": entry.get("purity", "sfw"),
        })

    meta = payload.get("meta") or {}

    if not isinstance(meta, dict):
        meta = {}

    last_page = int(
        meta.get("last_page") or args.page
    )

    return pagination_result(
        items,
        args.page,
        last_page=last_page,
    )
