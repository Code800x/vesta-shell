
"""Central provider registry for Vesta Shell wallpapers."""

from providers import wallhaven, konachan, yandere

PROVIDERS = {
    "wallhaven": wallhaven,
    "konachan": konachan,
    "yandere": yandere,
}

PROVIDER_NAMES = {
    "wallhaven": "Wallhaven",
    "konachan": "Konachan",
    "yandere": "Yande.re",
}


def compatible(purity):
    """Return providers compatible with a content classification."""
    return [
        {
            "code": code,
            "name": PROVIDER_NAMES.get(code, code),
        }
        for code, module in PROVIDERS.items()
        if purity in module.SUPPORTED_PURITY
    ]


def get(provider, purity):
    """Resolve a provider and validate its supported classification."""
    module = PROVIDERS.get(provider)

    if module is None:
        raise ValueError(
            f"Provedor desconhecido: {provider}"
        )

    if purity not in module.SUPPORTED_PURITY:
        raise ValueError(
            "Provedor indisponível para este tipo de conteúdo."
        )

    return module
