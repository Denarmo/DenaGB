# Provenance

Where each concept in Dena.emu came from (CLAUDE.md §7, clean-room rules).
Allowed sources: public documentation, file-format descriptions, observed
behaviour, and permissively licensed code recorded in `docs/licenses.md`.
Never: Delta/DeltaCore, MinUI, SpruceOS, DuckStation, official PICO-8 source.

| Area | Concept | Source |
| --- | --- | --- |
| Host | libretro frontend callbacks and environment commands | `libretro.h` API header (MIT) and its comments |
| Host | Frame/audio hashing with FNV-1a 64 | Public FNV specification (Fowler/Noll/Vo) |
| Host | `.dreplay` input replay format | Our own design, docs/specs/test-harness.md |
| Host | `dena_testcore` | Our own code |
| Rig | Android input/capture via `adb shell input`, `screencap` | Android developer documentation |
| Rig | Photodiode latency probe protocol | Our own design, docs/specs/rig.md |
| App | Material 3 theming with `dynamic_color` | Package documentation (Apache-2.0) |
| Test ROM | GBA header layout, mode 3 video, KEYINPUT, PSG channel 2 registers | Public GBA hardware documentation (GBATEK) |
| Test ROM | ARM instruction encodings | ARM Architecture Reference Manual |
| Test ROM | NES iNES header, PPU/controller registers, 6502 opcodes | Public NES hardware documentation (NESdev wiki) |
| Test ROM | SNES LoROM header, PPU/CPU registers, 65816 opcodes | Public SNES hardware documentation (fullsnes, SNESdev wiki) |
| Host | PNG writer (stored deflate, CRC-32, Adler-32) | PNG specification (W3C) and RFC 1950/1951 |
| App | Cheat code shapes per system | Public cheat-device descriptions; codes are passed to the cores unparsed |
| App | `.deltaskin` file format (info.json keys, input names) | Public Delta skin documentation and community skin guides (format description only, no code) |
| App | Built-in touch skins | Our own design (Material shapes) |
| Host/App | Rewind ring buffer (XOR delta + run-length) | Our own design, docs/specs/rewind.md |
| Host/App | DS touch screen as libretro pointer, stacked-screen layout | libretro.h pointer API; observed melonDS libretro output |
| App | PlayStation skin (△ ○ ✕ □, L1/L2/R1/R2), GameShark code shape | Public controller and cheat-device descriptions |
| App | Cheat database (`.cht` key/value format, file naming, popularity heuristic) | libretro-database `cht/` files (CC-BY-SA-4.0) as data; our own matching and ranking, docs/specs/cheats.md |
| App | Box-art lookup (CRC to No-Intro name, thumbnail URL scheme) | libretro-database DATs (CC-BY-SA-4.0) and the public thumbnail server layout |
| Host/App | Analog sticks (libretro analog input, touch thumbstick, gamepad pass-through) | libretro.h analog API; our own design, docs/specs/n64.md |
| App | N64 skin and `.deltaskin` N64 input names, GameShark code shape | Public controller descriptions and the public `.deltaskin` format description |
| App | PSP skin (analog nub, △ ○ ✕ □), CWCheat code shape | Public controller and cheat-format descriptions |
| Android/App | `dena://play/<sha1>` links, pinned and recent-game shortcuts | Android ShortcutManager documentation; our own design, docs/specs/shortcuts.md |
| Android/App | Game picture on an external display (Presentation, surface routing, aspect fit) | Android Presentation and DisplayManager documentation; our own design, docs/specs/external-display.md |
| App | Tabletop-posture skin layout, control size cap | Flutter DisplayFeature / Android Jetpack WindowManager documentation; our own design, docs/specs/adaptive.md |
| Core | PICO-8 oval/ovalfill replacement for fake-08 | Our own, from the ellipse definition (no reference code) |
| Host | PICO-8 test cart `host/tests/roms/pico8/test.p8` | Our own, written against the public `.p8` text format description |
| App | Carts tab, PICO-8 skin (O / X / Pause), no-state mode | Our own design, docs/specs/pico8.md |
| Linux | Device profiles (`shells/linux/profiles`), key mapping, sysfs parsing, dena-keytest | Linux input-event-codes.h and kernel gamepad documentation, public device spec sheets; our own design, docs/specs/platform-modules.md |
| OS | SD-card layout, builder, boot hook and update-by-file scripts | CLAUDE.md §4 layout; our own design, docs/specs/sd-card.md (no MinUI/SpruceOS material) |
| OS | Single-card H700 image: layout, initramfs, init scripts, first-boot partitioning, build and assembly scripts | Our own design and code, docs/specs/single-card.md; boot ROM offset and eGON header from the public linux-sunxi wiki; ROCKNIX's public H700 build only as a reference for working versions and patches (none of its scripts used); nothing from the stock firmware |
| OS | H700 kernel patches (`os/image/linux/patches`), U-Boot LPDDR3 values and DRAM fix | Unchanged GPL-2.0 patches by their upstream authors, as collected in ROCKNIX's public H700 tree; see single-card.md, Provenance |
| OS | Panel init sequences (`os/image/linux/panels/*.json`) | Hardware register data decoded from ROCKNIX's panel firmware files; binary format from the kernel's `panel-mipi.c` |
| Linux | Embedder design (KMS/DRM + GBM + EGL, external texture, evdev keys) | Flutter's public embedder API docs (`flutter_embedder.h`), Linux DRM/KMS and evdev kernel docs, flutter-pi public README as a concept only (also for the AOT build: frontend server product kernel, then gen_snapshot `app-aot-elf`); docs/specs/embedder.md |
| App | Bundled console-style skins (`tools/skins/build_skins.py`): palettes, button layouts and shapes | Our own artwork from plain shapes, informed by public photos and descriptions of each console's controller; no logos, trademarks, brand names or traced art |
| Host/App | Shader presets (.glslp keys, pass uniforms, `#pragma parameter`) and the multi-pass chain | libretro GLSL shader documentation; Cannelloni's `ShaderPipeline.kt`/`PresetParser.kt` (GPL-3.0/MIT, the user's own repo) as reference |
| Host | Bundled shaders | libretro `glsl-shaders` (public domain / GPL), see host/shaders/README.md; `scanlines` is our own |
| Linux | `dena-launcher` (DRM/GBM/EGL display, page flips, vsync, task runner, evdev keys) | Flutter's public `embedder.h` API docs, libdrm/gbm/EGL headers and kernel DRM docs; our own code, docs/specs/embedder.md |
| App | PICO-8 BBS cart browser: listing URLs, listing row fields, cart file and thread URL scheme | Observed public behaviour of the Lexaloffle BBS web pages (URLs and the page's listing data); no Lexaloffle or PICO-8 source; our own design, docs/specs/pico8-cart-browser.md. Test fixture is invented data |
| App/Core | Dena Explore launcher cart (`app/assets/carts/dena-explore.p8`), its GPIO host API and the fake-08 system-RAM fixup | Our own cart, protocol and code, docs/specs/pico8-launcher-cart.md. The general shape (tabs across the top, a cart list, one button to run and one for options) comes from public descriptions and videos of PICO-8's built-in cart browser; its cart was not shipped, fetched, read or reproduced. GPIO at 0x5f80 from the public PICO-8 memory-map documentation |
| Policy | PICO-8 BBS browsing needs no Lexaloffle permission (CLAUDE.md §4, 2026-10-17) | Public pages only: per-cart licenses shown on BBS cart pages (e.g. "License: CC4-BY-NC-SA", https://www.lexaloffle.com/bbs/?pid=176116); zep's comments on third-party players in the pemsa thread (https://lexaloffle.com/bbs/?tid=47376): welcome as a way to reach platforms, concern only with products posing as official PICO-8 or repackaging carts |
| Host/Core | Link cable over Wi-Fi (`host/src/link.c`, `cores/mgba/dena_link.inc`, link test ROMs) | Our own code and protocol, docs/specs/link-cable.md. Hardware behaviour from public GB/GBA serial-port documentation (Pan Docs, GBATEK); SIO driver hooks from mGBA's own public headers (MPL-2.0). The 4-byte GB header magic in the test ROMs is the value mGBA checks and writes itself |
| Host/App | RetroAchievements: rc_client integration, HTTP hand-off to the app, memory map capture, hardcore rules, event JSON | rcheevos' public headers and its rc_client integration guide (https://github.com/RetroAchievements/rcheevos/wiki/rc_client-integration); RetroAchievements' public hardcore rules; our own design and code, docs/specs/achievements.md |
| App | Launch animation: box opening, cartridge/disc/UMD drawings, label frames (`app/lib/src/library/{launch_animation,game_media}.dart`) | Our own artwork from plain shapes; cartridge proportions from the published outside dimensions of each retail cart; no logos, trademarks or traced art; docs/specs/launch-animation.md |
| App | ScreenScraper media lookup (`media_art.dart`): `jeuInfos.php` parameters, system ids, media types `support-texture` / `support-2D`, region codes | ScreenScraper's public API v2 documentation; our own code. Images are fetched per game on the player's device and never bundled |
