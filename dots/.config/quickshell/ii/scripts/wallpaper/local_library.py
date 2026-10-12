#!/usr/bin/env python3
"""Inventário local de wallpapers; não altera os arquivos encontrados."""
import json
import os
import sys
from pathlib import Path

IMAGES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".avif"}
VIDEOS = {".mp4", ".webm", ".mkv", ".mov"}

def scan(directory):
    base = Path(directory).expanduser()
    images, videos = [], []
    if not base.is_dir():
        return {"images": [], "videos": []}
    for parent, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if not d.startswith(".") and not (Path(parent) / d).is_symlink()]
        for name in files:
            if name.startswith("."):
                continue
            path = Path(parent) / name
            ext = path.suffix.lower()
            if ext not in IMAGES | VIDEOS:
                continue
            try:
                stat = path.stat()
                if not path.is_file():
                    continue
                item = {"name": path.stem.replace("_", " ").replace("-", " "),
                        "path": str(path), "modified": int(stat.st_mtime), "bytes": stat.st_size}
                (images if ext in IMAGES else videos).append(item)
            except OSError:
                continue
    for items in (images, videos):
        items.sort(key=lambda x: (-x["modified"], x["name"].casefold()))
    return {"images": images, "videos": videos}

if __name__ == "__main__":
    print(json.dumps(scan(sys.argv[1] if len(sys.argv) > 1 else str(Path.home() / "Pictures" / "Wallpapers")), ensure_ascii=False))
