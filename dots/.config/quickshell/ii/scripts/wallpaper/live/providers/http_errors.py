"""Tratamento compartilhado de páginas de listagem HTTP.

404 e 410 podem significar fim de paginação; nunca são
convertidos em lista vazia na primeira página.
Erros de acesso, limite de requisições e servidor são propagados.
"""

from urllib.error import HTTPError


def fetch_listing_or_end(fetch_page, url, hosts, *, page, missing_page_is_end):
    """Retorna documento HTML ou None para fim de paginação conhecido."""
    try:
        return fetch_page(url, hosts)
    except HTTPError as error:
        if (
            error.code in (404, 410)
            and int(page) > 1
            and missing_page_is_end
        ):
            return None
        raise
