# Dena.emu — Project Brief for Claude

> **This repository is Dena.emu GB**, a fork of Dena.emu that plays only GB, GBC, GBA and DS
> games with the Pocket LCD look and a dot matrix LCD filter on every game. No PICO-8, apps,
> web file manager, RomM or cloud sync. See [docs/dev/gb-fork.md](docs/dev/gb-fork.md)
> for what was removed and how to merge upstream fixes. The brief below is upstream's.

Dena.emu is a multi-system emulator with the functionality of Delta (iOS), built as one
Flutter app with a Material You (Material 3) UI. It ships on **Android first**, then as an
**SD-card OS layer for Linux handhelds** (Anbernic / TrimUI / Miyoo class), then **iOS**.

Claude writes all code, tests, build scripts and docs. Humans own hardware, accounts,
signing, legal decisions and design sign-off. This file is the working summary and the rules.

---

## 1. Goals

1. Reproduce Delta's feature set on Android, Linux handhelds and iOS from one codebase.
2. Add PSX, PSP and PICO-8 (with a cart browser) beyond Delta's systems.
3. Material You look and feel everywhere, usable equally by **touch** and by **gamepad / D-pad**.
4. Input-to-photon latency **under 50 ms**, stable 60 fps, no audio crackle on target devices.
5. Free, with full emulation.
6. Fully legal: GPL-3.0 open source, no bundled ROMs/BIOS, clean-room implementation.

## 2. Platforms and devices

| Target | Shell | Rendering | Audio | Input |
| --- | --- | --- | --- | --- |
| Android (first) | Kotlin Activity | GLES/Vulkan into `SurfaceView` PlatformView (or `Texture`), Swappy pacing | Oboe (AAudio) | `InputDevice`/`MotionEvent`, read before Flutter |
| Linux handheld | Own Flutter embedder (flutter-pi style) on KMS/DRM or fbdev | Emulator frame composited directly as GLES texture | ALSA | evdev / libinput |
| iOS (last) | Swift app | Metal view embedded in Flutter | AVAudioEngine | GameController framework |
| Windows / Linux PC, Steam Deck | Stock Flutter runner + `dena_host` library ([desktop-shell](docs/specs/desktop-shell.md)) | Desktop GL; D3D11 shared texture (Windows), pixel-buffer texture (Linux) | SDL3 | SDL3 gamepads, keyboard |

Handheld support: Allwinner H700 (RG35XX/RG40XX), Allwinner A133P (TrimUI Smart Pro/Brick),
RK3566 (RG353, Miyoo Flip). Miyoo A30 marginal. **Miyoo Mini/Mini Plus unsupported** (no GPU, 32-bit; skipped for now, user 2026-10-17).

## 3. Architecture

```
Flutter UI (Dart, shared)  ── dart:ffi (hot path) / Pigeon (lifecycle) ──┐
                                                                          ▼
Shared C/C++ emulator host (libretro frontend): emu thread, audio, input,
save states, rewind, cheats, shaders                                      │
                                                                          ▼
libretro cores (.so / static)        Platform shell: Android | Linux | iOS
```

- Flutter owns everything except the emulation loop, audio and the game framebuffer.
- Input, save/load and frame callbacks go through `dart:ffi`. **Never** method channels on the hot path.
- Storage: Drift (SQLite) for library/metadata; app-private storage on Android/iOS; fixed SD-card layout on handhelds.
- Artwork: bundled OpenVGDB database; images fetched on demand, never bundled.

### Cores (all must permit commercial use)

| System | Core | License |
| --- | --- | --- |
| NES | FCEUmm or Mesen | GPL |
| SNES | bsnes (performance profile for 1 GB handhelds) | GPL-3.0 |
| GB / GBC / GBA | mGBA | MPL-2.0 |
| N64 | Mupen64Plus-Next | GPL-2.0 |
| Nintendo DS | melonDS | GPL-3.0 |
| Genesis | **Skipped for now** (user, 2026-10-16); no commercial-safe ARM core chosen | — |
| PSX | PCSX ReARMed (ARM, handhelds); Beetle PSX HW (strong phones, Windows/SteamOS) | GPL-2.0 |
| PSP | PPSSPP | GPL-2.0+ |
| Dreamcast (desktop) | Flycast | GPL-2.0+ (built with GPL-3.0 xBRZ) |
| Saturn (desktop) | Beetle Saturn | GPL-2.0+ |
| PICO-8 | Our own clean-room compatible runtime (or a permissive one after license check) | GPL-3.0 |

**Banned:** Snes9x, Genesis Plus GX, PicoDrive (non-commercial), DuckStation (non-commercial,
no derivatives), Delta/DeltaCore source (AGPL; clean-room only), official PICO-8 binaries.
iOS has no JIT: N64, DS, PSX and PSP must run in interpreter modes there.

## 4. Feature list

**Library**
- Box-art grid (OpenVGDB lookup, custom art), search, filter chips per system
- Import via SAF / share sheet / Quick Share / SD-card folder; `.zip`, `.chd`, `.m3u`, `.iso`, `.cso`, `.p8.png`
- Long-press preview sheet; rename, share, delete; recently played / resume

**Playback**
- Auto-save on exit/pause/sleep, resume last session
- Save states with thumbnails, quick save/load, battery saves
- Rewind (ring buffer of compressed states), fast-forward (selectable speeds)
- Cheats: Game Genie, Action Replay, GameShark, raw codes; toggled in game
- Screenshots; external display via `Presentation` API (HDMI/USB-C); Google Cast for watching only
- Link cable over Wi-Fi for GB/GBC/GBA between two devices: host, nearby list, join by address ([spec](docs/specs/link-cable.md))
- Shaders (CRT, LCD and dot matrix looks)
- RetroAchievements (rcheevos): sign-in in Settings, unlock toasts, hardcore mode, per-game achievement list ([spec](docs/specs/achievements.md))

**Controllers and input** — touch and gamepads, everywhere
- `.deltaskin` support (parse `info.json`, rasterize PDF art, per orientation/device, DS dual screen); skin import; bundled console-style skins per system (own art, no logos; `tools/skins`)
- Gamepads: Xbox, DualShock/DualSense, Switch Pro, 8BitDo, generic HID; keyboard
- **Last input wins**: tap hides the focus ring; a button press shows it and hides the skin
- Up to 4 players, slot assignment in pause menu; per-game and per-controller remapping; matching button glyphs
- DS/PSP: touch → bottom screen; with a gamepad the right stick drives a pointer
- Gamepad disconnect mid-game → pause and restore the skin; haptics and rumble

**PICO-8**
- Cart browser (Featured / New / Search / by author) from the Lexaloffle BBS, one-tap download
- PICO-8 boots into **Dena Explore**, our own clean-room launcher cart (library carts, favourites, launch, BBS lists and downloads) talking to the app through the GPIO mailbox ([spec](docs/specs/pico8-launcher-cart.md)). Never ship, fetch or read Lexaloffle's own browser cart (splore.p8)
- No Lexaloffle permission is needed for a third-party player or browser (checked 2026-10-17, see docs/provenance.md); the browser is on. Rules:
  - Never rehost or bundle BBS carts; fetch from the BBS only on the user's request.
  - Show author, license and BBS link for every cart; respect each cart's license (most are CC4-BY-NC-SA: the browser and downloads are free for everyone).
  - Never present Dena.emu or the launcher as official PICO-8 or use Lexaloffle branding.
  - Be polite to the BBS: cache, low request rate, no background scraping.

**RomM (free)**
- Connect a self-hosted RomM server to download games and sync saves and states; free for everyone ([spec](docs/specs/romm.md))

**Backup**
- Local backup/export (zip)

**Apple features replaced with Google equivalents (all platforms)**
- Spotlight → App Search
- Siri → Gemini/Assistant App Actions
- AirPlay → `Presentation` API + Cast
- AirDrop → Quick Share

**Platform**
- Home-screen shortcuts, deep links, foldable/tablet adaptive layouts

**Linux handheld OS layer** (modelled on MinUI/SpruceOS concepts — **never copy or fork their code**)
- Boot hook in stock firmware startup script (stock OS still works without the card), or a single-card image with our own U-Boot, kernel and system that needs no stock card (H700 first; docs/specs/single-card.md)
- Launcher = Flutter embedder + shared UI + emulator host, one process
- Power daemon: sleep/resume, backlight, battery, safe shutdown flushing saves
- Per-device platform modules in C (H700, A133P, RK3566): evdev map, display mode, power
- Fixed SD-card layout (`Roms/<system>`, `Bios`, `Saves`, `States`, `Carts`); update by file replacement
- Settings: Wi-Fi, volume, brightness, time. Never redistribute vendor firmware.

## 5. UI rules (Material You)

- Material 3 with `dynamic_color`; on Linux derive the palette from the wallpaper with `material_color_utilities`.
- `NavigationBar` on phones (Games / Carts / Skins / Settings), `NavigationRail` on tablets/foldables.
- Pause menu = bottom sheet with tonal buttons (Save, Load, Rewind, Fast, Cheats, Capture), controller row, save-state slots.
- Game screen is edge-to-edge with no Material chrome; the skin is the controller.
- **Every screen must be fully operable with D-pad alone**: visible focus ring, L1/R1 switch tabs, A select, B back, button-hint bar on handhelds.
- Design for 640×480 and 720×720 first, then scale up; denser spacing than M3 default.
- Predictive back, edge-to-edge insets. Icons are our own **Dena Icons** (`tools/icons/build_icons.py`), never Material icons; type is Nunito. Console look: key-cap buttons, bevelled panels ([look and feel](docs/specs/ui-look-and-feel.md)).
- Dark by default with `#F1C40F` as accent; light/system modes, Material You and console themes are user choices ([theming](docs/specs/theming.md)). Gold is a fill only in light mode: text uses the darker gold.
- Use generic system names in store listings; no console logos.

## 6. Roadmap (milestones end at a human checkpoint)

| # | Milestone | Checkpoint |
| --- | --- | --- |
| 0 | Foundations: monorepo, this file, specs, CI, test harness, rig scripts | Rig assembled |
| 1 | Latency spike: mGBA in Flutter on Android (`Texture` vs `SurfaceView`) and on H700 (own embedder) | **Gate:** <50 ms, 60 fps, no crackle |
| 2 | Android MVP: NES, SNES, GB/GBC, GBA (Genesis deferred); library, art, states, auto-save, FF, cheats, gamepads, skins, M3 UI | Design sign-off; Play internal track |
| 3 | Android parity: N64, DS, PSX, PSP, PICO-8 runtime (+ browser if permitted), rewind, shortcuts, external display, foldables | Play release |
| 4 | Handheld layer: boot hooks, power daemon, platform modules, SD image builder, D-pad polish | Flash + test each device |
| 5 | Handheld release: tuning, update-by-file, docs | Public SD-card release |
| 6 | iOS: Swift shell, Metal, interpreter cores | App Store submission |

Claude moves on to the next milestone itself once the previous one is merged. Checkpoints that
need hardware stay open and are revisited when the user adds that hardware.

## 7. How to work (methodology)

**Specs first.** Every feature gets a short spec in `docs/specs/<feature>.md` (behaviour, inputs,
edge cases, acceptance tests) before code. Implement only from specs.

**Small tasks.** One feature or fix per branch/PR. Keep PRs reviewable; update the spec and this
file when behaviour changes.

**Delegate coding to OpenCode DeepSeek (user rule).** Routine, well-specified coding tasks
(boilerplate, small features, unit tests, refactors within a few files) go to OpenCode's
`opencode/deepseek-v4.1-flash-free` first, per [docs/dev/opencode.md](docs/dev/opencode.md);
Claude writes the prompt, reviews the diff and runs the tests. Claude codes directly only for
design, FFI/threading hot paths, tricky debugging, or when a delegated run stalls or fails.

**Clean-room rules (mandatory).**
- Never read, paste or reproduce source from Delta/DeltaCore, MinUI, SpruceOS, DuckStation or official PICO-8.
- Public docs, file-format descriptions and observed behaviour are fine. Record where each concept came from in `docs/provenance.md`.
- If code you are writing looks like it is recalled from one of those projects, stop and tell the user.
- License scanning runs in CI; every new dependency gets a license check and an entry in `docs/licenses.md`.

**Testing — Claude must be able to verify its own work.**
- Golden-frame tests: run a core N frames with a test ROM (homebrew/public-domain only), hash the framebuffer.
- Save-state round trip: save → load → identical frame hash.
- Input replay: recorded input files produce identical output.
- Flutter widget and golden (screenshot) tests for every screen, at 640×480 and phone size, touch and focus modes.
- PICO-8 runtime: compatibility suite of permitted carts.
- CI on arm64 runners for Android, Linux aarch64/armhf, and iOS builds.

**Hardware rig.** One device per class connected over adb (Android) or SSH/serial (handhelds).
Claude deploys builds, injects input (uinput / `adb shell input`), captures screen and logs, and
reads latency from the camera/photodiode tool. Anything requiring physical access — flashing,
recovery, judging feel — is a human checkpoint: say exactly what you need and stop.

**Standing approval (user, 2026-10-16):** Claude may take action without consulting the user,
including approving and merging its own PRs into `main` once CI is green. The user steps in only
to change goals or request features. Rig hardware is added as needed; the Android app is the
current focus.

**Still needs the user's own hand** (their accounts, keys or legal standing): store submissions,
signing, purchases, publishing public releases, contacting third parties (e.g. Lexaloffle),
adding copyrighted assets, ROMs or BIOS files.

## 8. Repo layout (target)

```
app/            Flutter app (shared UI, Drift DB, FFI bindings)
host/           C/C++ libretro frontend (CMake), shaders
cores/          core build scripts / submodules (licensed per §3)
shells/android/ Kotlin shell     shells/linux/ embedder + power daemon + platform modules
shells/ios/     Swift shell
os/             SD-card image builder, boot hooks per device
tools/rig/      hardware-rig scripts (deploy, input, capture, latency)
docs/           specs/, provenance.md, licenses.md
```

## 9. Open questions (ask the user; do not decide alone)

- Genesis core choice (must be commercial-safe). Deferred by the user on 2026-10-16.
- MinUI and SpruceOS license terms (verify before studying their behaviour closely).
- Exact supported firmware versions per handheld.
