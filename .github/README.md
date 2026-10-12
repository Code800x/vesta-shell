# Instalador Vesta — Wallpapers + teclado

Coloque `instalar-wallpapers.py` na **raiz** do repositório `~/Projetos/vesta-shell`, ao lado da pasta `dots/`.

## Prévia segura

```fish
cd ~/Projetos/vesta-shell
python3 instalar-wallpapers.py --dry-run
```

## Instalar no end4 existente (somente se desejar)

```fish
python3 instalar-wallpapers.py
```

O script mantém o destino original `~/.config/quickshell/ii`, **não** altera o checkout `~/Projetos/vesta-shell` nem executa automaticamente a instalação. Cria backup em `~/Backups/end4-vesta-wallpapers-*` antes de sobrescrever arquivos.

## O que é incluído

- `modules/settings/WallpapersConfig.qml`
- Toda a árvore `modules/settings/wallpaper/` (views, components, controllers, utils)
- Toda a árvore `scripts/wallpaper/` (biblioteca local, live wallpapers, provedores, downloader, cache)
- `modules/settings/components/KeyboardLayoutConfig.qml` e `scripts/keyboard/`
- Integração não destrutiva de `settings.qml`, `GeneralConfig.qml` e traduções
- Verificação de `ffmpeg`, `ffprobe`, `mpvpaper`, `mpv`, `patch` e `git`

## Observações

- O pacote `mpvpaper` pode não existir nos repositórios oficiais de algumas distribuições; o instalador interrompe com orientação se a instalação falhar. Em Arch pode usar `paru` ou `yay` se disponíveis.
- `--no-packages` não instala dependências e falha se alguma estiver ausente.
- `--dry-run` não instala pacotes nem modifica arquivos.
- A instalação real depende de um checkout completo da Vesta, do end4 existente e do commit ancestral configurado no script. Testado apenas quanto à sintaxe Python neste ambiente; não foi executado contra seu end4.
