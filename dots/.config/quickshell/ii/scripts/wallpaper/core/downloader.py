
"""Validated wallpaper download and cache handling."""

import json
import os
from pathlib import Path
import re
import tempfile
from urllib.parse import urlparse

from core.http import fetch

DESTINATION = Path.home() / "Pictures" / "Wallpapers"
MAX_BYTES = 50 * 1024 * 1024
ALLOWED_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp")
ID_PATTERN = re.compile(r"[a-zA-Z0-9]{1,24}")


def emit(**data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def validate_image_id(image_id):
    if not ID_PATTERN.fullmatch(str(image_id)):
        raise ValueError("Identificador de wallpaper inválido.")


def cached_wallpaper(provider, image_id):
    """Retorna o arquivo local, se existir e não estiver vazio."""
    validate_image_id(image_id)

    directory = DESTINATION / provider.capitalize()

    for suffix in ALLOWED_EXTENSIONS:
        target = directory / f"{provider}-{image_id}{suffix}"

        if target.is_file() and target.stat().st_size > 0:
            return str(target)

    return None


def cached_wallpapers(provider, image_ids):
    """Consulta vários wallpapers sem acesso à rede."""
    result = {}

    for image_id in image_ids:
        validate_image_id(image_id)

        path = cached_wallpaper(provider, image_id)

        result[image_id] = {
            "cached": path is not None,
            "path": path,
        }

    return result


def allowed_download_host(provider, hostname):
    if not hostname:
        return False

    hostname = hostname.lower()

    if provider == "wallhaven":
        return hostname == "w.wallhaven.cc"

    if provider == "konachan":
        return (
            hostname == "konachan.com"
            or hostname.endswith(".konachan.com")
        )

    if provider == "yandere":
        return (
            hostname == "yande.re"
            or hostname.endswith(".yande.re")
        )

    return False


def validate_image_url(provider, url):
    parsed = urlparse(url)

    if (
        parsed.scheme != "https"
        or not allowed_download_host(provider, parsed.hostname)
        or parsed.username
        or parsed.password
        or parsed.port is not None
    ):
        raise ValueError("URL de imagem não permitida.")

    suffix = Path(parsed.path).suffix.lower()

    if suffix not in ALLOWED_EXTENSIONS:
        raise ValueError("Formato de imagem não permitido.")

    return suffix


def download(args):
    suffix = validate_image_url(args.provider, args.url)
    validate_image_id(args.image_id)

    existing = cached_wallpaper(
        args.provider,
        args.image_id,
    )

    if existing is not None:
        emit(ok=True, path=existing, cached=True)
        return

    destination = DESTINATION / args.provider.capitalize()
    destination.mkdir(parents=True, exist_ok=True)

    target = destination / (
        f"{args.provider}-{args.image_id}{suffix}"
    )

    fd, temporary = tempfile.mkstemp(
        prefix=".vesta-",
        dir=destination,
    )

    try:
        with os.fdopen(fd, "wb") as output:
            with fetch(args.url, accept="image/*") as response:
                final_url = response.geturl()

                validate_image_url(args.provider, final_url)

                content_type = response.headers.get(
                    "Content-Type", ""
                ).lower()

                if not content_type.startswith("image/"):
                    raise ValueError(
                        "O servidor não retornou uma imagem."
                    )

                total = 0

                while True:
                    chunk = response.read(65536)

                    if not chunk:
                        break

                    total += len(chunk)

                    if total > MAX_BYTES:
                        raise ValueError(
                            "Imagem excede o limite de 50 MB."
                        )

                    output.write(chunk)

                if total == 0:
                    raise ValueError(
                        "O arquivo recebido está vazio."
                    )

        os.replace(temporary, target)

    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

    emit(ok=True, path=str(target), cached=False)
