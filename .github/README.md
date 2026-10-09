# ✦ Vesta Shell

<div align="center">

**A modern and customizable desktop experience for Linux.**

*Fluid interactions. Thoughtful design. Freedom to customize.*

![Status](https://img.shields.io/badge/Status-Active%20Development-9575CD?style=flat-square)
![Linux](https://img.shields.io/badge/Platform-Linux-555555?style=flat-square)
![Wayland](https://img.shields.io/badge/Display-Wayland-555555?style=flat-square)
![Quickshell](https://img.shields.io/badge/Framework-Quickshell-9575CD?style=flat-square)
![Hyprland](https://img.shields.io/badge/Compositor-Hyprland-555555?style=flat-square)

</div>

---

## Overview

**Vesta Shell** is a customizable desktop shell built with Quickshell, Qt Quick, and QML for Linux systems using Wayland and Hyprland.

Vesta aims to combine a cohesive visual language, smooth animations, translucent surfaces, and practical desktop functionality into a unified experience.

The project is currently under active development, with a focus on improving system configuration, visual consistency, and customization.

## Design philosophy

Vesta Shell is guided by five principles:

- **Consistency:** A unified design language across panels, controls, and settings.
- **Fluidity:** Responsive interactions and meaningful animations.
- **Depth:** Transparency, blur, and layered surfaces used with restraint.
- **Customization:** Flexible controls that adapt to different workflows.
- **Usability:** Powerful features without unnecessary visual complexity.

## Features

### Desktop experience

Vesta Shell provides a Quickshell-based desktop environment with graphical configuration interfaces and Hyprland integration.

The project is being developed incrementally, with individual components and services evolving toward a more modular and maintainable architecture.

### Display configuration

The display configuration module is one of Vesta Shell's implemented features.

It provides:

- Connected monitor detection.
- Resolution and refresh rate selection.
- Display scaling controls.
- Interactive monitor arrangement.
- Drag-and-drop positioning.
- Automatic snapping and alignment guides.
- Physical monitor identification.
- Persistent display layouts.
- Confirmation and automatic rollback of display changes.

#### Interactive monitor arrangement

Monitor previews can be repositioned visually. The arrangement system includes snapping and alignment assistance to simplify multi-monitor layouts.

#### Safe configuration changes

Potentially disruptive display changes use a confirmation workflow.

If a configuration is not confirmed within **15 seconds**, the previous configuration is restored automatically.

#### Persistent configuration

Confirmed display configurations can be stored in:

`~/.config/hypr/monitors.lua`

Persistence requires a compatible Hyprland Lua configuration that loads this module.

### Settings

Vesta Shell includes a graphical settings interface intended to bring desktop configuration into one place.

The settings experience emphasizes clear navigation, consistent controls, and immediate feedback.

## Technology

| Technology | Role |
|---|---|
| Quickshell | Desktop shell framework |
| Qt Quick / QML | Interface and animations |
| Hyprland | Wayland compositor |
| Python 3 | Supporting services and display transactions |
| Lua | Hyprland configuration integration |
| JSON | Localization resources |

## Project structure

The display configuration module is organized as follows:

```text
dots/.config/quickshell/ii/
├── modules/
│   └── settings/
│       ├── DisplaysConfig.qml
│       └── components/
│           ├── MonitorArrangement.qml
│           └── MonitorIdentifier.qml
├── scripts/
│   └── displays/
│       ├── display_transaction.py
│       └── display_persistent.py
├── services/
│   └── DisplayManager.qml
├── translations/
│   └── pt_BR.json
└── settings.qml

instalar-monitores.py
```

This is a simplified view of the display module, not the complete repository structure.

## Getting started

### Requirements

The development environment uses:

- Linux with Wayland.
- Hyprland with compatible Lua configuration support.
- Quickshell.
- Python 3.
- Qt Quick / QML dependencies required by the shell.

Additional dependencies may be necessary for other modules.

### Clone

```bash
git clone https://github.com/Code800x/vesta-shell.git
cd vesta-shell
```

### Preview the settings interface

From the repository root:

```bash
qs -p "$PWD/dots/.config/quickshell/ii/settings.qml"
```

This launches the settings interface for development and testing. It is not a complete system installation procedure.

## Installing the display module into an existing desktop configuration

Vesta Shell includes an integration installer for adding its monitor configuration functionality to a compatible existing Quickshell desktop configuration.

The installer is located at:

`instalar-monitores.py`

### Installation

First, clone the repository:

```bash
git clone https://github.com/Code800x/vesta-shell.git
cd vesta-shell
```

Then execute:

```bash
python3 instalar-monitores.py
```

The installer is designed around the following paths:

- Source: `~/Projetos/vesta-shell/dots/.config/quickshell/ii`
- Target: `~/.config/quickshell/ii`
- Hyprland configuration: `~/.config/hypr`

**Important:** Because the installer expects the source repository under `~/Projetos/vesta-shell`, clone or place the repository there before running it.

For example:

```bash
mkdir -p ~/Projetos
git clone https://github.com/Code800x/vesta-shell.git ~/Projetos/vesta-shell
python3 ~/Projetos/vesta-shell/instalar-monitores.py
```

### What the installer does

The installer is intended to:

1. Validate the expected source and destination directories.
2. Check compatibility with the existing settings interface.
3. Copy the display configuration components and supporting scripts.
4. Integrate the display settings page.
5. Merge Brazilian Portuguese translation entries.
6. Prepare compatible Hyprland Lua monitor persistence.
7. Back up files before modifying them.

The installer does **not** automatically restart Hyprland.

### Before installing

Back up your existing configuration and review the installer source.

The integration currently targets a specific configuration layout. Compatibility with arbitrary Quickshell setups is not guaranteed.

If the target settings interface differs significantly from the expected version, installation may stop rather than overwrite it.

### After installing

Restart the relevant Quickshell process to load the updated settings interface.

Before reloading Hyprland, check that existing monitor rules do not conflict with the generated Lua configuration.

## Development roadmap

- [x] Monitor detection.
- [x] Resolution and refresh rate configuration.
- [x] Display scaling.
- [x] Interactive monitor arrangement.
- [x] Monitor identification.
- [x] Alignment guides and snapping.
- [x] Display change confirmation and rollback.
- [x] Persistent monitor configuration.
- [x] Display module integration installer.
- [ ] Keyboard layout configuration.
- [ ] Extended system settings.
- [ ] More flexible appearance customization.
- [ ] Improved portability between configurations.
- [ ] Comprehensive installation workflow.
- [ ] Expanded documentation and testing.

## Development status

Vesta Shell is an experimental project under active development.

Some components may require environment-specific configuration. Features and internal APIs may change as the project evolves.

## Contributing

Suggestions, bug reports, and contributions are welcome.

Please consider the existing architecture and visual language when proposing changes.

## License and attribution

Vesta Shell includes material derived from existing open-source work.

Applicable copyright notices, license terms, and attribution requirements remain in effect for inherited code.

Consult the repository's license files and source headers before redistributing or modifying components.

---

<div align="center">

**✦ Vesta Shell**

*Elegance in motion. Freedom by design.*

[Repository](https://github.com/Code800x/vesta-shell)

</div>
