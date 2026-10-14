# Scrolling Layout — atalhos da Vesta Shell

Os atalhos abaixo são adicionados em `dots/.config/hypr/hyprland/keybinds.lua` e aparecem automaticamente em **Super + /**, categoria **Scrolling Layout**, porque a lista usa `hyprctl binds -j` e as descrições de `hl.bind`.

| Atalho | Ação |
|---|---|
| Super + Ctrl + H | Focar coluna à esquerda |
| Super + Ctrl + L | Focar coluna à direita |
| Super + Ctrl + Shift + H | Trocar coluna com a esquerda |
| Super + Ctrl + Shift + L | Trocar coluna com a direita |
| Super + Alt + [ | Diminuir largura da coluna |
| Super + Alt + ] | Aumentar largura da coluna |
| Super + Ctrl + [ | Incorporar janela à coluna anterior |
| Super + Ctrl + ] | Expulsar janela para nova coluna |

Atenção: `Super + L` (bloquear), `Super + Shift + L` (suspender) e `Super + /` (ajuda) permanecem intactos.

## Instalação no repositório local

Copie o arquivo `dots/.config/hypr/hyprland/keybinds.lua` desta versão para o mesmo caminho do seu repositório e execute `hyprctl reload` (ou reinicie a sessão). O cheatsheet consulta os atalhos ativos do Hyprland; não precisa cadastrar entradas manualmente no QML.

Verifique os atalhos efetivos em `hyprctl binds -j` e confira `~/.config/hypr/custom/keybinds.lua`, pois atalhos personalizados podem ter sido criados fora do repositório. A verificação estática foi feita contra os atalhos do projeto empacotado, não contra a instalação em execução.
