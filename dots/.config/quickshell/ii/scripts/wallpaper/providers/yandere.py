
"""Yande.re provider."""

from providers.moebooru import search as search_moebooru

SUPPORTED_PURITY = ("100", "110", "111")
API = "https://yande.re/post.json"


def search(args):
    return search_moebooru(args, API)
