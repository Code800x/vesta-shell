#!/usr/bin/env bash
# Restore per-monitor video wallpapers using the shared Vesta backend.
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
exec python3 "$config_home/quickshell/ii/scripts/wallpaper/output_manager.py" restore
