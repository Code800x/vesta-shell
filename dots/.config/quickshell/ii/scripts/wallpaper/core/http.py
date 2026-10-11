
"""HTTP helpers for wallpaper providers."""

import json
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def fetch(url, accept="application/json"):
    request = Request(
        url,
        headers={
            "User-Agent": "VestaShell/0.1 WallpaperBrowser",
            "Accept": accept,
        },
    )
    return urlopen(request, timeout=25)


def parse_api_error(error):
    try:
        payload = json.loads(
            error.read().decode("utf-8", errors="replace")
        )
        message = payload.get("error")

        if isinstance(message, str) and message:
            return message
    except (ValueError, TypeError, UnicodeError, OSError):
        pass

    if error.code == 429:
        return "Limite de requisições atingido. Tente novamente mais tarde."

    if error.code in (401, 403):
        return "O provedor recusou o acesso à pesquisa solicitada."

    return f"Erro HTTP {error.code} ao consultar o provedor."


def request_json(url):
    try:
        with fetch(url) as response:
            return json.load(response)
    except HTTPError as error:
        raise ValueError(parse_api_error(error)) from error
