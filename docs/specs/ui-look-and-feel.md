# UI look and feel

Visual polish for the shared Flutter UI (CLAUDE.md §5). Behaviour, focus order and
texts are unchanged; this spec covers styling only.

## Theme (`denaTheme`, app/lib/src/app.dart)

A moulded console look over Material 3 (third pass, 2026-10-17: the owner found the
earlier passes too flat and too Material).

- Colours come from the chosen palette (theming.md): dark Dena gold by default,
  Material You or a console theme on request. Compact density.
- Type: Nunito (rounded terminals) everywhere, Roboto as fallback. Headlines and
  titleLarge w800, titleMedium/Small w700, body w500, labels w700 with slight tracking.
- No Material ink ripples anywhere (`NoSplash`): keys travel, wells press in.
- Back, close and drawer buttons use Dena Icons (`ActionIconThemeData`).
- Focus colour is `primary` at 16 % so D-pad focus reads clearly.

## Icons (tools/icons/build_icons.py → app/lib/src/ui/dena_icons.dart)

- Our own icon font, Dena Icons: every glyph drawn from rounded primitives on a 24-unit
  grid in one style: solid moulded silhouettes, 2.5-unit strokes with round caps,
  generous corner radii and cut-out details (controller with D-pad, cartridge with label,
  trophy with star). Outline variants exist for unselected navigation tabs.
- No `Icons.*` in the launcher, settings, menus or dialogs. The only exception is the
  touch-skin menu glyph in `touch_controls.dart`, owned by the D-pad skin work.
- Codepoints run from U+E000 in definition order; new glyphs are appended so existing
  codepoints never move. Rebuild with `python3 tools/icons/build_icons.py --preview x.png`.

## Plastic finish (app/lib/src/ui/plastic.dart)

- Shell texture: the fine matte stipple of a Game Boy shell, soft-light blended over the
  whole app (off on handhelds), lit from above. Hidden while the game screen is open.
  The tile's soft bumps are computed on the CPU and drawn as plain pixels: drawing them
  as mask-blurred circles ran Impeller (Vulkan) out of memory at launch on phones.
- Buttons (filled, tonal, elevated, outlined, text) are key caps standing on a shaded
  side wall 4 px high: convex face lit from above with its own stipple, a bright chamfer
  on the top edge, a crisp shadow line where the face meets the wall, a dark outer rim and
  a drop shadow (elevation 2, 5 on focus/hover). Pressed, the face travels down into the
  wall over 50 ms (springs back over 110 ms), the rim shades its top and the label sinks
  with it. Outlined and text buttons get a neutral cap (`surfaceContainerHighest` /
  `surfaceContainerHigh`).
- Panels (cards, dialogs, bottom sheets, snack bars, chips, FAB) use `BevelBorder`: a
  bright chamfer on top and a shaded lip below, drawn over the content so it shows over
  cover art. Sunken bevels (search bar, selected navigation tab, chosen segment) reverse it
  like a window set into the case.
- Navigation bar and rail: the selected tab sits in a dark well with a gold glyph (gold
  fill with dark glyph in light mode). Segmented buttons do the same for the chosen
  segment; the others are raised.
- Settings list tiles show gold glyphs; section labels carry a short gold bar.
- Pause menu tiles are dark keys with gold glyphs; Quit is the red key.
- Labels and icons are debossed; icon buttons sink as a round dimple when pressed.
- Switches show a check or cross on the thumb.

## System accents (app/lib/src/ui/system_palette.dart)

- Each system has a generic seed hue (no console logos or trade dress), harmonised
  towards the app's primary colour, expanded to a tonal scheme matching the current
  brightness. Unknown systems use the app's primary.

## Library and Carts

- Cover placeholder: diagonal gradient in the system accent, the system's short name
  large and bold, a faint controller glyph in the corner.
- Card: cover, then a two-line title area (fixed height so covers align) and the
  system name in the accent colour. Favourites get a star badge on the cover.
- D-pad focus (traditional highlight mode only): the card scales to 104 % and gets a
  3 px primary outline. Touch mode shows neither.
- "N games" label above the grid; "Continue playing" card on `primaryContainer`
  with a cover thumbnail and play glyph.
- Empty states use a large icon in a tonal circle.
- Carts: the browser notice is a `tertiaryContainer` card.

## Skins and Settings

- Skins: each system's choices sit in a filled card under its heading.
- Settings: grouped bevelled cards under section labels with a gold bar.

## Pause sheet

- Title in titleLarge, section labels in `onSurfaceVariant`.
- Quit tile uses the error container colours; the other tiles are dark keys with gold glyphs.
- Speed segments carry play / fast-forward icons, no selected checkmark.

## Acceptance

- `flutter analyze` clean; all widget tests pass; goldens regenerated.
- `tool/screenshots_test.dart` renders every screen without overflow at phone and
  640×480.
