
#!/usr/bin/env python3
"""CLI de wallpapers animados do Vesta Shell."""

import argparse
import json
import re
import sys
from urllib.error import HTTPError, URLError

from core import (
    identifier,
    save_wallpaper,
    validate_url,
)
from providers.desktophut import DesktopHut
from providers.motionbgs import MotionBGS
from providers.moewalls import MoeWalls


PROVIDERS = {
    provider.code: provider
    for provider in (
        DesktopHut(),
        MotionBGS(),
        MoeWalls(),
    )
}


def emit(**data):
    print(
        json.dumps(data, ensure_ascii=False),
        flush=True,
    )


def list_providers():
    emit(
        ok=True,
        providers=[
            {
                "code": provider.code,
                "name": provider.name,
                "download": provider.download,
            }
            for provider in PROVIDERS.values()
        ],
    )


def search(args):
    if not 1 <= args.page <= 100:
        raise ValueError(
            "A página deve estar entre 1 e 100."
        )

    provider = PROVIDERS[args.provider]

    result = provider.search(
        args.query,
        args.page,
    )

    emit(
        ok=True,
        provider=provider.code,
        items=result["items"],
        page=result["page"],
        last_page=result["last_page"],
    )


def download(args):
    provider = PROVIDERS[args.provider]

    if not provider.download:
        raise ValueError(
            "Este provedor não permite download."
        )

    validate_url(args.url, provider.hosts)

    if not re.fullmatch(
        r"[0-9a-f]{20}",
        args.image_id,
    ):
        raise ValueError(
            "Identificador do wallpaper inválido."
        )

    if identifier(args.url) != args.image_id:
        raise ValueError(
            "O identificador não corresponde "
            "ao wallpaper solicitado."
        )

    source = provider.resolve(args.url)

    path = save_wallpaper(
        provider.code,
        args.image_id,
        source,
        provider.hosts,
    )

    emit(
        ok=True,
        path=path,
    )


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Gerenciador online de wallpapers "
            "animados do Vesta Shell"
        )
    )

    commands = parser.add_subparsers(
        dest="action",
        required=True,
    )

    commands.add_parser(
        "providers",
        help="Lista os provedores disponíveis.",
    )

    search_cmd = commands.add_parser(
        "search",
        help="Pesquisa wallpapers animados.",
    )

    search_cmd.add_argument(
        "--provider",
        choices=PROVIDERS,
        default="desktophut",
    )

    search_cmd.add_argument(
        "--query",
        default="",
    )

    search_cmd.add_argument(
        "--page",
        type=int,
        default=1,
    )

    download_cmd = commands.add_parser(
        "download",
        help="Baixa o wallpaper original.",
    )

    download_cmd.add_argument(
        "--provider",
        choices=PROVIDERS,
        required=True,
    )

    download_cmd.add_argument(
        "--url",
        required=True,
    )

    download_cmd.add_argument(
        "--image-id",
        required=True,
    )

    args = parser.parse_args()

    try:
        if args.action == "providers":
            list_providers()

        elif args.action == "search":
            search(args)

        elif args.action == "download":
            download(args)

    except (
        ValueError,
        OSError,
        HTTPError,
        URLError,
        TimeoutError,
        EOFError,
    ) as error:
        emit(
            ok=False,
            error=str(error),
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
