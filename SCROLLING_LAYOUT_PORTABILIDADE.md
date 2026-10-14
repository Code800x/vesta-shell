# Vesta Shell — Scrolling Layout e atalhos

## Organização definitiva

- `dots/.config/quickshell/ii/`: interface, configurações e script de ativação/persistência do layout.
- `dots/.config/hypr/hyprland/keybinds.lua`: oito atalhos nativos do Hyprland e descrições para o painel `Super + /`.
- `dots/.config/hypr/hyprland.lua`: arquivo principal que carrega os módulos da configuração do Hyprland.

Não há instalador de atalhos dentro de `ii` nem carregador gerado automaticamente. Copiar **somente** `ii` não instala os atalhos. Para uma máquina nova, instale **ambos** `hypr/` e `quickshell/ii/` da pasta `dots/.config/`, preservando arquivos pessoais que já existirem no destino.

## Atualização de uma máquina já configurada

Copie o arquivo `dots/.config/hypr/hyprland/keybinds.lua` para `~/.config/hypr/hyprland/keybinds.lua` (faça backup antes), além de atualizar `ii`. Execute `hyprctl reload` e confira com:

```sh
hyprctl binds -j | jq -r '.[] | select((.description // "") | contains("Scrolling Layout")) | .description'
```

## Atenção: instalação anterior com atalhos manuais

Se você já acrescentou a seção `--##! Scrolling Layout` a `~/.config/hypr/custom/keybinds.lua`, remova **somente aquela seção**, após confirmar que a configuração principal carrega os atalhos novos, para evitar duplicações. Preserve os demais atalhos personalizados.

Se chegou a usar a versão experimental que escrevia `VESTA_SCROLLING_SHORTCUTS_BEGIN`/`END` em `~/.config/hypr/hyprland.lua`, remova **somente esse bloco experimental** depois de fazer backup. Não remova o bloco `VESTA_SCROLLING_LAYOUT_BEGIN`/`END`, que guarda a preferência persistente de layout.

## Atalhos

| Teclas | Ação |
| --- | --- |
| Super + Ctrl + H / L | Focar coluna à esquerda / direita |
| Super + Ctrl + Shift + H / L | Trocar coluna à esquerda / direita |
| Super + Alt + [ / ] | Diminuir / aumentar largura da coluna |
| Super + Ctrl + [ / ] | Incorporar / separar janela da coluna |

Os atalhos são registrados no Hyprland e suas descrições aparecem no painel de atalhos da configuração que suporta o `Super + /`.
