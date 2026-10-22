# Spec: PlayStation

Status: draft (Milestone 3, package 3)

## Core

- PCSX ReARMed libretro port (GPL-2.0; bundled deps: lightrec LGPL-2.1,
  GNU lightning LGPL-3.0, libchdr BSD-3-Clause, zlib) at a pinned commit, built
  by `cores/pcsx_rearmed/build.sh` and packaged as `libpcsx_rearmed_libretro.so`.
- No BIOS needed: the core's HLE BIOS runs most games. A user-supplied
  `scph5501.bin` (or another region's) in the system folder is used if present.

## Library

- Imports as system `psx` ("PS1"):
  - `.chd` (compressed disc image) and `.pbp` (single-file EBOOT): one file each.
  - `.m3u` playlists, `.cue` + track `.bin` files: need sibling files, so they
    come with folder import (later package). Plain `.bin` stays unrecognised.
- Box art: the CRC of a CHD/PBP container doesn't identify the disc, so PSX
  games show the placeholder until a title-based lookup exists.

## Controls

- Built-in skin: D-pad, △ ○ ✕ □ (RetroPad X, A, B, Y), L1/R1/L2/R2,
  Start/Select, menu.
- PlayStation games use L2, so a held gamepad L2 is passed to the game and
  does not rewind (rewind stays in the pause menu).
- Cheats: GameShark (`XXXXXXXX YYYY`), several lines per cheat.

## Multi-disc (later)

- `.m3u` lists discs; the pause menu gets "Change disc" (libretro disk control
  interface). Changing disc clears the rewind buffer (rewind.md).

## Acceptance tests

- Dart: `.chd`/`.pbp` detection; skin has L2/R2 and the PlayStation labels;
  session configures rewind with `l2Hold` off for `psx`; skin goldens.
- Host golden with our own PS-EXE test program (`host/tests/roms/psx/`), when
  it exists.
