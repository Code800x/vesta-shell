#!/usr/bin/env python3
"""Downloads monitorados de live wallpapers do Vesta Shell."""

import os
import signal
import tempfile
import time
import zipfile

from pathlib import Path
from urllib.parse import urlparse

from .core import (
    DESTINATION,
    MAX_FILE,
    VIDEO_EXTENSIONS,
    extract_zip,
    open_remote,
)


CHUNK_SIZE = 256 * 1024
PROGRESS_INTERVAL = 0.15


class DownloadCancelled(Exception):
    """Download interrompido pelo usuário."""


def _handle_cancel(signum, frame):
    raise DownloadCancelled(
        "Download cancelado pelo usuário."
    )


def cached_wallpaper(provider, item_id):
    """Retorna o vídeo existente, caso esteja disponível."""

    folder = DESTINATION / provider
    basename = f"{provider}-{item_id}"

    for extension in sorted(VIDEO_EXTENSIONS):
        path = folder / (basename + extension)

        if path.is_file() and path.stat().st_size > 0:
            return str(path)

    return None


def _extension_for(kind, url):
    extension = Path(
        urlparse(url).path
    ).suffix.lower()

    if extension in VIDEO_EXTENSIONS:
        return extension

    extensions = {
        "video/mp4": ".mp4",
        "video/webm": ".webm",
        "video/quicktime": ".mov",
        "video/x-matroska": ".mkv",
        "application/x-matroska": ".mkv",
    }

    return extensions.get(kind)


def _emit_progress(callback, received, total, started):
    if callback is None:
        return

    elapsed = max(
        time.monotonic() - started,
        0.001,
    )

    callback({
        "event": "progress",
        "received": received,
        "total": total,
        "percent": (
            round(received * 100 / total, 2)
            if total
            else None
        ),
        "speed": round(received / elapsed),
    })


def download_wallpaper(
    provider,
    item_id,
    source,
    hosts,
    callback=None,
):
    """Baixa, valida e publica um wallpaper com progresso."""

    existing = cached_wallpaper(
        provider,
        item_id,
    )

    if existing:
        if callback:
            callback({
                "event": "cached",
                "path": existing,
            })

        return existing, True

    folder = DESTINATION / provider
    folder.mkdir(parents=True, exist_ok=True)

    basename = f"{provider}-{item_id}"

    previous_handler = signal.getsignal(
        signal.SIGTERM
    )

    signal.signal(
        signal.SIGTERM,
        _handle_cancel,
    )

    try:
        with tempfile.TemporaryDirectory(
            prefix=".vesta-",
            dir=folder,
        ) as temporary:

            temporary_dir = Path(temporary)
            raw = temporary_dir / "download"

            with open_remote(
                source,
                hosts,
                accept=(
                    "video/*, application/zip, "
                    "application/octet-stream"
                ),
            ) as response:

                kind = (
                    response.headers.get(
                        "Content-Type",
                        "",
                    )
                    .split(";")[0]
                    .strip()
                    .lower()
                )

                allowed = (
                    kind.startswith("video/")
                    or kind in {
                        "application/zip",
                        "application/x-zip-compressed",
                        "application/octet-stream",
                        "application/x-matroska",
                    }
                )

                if not allowed:
                    raise ValueError(
                        "O servidor não retornou vídeo "
                        "ou ZIP. Content-Type: "
                        + (kind or "desconhecido")
                    )

                length = response.headers.get(
                    "Content-Length"
                )

                try:
                    total = (
                        int(length)
                        if length
                        else None
                    )
                except ValueError:
                    total = None

                if total is not None:
                    if total < 0 or total > MAX_FILE:
                        raise ValueError(
                            "Tamanho do download inválido "
                            "ou superior a 1 GB."
                        )

                final_url = response.geturl()
                received = 0
                started = time.monotonic()
                last_update = started

                _emit_progress(
                    callback,
                    received,
                    total,
                    started,
                )

                with raw.open("wb") as output:
                    while True:
                        chunk = response.read(
                            CHUNK_SIZE
                        )

                        if not chunk:
                            break

                        received += len(chunk)

                        if received > MAX_FILE:
                            raise ValueError(
                                "Download excede o "
                                "limite de 1 GB."
                            )

                        output.write(chunk)

                        now = time.monotonic()

                        if (
                            now - last_update
                            >= PROGRESS_INTERVAL
                        ):
                            _emit_progress(
                                callback,
                                received,
                                total,
                                started,
                            )
                            last_update = now

                if received == 0:
                    raise ValueError(
                        "O arquivo baixado está vazio."
                    )

                if (
                    total is not None
                    and received != total
                ):
                    raise ValueError(
                        "Download incompleto: "
                        "tamanho recebido diferente "
                        "do informado pelo servidor."
                    )

                _emit_progress(
                    callback,
                    received,
                    total,
                    started,
                )

            extension = Path(
                urlparse(final_url).path
            ).suffix.lower()

            is_zip = (
                extension == ".zip"
                or kind in {
                    "application/zip",
                    "application/x-zip-compressed",
                }
                or zipfile.is_zipfile(raw)
            )

            if is_zip:
                if callback:
                    callback({
                        "event": "extracting",
                    })

                extracted = extract_zip(
                    raw,
                    temporary_dir / basename,
                )

            else:
                extension = _extension_for(
                    kind,
                    final_url,
                )

                if extension is None:
                    raise ValueError(
                        "Não foi possível identificar "
                        "o formato do vídeo."
                    )

                extracted = (
                    temporary_dir
                    / (basename + extension)
                )

                os.replace(
                    raw,
                    extracted,
                )

            destination = folder / (
                basename
                + extracted.suffix.lower()
            )

            os.replace(
                extracted,
                destination,
            )

            return str(destination), False

    finally:
        signal.signal(
            signal.SIGTERM,
            previous_handler,
        )