# Launch animation

Playing a game (tap a box, Play in the hold menu, or A on a focused box on the
handheld) opens the game's box and loads its media: the core starts underneath
while the animation runs, so the load time hides behind it.

In Dena.emu GB the launch is the Pocket LCD version: 11 frames at 12 fps on
every device, ending in an ink frame and a centre-line wipe instead of the
insert and black frame; see [pocket-lcd-ui.md](pocket-lcd-ui.md), Launch. The
timings below are the parent app's.

## Behaviour

- **One entry point.** `playGame` pushes a `LaunchRoute` (`app/lib/src/library/launch_animation.dart`).
  Every play path (grid, stash, Continue card, hold menu, PICO-8 launcher, shortcuts)
  goes through it. The Dena Explore launcher cart itself does not animate.
- **Session starts on frame one.** The route builds `SessionScreen` immediately; it stays
  unpainted until the backdrop covers the library (`LaunchTimeline.sessionShownAt`), then
  the box animation plays over it.
- **Timeline** (1.9 s, fractions in `LaunchTimeline`):
  1. *Fly* (0–0.18): the box flies from where it was tapped (`LaunchOrigin`; the
     focused box with a D-pad) to the middle; the Dark Anthracite backdrop fades in with a
     faint gold glow.
  2. *Open* (0.16–0.42): cardboard boxes (NES, SNES, N64, GB, GBC, GBA) lift the top flap;
     plastic cases (PS1, PSP, DS, 3DS, Genesis, Saturn, Dreamcast, PS2) swing the front open
     on the spine, showing the tray.
  3. *Lift* (0.38–0.62): the media slides up out of the flap, or lifts off the tray. Discs
     and UMDs start spinning.
  4. *Insert* (0.62–0.9): the box falls away; the media moves to the centre and grows past
     the screen toward the viewer (carts tip as if pushed into a slot, discs spin up),
     fading to black.
  5. *Reveal* (0.92–1): the overlay fades out over the running game.
- **Skip:** a tap anywhere or any key / button jumps to the end. Keys use a global
  `HardwareKeyboard` handler so the session keeps its own focus.
- **Reduced motion** (`MediaQuery.disableAnimations`): a 200 ms fade, no box.
- **Exit** (popping the session): a 250 ms fade, never the launch in reverse.

## Media

| Kind | Systems | Drawing |
| --- | --- | --- |
| Cartridge | NES, SNES, N64, GB, GBC, GBA, DS, 3DS, Genesis | `CartShape` per system: real outside proportions, plastic colour, label well, grip ridges, top notch (GBA/DS), stepped shoulders (N64) |
| Disc | PS1, PS2, Saturn, Dreamcast | Silver disc with clear hub and centre hole |
| UMD | PSP | Dark shell, label across the top, disc window below |
| PICO-8 cart | PICO-8 | The `.p8.png` itself (it is a picture of a cart) |

All drawings are our own: plain shapes, no logos or trademarks.

## Media art

`MediaArtCache` (`media_art.dart`), cached under `<dataDir>/art/<sha1>.media.png` next to
the covers, so `BoxArtCache.forget` deletes both.

1. The player's custom media art (`<sha1>.media.custom.png`).
2. The cached download.
3. **ScreenScraper** (`ScreenScraperSource`), when the build has developer credentials
   (`--dart-define=DENA_SCREENSCRAPER_DEVID=… --dart-define=DENA_SCREENSCRAPER_DEVPASSWORD=…`).
   Looked up by CRC, SHA-1 and file name; cartridges take `support-texture` (the flat label),
   discs and UMDs `support-2D` (the face scan). Region: the file's own tags, then USA, World,
   Europe, Japan. One request at a time.
4. **Fallback:** the game's cover, cropped onto the console's label frame (the printed
   band around the label, e.g. black on NES, light on SNES) or onto the disc's print area.

A miss writes `<sha1>.media.none` and is retried after 7 days; a failed lookup (offline,
quota) records nothing and is retried after a restart. Media art is prefetched on import and
at each launch; the launch waits at most 350 ms for the cover and media art, so a slow
network only means the fallback shows this time.

The libretro thumbnail server has covers, snaps and title screens but no label or disc
scans, which is why genuine media art needs ScreenScraper.

## Box shape

The box comes from the library's box model (`game_box_model.dart`, game-boxes.md):
`aspect` and `depthMm` size it, `hinge` picks the opening (left: case, top: carton,
none: PICO-8, which only lifts), and `mediaRect` seats the media at its real size in the
open box. The insert phase grows small media (a DS card) to the same on-screen size as a disc.

## Handhelds

The Linux handheld plays the same launch in 1.1 s instead of 1.9 s: the core
starts underneath on four small cores, and a shorter overlap keeps the frames
even. Any button still skips; reduced motion still fades.

## Tests

`test/library/media_art_test.dart`: media kinds, ScreenScraper reply picking and request
queueing, cache hits, misses, failures and custom art.
`test/library/launch_animation_test.dart`: session starts on the first frame, tap and key
skip, reduced motion, every frame draws for each media kind, `LaunchOrigin` rects.
