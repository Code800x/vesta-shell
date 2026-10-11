"""Shared Moebooru implementation."""

import re
from urllib.parse import urlencode

from core.http import request_json


PAGE_SIZE = 24


def moebooru_ratings(purity):
    if purity == "100":
        return ["s"]

    if purity == "110":
        return ["s", "q"]

    return ["s", "q", "e"]


def moebooru_sorting(sorting):
    mapping = {
        "date_added": "date",
        "relevance": "date",
        "random": "random",
        "views": "score",
        "favorites": "score",
        "toplist": "score",
    }

    return mapping.get(sorting, "date")


def minimum_dimensions(value):
    if not value:
        return 0, 0

    match = re.fullmatch(r"(\d+)x(\d+)", value)

    if not match:
        raise ValueError("Resolução mínima inválida.")

    return int(match.group(1)), int(match.group(2))


def normalize_url(value):
    return str(value or "").strip()


def search(args, api):
    provider = args.provider

    tags = args.query.strip().split()

    min_width, min_height = minimum_dimensions(
        args.resolutions
    )

    if min_width:
        tags.append(f"width:>={min_width}")

    if min_height:
        tags.append(f"height:>={min_height}")

    order = moebooru_sorting(args.sorting)

    if order == "score":
        tags.append("order:score")
    elif order == "random":
        tags.append("order:random")

    ratings = moebooru_ratings(args.purity)

    combined = []
    has_more = False

    for rating in ratings:
        rating_tags = tags + [f"rating:{rating}"]

        params = {
            "tags": " ".join(rating_tags),
            "limit": PAGE_SIZE + 1,
            "page": args.page,
        }

        payload = request_json(
            api + "?" + urlencode(params)
        )

        if not isinstance(payload, list):
            raise ValueError(
                "Resposta inesperada do provedor."
            )

        # A consulta de um item adicional permite
        # detectar a existência de outra página.
        if len(payload) > PAGE_SIZE:
            has_more = True

        for entry in payload[:PAGE_SIZE]:
            if not isinstance(entry, dict):
                continue

            image_id = entry.get("id")

            image_url = normalize_url(
                entry.get("file_url")
                or entry.get("jpeg_url")
            )

            thumb_url = normalize_url(
                entry.get("preview_url")
                or entry.get("sample_url")
            )

            if not image_id or not image_url or not thumb_url:
                continue

            rating_code = str(
                entry.get("rating", "s")
            ).lower()

            if rating_code not in ratings:
                continue

            width = int(entry.get("width") or 0)
            height = int(entry.get("height") or 0)

            if width < min_width or height < min_height:
                continue

            combined.append({
                "id": str(image_id),
                "provider": provider,
                "thumb": thumb_url,
                "url": image_url,
                "resolution": f"{width}x{height}",
                "purity": {
                    "s": "sfw",
                    "q": "sketchy",
                    "e": "nsfw",
                }.get(rating_code, "sfw"),
                "score": int(
                    entry.get("score") or 0
                ),
            })

    # Remove publicações duplicadas e arquivos
    # originais repetidos na mesma página.
    seen_ids = set()
    seen_urls = set()
    unique = []

    for item in combined:
        image_id = item["id"]
        image_url = item["url"]

        if image_id in seen_ids:
            continue

        if image_url in seen_urls:
            continue

        seen_ids.add(image_id)
        seen_urls.add(image_url)

        unique.append(item)

    if args.sorting in (
        "views",
        "favorites",
        "toplist",
    ):
        unique.sort(
            key=lambda item: item["score"],
            reverse=True,
        )

    elif args.sorting == "date_added":
        unique.sort(
            key=lambda item: int(item["id"]),
            reverse=True,
        )

    for item in unique:
        item.pop("score", None)

    return {
        "items": unique,
        "last_page": (
            args.page + 1
            if has_more
            else args.page
        ),
    }