// SPDX-License-Identifier: GPL-3.0-or-later
// The bundled shaders the app offers, by id (`host/shaders/<id>/<id>.glslp`).
// Spec: docs/specs/shaders.md
class ShaderInfo {
  const ShaderInfo(this.id, this.name, this.description, this.suggestedFor);

  /// Folder and preset name under `host/shaders`; what `setShader` takes.
  final String id;
  final String name;

  /// One line saying what it looks like.
  final String description;

  /// System ids this shader suits (empty: any system).
  final Set<String> suggestedFor;

  bool suits(String system) =>
      suggestedFor.isEmpty || suggestedFor.contains(system);
}

/// In the order the spec lists them (shaders.md, Bundled shaders), the dot
/// matrix LCDs first (dot-matrix.md).
const shaderCatalog = [
  ShaderInfo(
    'pocket-lcd-dmg',
    'Dot matrix LCD',
    'Green-grey Game Boy screen with a cell grid and shadows',
    {'gb'},
  ),
  ShaderInfo(
    'pocket-lcd-color',
    'Dot matrix LCD',
    'Bright colour screen with a fine cell grid',
    {'gbc', 'gba'},
  ),
  ShaderInfo(
    'pocket-lcd-ds',
    'Dot matrix LCD',
    'Both DS screens on a dark cell grid',
    {'nds'},
  ),
  ShaderInfo(
    'sharp-bilinear',
    'Sharp pixels',
    'Crisp pixels at any scale, without shimmer',
    {},
  ),
  ShaderInfo('scanlines', 'Scanlines', 'Dark lines between pixel rows', {
    'nes',
    'snes',
    'psx',
    'n64',
  }),
  ShaderInfo('crt-fast', 'CRT (fast)', 'Light CRT look for slower devices', {
    'nes',
    'snes',
    'psx',
    'n64',
    'pico8',
  }),
  ShaderInfo('crt-lottes', 'CRT (Lottes)', 'Shadow mask and soft scanlines', {
    'nes',
    'snes',
    'psx',
  }),
  ShaderInfo('crt-easymode', 'CRT (EasyMode)', 'Flat CRT with a fine mask', {
    'nes',
    'snes',
    'psx',
  }),
  ShaderInfo(
    'crt-aperture',
    'CRT (aperture grille)',
    'Vertical stripe mask with glow',
    {'nes', 'snes', 'psx'},
  ),
  ShaderInfo('crt-geom', 'CRT (curved)', 'Curved glass and rounded corners', {
    'nes',
    'snes',
    'psx',
    'n64',
  }),
  ShaderInfo(
    'crt-bloom',
    'CRT (bloom)',
    'Curved CRT with glow and a refresh sweep',
    {'nes', 'snes', 'psx', 'n64'},
  ),
  ShaderInfo(
    'lcd-grid',
    'LCD grid',
    'Thin gaps between pixels, like a handheld screen',
    {'gb', 'gbc', 'gba', 'nds', 'psp'},
  ),
  ShaderInfo('lcd3x', 'LCD subpixels', 'Red, green and blue subpixel stripes', {
    'gb',
    'gbc',
    'gba',
  }),
  ShaderInfo(
    'dot-matrix',
    'Dot matrix',
    'Round dots of an early handheld screen',
    {'gb', 'gbc'},
  ),
];

/// The shader with [id], or null (also for "" = Off).
ShaderInfo? shaderById(String id) {
  for (final s in shaderCatalog) {
    if (s.id == id) return s;
  }
  return null;
}

/// Display name of [id]; "Off" for "" or an unknown id.
String shaderName(String id) => shaderById(id)?.name ?? 'Off';

/// [shaderCatalog] with the shaders suggested for [system] first; the
/// catalogue order is kept within each group. Another system's dot matrix
/// LCD is left out.
List<({ShaderInfo shader, bool suggested})> shadersFor(String system) => [
  for (final s in shaderCatalog)
    if (s.suits(system)) (shader: s, suggested: true),
  for (final s in shaderCatalog)
    if (!s.suits(system) && !isLcdFilter(s.id)) (shader: s, suggested: false),
];

/// The dot matrix LCD laid over every game of [system] unless the player
/// picks another shader (dot-matrix.md); "" for systems without one.
String lcdFilterFor(String system) => switch (system) {
  'gb' => 'pocket-lcd-dmg',
  'gbc' || 'gba' => 'pocket-lcd-color',
  'nds' => 'pocket-lcd-ds',
  _ => '',
};

/// Whether [id] is one of the dot matrix LCD presets.
bool isLcdFilter(String id) => id.startsWith('pocket-lcd-');

const defaultLcdIntensity = 0.8;

/// The Game Boy screen palettes, by the shader's `palette` index.
const lcdPalettes = ['Olive', 'Pocket grey', 'Backlit amber', 'Inverted'];
