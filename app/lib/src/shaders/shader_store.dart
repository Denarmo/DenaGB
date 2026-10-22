// SPDX-License-Identifier: GPL-3.0-or-later
// The chosen shader per system and per game.
// Spec: docs/specs/shaders.md (App)
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'shader_catalog.dart';

/// `<dataDir>/shaders.json`, shaped as
/// `{"systems": {"<system>": "<id>"}, "games": {"<sha1>": "<id>"}}`, plus
/// `"upscale": {"systems": {"<system>": 2}, "games": {"<sha1>": 0}}`, and
/// `"lcd": {"intensity": 0.8, "palette": 0}` (dot-matrix.md).
/// A game override of "" is Off for that game; an upscale of 0 is the core's
/// default resolution.
///
/// The file is a few hundred bytes and is read before the first frame, so
/// it is read and written synchronously; that also keeps widget tests free of
/// real async IO.
class ShaderStore {
  ShaderStore(this.dataDir);

  final String dataDir;

  File get _file => File(p.join(dataDir, 'shaders.json'));

  _Choices _read() {
    final empty = _Choices({}, {}, {}, {}, {});
    try {
      if (!_file.existsSync()) return empty;
      final j = jsonDecode(_file.readAsStringSync());
      if (j is! Map) return empty;
      Map<String, String> strings(Object? m) => {
        if (m is Map)
          for (final e in m.entries)
            if (e.value is String) '${e.key}': e.value as String,
      };
      Map<String, int> ints(Object? m) => {
        if (m is Map)
          for (final e in m.entries)
            if (e.value is int) '${e.key}': e.value as int,
      };
      final up = j['upscale'] is Map ? j['upscale'] as Map : const {};
      return _Choices(
        strings(j['systems']),
        strings(j['games']),
        ints(up['systems']),
        ints(up['games']),
        {
          if (j['lcd'] is Map)
            for (final e in (j['lcd'] as Map).entries)
              if (e.value is num) '${e.key}': (e.value as num).toDouble(),
        },
      );
    } on Object {
      // A damaged file counts as no choices; the next save rewrites it.
      return empty;
    }
  }

  void _write(_Choices c) {
    _file.parent.createSync(recursive: true);
    _file.writeAsStringSync(
      jsonEncode({
        'systems': c.systems,
        'games': c.games,
        if (c.upSystems.isNotEmpty || c.upGames.isNotEmpty)
          'upscale': {'systems': c.upSystems, 'games': c.upGames},
        if (c.lcd.isNotEmpty) 'lcd': c.lcd,
      }),
    );
  }

  static String _known(String? id) =>
      id != null && shaderById(id) != null ? id : '';

  /// The shader for a game: its override, else the system default, else the
  /// dot matrix LCD for its system (dot-matrix.md), else Off (""). Unknown
  /// ids are Off.
  String resolve(String system, String sha1) {
    final r = _read();
    return _known(r.games[sha1] ?? r.systems[system] ?? lcdFilterFor(system));
  }

  /// The system default: its choice, else its dot matrix LCD, else Off ("").
  String systemDefault(String system) =>
      _known(_read().systems[system] ?? lcdFilterFor(system));

  /// Whether [sha1] has its own choice (possibly Off).
  bool hasGameOverride(String sha1) => _read().games.containsKey(sha1);

  /// Sets the default for [system]; "" is Off, except that a system with a
  /// dot matrix LCD only goes back to it (the filter is never off by
  /// system, dot-matrix.md).
  void setSystem(String system, String id) {
    final r = _read();
    if (id.isEmpty || id == lcdFilterFor(system)) {
      r.systems.remove(system);
    } else {
      r.systems[system] = id;
    }
    _write(r);
  }

  // ---- Dot matrix LCD (dot-matrix.md) ----

  /// How strongly the LCD filter draws, 0-1; 0.8 by default.
  double get lcdIntensity => _read().lcd['intensity'] ?? defaultLcdIntensity;

  set lcdIntensity(double v) {
    final r = _read();
    r.lcd['intensity'] = v.clamp(0.0, 1.0);
    _write(r);
  }

  /// The Game Boy screen's palette, an index into [lcdPalettes].
  int get lcdPalette =>
      (_read().lcd['palette'] ?? 0).round().clamp(0, lcdPalettes.length - 1);

  set lcdPalette(int v) {
    final r = _read();
    r.lcd['palette'] = v.clamp(0, lcdPalettes.length - 1).toDouble();
    _write(r);
  }

  /// Overrides the shader of one game; "" is Off for that game.
  void setGame(String sha1, String id) {
    final r = _read();
    r.games[sha1] = id;
    _write(r);
  }

  /// Makes the game follow its system default again.
  void clearGame(String sha1) {
    final r = _read();
    if (r.games.remove(sha1) == null) return;
    _write(r);
  }

  // ---- Internal resolution (shaders.md, Upscale) ----

  /// The factor a game starts with: its own choice, else the system default,
  /// else 0 (the core's default), capped at what the system can do.
  int resolveUpscale(String system, String sha1) {
    final r = _read();
    return _cap(system, r.upGames[sha1] ?? r.upSystems[system] ?? 0);
  }

  int systemUpscale(String system) =>
      _cap(system, _read().upSystems[system] ?? 0);

  bool hasGameUpscale(String sha1) => _read().upGames.containsKey(sha1);

  /// Sets the default for [system]; 0 removes it.
  void setSystemUpscale(String system, int factor) {
    final r = _read();
    if (factor == 0) {
      r.upSystems.remove(system);
    } else {
      r.upSystems[system] = factor;
    }
    _write(r);
  }

  void setGameUpscale(String sha1, int factor) {
    final r = _read();
    r.upGames[sha1] = factor;
    _write(r);
  }

  void clearGameUpscale(String sha1) {
    final r = _read();
    if (r.upGames.remove(sha1) == null) return;
    _write(r);
  }

  static int _cap(String system, int f) {
    final max = maxUpscale(system);
    return f < 2 || max < 2 ? 0 : (f > max ? max : f);
  }
}

class _Choices {
  _Choices(this.systems, this.games, this.upSystems, this.upGames, this.lcd);

  final Map<String, String> systems, games;
  final Map<String, int> upSystems, upGames;
  final Map<String, double> lcd;
}

/// Highest internal-resolution factor per system (shaders.md, Upscale); 1
/// when it draws only at native size. Mirrors the host's table in
/// host/runner/runner.cpp; [filterUpscale] systems use the xBRZ filter.
int maxUpscale(String system) => switch (system) {
  'n64' || 'psp' => 4,
  'gb' || 'gbc' || 'nds' => 4,
  'psx' => 2,
  _ => 1,
};

/// Systems whose core has no resolution option: 2x-4x run the frame through
/// the xBRZ pixel-art filter before the shader (shaders.md, Upscale).
bool filterUpscale(String system) => system == 'gb' || system == 'gbc';

/// Systems whose 2x-4x switch to a GPU renderer with its own requirement,
/// named in the resolution note (ds.md, Internal resolution).
String? upscaleRequirement(String system) => switch (system) {
  'nds' => 'OpenGL ES 3.2',
  _ => null,
};
