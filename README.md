<p align="center"><img src="docs/branding/icon-512.png" alt="Dena.emu GB logo" width="128"></p>

# Dena.emu GB

An emulator for Android that plays Game Boy, Game Boy Color, Game Boy Advance
and DS games with the look of a pocket handheld: a dot matrix LCD filter on
every game (per-console styles, intensity and LCD palettes), covers in LCD
shades, and a UI that is fully usable by touch or by gamepad. Free, with no
ads and no paid features. GPL-3.0-or-later.

No ROMs or BIOS files are included or downloaded. Bring your own games.

## Download

Get the APK from [Releases](../../releases). It installs as **DenaGB**
(package `app.dena.emu.gb`).

## Features

- Game library with box art, search, favourites and recently played
- Import with the built-in file browser, the system picker or a share
- Auto-save and resume, save states with thumbnails, rewind, fast-forward
- Cheats, screenshots, home-screen shortcuts (`denagb://play/<sha1>`)
- Gamepads and keyboards, touch skins and `.deltaskin` skins
- RetroAchievements, link cable over Wi-Fi for GB/GBC/GBA

## Cores

| System | Core | License |
| --- | --- | --- |
| GB / GBC / GBA | mGBA | MPL-2.0 |
| Nintendo DS | melonDS | GPL-3.0 |

## Layout

| Path | What |
| --- | --- |
| `app/` | Flutter app (UI, library database, FFI bindings) |
| `host/` | C/C++ libretro frontend, shaders and headless test harness |
| `cores/` | libretro core build scripts |
| `shells/` | platform shells (Android is the one this app ships) |
| `tools/` | icons, skins, rig and license scripts |
| `docs/` | specs, provenance and licenses |

Specs are in [docs/specs](docs/specs); what this fork changes from Dena.emu is
in [docs/dev/gb-fork.md](docs/dev/gb-fork.md).

## Build and test

```bash
cmake -S host -B host/build && cmake --build host/build && ctest --test-dir host/build
cd app && flutter test
python tools/licenses/check_licenses.py
```
