#!/usr/bin/env python3
"""Instala wallpapers (estáticos, animados) e teclado da Vesta em end4 existente.

Não substitui a shell inteira. Cria backup e interrompe diante de conflitos.
"""
import argparse
import difflib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REL = Path('dots/.config/quickshell/ii')
SOURCE = ROOT / REL
TARGET = Path.home() / '.config/quickshell/ii'
BASE_COMMIT = '33f31a08'  # Mesmo ancestral usado por instalar-monitores.py


def run(argv, **kwargs):
    result = subprocess.run(argv, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"Comando falhou: {' '.join(argv)}\n{result.stderr or result.stdout}")
    return result.stdout


def base_file(name):
    return run(['git', 'show', f'{BASE_COMMIT}:{REL / name}'], cwd=ROOT)


def merge_file(name):
    """Aplica somente a diferença Vesta/end4, sem substituir personalizações."""
    source = (SOURCE / name).read_text(encoding='utf-8')
    target_path = TARGET / name
    if not target_path.is_file():
        raise RuntimeError(f'Arquivo obrigatório não encontrado: {target_path}')
    installed = target_path.read_text(encoding='utf-8')
    if installed == source:
        return installed.encode()
    base = base_file(name)
    if source == base:
        return installed.encode()
    patch_text = ''.join(difflib.unified_diff(
        base.splitlines(keepends=True), source.splitlines(keepends=True),
        fromfile=name, tofile=name,
    ))
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(installed, encoding='utf-8')
        result = subprocess.run(
            ['patch', '--batch', '--fuzz=0', '-p0', '-i', '-'],
            cwd=directory, input=patch_text, text=True, capture_output=True,
        )
        if result.returncode:
            raise RuntimeError(
                f'Conflito ao integrar {name}. Nenhum arquivo foi alterado.\n'
                + (result.stderr or result.stdout)
            )
        return path.read_bytes()


def merge_settings():
    """Adiciona apenas a página Wallpapers sem aplicar o diff integral do Vesta.

    Outras personalizações e páginas do end4 permanecem intactas.
    """
    import re

    path = TARGET / 'settings.qml'
    installed = path.read_text(encoding='utf-8')
    page = 'modules/settings/WallpapersConfig.qml'
    if page in installed:
        print('[OK] Página Wallpapers já registrada em settings.qml')
        return installed.encode('utf-8')

    # Busca um bloco de página conhecido; não depende de números de linha.
    pattern = re.compile(
        r'(?P<indent>^[ \t]*)\{\s*\n'
        r'(?:(?!^[ \t]*\}).*\n)*?'
        r'[ \t]*component:\s*["\']modules/settings/(?:BarConfig|BackgroundConfig)\.qml["\']'
        r'(?:(?!^[ \t]*\}).*\n)*?^[ \t]*\},?',
        re.MULTILINE,
    )
    match = pattern.search(installed)
    if not match:
        raise RuntimeError(
            'Não foi possível localizar o bloco Bar/Background em settings.qml. '
            'Envie o arquivo instalado para integração segura.'
        )
    indent = match.group('indent')
    page_block = (
        f'{indent}{{\n'
        f'{indent}    name: "Wallpapers",\n'
        f'{indent}    icon: "wallpaper",\n'
        f'{indent}    component: "{page}"\n'
        f'{indent}}},\n'
    )
    merged = installed[:match.start()] + page_block + installed[match.start():]
    return merged.encode('utf-8')


def merge_dict(base, source, target, prefix=''):
    result = dict(target)
    for key, new in source.items():
        name = f'{prefix}.{key}' if prefix else key
        old = base.get(key)
        current = target.get(key)
        if isinstance(new, dict) and isinstance(old, dict):
            if current is None:
                current = {}
            if not isinstance(current, dict):
                raise RuntimeError(f'Conflito de tradução: {name}')
            result[key] = merge_dict(old, new, current, name)
        elif key not in base:
            if key in target and current != new:
                raise RuntimeError(f'Conflito de tradução: {name}')
            result[key] = new
        elif new != old:
            if current not in (old, new):
                raise RuntimeError(f'Conflito de tradução: {name}')
            result[key] = new
    return result


def package_command(package):
    """Instala somente pacotes faltantes; mpvpaper pode não existir nos repos."""
    if shutil.which('pacman'):
        if package == 'mpvpaper':
            for helper in ('paru', 'yay'):
                if shutil.which(helper):
                    return [helper, '-S', '--needed', package]
        return ['sudo', 'pacman', '-S', '--needed', package]
    if shutil.which('dnf'):
        return ['sudo', 'dnf', 'install', package]
    if shutil.which('zypper'):
        return ['sudo', 'zypper', 'install', package]
    if shutil.which('apt-get'):
        return ['sudo', 'apt-get', 'install', package]
    raise RuntimeError('Gerenciador de pacotes não reconhecido; instale as dependências manualmente.')


def ensure_dependencies(dry_run, no_packages):
    required = ['ffmpeg', 'ffprobe', 'mpvpaper', 'mpv', 'patch', 'git']
    missing = [name for name in required if not shutil.which(name)]
    if not missing:
        print('[OK] Dependências executáveis encontradas')
        return
    print('[INFO] Dependências ausentes:', ', '.join(missing))
    packages = {'ffmpeg': 'ffmpeg', 'ffprobe': 'ffmpeg', 'mpvpaper': 'mpvpaper',
                'mpv': 'mpv', 'patch': 'patch', 'git': 'git'}
    if no_packages:
        raise RuntimeError('Dependências ausentes; remova --no-packages para instalar automaticamente.')
    for package in dict.fromkeys(packages[name] for name in missing):
        cmd = package_command(package)
        if dry_run:
            print('[DRY-RUN] Instalaria:', ' '.join(cmd))
            continue
        print('[INFO] Instalando:', package)
        try:
            run(cmd)
        except RuntimeError as exc:
            if package == 'mpvpaper':
                raise RuntimeError(
                    'Não foi possível instalar mpvpaper automaticamente. '
                    'Em algumas distribuições ele requer AUR, COPR ou compilação. '
                    'Instale mpvpaper manualmente e execute o instalador novamente.\n' + str(exc)
                ) from exc
            raise
    if not dry_run:
        remaining = [name for name in required if not shutil.which(name)]
        if remaining:
            raise RuntimeError('Dependências ainda ausentes: ' + ', '.join(remaining))


def source_files():
    """Inclui a árvore nova completa, sem caches ou artefatos temporários."""
    directories = [
        'modules/settings/wallpaper',
        'scripts/wallpaper',
        'scripts/keyboard',
    ]
    required = [
        'modules/settings/WallpapersConfig.qml',
        'modules/settings/components/KeyboardLayoutConfig.qml',
    ]
    optional = [
        'modules/settings/wallpaper/views/WallpaperBrowser.qml',
        'modules/settings/wallpaper/views/LiveWallpaperOnlineBrowser.qml',
        'modules/settings/wallpaper/views/LocalWallpaperLibrary.qml',
        'modules/settings/wallpaper/views/LiveWallpaperBrowser.qml',
        'modules/settings/wallpaper/components/WallpaperCard.qml',
        'scripts/wallpaper/local_library.py',
    ]
    for name in required + optional:
        if not (SOURCE / name).is_file():
            raise RuntimeError('Arquivo obrigatório do projeto não encontrado: ' + str(SOURCE / name))
    files = set(required)
    for directory in directories:
        folder = SOURCE / directory
        if not folder.is_dir():
            raise RuntimeError('Diretório obrigatório não encontrado: ' + str(folder))
        for path in folder.rglob('*'):
            if (path.is_file() and not path.is_symlink()
                    and not any(part in ('__pycache__', '.git', '.pytest_cache') for part in path.parts)
                    and path.suffix not in ('.pyc', '.pyo')
                    and not path.name.endswith(('~', '.swp', '.bak'))):
                files.add(str(path.relative_to(SOURCE)))
    return sorted(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true', help='Simula sem alterar arquivos ou instalar pacotes')
    parser.add_argument('--no-packages', action='store_true', help='Não instala pacotes do sistema')
    args = parser.parse_args()
    if not SOURCE.is_dir() or not TARGET.is_dir():
        raise RuntimeError(f'Origem ou destino ausente: {SOURCE} -> {TARGET}')
    if not (TARGET / 'settings.qml').is_file():
        raise RuntimeError('O destino não parece uma instalação end4 compatível (settings.qml ausente).')
    if not (Path.home() / '.config/hypr/hyprland/general.lua').is_file():
        print('[AVISO] ~/.config/hypr/hyprland/general.lua ausente; confira a compatibilidade da integração do teclado.')
    # Preparação completa antes de qualquer alteração no disco.
    changes = {}
    for name in source_files():
        src = SOURCE / name
        dst = TARGET / name
        content = src.read_bytes()
        if dst.is_symlink():
            raise RuntimeError(f'Destino é um link simbólico; intervenção manual necessária: {dst}')
        if dst.exists() and not dst.is_file():
            raise RuntimeError(f'Destino não é um arquivo regular: {dst}')
        if dst.exists() and dst.read_bytes() != content:
            managed = (name.startswith('modules/settings/wallpaper/') or
                       name.startswith('scripts/wallpaper/') or
                       name.startswith('scripts/keyboard/') or
                       name in ('modules/settings/WallpapersConfig.qml',
                                'modules/settings/components/KeyboardLayoutConfig.qml'))
            if not managed:
                raise RuntimeError(f'Conflito com arquivo existente: {dst}')
        changes[dst] = content
    changes[TARGET / 'settings.qml'] = merge_settings()
    changes[TARGET / 'modules/settings/GeneralConfig.qml'] = merge_file('modules/settings/GeneralConfig.qml')
    # Traduz apenas entradas novas/alteradas; preserva personalizações.
    for path in sorted((SOURCE / 'translations').glob('*.json')):
        name = str(path.relative_to(SOURCE))
        dest = TARGET / name
        if not dest.is_file():
            continue
        try:
            base = json.loads(base_file(name))
        except RuntimeError:
            continue
        updated = json.loads(path.read_text(encoding='utf-8'))
        installed = json.loads(dest.read_text(encoding='utf-8'))
        merged = merge_dict(base, updated, installed)
        changes[dest] = (json.dumps(merged, ensure_ascii=False, indent=2) + '\n').encode()
    changes = {p: data for p, data in changes.items() if not p.exists() or p.read_bytes() != data}
    print(f'[INFO] Arquivos a atualizar: {len(changes)}')
    ensure_dependencies(args.dry_run, args.no_packages)
    if args.dry_run:
        for path in changes:
            print('[DRY-RUN]', path)
        return
    if not changes:
        print('[OK] Arquivos já atualizados')
        return
    backup = Path.home() / 'Backups' / ('end4-vesta-wallpapers-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    manifest = []
    for path in changes:
        if not path.is_relative_to(Path.home()):
            raise RuntimeError(f'Destino fora da pasta pessoal: {path}')
        existed = path.exists()
        manifest.append({'path': str(path), 'existed': existed})
        if existed:
            backup_path = backup / path.relative_to(Path.home())
            backup_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup_path)
    backup.mkdir(parents=True, exist_ok=True)
    (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    written = []
    try:
        for path, content in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.vesta-', delete=False) as tmp:
                tmp.write(content)
                temp = Path(tmp.name)
            if path.exists():
                shutil.copymode(path, temp)
            os.replace(temp, path)
            written.append(path)
    except Exception:
        for path in reversed(written):
            original = backup / path.relative_to(Path.home())
            if original.is_file():
                shutil.copy2(original, path)
            else:
                path.unlink(missing_ok=True)
        raise
    print(f'[OK] Instalação concluída. Backup: {backup}')
    print('[INFO] Reinicie o processo Quickshell do end4 para carregar as alterações.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError) as exc:
        print('[ERRO]', exc, file=sys.stderr)
        sys.exit(1)
