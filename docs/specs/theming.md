# Theming

The app is dark by default with `#F1C40F` (Dena gold) as its accent. Users can switch to
light or follow the system, and pick another palette: Material You (wallpaper colours) or a
console theme drawn from the bundled skins (CLAUDE.md §5, ui-look-and-feel.md).

## Choices (Settings > Appearance > Theme)

- **Mode**: Dark (default) / Light / System, a segmented button (D-pad operable).
- **Colours**: Dena gold (default); Material You, disabled with "Not offered by this device"
  when `dynamic_color` returns no palette; and one console theme per bundled skin and
  edition (26), grouped by system, named after the skin (`tools/skins/build_skins.py`).
- Saved to `<dataDir>/theme.json` as `{"mode": "dark"|"light"|"system", "palette": "<id>"}`.
  A missing or damaged file, or an unknown palette id, gives the defaults.

## Schemes (app/lib/src/ui/app_theme.dart)

- Dena gold: `ColorScheme.fromSeed(#F1C40F, fidelity)`.
  - Dark: `primary` = `#F1C40F`, `onPrimary` = `#241A00`. Surfaces are neutral Dark
    Anthracite: `surface` `#202024`, containers stepping up to `#3E3E46` (highest).
  - Light: bright yellow on white is unreadable (1.6:1), so `#F1C40F` stays the fill
    (`primaryContainer`, e.g. the FAB) with `#241A00` on it, while `primary` (text, icons,
    focus rings) is the darker gold the tonal palette picks.
- Console themes: `fromSeed(<skin signature colour>, fidelity)`. Grey consoles use their
  accent colour (e.g. the NES face buttons) so the theme is not just grey.
- Material You uses the platform's schemes; without them it falls back to Dena gold.
  Only Android has one: elsewhere (the Linux handheld) the app never asks the platform
  (`hasAndroidShell`), Material You is shown as not offered, and Dena gold and the
  console themes are built in Dart (`ColorScheme.fromSeed`, material_color_utilities)
  exactly as on Android.
- The handheld launcher reports `platformBrightness: dark` on `flutter/settings`, so
  the System mode matches the dark default there.
- The game backdrop is always black, so built-in touch controls use the light scheme's
  tones in both modes.

## Fonts

Roboto (OFL-1.1, `app/assets/fonts/roboto/`, weights 400/500/600/700) is bundled as
family `Roboto`, the family Material's typography asks for on Android and Linux. Linux
handhelds have no system fonts or fontconfig, so without it no text renders there.

Nunito (OFL-1.1, `app/assets/fonts/nunito/`, weights 400/500/600/700/800) is the UI
typeface (`denaFont`): rounded terminals that read like a console's system font. Roboto
stays as `fontFamilyFallback` for glyphs Nunito lacks. Dena Icons
(`app/assets/fonts/dena_icons/DenaIcons.otf`) is our own icon font
(ui-look-and-feel.md, Icons).

## Acceptance

- Every palette in both brightnesses meets WCAG AA: 4.5:1 for `onSurface`/`surface`,
  `primary` on `surface` and `surfaceContainer`, and each on-colour on its container; 3:1
  for `primary` on `surfaceContainerHigh` (focus rings). `test/ui/app_theme_test.dart`.
- Fresh install starts dark with the gold accent; choosing Light and a console theme
  restyles the app at once and survives a restart.
- On the Linux handheld: all text shows, dark Anthracite with the gold accent, console
  themes apply, no `dynamic_color` channel call.
- Goldens regenerated; `tool/screenshots_test.dart` renders the theme page and the library
  in other themes.
