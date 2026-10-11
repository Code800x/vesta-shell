
#!/usr/bin/env python3
"""Inspeciona páginas públicas de provedores de live wallpapers.

Uso:
    python3 inspect_provider.py motionbgs
    python3 inspect_provider.py desktophut
    python3 inspect_provider.py motionbgs --url https://motionbgs.com/...
"""

import argparse
import json
import sys
from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen


PROVIDERS = {
    "motionbgs": {
        "name": "MotionBGS",
        "base_url": "https://motionbgs.com/",
        "hosts": ("motionbgs.com",),
    },
    "desktophut": {
        "name": "DesktopHut",
        "base_url": "https://www.desktophut.com/",
        "hosts": ("desktophut.com",),
    },
}


def emit(**data):
    print(json.dumps(data, ensure_ascii=False, indent=2))


def host_allowed(hostname, allowed_hosts):
    hostname = (hostname or "").lower()
    return any(
        hostname == domain or hostname.endswith("." + domain)
        for domain in allowed_hosts
    )


def validate_url(url, provider):
    parsed = urlparse(url)
    config = PROVIDERS[provider]

    if (
        parsed.scheme != "https"
        or not host_allowed(parsed.hostname, config["hosts"])
        or parsed.username
        or parsed.password
        or parsed.port is not None
    ):
        raise ValueError("URL fora do domínio permitido.")

    return url


class PageInspector(HTMLParser):
    def __init__(self, base_url):
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.links = []
        self.images = []
        self.videos = []
        self.metadata = []
        self.title = ""
        self._inside_title = False

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)

        if tag == "title":
            self._inside_title = True

        if tag == "meta":
            self.metadata.append({
                "property": (
                    attributes.get("property")
                    or attributes.get("name")
                    or ""
                ),
                "content": attributes.get("content", ""),
            })

        if tag == "a" and attributes.get("href"):
            self.links.append({
                "url": urljoin(
                    self.base_url,
                    attributes["href"],
                ),
                "title": (
                    attributes.get("title")
                    or attributes.get("aria-label")
                    or ""
                ),
                "download": "download" in attributes,
            })

        if tag == "img":
            source = (
                attributes.get("data-src")
                or attributes.get("src")
                or ""
            )

            if source:
                self.images.append({
                    "url": urljoin(self.base_url, source),
                    "alt": attributes.get("alt", ""),
                })

        if tag in ("video", "source"):
            source = attributes.get("src", "")

            if source:
                self.videos.append({
                    "url": urljoin(self.base_url, source),
                    "type": attributes.get("type", ""),
                })

    def handle_endtag(self, tag):
        if tag == "title":
            self._inside_title = False

    def handle_data(self, data):
        if self._inside_title:
            self.title += data


def inspect(provider, url):
    validate_url(url, provider)

    request = Request(
        url,
        headers={
            "User-Agent": "VestaShell/0.1",
            "Accept": "text/html",
        },
    )

    with urlopen(request, timeout=25) as response:
        final_url = response.geturl()
        validate_url(final_url, provider)

        content_type = response.headers.get(
            "Content-Type", ""
        ).lower()

        if "text/html" not in content_type:
            raise ValueError(
                "O servidor não retornou uma página HTML."
            )

        html = response.read(2 * 1024 * 1024).decode(
            "utf-8",
            errors="replace",
        )

    parser = PageInspector(final_url)
    parser.feed(html)

    video_links = [
        item
        for item in parser.links
        if ".mp4" in item["url"].lower()
        or ".webm" in item["url"].lower()
        or item["download"]
    ]

    metadata = [
        item
        for item in parser.metadata
        if item["property"] in (
            "og:title",
            "og:image",
            "og:video",
            "description",
            "twitter:image",
        )
    ]

    emit(
        ok=True,
        provider=provider,
        page=final_url,
        title=parser.title.strip(),
        metadata=metadata[:30],
        links_count=len(parser.links),
        images=parser.images[:15],
        videos=parser.videos[:15],
        download_candidates=video_links[:30],
        internal_links=[
            item
            for item in parser.links
            if host_allowed(
                urlparse(item["url"]).hostname,
                PROVIDERS[provider]["hosts"],
            )
        ][:30],
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "provider",
        choices=PROVIDERS.keys(),
    )
    parser.add_argument("--url", default="")
    args = parser.parse_args()

    url = (
        args.url
        or PROVIDERS[args.provider]["base_url"]
    )

    try:
        inspect(args.provider, url)
    except (
        ValueError,
        HTTPError,
        URLError,
        OSError,
        TimeoutError,
    ) as error:
        emit(ok=False, error=str(error))
        sys.exit(1)


if __name__ == "__main__":
    main()
