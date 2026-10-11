
#!/usr/bin/env python3
"""Vesta Shell - Keyboard layout configuration for Hyprland Lua."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CONFIG = Path.home() / ".config/hypr/hyprland/general.lua"

LAYOUTS = {
    "br": ("", "abnt2", "nodeadkeys"),
    "us": ("", "intl", "altgr-intl"),
    "pt": ("", "nodeadkeys"),
    "es": ("", "nodeadkeys"),
    "gb": ("", "intl"),
    "de": ("", "nodeadkeys"),
    "fr": ("", "oss"),
    "it": ("",),
}


def emit(data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def lua_string(value):
    return json.dumps(value, ensure_ascii=True)


def read_config():
    if not CONFIG.is_file():
        raise RuntimeError(
            f"Arquivo de configuração não encontrado: {CONFIG}"
        )
    return CONFIG.read_text(encoding="utf-8")


def get_field(content, name, default=""):
    pattern = (
        rf'^\s*{re.escape(name)}\s*=\s*'
        rf'["\']([^"\']*)["\']\s*,?'
    )

    match = re.search(pattern, content, flags=re.MULTILINE)
    return match.group(1) if match else default


def current_state():
    content = read_config()

    return {
        "ok": True,
        "layout": get_field(content, "kb_layout", "br"),
        "variant": get_field(content, "kb_variant", "abnt2"),
        "options": get_field(content, "kb_options", ""),
        "config": str(CONFIG),
    }


def replace_field(content, name, value):
    pattern = (
        rf'^(\s*{re.escape(name)}\s*=\s*)'
        rf'(["\'])[^"\']*\2(\s*,?)'
    )

    matches = list(re.finditer(pattern, content, re.MULTILINE))

    if len(matches) > 1:
        raise RuntimeError(
            f"Campo {name} aparece mais de uma vez em general.lua"
        )

    if matches:
        return re.sub(
            pattern,
            lambda m: (
                f"{m.group(1)}{m.group(2)}"
                f"{value}{m.group(2)}{m.group(3)}"
            ),
            content,
            count=1,
            flags=re.MULTILINE,
        )

    anchor_pattern = r"^([ \t]*)kb_layout\s*="

    anchor = re.search(anchor_pattern, content, re.MULTILINE)

    if not anchor:
        raise RuntimeError(
            "Não foi encontrado kb_layout em general.lua"
        )

    indentation = anchor.group(1)

    return re.sub(
        r"^([ \t]*kb_layout\s*=.*)$",
        lambda m: (
            m.group(0)
            + f'\n{indentation}{name} = "{value}",'
        ),
        content,
        count=1,
        flags=re.MULTILINE,
    )


def validate(layout, variant, options):
    if layout not in LAYOUTS:
        raise ValueError(f"Layout não suportado: {layout}")

    if variant not in LAYOUTS[layout]:
        raise ValueError(
            f"Variante '{variant}' inválida para '{layout}'"
        )

    if options:
        raise ValueError(
            "A configuração de atalhos ainda não está habilitada"
        )


def run_eval(layout, variant, options):
    """
    Apply keyboard settings through Hyprland's Lua evaluator.

    This avoids `hyprctl keyword`, which is unsupported by
    the non-legacy Lua configuration parser.
    """

    expression = (
        "hl.config({"
        "input = {"
        f"kb_layout = {lua_string(layout)},"
        f"kb_variant = {lua_string(variant)},"
        f"kb_options = {lua_string(options)}"
        "}"
        "})"
    )

    try:
        result = subprocess.run(
            ["hyprctl", "eval", expression],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except FileNotFoundError as error:
        raise RuntimeError(
            "hyprctl não foi encontrado no sistema"
        ) from error

    response = (
        result.stdout.strip()
        + "\n"
        + result.stderr.strip()
    ).strip()

    if result.returncode != 0:
        raise RuntimeError(
            response or "Falha ao aplicar configuração Lua"
        )

    if re.search(
        r"\b(error|exception|failed|invalid)\b",
        response,
        re.IGNORECASE,
    ):
        raise RuntimeError(response)

    if not response:
        raise RuntimeError(
            "O Hyprland não confirmou a execução do comando"
        )

    return response


def atomic_write(content):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)

    fd, temporary = tempfile.mkstemp(
        prefix=".vesta-keyboard-",
        suffix=".lua",
        dir=str(CONFIG.parent),
    )

    try:
        os.fchmod(fd, CONFIG.stat().st_mode & 0o777)

        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(temporary, CONFIG)

    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def apply(layout, variant, options):
    validate(layout, variant, options)

    previous = current_state()
    original = read_config()

    updated = original
    updated = replace_field(updated, "kb_layout", layout)
    updated = replace_field(updated, "kb_variant", variant)
    updated = replace_field(updated, "kb_options", options)

    backup = CONFIG.with_name(
        CONFIG.name + ".vesta-keyboard-backup"
    )

    if not backup.exists():
        shutil.copy2(CONFIG, backup)

    try:
        response = run_eval(layout, variant, options)
    except Exception:
        raise

    try:
        atomic_write(updated)
    except Exception as error:
        try:
            run_eval(
                previous["layout"],
                previous["variant"],
                previous["options"],
            )
        except Exception:
            pass

        raise RuntimeError(
            f"Não foi possível salvar general.lua: {error}"
        ) from error

    return {
        "ok": True,
        "message": "Layout aplicado e salvo",
        "layout": layout,
        "variant": variant,
        "options": options,
        "response": response,
        "backup": str(backup),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Vesta Shell keyboard configuration"
    )

    subparsers = parser.add_subparsers(
        dest="action",
        required=True,
    )

    subparsers.add_parser("status")

    apply_parser = subparsers.add_parser("apply")

    apply_parser.add_argument(
        "--layout",
        required=True,
    )

    apply_parser.add_argument(
        "--variant",
        default="",
    )

    apply_parser.add_argument(
        "--options",
        default="",
    )

    args = parser.parse_args()

    try:
        if args.action == "status":
            emit(current_state())
        elif args.action == "apply":
            emit(
                apply(
                    args.layout,
                    args.variant,
                    args.options,
                )
            )
    except Exception as error:
        emit({
            "ok": False,
            "error": str(error),
        })
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
