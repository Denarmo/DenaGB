// SPDX-License-Identifier: GPL-3.0-or-later
// The app's colour choices: the Dena gold default, Material You, and themes
// drawn from the console skins' colours.
// Spec: docs/specs/theming.md
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'pocket.dart';

/// The app accent. Bright yellow is only readable as a fill: in light mode
/// it is the container colour and text/icons use a darker gold.
const Color denaAccent = Color(0xFFF1C40F);

/// The dark base colour: Dark Anthracite, a warm near-black like moulded
/// console plastic.
const Color denaAnthracite = Color(0xFF202024);

/// Text and icons on [denaAccent] (13:1).
const Color onDenaAccent = Color(0xFF241A00);

/// The UI typeface: Nunito, a rounded sans with soft terminals that reads
/// like a console's system font (bundled, OFL-1.1; theming.md, Fonts).
const String denaFont = 'Nunito';

/// The default palette id.
const String denaPalette = 'dena';

/// The wallpaper palette id (Material You, `dynamic_color`).
const String dynamicPalette = 'dynamic';

/// A theme drawn from a console skin's colours (tools/skins/build_skins.py):
/// [id] is the skin key, [name] the skin's name, [seed] its signature colour.
class ConsoleTheme {
  const ConsoleTheme(this.id, this.system, this.name, this.seed);

  final String id;
  final String system;
  final String name;
  final Color seed;
}

/// One theme per bundled skin and edition, in the Skins tab's order. Grey
/// consoles use their accent colour so the theme is not just grey.
const consoleThemes = <ConsoleTheme>[
  ConsoleTheme('nes', 'nes', 'Graphite Brick', Color(0xFFC42433)),
  ConsoleTheme('nes_cream', 'nes', 'Cream & Crimson', Color(0xFF8C1D2A)),
  ConsoleTheme('snes', 'snes', 'Four Color Pad', Color(0xFF3651B0)),
  ConsoleTheme('snes_lavender', 'snes', 'Lavender Concave', Color(0xFF4B3A8F)),
  ConsoleTheme('gb', 'gb', 'Pocket Classic', Color(0xFF9B2A5D)),
  ConsoleTheme('gb_clear', 'gb', 'Clear Pocket', Color(0xFF5A786E)),
  ConsoleTheme('gb_sunshine', 'gb', 'Pocket Sunshine', Color(0xFFF2C512)),
  ConsoleTheme('gbc', 'gbc', 'Pocket Grape', Color(0xFF6A4B9E)),
  ConsoleTheme('gbc_teal', 'gbc', 'Pocket Teal', Color(0xFF15A3A6)),
  ConsoleTheme('gbc_berry', 'gbc', 'Pocket Berry', Color(0xFFC41F4E)),
  ConsoleTheme('gbc_dandelion', 'gbc', 'Pocket Dandelion', Color(0xFFF2C21C)),
  ConsoleTheme('gba', 'gba', 'Indigo Wide', Color(0xFF4B3F98)),
  ConsoleTheme('gba_glacier', 'gba', 'Glacier Wide', Color(0xFFA7D2E9)),
  ConsoleTheme('gba_fuchsia', 'gba', 'Fuchsia Wide', Color(0xFFC3227A)),
  ConsoleTheme('n64', 'n64', 'Three Grip', Color(0xFF2F4FB4)),
  ConsoleTheme('n64_smoke', 'n64', 'Smoke Grip', Color(0xFF43464C)),
  ConsoleTheme('n64_jungle', 'n64', 'Jungle Grip', Color(0xFF2F6C4B)),
  ConsoleTheme('nds', 'nds', 'Dual Slate', Color(0xFF43C2FF)),
  ConsoleTheme('nds_polar', 'nds', 'Polar Dual', Color(0xFFEEF0F3)),
  ConsoleTheme('nds_ice', 'nds', 'Ice Dual', Color(0xFFB6D8EE)),
  ConsoleTheme('psx', 'psx', 'Gray Disc Pad', Color(0xFF7096DC)),
  ConsoleTheme('psx_midnight', 'psx', 'Midnight Pad', Color(0xFF2B2C2F)),
  ConsoleTheme('psp', 'psp', 'Gloss Black Portable', Color(0xFF141518)),
  ConsoleTheme('psp_blue', 'psp', 'Vibrant Blue Portable', Color(0xFF1B90D8)),
  ConsoleTheme('psp_white', 'psp', 'Ceramic White Portable', Color(0xFFF1F1EF)),
  ConsoleTheme('psp_red', 'psp', 'Radiant Red Portable', Color(0xFFC5171D)),
];

ConsoleTheme? consoleThemeById(String id) {
  for (final t in consoleThemes) {
    if (t.id == id) return t;
  }
  return null;
}

/// Whether [id] names a palette this build knows.
bool knownPalette(String id) =>
    id == denaPalette ||
    id == dynamicPalette ||
    consoleThemeById(id) != null ||
    lcdUiPalettes.any((p) => p.id == id);

/// The Dena gold scheme. Dark: gold is `primary` with dark text on it.
/// Light: gold stays the container fill while `primary` (text, icons, focus
/// rings on white) is the darker gold the tonal palette picks.
ColorScheme denaScheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: denaAccent,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  return brightness == Brightness.dark
      ? base.copyWith(
          primary: denaAccent,
          onPrimary: onDenaAccent,
          // Neutral anthracite surfaces, lightest for the highest container.
          surface: denaAnthracite,
          surfaceDim: const Color(0xFF18181B),
          surfaceBright: const Color(0xFF3A3A40),
          surfaceContainerLowest: const Color(0xFF141417),
          surfaceContainerLow: const Color(0xFF26262B),
          surfaceContainer: const Color(0xFF2A2A30),
          surfaceContainerHigh: const Color(0xFF33333A),
          surfaceContainerHighest: const Color(0xFF3E3E46),
          onSurface: const Color(0xFFE7E6EA),
          onSurfaceVariant: const Color(0xFFC8C6CE),
          outline: const Color(0xFF908E98),
          outlineVariant: const Color(0xFF4A4A52),
        )
      : base.copyWith(
          primaryContainer: denaAccent,
          onPrimaryContainer: onDenaAccent,
        );
}

final _schemes = <(String, Brightness), ColorScheme>{};

/// The scheme for [palette] at [brightness]. Material You falls back to Dena
/// gold when the platform has no wallpaper palette ([dynamic] is null).
ColorScheme paletteScheme(
  String palette,
  Brightness brightness, {
  ColorScheme? dynamic,
}) {
  if (palette == dynamicPalette && dynamic != null) return dynamic;
  final console = consoleThemeById(palette);
  if (console == null) {
    return _schemes.putIfAbsent((
      denaPalette,
      brightness,
    ), () => denaScheme(brightness));
  }
  return _schemes.putIfAbsent(
    (palette, brightness),
    () => ColorScheme.fromSeed(
      seedColor: console.seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ),
  );
}

/// WCAG contrast ratio of two opaque colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Audio buffer targets offered in Settings, in ms (performance.md).
const audioLatencyOptions = [40, 30, 20];

/// The default audio buffer target, in ms (performance.md).
const defaultAudioLatency = 40;

/// The chosen brightness mode, palette, library view and audio latency, saved to
/// `<dataDir>/theme.json` as JSON. Dark and Dena gold by default, with a
/// 40 ms audio buffer. Without a [file] (tests) choices last for the session.
/// `"library": "stash"` picks the stash view of the Games tab
/// (docs/specs/library-stash.md); the grid is the default.
///
/// The file is a few bytes and is read before the first frame, so it is read
/// and written synchronously, like the shader store.
class ThemeSettings extends ChangeNotifier {
  ThemeSettings({
    this.file,
    this._mode = ThemeMode.dark,
    String? palette,
    int? audioLatencyMs,
    this._stash = false,
    this._colourCovers = false,
  }) : _palette = palette ?? denaPalette,
       _audioLatencyMs = audioLatencyMs ?? defaultAudioLatency;

  /// Reads [file]; a missing or damaged file gives the defaults.
  factory ThemeSettings.load(File file) {
    var mode = ThemeMode.dark;
    var palette = denaPalette;
    var audioLatency = defaultAudioLatency;
    var stash = false;
    var colourCovers = false;
    try {
      if (file.existsSync()) {
        final j = jsonDecode(file.readAsStringSync());
        if (j is Map) {
          mode = ThemeMode.values.firstWhere(
            (m) => m.name == j['mode'],
            orElse: () => ThemeMode.dark,
          );
          final id = j['palette'];
          if (id is String && knownPalette(id)) palette = id;
          final ms = j['audioLatencyMs'];
          if (ms is int && audioLatencyOptions.contains(ms)) {
            audioLatency = ms;
          }
          stash = j['library'] == 'stash';
          colourCovers = j['colourCovers'] == true;
        }
      }
    } on Object {
      // Defaults; the next change rewrites the file.
    }
    return ThemeSettings(
      file: file,
      mode: mode,
      palette: palette,
      audioLatencyMs: audioLatency,
      stash: stash,
      colourCovers: colourCovers,
    );
  }

  final File? file;
  ThemeMode _mode;
  String _palette;
  int _audioLatencyMs;
  bool _stash;
  bool _colourCovers;

  /// Whether covers show in full colour instead of the LCD's four shades
  /// (pocket-lcd-ui.md).
  bool get colourCovers => _colourCovers;

  set colourCovers(bool value) {
    if (value == _colourCovers) return;
    _colourCovers = value;
    _save();
  }

  ThemeMode get mode => _mode;

  /// Whether the Games tab shows the stash instead of the grid.
  bool get stash => _stash;

  set stash(bool value) {
    if (value == _stash) return;
    _stash = value;
    _save();
  }

  String get palette => _palette;
  int get audioLatencyMs => _audioLatencyMs;

  set mode(ThemeMode value) {
    if (value == _mode) return;
    _mode = value;
    _save();
  }

  set palette(String value) {
    if (value == _palette || !knownPalette(value)) return;
    _palette = value;
    _save();
  }

  set audioLatencyMs(int value) {
    if (value == _audioLatencyMs || !audioLatencyOptions.contains(value)) {
      return;
    }
    _audioLatencyMs = value;
    _save();
  }

  void _save() {
    notifyListeners();
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({
          'mode': _mode.name,
          'palette': _palette,
          'audioLatencyMs': _audioLatencyMs,
          if (_stash) 'library': 'stash',
          if (_colourCovers) 'colourCovers': true,
        }),
      );
    } on Object catch (e) {
      debugPrint('Theme not saved: $e');
    }
  }
}

/// Gives the settings screen the app's [ThemeSettings], and whether the
/// platform offers a wallpaper palette.
class ThemeScope extends InheritedNotifier<ThemeSettings> {
  const ThemeScope({
    super.key,
    required ThemeSettings settings,
    required this.dynamicAvailable,
    required super.child,
  }) : super(notifier: settings);

  final bool dynamicAvailable;

  static ThemeScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!;

  @override
  bool updateShouldNotify(ThemeScope oldWidget) =>
      super.updateShouldNotify(oldWidget) ||
      dynamicAvailable != oldWidget.dynamicAvailable;
}
