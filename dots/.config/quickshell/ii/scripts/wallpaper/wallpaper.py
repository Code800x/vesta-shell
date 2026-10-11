
#!/usr/bin/env python3
"""Vesta Shell wallpaper CLI."""

import argparse
import json
import sys
from urllib.error import HTTPError, URLError

from core.registry import PROVIDERS, compatible, get
from core.downloader import download

PURITY_OPTIONS = ("100", "110", "111")


def emit(**data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def search(args):
    result = get(args.provider, args.purity).search(args)
    emit(
        ok=True,
        provider=args.provider,
        items=result["items"],
        page=args.page,
        last_page=result["last_page"],
        purity=args.purity,
    )


def main():
    parser = argparse.ArgumentParser(
        description="Vesta Shell multi-provider wallpaper backend"
    )

    subparsers = parser.add_subparsers(
        dest="action",
        required=True,
    )

    search_parser = subparsers.add_parser("search")
    search_parser.add_argument(
        "--provider",
        choices=PROVIDERS.keys(),
        default="wallhaven",
    )
    search_parser.add_argument("--query", default="")
    search_parser.add_argument(
        "--categories",
        choices=["111", "100", "010", "001"],
        default="111",
    )
    search_parser.add_argument(
        "--sorting",
        choices=[
            "date_added",
            "relevance",
            "random",
            "views",
            "favorites",
            "toplist",
        ],
        default="date_added",
    )
    search_parser.add_argument(
        "--purity",
        choices=PURITY_OPTIONS,
        default="100",
    )
    search_parser.add_argument("--resolutions", default="")
    search_parser.add_argument("--page", type=int, default=1)

    providers_parser = subparsers.add_parser("providers")
    providers_parser.add_argument(
        "--purity",
        choices=PURITY_OPTIONS,
        default="100",
    )

    download_parser = subparsers.add_parser("download")
    download_parser.add_argument(
        "--provider",
        choices=PROVIDERS.keys(),
        default="wallhaven",
    )
    download_parser.add_argument("--url", required=True)
    download_parser.add_argument("--image-id", required=True)

    args = parser.parse_args()

    try:
        if args.action == "providers":
            emit(ok=True, providers=compatible(args.purity))

        elif args.action == "search":
            if args.page < 1:
                raise ValueError("Número de página inválido.")

            search(args)

        else:
            download(args)

    except (
        ValueError,
        OSError,
        HTTPError,
        URLError,
        TimeoutError,
        json.JSONDecodeError,
    ) as error:
        emit(ok=False, error=str(error))
        sys.exit(1)


if __name__ == "__main__":
    main()
