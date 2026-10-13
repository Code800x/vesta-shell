
"""Infraestrutura compartilhada dos provedores de live wallpapers."""

import hashlib
import os
import re
import tempfile
import zipfile
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from urllib.parse import urljoin, urlparse, urlsplit, urlunsplit, quote
from urllib.request import Request, urlopen

from xdg_paths import wallpapers_directory

DESTINATION = wallpapers_directory() / "Live"

MAX_HTML = 4 * 1024 * 1024
MAX_FILE = 1024 * 1024 * 1024
MAX_ZIP_ENTRIES = 2000

VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov"}
DOWNLOAD_EXTENSIONS = VIDEO_EXTENSIONS | {".zip"}


def identifier(url):
    return hashlib.sha256(
        url.encode("utf-8")
    ).hexdigest()[:20]


def validate_url(url, hosts):
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()

    if (
        parsed.scheme != "https"
        or parsed.username
        or parsed.password
        or parsed.port is not None
        or not any(
            host == allowed or host.endswith("." + allowed)
            for allowed in hosts
        )
    ):
        raise ValueError("URL fora dos domínios permitidos.")

    return url


def open_remote(url, hosts, accept="*/*", timeout=45):
    # Preserve URL separators and existing percent-encoded sequences while
    # escaping spaces, Unicode and other unsafe characters in path/query.
    validate_url(url, hosts)
    parts = urlsplit(url)
    safe_url = urlunsplit((
        parts.scheme,
        parts.netloc,
        quote(parts.path, safe="/%:@!$&'()*+,;=-._~"),
        quote(parts.query, safe="/%?:@!$&'()*+,;=-._~"),
        parts.fragment,
    ))
    validate_url(safe_url, hosts)

    request = Request(
        safe_url,
        headers={
            "User-Agent": "Mozilla/5.0 VestaShell/0.2",
            "Accept": accept,
            "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8",
        },
    )

    response = urlopen(request, timeout=timeout)

    try:
        validate_url(response.geturl(), hosts)
    except Exception:
        response.close()
        raise

    return response


class HTMLDocument(HTMLParser):
    def __init__(self, base):
        super().__init__(convert_charrefs=True)

        self.base = base
        self.links = []
        self.images = []
        self.videos = []
        self.metadata = {}

        self._anchors = []
        self._articles = []
        self._video_depth = 0
        self.headings = []
        self._heading_depth = 0
        self._heading_text = []

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)

        if tag == "article":
            dimensions = None
            for token in attrs.get("class", "").split():
                match = re.fullmatch(r"resolutions-(\d{3,5})x(\d{3,5})", token)
                if match:
                    dimensions = advertised_resolution("x".join(match.groups()), "")
                    break
            self._articles.append({"dimensions": dimensions, "links": []})

        if tag == "meta":
            key = (
                attrs.get("property")
                or attrs.get("name")
                or ""
            ).lower()

            if key:
                self.metadata[key] = (
                    attrs.get("content") or ""
                )

        if tag == "a":
            href = attrs.get("href")

            if href:
                if self._articles and urlparse(urljoin(self.base, href)).path.startswith("/resolution/"):
                    dimensions = advertised_resolution("", href)
                    if dimensions:
                        self._articles[-1]["dimensions"] = dimensions
                self._anchors.append({
                    "url": urljoin(self.base, href),
                    "title": str(
                        attrs.get("title")
                        or attrs.get("aria-label")
                        or ""
                    ),
                    "thumb": "",
                    "download": "download" in attrs,
                })

        if tag == "img":
            src = (
                attrs.get("data-src")
                or attrs.get("data-original")
                or attrs.get("data-lazy-src")
                or attrs.get("src")
            )

            if src:
                image_url = urljoin(self.base, src)

                self.images.append({
                    "url": image_url,
                    "alt": attrs.get("alt") or "",
                })

                if self._anchors:
                    anchor = self._anchors[-1]

                    if not anchor["thumb"]:
                        anchor["thumb"] = image_url

                    if not anchor["title"]:
                        anchor["title"] = str(
                            attrs.get("alt") or ""
                        )

        if tag == "h1":
            self._heading_depth += 1
            self._heading_text = []

        if tag == "video":
            self._video_depth += 1

        if tag in ("video", "source"):
            src = attrs.get("src")

            if src and (
                tag == "video"
                or self._video_depth > 0
            ):
                self.videos.append(
                    urljoin(self.base, src)
                )

    def handle_data(self, data):
        if self._heading_depth and data.strip():
            self._heading_text.append(data.strip())

        if self._anchors and data.strip():
            anchor = self._anchors[-1]

            anchor["title"] = (
                str(anchor.get("title") or "")
                + " "
                + data.strip()
            )

    def handle_endtag(self, tag):
        if tag == "h1" and self._heading_depth:
            self.headings.append(" ".join(self._heading_text))
            self._heading_depth -= 1
            self._heading_text = []

        if tag == "a" and self._anchors:
            anchor = self._anchors.pop()
            self.links.append(anchor)
            if self._articles:
                self._articles[-1]["links"].append(anchor)

        if tag == "article" and self._articles:
            article = self._articles.pop()
            if article["dimensions"]:
                for link in article["links"]:
                    link["advertised_dimensions"] = article["dimensions"]

        if tag == "video":
            self._video_depth = max(
                0,
                self._video_depth - 1,
            )


def fetch_page(url, hosts, timeout=45):
    with open_remote(
        url,
        hosts,
        accept="text/html",
        timeout=timeout,
    ) as response:

        content_type = response.headers.get(
            "Content-Type", ""
        ).lower()

        if "text/html" not in content_type:
            raise ValueError(
                "O servidor não retornou HTML."
            )

        data = response.read(MAX_HTML + 1)

        if len(data) > MAX_HTML:
            raise ValueError(
                "Página HTML muito grande."
            )

        document = HTMLDocument(
            response.geturl()
        )

        document.feed(
            data.decode(
                "utf-8",
                errors="replace",
            )
        )

        return document


def clean_title(title, fallback):
    title = " ".join(
        str(title or "").split()
    )

    title = re.sub(
        r"^(download|watch|preview)\s+",
        "",
        title,
        flags=re.IGNORECASE,
    )

    match = re.search(
        r"(.+?live wallpaper)",
        title,
        flags=re.IGNORECASE,
    )

    if match:
        title = match.group(1)

    return (
        title
        or fallback.replace("-", " ").title()
    )[:160]


def advertised_resolution(title, url):
    """Infer only resolutions explicitly advertised by the listing.

    This is not a measurement of the video file. Unknown is intentional.
    """
    text = f"{title or ''} {urlparse(url).path}".lower()
    dimensions = re.search(r"(?<!\d)(\d{3,5})\s*[x×]\s*(\d{3,5})(?!\d)", text)
    if dimensions:
        width, height = map(int, dimensions.groups())
        if 240 <= min(width, height) and max(width, height) <= 16384:
            return width, height
    if re.search(r"(?<![a-z0-9])(?:8k|4320p)(?![a-z0-9])", text):
        return 7680, 4320
    if re.search(r"(?<![a-z0-9])(?:4k|uhd|2160p)(?![a-z0-9])", text):
        return 3840, 2160
    if re.search(r"(?<![a-z0-9])(?:2k|qhd|1440p)(?![a-z0-9])", text):
        return 2560, 1440
    if re.search(r"(?<![a-z0-9])(?:fhd|1080p)(?![a-z0-9])", text):
        return 1920, 1080
    return None


def wallpaper_item(provider, url, title, thumb):
    slug = (
        urlparse(url)
        .path.rstrip("/")
        .split("/")[-1]
    )

    dimensions = advertised_resolution(title, url)

    return {
        "id": identifier(url),
        "title": clean_title(title, slug),
        "provider": provider,
        "url": url,
        "thumb": thumb,
        "resolution": (
            f"{dimensions[0]}x{dimensions[1]}" if dimensions else "Desconhecida"
        ),
        "width": dimensions[0] if dimensions else None,
        "height": dimensions[1] if dimensions else None,
    }


def unique_items(items):
    result = []
    seen = set()

    for item in items:
        if item["url"] in seen:
            continue

        seen.add(item["url"])
        result.append(item)

    return result


def has_next_page(provider, query, number, items):
    if number >= 100:
        return False

    from urllib.error import HTTPError

    try:
        next_items = provider.fetch(
            query,
            number + 1,
        )
    except HTTPError as error:
        if error.code in (404, 410):
            return False
        raise

    current = {
        item["id"]
        for item in items
    }

    return any(
        item["id"] not in current
        for item in next_items
    )


def download_remote(url, hosts, target):
    with open_remote(
        url,
        hosts,
        accept=(
            "video/*, application/zip, "
            "application/octet-stream"
        ),
    ) as response:

        kind = (
            response.headers.get(
                "Content-Type", ""
            )
            .lower()
            .split(";")[0]
            .strip()
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
                "O servidor não retornou vídeo ou ZIP. "
                f"Content-Type: {kind or 'desconhecido'}"
            )

        total = 0

        with open(target, "wb") as output:
            while True:
                chunk = response.read(
                    1024 * 1024
                )

                if not chunk:
                    break

                total += len(chunk)

                if total > MAX_FILE:
                    raise ValueError(
                        "Download excede o limite de 1 GB."
                    )

                output.write(chunk)

        if not total:
            raise ValueError(
                "Arquivo baixado está vazio."
            )

        return kind, response.geturl()


def extract_zip(source, target_base):
    try:
        with zipfile.ZipFile(source) as archive:
            entries = archive.infolist()

            if len(entries) > MAX_ZIP_ENTRIES:
                raise ValueError(
                    "ZIP contém arquivos demais."
                )

            candidates = []
            found = set()

            for info in entries:
                path = PurePosixPath(
                    info.filename
                )

                if (
                    info.is_dir()
                    or path.is_absolute()
                    or ".." in path.parts
                    or "\\" in info.filename
                ):
                    continue

                file_type = (
                    info.external_attr >> 16
                ) & 0o170000

                if file_type not in (
                    0,
                    0o100000,
                ):
                    continue

                extension = (
                    path.suffix.lower()
                )

                if extension:
                    found.add(extension)

                if (
                    extension in VIDEO_EXTENSIONS
                    and 0 < info.file_size <= MAX_FILE
                ):
                    candidates.append(info)

            if not candidates:
                extensions = (
                    ", ".join(sorted(found))
                    or "nenhum"
                )

                raise ValueError(
                    "O ZIP não contém vídeo compatível "
                    "com mpvpaper. Formatos encontrados: "
                    + extensions
                )

            selected = max(
                candidates,
                key=lambda entry: entry.file_size,
            )

            extension = PurePosixPath(
                selected.filename
            ).suffix.lower()

            output_path = (
                target_base.with_suffix(
                    extension
                )
            )

            total = 0

            with (
                archive.open(selected) as reader,
                open(output_path, "wb") as writer,
            ):
                while True:
                    chunk = reader.read(
                        1024 * 1024
                    )

                    if not chunk:
                        break

                    total += len(chunk)

                    if total > MAX_FILE:
                        raise ValueError(
                            "Vídeo extraído excede 1 GB."
                        )

                    writer.write(chunk)

            if total != selected.file_size:
                raise ValueError(
                    "Extração incompleta do vídeo."
                )

            return output_path

    except (
        zipfile.BadZipFile,
        RuntimeError,
    ) as error:
        raise ValueError(
            "ZIP inválido ou protegido por senha."
        ) from error


def save_wallpaper(provider, item_id, source, hosts):
    folder = DESTINATION / provider

    folder.mkdir(
        parents=True,
        exist_ok=True,
    )

    basename = (
        f"{provider}-{item_id}"
    )

    for extension in VIDEO_EXTENSIONS:
        existing = folder / (
            basename + extension
        )

        if (
            existing.is_file()
            and existing.stat().st_size > 0
        ):
            return str(existing)

    with tempfile.TemporaryDirectory(
        prefix=".vesta-",
        dir=folder,
    ) as temporary_dir:

        temporary_dir = Path(
            temporary_dir
        )

        raw = (
            temporary_dir / "download"
        )

        kind, final_url = download_remote(
            source,
            hosts,
            raw,
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
            extracted = extract_zip(
                raw,
                temporary_dir / basename,
            )
        else:
            if extension not in VIDEO_EXTENSIONS:
                if kind == "video/webm":
                    extension = ".webm"

                elif kind in (
                    "video/x-matroska",
                    "application/x-matroska",
                ):
                    extension = ".mkv"

                elif kind in (
                    "video/mp4",
                    "video/quicktime",
                ):
                    extension = (
                        ".mov"
                        if kind == "video/quicktime"
                        else ".mp4"
                    )

                else:
                    raise ValueError(
                        "Não foi possível identificar "
                        "o formato do vídeo."
                    )

            extracted = temporary_dir / (
                basename + extension
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

        return str(destination)
