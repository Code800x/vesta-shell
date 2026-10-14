#!/usr/bin/env python3
"""Session-only Hyprland scrolling layout switch; preserves previous layout."""
import json
import os
import subprocess
import sys
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "vesta-shell" / "previous-layout.json"

def hypr(*args):
    return subprocess.run(["hyprctl", *args], text=True, capture_output=True, timeout=5)

def current():
    result = hypr("-j", "getoption", "general:layout")
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Hyprland indisponível")
    data = json.loads(result.stdout)
    return data.get("str", "")

def set_layout(layout):
    # Lua-backed Hyprland rejects `keyword`; legacy Hyprlang accepts it.
    result = hypr("eval", f'hl.config({{ general = {{ layout = "{layout}" }} }})')
    if result.returncode == 0 and result.stdout.strip().lower().startswith("ok"):
        return
    legacy = hypr("keyword", "general:layout", layout)
    if legacy.returncode != 0 or "error" in legacy.stdout.lower() or "can't work" in legacy.stdout.lower():
        raise RuntimeError(legacy.stderr.strip() or legacy.stdout.strip() or result.stderr.strip() or result.stdout.strip() or "Could not change layout")


START_LUA = "-- VESTA_SCROLLING_LAYOUT_BEGIN"
END_LUA = "-- VESTA_SCROLLING_LAYOUT_END"
START_CONF = "# VESTA_SCROLLING_LAYOUT_BEGIN"
END_CONF = "# VESTA_SCROLLING_LAYOUT_END"


def config_path():
    base = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "hypr"
    lua, conf = base / "hyprland.lua", base / "hyprland.conf"
    if lua.is_file():
        return lua, True
    if conf.is_file():
        return conf, False
    raise RuntimeError("Hyprland configuration file not found")


def strip_managed_block(content):
    import re
    pattern = r"(?m)^[ \t]*(?:--|#) VESTA_SCROLLING_LAYOUT_BEGIN[ \t]*\n.*?^[ \t]*(?:--|#) VESTA_SCROLLING_LAYOUT_END[ \t]*(?:\n|$)"
    return re.sub(pattern, "", content, flags=re.DOTALL)


def persistent():
    path, is_lua = config_path()
    return (START_LUA if is_lua else START_CONF) in path.read_text()


def write_config(enabled):
    import shutil
    import tempfile
    path, is_lua = config_path()
    before = path.read_text()
    after = strip_managed_block(before)
    if enabled:
        if is_lua:
            block = f'\n{START_LUA}\nhl.config({{ general = {{ layout = "scrolling" }} }})\n{END_LUA}\n'
        else:
            block = f'\n{START_CONF}\ngeneral:layout = scrolling\n{END_CONF}\n'
        after = after.rstrip("\n") + "\n" + block
    if after == before:
        return
    backup = path.with_name(path.name + ".vesta-backup")
    if not backup.exists():
        shutil.copy2(path, backup)
    fd, temp = tempfile.mkstemp(prefix=".vesta-layout-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(after)
        os.chmod(temp, path.stat().st_mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def previous_layout():
    try:
        value = json.loads(STATE.read_text()).get("previous", "dwindle")
        return value if value in ("dwindle", "master") else "dwindle"
    except (OSError, ValueError):
        return "dwindle"


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action not in ("status", "enable", "disable"):
        raise ValueError("Unknown action")
    before = current()
    if action == "enable":
        if before != "scrolling":
            STATE.parent.mkdir(parents=True, exist_ok=True)
            STATE.write_text(json.dumps({"previous": before}))
        write_config(True)
        if before != "scrolling":
            set_layout("scrolling")
    elif action == "disable":
        write_config(False)
        if before == "scrolling":
            set_layout(previous_layout())
    actual = current()
    if action == "enable" and actual != "scrolling":
        raise RuntimeError(f"Hyprland did not activate scrolling: {actual}")
    if action == "disable" and actual == "scrolling":
        raise RuntimeError("Hyprland is still using scrolling")
    print(json.dumps({"ok": True, "layout": actual, "persistent": persistent()}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        sys.exit(1)
