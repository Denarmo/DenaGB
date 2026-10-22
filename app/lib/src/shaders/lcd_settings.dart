// SPDX-License-Identifier: GPL-3.0-or-later
// Settings > Display: the dot matrix LCD laid over every game.
// Spec: docs/specs/dot-matrix.md
import 'package:material_ui/material_ui.dart';

import '../ui/app_theme.dart';
import '../ui/pixel_icons.dart';
import '../ui/pocket.dart';
import 'shader_store.dart';

/// Intensity slider for the dot matrix LCD (0-100% in steps of 5).
class LcdIntensityTile extends StatefulWidget {
  const LcdIntensityTile({super.key, required this.store});

  final ShaderStore store;

  @override
  State<LcdIntensityTile> createState() => _LcdIntensityTileState();
}

class _LcdIntensityTileState extends State<LcdIntensityTile> {
  late int percent = (widget.store.lcdIntensity * 100).round();

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const PixelIcon(PixelGlyphs.tv),
    title: Text('LCD filter intensity · $percent%'),
    // Directional mode: left / right change the slider, up / down leave it.
    subtitle: MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(navigationMode: NavigationMode.directional),
      child: Slider(
        value: percent.toDouble(),
        max: 100,
        divisions: 20,
        label: '$percent%',
        semanticFormatterCallback: (v) => '${v.round()}%',
        onChanged: (v) {
          setState(() => percent = v.round());
          widget.store.lcdIntensity = percent / 100;
        },
      ),
    ),
  );
}

/// The LCD palette: the app's four shades and the Game Boy screen's
/// (pocket-lcd-ui.md). Kept in [settings]; [store] gets the same index for
/// the dot matrix shader.
class LcdPaletteTile extends StatelessWidget {
  const LcdPaletteTile({
    super.key,
    required this.settings,
    this.store,
    this.autofocus = false,
  });

  final ThemeSettings settings;
  final ShaderStore? store;
  final bool autofocus;

  Future<void> _pick(BuildContext context) async {
    final current = lcdUiPaletteIndex(settings.palette);
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('LCD palette'),
        children: [
          for (final (i, p) in lcdUiPalettes.indexed)
            ListTile(
              autofocus: i == current,
              selected: i == current,
              leading: _Swatch(p),
              title: Text(p.name),
              onTap: () => Navigator.of(context).pop(i),
            ),
        ],
      ),
    );
    if (picked == null) return;
    store?.lcdPalette = picked;
    settings.palette = lcdUiPalettes[picked].id;
  }

  @override
  Widget build(BuildContext context) => ListTile(
    autofocus: autofocus,
    leading: const PixelIcon(PixelGlyphs.palette),
    title: const Text('LCD palette'),
    subtitle: Text(lcdUiPalette(settings.palette).name),
    trailing: _Swatch(lcdUiPalette(settings.palette)),
    onTap: () => _pick(context),
  );
}

/// The palette's four shades side by side.
class _Swatch extends StatelessWidget {
  const _Swatch(this.p);

  final LcdPalette p;

  @override
  Widget build(BuildContext context) {
    final px = PocketMetrics.of(context).px;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface,
          width: px,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in [p.paper, p.light, p.dark, p.ink])
            Container(width: 5 * px, height: 7 * px, color: c),
        ],
      ),
    );
  }
}
