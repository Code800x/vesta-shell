
"""Wallhaven provider."""

import os
from urllib.parse import urlencode

from core.http import request_json

API = "https://wallhaven.cc/api/v1/search"
API_KEY = os.environ.get("WALLHAVEN_API_KEY", "").strip()

SUPPORTED_PURITY = ("100",)


def search(args):
    if args.purity != "100" and not API_KEY:
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

    if API_KEY:
        params["apikey"] = API_KEY

    payload = request_json(
        API + "?" + urlencode(params)
    )

    items = []

    for entry in payload.get("data", []):
        thumbs = entry.get("thumbs") or {}

        items.append({
            "id": str(entry.get("id", "")),
            "provider": "wallhaven",
            "thumb": (
                thumbs.get("large")
                or thumbs.get("original")
                or ""
            ),
            "url": entry.get("path", ""),
            "resolution": entry.get("resolution", ""),
            "purity": entry.get("purity", "sfw"),
        })

    meta = payload.get("meta") or {}

    return {
        "items": items,
        "last_page": max(
            1,
            int(meta.get("last_page") or 1),
        ),
    }
