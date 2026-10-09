
#!/usr/bin/env python3
"""
Instalador da funcionalidade Monitores do Vesta Shell
para uma instalação existente do end4.

Não substitui a shell completa.
Não reinicia o Hyprland.
Cria backup antes de modificar arquivos.
"""

import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

HOME = Path.home()
REPO = HOME / "Projetos/vesta-shell"
REL = Path("dots/.config/quickshell/ii")
SOURCE = REPO / REL
TARGET = HOME / ".config/quickshell/ii"
HYPR = HOME / ".config/hypr"

BASE_COMMIT = "33f31a08"

FILES = [
    "modules/settings/DisplaysConfig.qml",
    "modules/settings/components/MonitorArrangement.qml",
    "modules/settings/components/MonitorIdentifier.qml",
    "services/DisplayManager.qml",
    "scripts/displays/display_transaction.py",
    "scripts/displays/display_persistent.py",
]

SETTINGS = "settings.qml"
TRANSLATIONS = "translations/pt_BR.json"


def info(message):
    print(f"[INFO] {message}")


def fail(message):
    raise RuntimeError(message)


def command(args, cwd=None, input_text=None):
    result = subprocess.run(
        args,
        cwd=cwd,
        input=input_text,
        text=True,
        capture_output=True
    )
    if result.returncode != 0:
        fail(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def git_base(relative):
    return command([
        "git", "show",
        f"{BASE_COMMIT}:{REL / relative}"
    ], cwd=REPO)


def merge_translation(base, new, installed):
    if not isinstance(base, dict):
        return new if installed == base else installed

    if not isinstance(new, dict) or not isinstance(installed, dict):
        fail("Estrutura de traduções incompatível")

    merged = dict(installed)

    for key, value in new.items():
        if key not in base:
            if key in merged and merged[key] != value:
                fail(f"Conflito de tradução: {key}")
            merged[key] = value
        elif isinstance(value, dict) and isinstance(base[key], dict):
            existing = merged.get(key, {})
            merged[key] = merge_translation(
                base[key], value, existing
            )
        elif value != base[key]:
            existing = merged.get(key, base[key])
            if existing not in (base[key], value):
                fail(f"Conflito de tradução: {key}")
            merged[key] = value

    return merged


def patch_settings():
    original = git_base(SETTINGS)
    modified = (SOURCE / SETTINGS).read_text(
        encoding="utf-8"
    )
    installed = (TARGET / SETTINGS).read_text(
        encoding="utf-8"
    )

    if installed == modified:
        info("settings.qml já corresponde ao Vesta Shell")
        return installed

    if "DisplaysConfig" in installed:
        info("Página Monitores já aparece em settings.qml")
        return installed

    patch = "".join(difflib.unified_diff(
        original.splitlines(keepends=True),
        modified.splitlines(keepends=True),
        fromfile="settings.qml",
        tofile="settings.qml"
    ))

    if not patch:
        fail("Não encontrei alterações de integração em settings.qml")

    if not shutil.which("patch"):
        fail("O comando 'patch' não está instalado")

    with tempfile.TemporaryDirectory() as directory:
        temporary = Path(directory)
        destination = temporary / "settings.qml"
        destination.write_text(installed, encoding="utf-8")

        test = subprocess.run(
            ["patch", "--batch", "--fuzz=0", "--dry-run",
             "-p0", "-i", "-"],
            cwd=temporary,
            input=patch,
            text=True,
            capture_output=True
        )

        if test.returncode != 0:
            fail(
                "A versão de settings.qml do end4 não é "
                "compatível com a integração automática. "
                "Nenhum arquivo foi modificado."
            )

        command(
            ["patch", "--batch", "--fuzz=0", "-p0", "-i", "-"],
            cwd=temporary,
            input_text=patch
        )

        result = destination.read_text(encoding="utf-8")

    if "DisplaysConfig" not in result:
        fail("A página Monitores não foi integrada corretamente")

    return result


def prepare_monitors_lua():
    lua = HYPR / "hyprland.lua"

    if not lua.exists():
        fail(
            "Não encontrei ~/.config/hypr/hyprland.lua. "
            "Esta instalação não usa a estrutura Lua esperada."
        )

    original = lua.read_text(encoding="utf-8")
    module = HYPR / "monitors.lua"

    if module.exists():
        monitor_content = None
    else:
        current = json.loads(
            command(["hyprctl", "monitors", "-j"])
        )

        if not current:
            fail("Nenhum monitor ativo encontrado")

        lines = [
            "-- Configuração de monitores gerenciada pelo Vesta Shell.",
            "-- Criada a partir do estado atual do Hyprland.",
            "",
        ]

        for monitor in current:
            name = json.dumps(monitor["name"])
            mode = (
                f"{monitor['width']}x{monitor['height']}@"
                f"{float(monitor['refreshRate']):.5f}"
            )
            available = [
                item.removesuffix("Hz")
                for item in monitor.get("availableModes", [])
            ]
            for candidate in available:
                if not candidate.startswith(
                    f"{monitor['width']}x{monitor['height']}@"
                ):
                    continue
                try:
                    rate = float(candidate.split("@", 1)[1])
                    if abs(
                        rate - float(monitor["refreshRate"])
                    ) < 0.15:
                        mode = candidate
                        break
                except ValueError:
                    continue

            position = f"{monitor['x']}x{monitor['y']}"
            scale = float(monitor["scale"])
            transform = int(monitor["transform"])
            vrr = int(bool(monitor.get("vrr", False)))

            lines.append(
                "hl.monitor({"
                f"output={name}, "
                f"mode={json.dumps(mode)}, "
                f"position={json.dumps(position)}, "
                f"scale={scale:.10g}, "
                f"transform={transform}, "
                f"vrr={vrr}"
                "})"
            )

        monitor_content = "\n".join(lines) + "\n"

    if re.search(
        r"""require\s*\(\s*["']monitors["']\s*\)""",
        original
    ):
        lua_content = None
    else:
        # Insere o carregamento depois das configurações
        # existentes, preservando o restante do arquivo.
        lua_content = (
            original.rstrip()
            + '\n\n-- Vesta Shell: monitores persistentes\n'
            + 'require("monitors")\n'
        )

    return module, monitor_content, lua, lua_content


def main():
    info("Instalador de Monitores — Vesta Shell / end4")

    if not SOURCE.is_dir():
        fail(f"Projeto não encontrado: {SOURCE}")

    if not TARGET.is_dir():
        fail(f"Instalação do end4 não encontrada: {TARGET}")

    for relative in FILES + [SETTINGS, TRANSLATIONS]:
        if not (SOURCE / relative).is_file():
            fail(f"Arquivo ausente no Vesta Shell: {relative}")

    if not (TARGET / SETTINGS).is_file():
        fail("settings.qml não encontrado no end4")

    if not (TARGET / TRANSLATIONS).is_file():
        fail("pt_BR.json não encontrado no end4")

    info("Preparando integração da página de monitores")
    settings_content = patch_settings()

    info("Preparando traduções")
    base_translation = json.loads(
        git_base(TRANSLATIONS)
    )
    source_translation = json.loads(
        (SOURCE / TRANSLATIONS).read_text(encoding="utf-8")
    )
    target_translation = json.loads(
        (TARGET / TRANSLATIONS).read_text(encoding="utf-8")
    )

    merged_translation = merge_translation(
        base_translation,
        source_translation,
        target_translation
    )

    info("Verificando configuração Lua do Hyprland")
    module, monitor_content, lua, lua_content = (
        prepare_monitors_lua()
    )

    changes = {}

    for relative in FILES:
        changes[TARGET / relative] = (
            SOURCE / relative
        ).read_bytes()

    changes[TARGET / SETTINGS] = settings_content.encode(
        "utf-8"
    )

    changes[TARGET / TRANSLATIONS] = (
        json.dumps(
            merged_translation,
            ensure_ascii=False,
            indent=2
        ) + "\n"
    ).encode("utf-8")

    if monitor_content is not None:
        changes[module] = monitor_content.encode("utf-8")

    if lua_content is not None:
        changes[lua] = lua_content.encode("utf-8")

    # Remove alterações que não mudariam o conteúdo.
    changes = {
        path: content
        for path, content in changes.items()
        if not path.exists() or path.read_bytes() != content
    }

    if not changes:
        info("Todos os arquivos já estão instalados")
        return

    backup = HOME / "Backups" / (
        "end4-monitores-"
        + datetime.now().strftime("%Y%m%d-%H%M%S")
    )

    info(f"Criando backup em: {backup}")

    manifest = []

    for path in changes:
        existed = path.exists()

        try:
            relative = path.relative_to(HOME)
        except ValueError:
            fail(f"Caminho fora da pasta pessoal: {path}")

        manifest.append({
            "path": str(path),
            "existed": existed
        })

        if existed:
            destination = backup / relative
            destination.parent.mkdir(
                parents=True,
                exist_ok=True
            )
            shutil.copy2(path, destination)

    backup.mkdir(parents=True, exist_ok=True)
    (backup / "manifest.json").write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8"
    )

    written = []

    try:
        for path, content in changes.items():
            path.parent.mkdir(
                parents=True,
                exist_ok=True
            )

            temporary = path.with_name(
                path.name + ".vesta-install.tmp"
            )
            temporary.write_bytes(content)

            if path.exists():
                shutil.copymode(path, temporary)

            os.replace(temporary, path)
            written.append(path)
            info(f"Instalado: {path.relative_to(HOME)}")

    except Exception:
        info("Erro durante a instalação. Restaurando arquivos.")

        for path in reversed(written):
            relative = path.relative_to(HOME)
            previous = backup / relative

            if previous.exists():
                shutil.copy2(previous, path)
            else:
                path.unlink(missing_ok=True)

        raise

    print()
    print("Instalação concluída.")
    print(f"Backup: {backup}")
    print()
    print("A configuração Lua foi preparada, mas o")
    print("Hyprland NÃO foi recarregado automaticamente.")
    print("Reinicie apenas o Quickshell para testar a página.")
    print()
    print("Observação: se a configuração Lua do Hyprland")
    print("já contiver regras de monitor conflitantes,")
    print("elas precisarão ser revisadas antes do próximo")
    print("recarregamento do Hyprland.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"\n[ERRO] {error}", file=sys.stderr)
        sys.exit(1)
