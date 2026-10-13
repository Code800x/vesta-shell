"""Resolve XDG user directories consistently with Quickshell Directories.pictures."""
import os
import re
import subprocess
from pathlib import Path


def pictures_directory():
    home = Path.home()
    try:
        result = subprocess.run(
            ["xdg-user-dir", "PICTURES"], capture_output=True, text=True, timeout=3,
            check=True
        )
        value = result.stdout.strip()
        if value:
            return Path(os.path.expandvars(value)).expanduser()
    except (OSError, subprocess.SubprocessError):
        pass

    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "user-dirs.dirs"
    try:
        for line in config.read_text().splitlines():
            match = re.match(r'^\\s*XDG_PICTURES_DIR\\s*=\\s*["\\\']([^"\\\']+)["\\\']', line)
            if match:
                return Path(match.group(1).replace("$HOME", str(home))).expanduser()
    except OSError:
        pass
    return home / "Pictures"


def wallpapers_directory():
    return pictures_directory() / "Wallpapers"
