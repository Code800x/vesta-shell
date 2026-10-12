"""Cache JSON persistente compartilhado por wallpapers estáticos e animados."""
import hashlib
import json
import os
import tempfile
import time
from pathlib import Path

CACHE_DIR = Path.home() / ".cache" / "vesta-shell" / "live-wallpapers" / "search"

class SearchCache:
    """Cache JSON persistente com prazo de validade."""

    def __init__(self, directory=CACHE_DIR, ttl=1800):
        self.directory = Path(directory)
        self.ttl = ttl

    def _path(self, key):
        digest = hashlib.sha256(
            key.encode("utf-8")
        ).hexdigest()

        return self.directory / f"{digest}.json"

    def get(self, key):
        path = self._path(key)

        try:
            with path.open("r", encoding="utf-8") as handle:
                payload = json.load(handle)

            if time.time() - payload["created"] > self.ttl:
                return None

            return payload["data"]

        except (
            OSError,
            ValueError,
            KeyError,
            TypeError,
        ):
            return None

    def set(self, key, data):
        """Grava atomicamente para evitar JSON incompleto."""
        self.directory.mkdir(
            parents=True,
            exist_ok=True,
        )

        path = self._path(key)
        temporary = None

        payload = {
            "created": time.time(),
            "data": data,
        }

        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=self.directory,
                prefix=".search-",
                suffix=".tmp",
                delete=False,
            ) as handle:
                temporary = handle.name
                json.dump(
                    payload,
                    handle,
                    ensure_ascii=False,
                )

            os.replace(temporary, path)

        finally:
            if temporary and os.path.exists(temporary):
                os.unlink(temporary)

    def clear(self):
        """Remove somente os arquivos JSON deste cache."""
        if not self.directory.exists():
            return

        for path in self.directory.glob("*.json"):
            try:
                path.unlink()
            except OSError:
                pass


