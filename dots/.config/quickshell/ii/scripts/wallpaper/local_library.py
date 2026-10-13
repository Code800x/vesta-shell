#!/usr/bin/env python3
"""Inventário e cache assíncrono de miniaturas de wallpapers locais."""
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

IMAGES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".avif"}
VIDEOS = {".mp4", ".webm", ".mkv", ".mov"}
CACHE = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "vesta-shell" / "wallpaper-thumbnails"
LOCK = CACHE / ".worker.lock"

def thumb_path(path, stat, video):
    key = f"{path.resolve()}|{stat.st_size}|{stat.st_mtime_ns}"
    digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
    return CACHE / ("videos" if video else "images") / (digest + ".jpg")

def scan(directory):
    base = Path(directory).expanduser()
    images, videos = [], []
    if not base.is_dir():
        return {"images": [], "videos": [], "missing": 0, "generating": False}
    for parent, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if not d.startswith(".") and not (Path(parent) / d).is_symlink()]
        for name in files:
            if name.startswith("."):
                continue
            path = Path(parent) / name
            ext = path.suffix.lower()
            if ext not in IMAGES | VIDEOS or path.is_symlink():
                continue
            try:
                stat = path.stat()
                if not path.is_file():
                    continue
                video = ext in VIDEOS
                thumb = thumb_path(path, stat, video)
                item = {"name": path.stem.replace("_", " ").replace("-", " "),
                        "path": str(path), "modified": int(stat.st_mtime), "bytes": stat.st_size,
                        "thumbnail": str(thumb) if thumb.is_file() else ""}
                (videos if video else images).append(item)
            except OSError:
                continue
    for items in (images, videos):
        items.sort(key=lambda x: (-x["modified"], x["name"].casefold()))
    missing = sum(not item["thumbnail"] for item in images + videos)
    return {"images": images, "videos": videos, "missing": missing, "generating": False}

def scan_directories(directories):
    """Include legacy ~/Pictures downloads without moving or duplicating files."""
    images, videos = [], []
    seen = set()
    for directory in directories:
        path = Path(directory).expanduser()
        resolved = str(path.resolve())
        if resolved in seen:
            continue
        seen.add(resolved)
        result = scan(path)
        images.extend(result["images"])
        videos.extend(result["videos"])
    for items in (images, videos):
        items.sort(key=lambda item: (-item["modified"], item["name"].casefold()))
    missing = sum(not item["thumbnail"] for item in images + videos)
    return {"images": images, "videos": videos, "missing": missing, "generating": False}


def video_offset(path):
    try:
        result = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
            "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
            capture_output=True, text=True, timeout=8)
        duration = float(result.stdout.strip())
        return min(max(duration * 0.20, 0.5), max(0.5, duration - 0.1))
    except (ValueError, OSError, subprocess.TimeoutExpired):
        return 1.0

def generate(path, destination, video):
    destination.parent.mkdir(parents=True, exist_ok=True)
    tmp = destination.with_name(destination.stem + ".tmp.jpg")
    try:
        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y"]
        if video:
            cmd += ["-ss", str(video_offset(path))]
        cmd += ["-i", str(path), "-frames:v", "1",
                "-vf", "scale=360:210:force_original_aspect_ratio=increase,crop=360:210",
                "-q:v", "5", str(tmp)]
        result = subprocess.run(cmd, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=35)
        if result.returncode == 0 and tmp.is_file() and tmp.stat().st_size:
            os.replace(tmp, destination)
    except (OSError, subprocess.TimeoutExpired):
        pass
    finally:
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass

def worker(directories):
    CACHE.mkdir(parents=True, exist_ok=True)
    with LOCK.open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        inventory = scan_directories(directories)
        for item, video in [(i, False) for i in inventory["images"]] + [(i, True) for i in inventory["videos"]]:
            if item["thumbnail"]:
                continue
            path = Path(item["path"])
            try:
                stat = path.stat()
                dest = thumb_path(path, stat, video)
                if not dest.is_file():
                    generate(path, dest, video)
            except OSError:
                continue

def worker_active():
    CACHE.mkdir(parents=True, exist_ok=True)
    with LOCK.open("a+") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
            return False
        except BlockingIOError:
            return True

def main():
    from xdg_paths import wallpapers_directory
    generating = len(sys.argv) > 1 and sys.argv[1] == "--generate"
    args = sys.argv[2:] if generating else sys.argv[1:]
    primary = args[0] if args else str(wallpapers_directory())
    directories = [primary]
    legacy = Path.home() / "Pictures" / "Wallpapers"
    if legacy.resolve() != Path(primary).expanduser().resolve() and legacy.is_dir():
        directories.append(str(legacy))
    if generating:
        worker(directories)
        return
    result = scan_directories(directories)
    available = shutil.which("ffmpeg") is not None
    active = worker_active()
    if result["missing"] and available and not active:
        subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--generate", primary],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        active = True
    result["generating"] = active and available
    result["ffmpeg_available"] = available
    print(json.dumps(result, ensure_ascii=False))

if __name__ == "__main__":
    main()
