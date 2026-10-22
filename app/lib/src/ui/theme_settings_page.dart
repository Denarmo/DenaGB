// SPDX-License-Identifier: GPL-3.0-or-later
// Settings > Theme: dark / light / system, and the colour palette.
// Spec: docs/specs/theming.md
import 'package:material_ui/material_ui.dart';

import '../library/games_tab.dart' show SectionLabel;
import '../session/cheat_codes.dart' show systemLabel;
import '../shell/handheld.dart' show arrowsMoveFocus;
import 'app_theme.dart';
import 'dena_icons.dart';

/// "Dark · Dena gold": the Settings row's subtitle.
String themeSummary(ThemeSettings settings) {
  final mode = switch (settings.mode) {
    ThemeMode.dark => 'Dark',
    ThemeMode.light => 'Light',
    ThemeMode.system => 'Follows system',
  };
  return '$mode · ${paletteName(settings.palette)}';
}

String paletteName(String id) => switch (id) {
  denaPalette => 'Dena gold',
  dynamicPalette => 'Material You',
  _ => consoleThemeById(id)?.name ?? 'Dena gold',
};

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ThemeScope.of(context);
    final settings = scope.notifier!;
    final scheme = Theme.of(context).colorScheme;
    final systems = {for (final t in consoleThemes) t.system};
    Widget group(List<Widget> children) => Card.filled(
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
    Widget option(String id, {String? subtitle, bool enabled = true}) =>
        RadioListTile<String>(
          value: id,
          // The D-pad starts on the current choice.
          autofocus: id == settings.palette,
          enabled: enabled,
          dense: true,
          title: Text(paletteName(id)),
          subtitle: subtitle == null ? null : Text(subtitle),
          secondary: _Swatch(id),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: SafeArea(
        top: false,
        child: RadioGroup<String>(
          groupValue: settings.palette,
          onChanged: (id) {
            if (id != null) settings.palette = id;
          },
          child: Shortcuts(
            shortcuts: arrowsMoveFocus,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                const SectionLabel('Mode'),
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(DenaIcons.moon),
                      label: Text('Dark'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(DenaIcons.sun),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(DenaIcons.themeAuto),
                      label: Text('System'),
                    ),
                  ],
                  selected: {settings.mode},
                  onSelectionChanged: (s) => settings.mode = s.first,
                ),
                const SectionLabel('Colours'),
                group([
                  option(denaPalette, subtitle: 'The default'),
                  option(
                    dynamicPalette,
                    subtitle: scope.dynamicAvailable
                        ? 'Colours from your wallpaper'
                        : 'Not offered by this device',
                    enabled: scope.dynamicAvailable,
                  ),
                ]),
                const SectionLabel('Console themes'),
                for (final sys in systems) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                    child: Text(
                      systemLabel(sys),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  group([
                    for (final t in consoleThemes.where((t) => t.system == sys))
                      option(t.id),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A preview dot: the palette's container colour ringed by its primary, in
/// the current brightness.
class _Swatch extends StatelessWidget {
  const _Swatch(this.id);

  final String id;

  @override
  Widget build(BuildContext context) {
    final current = Theme.of(context).colorScheme;
    final s = id == dynamicPalette
        ? null
        : paletteScheme(id, current.brightness);
    final fill = s?.primaryContainer ?? current.surfaceContainerHighest;
    final ring = s?.primary ?? current.outline;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 3),
      ),
      child: id == dynamicPalette
          ? Icon(DenaIcons.image, size: 16, color: current.onSurfaceVariant)
          : null,
    );
  }
}
