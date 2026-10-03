# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/lang/en/).

This changelog covers the **Soplos packaging** of Plasma Login Manager, not the
upstream KDE software itself. Upstream release notes live at
<https://kde.org/announcements/plasma/>.

## [6.7.4-1-soplos] - 2026-10-01

### Fixed
- **The greeter language stayed in English, or a mix of English and the
  system language, on both fresh installs and upgrades.** `plasmalogin`
  writes its own `plasma-localerc` the first time the greeter runs, with a
  hardcoded `en_US` default, before `postinst` ever gets a chance to apply
  the real system locale: a Calamares install ships its squashfs with no
  locale set yet, and an already-installed system already has that
  first-run default on disk by the time `plasma-login-manager` is next
  upgraded. `postinst` wrote `LANGUAGE` only when none was present, which
  protected that wrong default forever instead of an actual choice. It now
  overwrites `LANGUAGE` unconditionally on every install and upgrade of
  this package.

## [6.7.2-1-soplos] - 2026-08-02

### Fixed
- **The greeter now comes up in the system language.** It was English-only, and
  the cause was not a missing translation: the 6.6.5 package already shipped 70
  `.mo` files in 35 languages. The greeter runs as the `plasmalogin` system user
  before any user session exists, and nothing exports `LANGUAGE` for it. A user
  session sets it for itself from its own `plasma-localerc`; an installer writes
  `LANG` and the `LC_*` formats to `/etc/default/locale` but not `LANGUAGE`. The
  daemon copies into the greeter's environment only the locale variables it has
  (`src/daemon/Greeter.cpp`), so the greeter got the formats and no language at
  all, which is why the clock and the date were localised while every label was
  in English.
  `postinst` now derives it from `LANG` and writes it to the greeter's
  `plasma-localerc`, read by `startplasma-login-wayland` at startup
  (`runStartupConfig` in `startplasma.cpp`). Nothing outside the package is
  touched, and it is skipped when a `LANGUAGE` is already set, so a language
  chosen through the System Settings module is never overwritten.

- **CMake could not detect anything while `hardening=+all` was in effect.** Every
  `check_*` in the configure step failed — X11 headers, `__GLIBC__`, `stdatomic`
  — which is what produced the long-standing and entirely wrong theory that the
  development packages were installed with their headers missing from disk. The
  headers were always there. `debian/rules` now builds with
  `hardening=-fortify`. This is a workaround, not a fix: it disables
  `_FORTIFY_SOURCE` for the whole package, which 6.6.5 did ship with. Narrowing
  it to the CMake feature checks alone is still pending.

- **Dependencies the maintainer scripts rely on were never declared.**
  `debian/rules` overrides `dh_installtmpfiles`, `dh_installsysusers` and
  `dh_installsystemd` to empty, because the ordering is handled by hand in the
  maintainer scripts. A side effect is that debhelper stops adding its own
  entries to `${misc:Depends}`, so `postinst` called `systemd-tmpfiles`,
  `systemd-sysusers` and `deb-systemd-helper` with nothing in `Depends`
  guaranteeing they exist. Now declared explicitly. The 6.6.5 package did carry
  the systemd alternative; 6.7.2 had lost it.
- **Upgrading the package logged the user out.** `postinst` restarted
  `plasmalogin.service` whenever it was an upgrade rather than a fresh install,
  and restarting a display manager tears down the graphical session running on
  top of it. Worse than the interruption itself: when the upgrade came in the
  middle of an `apt` run, everything still queued behind it was left half
  configured. The service is no longer touched on upgrade, so the new version
  takes effect on the next boot, which is how every display manager in Debian
  behaves. On a fresh install it is still started, and only if it is not
  already running.
- **Purge left files behind.** `/etc/plasmalogin.conf`, written by `postinst`,
  and `/var/lib/plasmalogin`, created by tmpfiles, survived a purge. Both are
  removed now. The `plasmalogin` system user is deliberately kept, as is usual
  in Debian: removing a system user can orphan files owned by it elsewhere.

### Added
- **European Portuguese translation**, in `po/pt/`, adapted from the Brazilian
  catalogue upstream ships. It is the only one of the eight Soplos languages
  that KDE does not translate. `compiler.sh` copies anything under `po/` into
  the source tree before building; upstream wins if it ever ships `pt`.
- `debian/copyright`, absent until now and required for a Debian package.
- `LICENSE` at the project root, the upstream GPL-2.0 text.
- `README.md` and this changelog.

### Changed
- Build dependencies raised to what 6.7.2 requires, verified against the
  upstream `CMakeLists.txt`: KF6 and ECM from 6.22.0 to **6.26.0**, and the
  Plasma components (PlasmaQuick, LayerShellQt, LibKWorkspace, LibKLookAndFeel,
  KF6Screen) from 6.6.5 to **6.7.0**. Qt stays at 6.10.0.
- Source comes from the official KDE release tarball at `download.kde.org`,
  the KDE-supported way of building a release and the one guaranteed to carry
  the `po/` directory.
- `compiler.sh` takes the version as an argument (`./compiler.sh 6.7.2`),
  so one script serves every release.
- `compiler.sh` uses the `debian/` directory versioned in this project instead
  of looking for a tarball in the user's home directory.
- The build script refuses to run if the version requested does not match
  `debian/changelog`, and if any file of the packaging is missing.
- The build script now counts the `.mo` files in the resulting package. It
  counted `.qm` before, which KDE never produces, so it warned that the greeter
  would be untranslated on every single build.

- Build dependencies completed: `libgl-dev`, `x11proto-dev`, `systemd-dev` and
  `build-essential` added, `libxcb1-dev` dropped. What the binary links against
  is not the same as what CMake needs to configure: the greeter links `libxau6`
  alone out of the whole X11 and OpenGL stack, yet Qt6Gui's CMake config still
  requires the OpenGL headers to be present or it is reported as not found.
  Building without them only worked as long as the machine had leftovers from
  earlier attempts installed.
- `debian/rules` forces the X11 and OpenGL detection that the hardening flags
  broke: an injected `OpenGL::GL` target and explicit `X11_*` cache entries.
  The library paths come from `DEB_HOST_MULTIARCH` rather than being hardcoded
  to amd64, and `dh_auto_clean` removes the generated `debian/inject.cmake`.
  These workarounds should be retested once the hardening issue is narrowed
  down; they are likely to be unnecessary by then.

### Removed
- From `compiler.sh`: the `apt-file` install and its `apt-file update`, which
  downloaded the Contents files of the whole Debian archive and were never used
  anywhere in the script; the block that reinstalled seven development packages
  on every run; the hard verification of X11 and OpenGL headers, which aborted
  the build on a Wayland-only display manager that needs neither; and the
  `apt autoremove` sweep at the end.
- The fallback branch of `compiler.sh` that generated a `debian/` directory from
  scratch when no scaffold tarball was found. It produced, with no error
  whatsoever, a package missing `Conflicts`/`Replaces`, the maintainer scripts,
  the hardening flags and the `dh` overrides: it installed fine but never took
  over the display manager, never created the `plasmalogin` user and never set
  the Soplos wallpaper. Renaming the version was enough to trigger it.

## [6.6.5-soplos] - 2026-06-22

### Added
- Initial Soplos packaging of Plasma Login Manager, the Wayland-native display
  manager KDE is building as a replacement for SDDM. No official Debian package
  exists, so it is built from source for Soplos.
- Debian-style PAM configuration adapted from SDDM: `plasmalogin`,
  `plasmalogin-greeter` and `plasmalogin-autologin`.
- Maintainer scripts creating the `plasmalogin` system user, its runtime
  directories, and taking over `display-manager.service` from SDDM.
- Soplos defaults applied on first install only, so they never overwrite what
  the user later sets through the KCM: Soplos wallpaper for the greeter and
  NumLock enabled.
