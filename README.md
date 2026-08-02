# Plasma Login Manager for Soplos Linux

[![License: GPL-2.0+](https://img.shields.io/badge/License-GPL--2.0%2B-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0)
[![Version](https://img.shields.io/badge/version-6.7.2--soplos-green.svg)]()

Soplos Linux packaging of KDE Plasma Login Manager, the display manager used by Soplos Linux Tyson.

*Empaquetado para Soplos Linux del Plasma Login Manager de KDE, el gestor de sesión que usa Soplos Linux Tyson.*

## Description

Plasma Login Manager is the display manager KDE is building as a Wayland-native replacement for SDDM, with a new greeter, wallpaper plugin integration and a System Settings module.

There is no official package for Debian or Debian-based distributions, so this repository holds everything needed to build it for Soplos: the Debian packaging tree and a build script that produces the `.deb`.

## What this packaging adds

- **PAM configuration** in Debian style, adapted from SDDM: `plasmalogin`, `plasmalogin-greeter` and `plasmalogin-autologin`.
- **System user** `plasmalogin` and its runtime directories, created through `systemd-sysusers` and `systemd-tmpfiles`.
- **Display manager takeover**: the package replaces SDDM and points `display-manager.service` at `plasmalogin`.
- **Soplos defaults**, applied only on first install so they never overwrite settings the user changed later through the System Settings module: the Soplos wallpaper for the greeter, and NumLock enabled.

## Requirements

To build:

- Soplos Linux on a Debian forky base. Any of the three works, including Tyron: the build dependencies come from Debian, not from the desktop in use.
- Internet access, to download the upstream source and the build dependencies.
- KF6 and ECM 6.26.0 or newer, and the Plasma development packages 6.7.0 or newer.

To install and run:

- Soplos Linux Tyson, or any system running KDE Plasma 6.7.

## Build

```bash
# Build the default version
./compiler.sh

# Or build a specific release
./compiler.sh 6.7.2
```

The script downloads the official KDE release tarball, imports the `debian/` directory of this project, installs the build dependencies, builds the package and removes everything it installed. The resulting `.deb` is left next to the script.

Before building a different version, update `debian/changelog` first: the script refuses to run if the version requested does not match what the changelog declares.

## Do not install it on a non-Plasma system

The `postinst` takes over `display-manager.service` and starts `plasmalogin`. Installing this package on Tyron or on any system that does not run Plasma leaves it without a graphical login. Build wherever you like, test only on Tyson.

## Source: the release tarball

The source comes from the official release tarball at <https://download.kde.org/stable/plasma/>. That is the KDE-supported way of building a release, and it is the one guaranteed to carry the `po/` directory, which is what CMake turns into the installed translations.

## Why the greeter used to come up in English

The greeter runs as the `plasmalogin` system user, before any user session exists. A normal Plasma session exports `LANGUAGE` for itself, reading it from the user's own `plasma-localerc`; the greeter has no session to do that for it, and `LANGUAGE` is not part of what an installer writes to `/etc/default/locale`. The daemon copies the locale variables it has into the greeter's environment (`src/daemon/Greeter.cpp`), so the greeter received the `LC_*` formats and no language at all: dates in the system language, every label in English, with the translations sitting installed and unused.

The packaging now derives it from `LANG` at install time and writes it to the greeter's own `plasma-localerc`, which `startplasma-login-wayland` reads at startup. Nothing outside the package is touched, and a language later chosen through the System Settings module is never overwritten.

## Supported languages

Upstream ships 39 languages, which CMake compiles and installs on its own through `ki18n_install(po)`. Seven of the eight languages Soplos supports come from upstream: English (the source language), Spanish, French, German, Italian, Russian and Romanian.

The eighth, European Portuguese, does not exist upstream — only Brazilian Portuguese (`pt_BR`) does — so this repository carries it in [po/pt/](po/pt/), adapted from the Brazilian catalogue. `compiler.sh` copies anything under `po/` into the source tree before building, and `ki18n_install(po)` compiles it like any other language, with no change to the upstream `CMakeLists.txt`.

Upstream always wins: if the KDE Portuguese team ever ships `pt`, the build keeps theirs and skips the Soplos copy, so the directory can simply be deleted at that point. Sending this translation upstream is the right long-term move, and it is not done yet.

## License

Upstream is licensed under GPL-2.0+, and so is the packaging in this repository. See [LICENSE](LICENSE) and [debian/copyright](debian/copyright).

## Links

- [Upstream project](https://invent.kde.org/plasma/plasma-login-manager)
- [KDE release tarballs](https://download.kde.org/stable/plasma/)
- [Soplos Linux](https://soplos.org)

## New in version 6.7.2-soplos (August 2, 2026)

- **Fixed**: the greeter comes up in the system language. It was English-only because nothing sets `LANGUAGE` for the user the greeter runs as, not because the translations were missing.
- **Changed**: build dependencies raised to KF6/ECM 6.26.0 and Plasma 6.7.0, as required by 6.7.2.
- **Changed**: `compiler.sh` takes the version as an argument and uses the `debian/` directory of this project.
- **Removed**: `libgl-dev` and `plasma-workspace` from the build dependencies. Neither is required by upstream, and `plasma-workspace` pulled the whole desktop onto the build machine.
- **Removed**: the fallback that silently generated a degraded `debian/` directory when the scaffold tarball was missing.

## New in version 6.6.5-soplos (June 22, 2026)

- Initial Soplos packaging, with Debian-style PAM configuration, systemd integration and Soplos defaults for the greeter.
