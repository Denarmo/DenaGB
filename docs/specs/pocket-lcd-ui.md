# Pocket LCD UI (Dena.emu GB)

Dena.emu GB draws every screen on an imaginary four-shade pocket LCD inside a
putty-and-slate shell. Source: proposal 03 "Pocket LCD" in the UI redesign
proposals (`/mnt/project-files/ui-redesign/ui-redesign-proposals.pdf`). The
deltaskins (touch controller skins) are out of scope and stay unchanged.

## Behaviour

- **Palette.** Four shades per LCD palette, the same as the dot matrix
  shader's (`host/shaders/_pocket-lcd/pocket-lcd.glsl`): Olive (default;
  Pea `#C5D48A`, Moss `#8DA24A`, Fern `#46652E`, Pine `#1B2E17`), Pocket grey,
  Backlit amber and Inverted. Settings > Appearance > LCD palette changes the
  app and the Game Boy screen together (`theme.json` `palette`, and
  `shaders.json` `lcd.palette` by index).
- **Type.** Press Start 2P for titles and headers, Silkscreen for lists,
  metadata and hints (both OFL-1.1, bundled). Shell print uses Nunito Black
  Italic.
- **Virtual pixels.** One LCD pixel is 2 logical pixels on phones and on the
  640x480 handheld (authored at 320x240), 3 on a desktop or TV fullscreen
  (width >= 1200 and short side >= 700). Glyph sizes are multiples of 8
  virtual pixels.
- **Materials.** Square corners, ink lines one or two virtual pixels wide, no
  shadows or ink ripples. Focus and press invert a control (paper on ink).
  Switches are two-cell OFF | ON pixel switches; sliders are segmented bars
  with a square knob.
- **Icons.** 1-bit pixel glyphs on a 9x9 grid with an optional mid shade
  (`app/lib/src/ui/pixel_icons.dart`).
- **Phone (width < 600).** The phone is the console: the screen sits in a
  slate bezel with an asymmetric big bottom-right radius, a POWER LED and the
  "DENA.EMU GB POCKET LCD" print with two pinstripes; under it "Dena.emu GB
  POCKET" and speaker slots on the putty, then the tabs as rubber keys in
  recessed wells (3 px travel) with an LED by the active tab's name.
- **Handheld and wide screens.** No bezel. The tabs are an inverted LCD strip
  with L / R shoulder tabs; L1 / R1 switch. The handheld keeps its button-hint
  bar.
- **Glass.** A faint pixel grid (not on the handheld, whose pixels are real)
  and a soft glare from the top left over the screen.
- **Library.** An inverted LIBRARY header with the game count; search, view,
  add and sort keys; system filter chips (the chosen one inverted). Boxes keep
  their real per-console proportions and stand on dithered pixel shelves:
  three across on the phone, longer shelves elsewhere. D-pad focus shows pixel
  corner brackets around the box. Under the shelves an inverted strip shows the
  focused game (else the first, most recently played): title, system,
  playtime, the A PLAY / HOLD ZOOM hints and its position; tapping it plays.
- **Covers.** Boxes and covers are drawn in the LCD's shades by default (a
  luminance map from ink to paper with a little extra contrast). Settings >
  Appearance > Colour covers shows them in full colour (`theme.json`
  `colourCovers`).
- **Settings.** One long RPG-style menu: inverted section headers over plain
  rows.

- **Pause menu.** The game stays visible under a 25% ink dither; a tap on it
  resumes. A double-bordered window sits at the bottom: the game title on an
  inverted bar, then two columns of commands with pixel glyphs (Resume, Save,
  Load, Rewind, Cheats, Shader, Capture, Quit). The focused command inverts and
  shows the ▶ cursor; Tab and the D-pad walk them row by row. Below: Speed as
  three cells (1X, 2X, 4X, the lit one is the speed), Turbo, Link cable and the
  players. Hardcore drops Load, Rewind and Cheats as before.
- **Save slots.** Each slot is its screenshot in an ink frame with the slot
  name and time under it; empty slots are a dithered frame. Brackets mark the
  focused slot.
- **Box zoom.** While a finger rests on a box a HOLD meter fills along its
  bottom in eight steps over the long-press time (hidden for quick taps). The
  zoom dims the shelf with the 25% dither, steps the box up at 12 fps onto a
  dithered plinth in whole pixels, sweeps a dithered foil sheen across it once,
  and opens an RPG window: title, system and playtime, Play, then Rename,
  Favourite, Add to home screen, Achievements, Choose cover, Game info and
  Delete in one column. Delete still asks first. The idle bob moves in whole
  pixels.
- **Launch.** 11 frames at 12 fps (just under a second, handhelds too): two
  dither frames hide the library, the box flies to the middle on paper and its
  lid opens, the cartridge lifts out and drops into the slot drawn below, one
  frame of the whole screen in ink, then a centre-line wipe opens onto the
  game. The box and cartridge use the LCD shades unless Colour covers is on. A
  tap or any button still skips; reduced motion is still a short fade.

## Edge cases

- An unknown or older palette id in `theme.json` (for example `dena`) shows
  Olive; the brightness mode setting no longer applies (Inverted is the dark
  look).
- The shader store and the theme can disagree only if `shaders.json` was edited
  by hand; the next palette pick writes both.

## Acceptance tests

- `test/ui/app_theme_test.dart`: the app starts on Olive with the pixel fonts;
  picking Backlit amber restyles the app; palette ids map to shader indexes;
  colour covers round-trip the file.
- `test/shell/handheld_navigation_test.dart`: the palette and colour covers are
  reachable and changed by D-pad and A; focus brackets show only in D-pad mode.
- `test/session_screen_test.dart`: the pause commands keep their D-pad order;
  the 2X cell sets the speed.
- `test/library/launch_animation_test.dart`: every frame draws for each system;
  the game page loads on the first frame; a tap or a key skips.
- Golden screenshots of the library, pause window, slots, box zoom, settings,
  shelves and sheets at
  640x480, 720x720 and phone size, touch and focus.
