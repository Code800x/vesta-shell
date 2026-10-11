
"""Validated wallpaper download handling."""

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


def emit(**data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


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

    if not re.fullmatch(r"[a-zA-Z0-9]{1,24}", args.image_id):
        raise ValueError("Identificador de wallpaper inválido.")

    destination = DESTINATION / args.provider.capitalize()
    destination.mkdir(parents=True, exist_ok=True)

    target = destination / (
        f"{args.provider}-{args.image_id}{suffix}"
    )

    if target.is_file() and target.stat().st_size > 0:
        emit(ok=True, path=str(target))
        return

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

    emit(ok=True, path=str(target))
