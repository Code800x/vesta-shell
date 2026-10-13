#!/usr/bin/env python3
"""Persist and restore wallpapers per output; keep theming in switchwall.sh."""

import argparse
import copy
import fcntl
import hashlib
import json
import os
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
CONFIG_FILE = CONFIG_HOME / "illogical-impulse/config.json"
RESTORE_SCRIPT = CONFIG_HOME / "hypr/custom/scripts/__restore_video_wallpaper.sh"
LOCK_FILE = STATE_HOME / "quickshell/wallpapers/outputs.lock"
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".avi", ".mov"}
VIDEO_OPTIONS = "no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"


def is_video(path):
    return Path(str(path)).suffix.lower() in VIDEO_EXTENSIONS


def entry_for(background, output):
    entries = background.get("wallpaperByMonitor") or {}
    default = background.get("wallpaperDefault") or {
        "path": background.get("wallpaperPath", ""),
        "thumbnailPath": background.get("thumbnailPath", ""),
    }
    return entries.get(output) or default


def updated_background(background, outputs, path, thumbnail, all_outputs=False):
    result = copy.deepcopy(background)
    default = copy.deepcopy(background.get("wallpaperDefault") or {
        "path": background.get("wallpaperPath", ""),
        "thumbnailPath": background.get("thumbnailPath", ""),
    })
    entry = {"path": path, "thumbnailPath": thumbnail}
    entries = copy.deepcopy(background.get("wallpaperByMonitor") or {})
    if all_outputs:
        default = entry.copy()
        entries = {}
    else:
        for output in outputs:
            entries[output] = entry.copy()
    result.update(wallpaperByMonitor=entries, wallpaperDefault=default,
                  wallpaperPath=path, thumbnailPath=thumbnail)
    return result


@contextmanager
def locked():
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def read_config():
    with CONFIG_FILE.open(encoding="utf-8") as handle:
        config = json.load(handle)
    if not isinstance(config, dict) or not isinstance(config.get("background", {}), dict):
        raise ValueError("Invalid wallpaper configuration")
    return config


def atomic_write(path, content, mode=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".vesta-wallpaper-", dir=path.parent)
    try:
        if mode is not None:
            os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def connected_outputs():
    completed = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True,
                               text=True, timeout=10, check=True)
    data = json.loads(completed.stdout)
    if not isinstance(data, list):
        raise ValueError("Invalid monitor list")
    return list(dict.fromkeys(item["name"] for item in data if item.get("name")))


def process_identity(pid):
    try:
        # starttime prevents signalling a different process if a PID was reused.
        stat = Path(f"/proc/{pid}/stat").read_text()
        return stat[stat.rfind(")") + 2:].split()[19]
    except (OSError, IndexError):
        return None


def players():
    result = []
    for folder in Path("/proc").iterdir():
        if not folder.name.isdecimal():
            continue
        try:
            if folder.stat().st_uid != os.getuid():
                continue
            argv = [part.decode() for part in (folder / "cmdline").read_bytes().split(b"\0") if part]
            if len(argv) < 3 or Path(argv[0]).name != "mpvpaper":
                continue
            # switchwall has always used: mpvpaper -o OPTIONS OUTPUT PATH.
            result.append((int(folder.name), process_identity(folder.name), argv[-2], argv[-1]))
        except (OSError, UnicodeError):
            continue
    return result


def stop_player(player):
    pid, identity, _, _ = player
    if identity is None or process_identity(pid) != identity:
        return
    try:
        os.kill(pid, signal.SIGTERM)
        deadline = time.monotonic() + 0.6
        while process_identity(pid) == identity and time.monotonic() < deadline:
            time.sleep(0.02)
        if process_identity(pid) == identity:
            os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def start_video(output, path):
    executable = shutil.which("mpvpaper")
    if not executable:
        raise RuntimeError("mpvpaper is not installed")
    log_directory = LOCK_FILE.parent
    log_directory.mkdir(parents=True, exist_ok=True)
    log_name = hashlib.sha256(output.encode()).hexdigest()[:16] + ".log"
    with (log_directory / log_name).open("ab") as log:
        process = subprocess.Popen([executable, "-o", VIDEO_OPTIONS, output, path],
                                   stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                   start_new_session=True, close_fds=True)
    time.sleep(0.15)
    if process.poll() is not None:
        raise RuntimeError(f"mpvpaper failed to start for {output}")
    return process


def reconcile(background, outputs, existing=None):
    """Touch only requested outputs; split any legacy ALL player when necessary."""
    existing = players() if existing is None else existing
    shared = [p for p in existing if p[2] in ("ALL", "*")]
    if shared:
        for player in shared:
            stop_player(player)
        outputs = list(dict.fromkeys(outputs + connected_outputs()))
    for output in outputs:
        entry = entry_for(background, output)
        path = str(entry.get("path", ""))
        matching = [p for p in existing if p[2] == output]
        if is_video(path) and Path(path).is_file():
            retained = next((p for p in matching if p[3] == path and process_identity(p[0]) == p[1]), None)
            for player in matching:
                if player != retained:
                    stop_player(player)
            if retained is None:
                start_video(output, path)
        else:
            for player in matching:
                stop_player(player)


def ensure_restore_script():
    # Existing Hyprland startup entry keeps working, including mixed backgrounds.
    command = "exec python3 " + shlex.quote(str(Path(__file__).resolve())) + " restore\n"
    atomic_write(RESTORE_SCRIPT, "#!/usr/bin/env bash\n# Managed by Vesta wallpaper output manager.\n" + command, 0o755)


def apply(path, thumbnail, requested, all_outputs):
    path = str(Path(path).expanduser().resolve(strict=True))
    if not Path(path).is_file():
        raise ValueError("Wallpaper file not found")
    if is_video(path) and not shutil.which("mpvpaper"):
        raise RuntimeError("mpvpaper is not installed")
    with locked():
        connected = connected_outputs()
        outputs = list(dict.fromkeys(requested or connected))
        if not outputs or any(output not in connected for output in outputs):
            raise ValueError("Selected monitor is no longer connected")
        config = read_config()
        old = config.get("background", {})
        new = updated_background(old, outputs, path, thumbnail, all_outputs)
        try:
            ensure_restore_script()
            reconcile(new, outputs)
            config["background"] = new
            atomic_write(CONFIG_FILE, json.dumps(config, ensure_ascii=False, indent=2) + "\n",
                         CONFIG_FILE.stat().st_mode & 0o777)
        except Exception:
            # Restore videos on the touched outputs if startup or persistence fails.
            reconcile(old, outputs)
            raise
    return outputs


def restore():
    with locked():
        config = read_config()
        outputs = connected_outputs()
        reconcile(config.get("background", {}), outputs)
    return outputs


def theme_entry(background, source=None):
    """Resolve a theme image independently of wallpaper application targets."""
    source = background.get("wallpaperThemeSource", "") if source is None else source
    source = "" if source == "auto" else str(source or "")
    entry = (entry_for(background, source) if source else {
        "path": background.get("wallpaperPath", ""),
        "thumbnailPath": background.get("thumbnailPath", ""),
    })
    path = str(entry.get("path", ""))
    if not path or not Path(path).is_file():
        raise ValueError("Theme wallpaper file not found")
    return {"source": source, "path": path,
            "thumbnailPath": str(entry.get("thumbnailPath", ""))}


def resolve_theme(source=None):
    with locked():
        config = read_config()
        background = config.get("background", {})
        if source and source != "auto" and source not in (background.get("wallpaperByMonitor") or {}) \
                and source != background.get("wallpaperThemeSource") and source not in connected_outputs():
            raise ValueError("Selected theme monitor is not available")
        return theme_entry(background, source)


def commit_theme(source, path, thumbnail):
    """Save a successfully generated theme; never touch monitor entries or players."""
    if not Path(path).is_file():
        raise ValueError("Theme wallpaper file not found")
    with locked():
        config = read_config()
        background = config.setdefault("background", {})
        background.update(wallpaperThemeSource="" if source == "auto" else source,
                          wallpaperThemePath=path,
                          wallpaperThemeThumbnailPath=thumbnail)
        atomic_write(CONFIG_FILE, json.dumps(config, ensure_ascii=False, indent=2) + "\n",
                     CONFIG_FILE.stat().st_mode & 0o777)
    return {"source": background["wallpaperThemeSource"], "path": path,
            "thumbnailPath": thumbnail}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    action = subparsers.add_parser("apply")
    action.add_argument("--image", required=True)
    action.add_argument("--thumbnail", default="")
    action.add_argument("--output", action="append", default=[])
    action.add_argument("--all-outputs", action="store_true")
    subparsers.add_parser("restore")
    action = subparsers.add_parser("theme-resolve")
    action.add_argument("--source", default=None)
    action = subparsers.add_parser("theme-commit")
    action.add_argument("--source", required=True)
    action.add_argument("--path", required=True)
    action.add_argument("--thumbnail", default="")
    args = parser.parse_args()
    try:
        if args.action == "theme-resolve":
            print(json.dumps({"ok": True, **resolve_theme(args.source)}, ensure_ascii=False))
        elif args.action == "theme-commit":
            print(json.dumps({"ok": True, **commit_theme(args.source, args.path, args.thumbnail)}, ensure_ascii=False))
        else:
            outputs = (apply(args.image, args.thumbnail, args.output,
                             args.all_outputs or not args.output)
                       if args.action == "apply" else restore())
            print(json.dumps({"ok": True, "outputs": outputs}))
        return 0
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
