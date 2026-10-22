# Spec: Pause menu

Status: draft (Milestone 2, package 6)

## Layout (Material 3 bottom sheet over the paused game)

1. Header: the game's title and a filled **Resume** button (focused first).
2. A row of tonal action tiles (icon above label, equal width):
   **Save**, **Load**, **Rewind** (rewind.md), **Cheats**, **Shader** (shaders.md),
   **Capture**, **Quit**.
   Long labels shrink to fit so the tiles stay one height.
3. **Speed**: segmented 1× / 2× / 4×.
4. **Controllers**: one chip per player (gamepads.md).

The sheet fits 640×480 without scrolling and scrolls when the system font is
large. Every control is reachable with the D-pad; B closes the sheet and
resumes.

## Capture

Writes the last game frame (core resolution, no skin) as a PNG to the shared
Pictures collection, folder `Pictures/Dena.emu`, named
`<title> <yyyy-MM-dd HH.mm.ss>.png`, through MediaStore (no storage
permission needed on Android 10+). On Android 8–9 it writes to the same folder and
needs the storage permission (`maxSdkVersion 28`); until a permission prompt
lands with the settings screens, it reports "The screenshot could not be saved"
there. The sheet stays open and a snackbar says "Screenshot saved".

## Native API

- Runner: `screenshot(path)` writes the current frame with
  `dena_frame_write_png` on the emulator thread.
- `GameHostApi.captureScreenshot(name)` → error message or null.

## Acceptance tests

- Dart: pause sheet goldens at the matrix sizes (touch and focus); D-pad order
  Resume → Save → Load → Rewind → Cheats → Shader → Capture → Quit → speed; Capture calls the API
  with the title and time and shows the snackbar without closing the sheet.
