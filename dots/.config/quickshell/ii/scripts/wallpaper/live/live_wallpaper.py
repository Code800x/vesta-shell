
#!/usr/bin/env python3
"""CLI de wallpapers animados do Vesta Shell."""

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError


# Raiz do backend, necessária para importar os pacotes
# "live" e "common" independentemente do diretório atual.
WALLPAPER_ROOT = Path(__file__).resolve().parent.parent

if str(WALLPAPER_ROOT) not in sys.path:
    sys.path.insert(0, str(WALLPAPER_ROOT))


from live.core import identifier, validate_url

from live.downloader import (
    DownloadCancelled,
    cached_wallpaper,
    download_wallpaper,
)

from live.providers.desktophut import DesktopHut
from live.providers.motionbgs import MotionBGS
from live.providers.moewalls import MoeWalls


PROVIDERS = {
    provider.code: provider
    for provider in (
        DesktopHut(),
        MotionBGS(),
        MoeWalls(),
    )
}

ID_PATTERN = re.compile(r"[0-9a-f]{20}")


def emit(**data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def validate_id(image_id):
    if not ID_PATTERN.fullmatch(image_id):
        raise ValueError(
            "Identificador do wallpaper inválido."
        )


def validate_item(args):
    provider = PROVIDERS[args.provider]
    validate_id(args.image_id)

    if hasattr(args, "url") and args.url:
        validate_url(args.url, provider.hosts)

        if identifier(args.url) != args.image_id:
            raise ValueError(
                "O identificador não corresponde "
                "ao wallpaper solicitado."
            )

    return provider


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
    result = provider.search(args.query, args.page)

    emit(
        ok=True,
        provider=provider.code,
        items=result["items"],
        page=result["page"],
        last_page=result["last_page"],
    )


def status(args):
    provider = validate_item(args)
    path = cached_wallpaper(
        provider.code,
        args.image_id,
    )

    emit(
        ok=True,
        cached=path is not None,
        path=path,
    )


def status_batch(args):
    if len(args.image_ids) > 200:
        raise ValueError(
            "O limite é de 200 wallpapers por consulta."
        )

    items = {}

    for image_id in args.image_ids:
        validate_id(image_id)

        path = cached_wallpaper(
            args.provider,
            image_id,
        )

        items[image_id] = {
            "cached": path is not None,
            "path": path,
        }

    emit(
        ok=True,
        provider=args.provider,
        items=items,
    )


def download(args):
    provider = validate_item(args)

    if not provider.download:
        raise ValueError(
            "Este provedor não permite download."
        )

    existing = cached_wallpaper(
        provider.code,
        args.image_id,
    )

    if existing:
        if args.events:
            emit(event="cached", path=existing)

        emit(
            ok=True,
            path=existing,
            cached=True,
        )
        return

    source = provider.resolve(args.url)

    def progress(event):
        if args.events:
            emit(**event)

    path, from_cache = download_wallpaper(
        provider.code,
        args.image_id,
        source,
        provider.hosts,
        callback=progress,
    )

    emit(
        ok=True,
        path=path,
        cached=from_cache,
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

    status_cmd = commands.add_parser(
        "status",
        help="Consulta o cache de um wallpaper.",
    )
    status_cmd.add_argument(
        "--provider",
        choices=PROVIDERS,
        required=True,
    )
    status_cmd.add_argument(
        "--image-id",
        required=True,
    )

    batch_cmd = commands.add_parser(
        "status-batch",
        help="Consulta o cache de vários wallpapers.",
    )
    batch_cmd.add_argument(
        "--provider",
        choices=PROVIDERS,
        required=True,
    )
    batch_cmd.add_argument(
        "--image-ids",
        nargs="+",
        required=True,
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
    download_cmd.add_argument(
        "--events",
        action="store_true",
        help="Emite eventos JSON durante o download.",
    )

    args = parser.parse_args()

    try:
        if args.action == "providers":
            list_providers()

        elif args.action == "search":
            search(args)

        elif args.action == "status":
            status(args)

        elif args.action == "status-batch":
            status_batch(args)

        elif args.action == "download":
            download(args)

    except DownloadCancelled as error:
        emit(
            ok=False,
            cancelled=True,
            error=str(error),
        )
        sys.exit(130)

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
