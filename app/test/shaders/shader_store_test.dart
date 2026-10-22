import 'dart:convert';
import 'dart:io';

import 'package:dena_emu/src/shaders/shader_catalog.dart';
import 'package:dena_emu/src/shaders/shader_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dena_shaders'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a missing file resolves to Off', () {
    final store = ShaderStore(p.join(dir.path, 'nested'));
    expect(store.resolve('nes', 'abc'), '');
    expect(store.systemDefault('nes'), '');
    expect(store.hasGameOverride('abc'), isFalse);
  });

  test('game override > system default > Off, and it round-trips', () {
    ShaderStore(dir.path)
      ..setSystem('nes', 'crt-fast')
      ..setGame('g1', 'scanlines')
      ..setGame('g2', '');
    final again = ShaderStore(dir.path);
    expect(again.resolve('nes', 'g1'), 'scanlines');
    expect(again.resolve('nes', 'g2'), '', reason: '"" is Off for that game');
    expect(again.resolve('nes', 'g3'), 'crt-fast');
    expect(again.resolve('snes', 'g3'), '');
    expect(again.hasGameOverride('g2'), isTrue);

    again
      ..clearGame('g2')
      ..setSystem('nes', '');
    expect(ShaderStore(dir.path).resolve('nes', 'g2'), '');
    expect(ShaderStore(dir.path).hasGameOverride('g2'), isFalse);
    expect(ShaderStore(dir.path).resolve('nes', 'g1'), 'scanlines');
  });

  test('the file has the documented shape', () {
    ShaderStore(dir.path)
      ..setSystem('gb', 'dot-matrix')
      ..setGame('g1', '');
    expect(
      File(p.join(dir.path, 'shaders.json')).readAsStringSync(),
      '{"systems":{"gb":"dot-matrix"},"games":{"g1":""}}',
    );
  });

  test('upscale: game > system > default, capped per system', () {
    final store = ShaderStore(dir.path)
      ..setSystem('n64', 'crt-fast')
      ..setSystemUpscale('n64', 3)
      ..setGameUpscale('g2', 0)
      ..setSystemUpscale('psx', 4)
      ..setSystemUpscale('gba', 2);
    expect(store.resolveUpscale('n64', 'g1'), 3);
    expect(store.resolveUpscale('n64', 'g2'), 0);
    expect(store.resolveUpscale('psx', 'g1'), 2); // PSX does 2x at most
    expect(store.resolveUpscale('gba', 'g1'), 0); // native only
    expect(store.resolve('n64', 'g1'), 'crt-fast'); // shaders untouched
    store
      ..clearGameUpscale('g2')
      ..setSystemUpscale('n64', 0);
    expect(store.resolveUpscale('n64', 'g2'), 0);
    expect(store.hasGameUpscale('g2'), isFalse);
    expect(
      jsonDecode(File(p.join(dir.path, 'shaders.json')).readAsStringSync()),
      {
        'systems': {'n64': 'crt-fast'},
        'games': <String, Object>{},
        'upscale': {
          'systems': {'psx': 4, 'gba': 2},
          'games': <String, Object>{},
        },
      },
    );
    expect(maxUpscale('psp'), 4);
    expect(maxUpscale('nes'), 1);
    // GB and GBC upscale through the filter; GBA shares GB's core but stays
    // native. DS renders true 3D resolution on OpenGL ES.
    for (final s in ['gb', 'gbc']) {
      expect(maxUpscale(s), 4, reason: s);
      expect(filterUpscale(s), isTrue, reason: s);
    }
    expect(maxUpscale('gba'), 1);
    expect(filterUpscale('n64'), isFalse);
    expect(maxUpscale('nds'), 4);
    expect(filterUpscale('nds'), isFalse);
    expect(upscaleRequirement('nds'), 'OpenGL ES 3.2');
    expect(upscaleRequirement('n64'), isNull);
  });

  test('unknown ids and damaged files are Off', () {
    final file = File(p.join(dir.path, 'shaders.json'));
    file.writeAsStringSync(
      '{"systems": {"nes": "crt-gone", "gb": 3}, "games": {"g": "nope"}}',
    );
    final store = ShaderStore(dir.path);
    expect(store.resolve('nes', 'x'), '');
    // A damaged entry falls back to the system's dot matrix LCD.
    expect(store.resolve('gb', 'x'), 'pocket-lcd-dmg');
    expect(store.resolve('nes', 'g'), '');

    file.writeAsStringSync('{"systems": ');
    expect(store.resolve('nes', 'x'), '');
    file.writeAsStringSync('[]');
    expect(store.resolve('nes', 'x'), '');
    // Saving over a damaged file starts it afresh.
    store.setSystem('nes', 'crt-geom');
    expect(store.resolve('nes', 'x'), 'crt-geom');
  });

  test('catalog ids match the presets in host/shaders', () {
    final root = Directory(p.join('..', 'host', 'shaders'));
    final folders = [
      for (final d in root.listSync())
        // "_upscale" is the upscale filter, not a user shader.
        if (d is Directory && !p.basename(d.path).startsWith('_'))
          p.basename(d.path),
    ]..sort();
    expect(shaderCatalog.map((s) => s.id).toList()..sort(), folders);
    for (final id in folders) {
      expect(
        File(p.join(root.path, id, '$id.glslp')).existsSync(),
        isTrue,
        reason: '$id/$id.glslp',
      );
    }
  });

  test('suggested shaders come first for a system', () {
    final gb = shadersFor('gb');
    expect(
      [
        for (final e in gb)
          if (e.suggested) e.shader.id,
      ],
      ['pocket-lcd-dmg', 'sharp-bilinear', 'lcd-grid', 'lcd3x', 'dot-matrix'],
    );
    // Less the GBC/GBA and DS LCDs.
    expect(gb.length, shaderCatalog.length - 2);
    expect(gb.skipWhile((e) => e.suggested).every((e) => !e.suggested), isTrue);
    expect(shaderById('crt-geom')!.name, 'CRT (curved)');
    expect(shaderById(''), isNull);
    expect(shaderName('nope'), 'Off');
  });

  group('dot matrix LCD', () {
    test('is the default for every GB-family and DS game', () {
      final store = ShaderStore(dir.path);
      expect(store.resolve('gb', 'g'), 'pocket-lcd-dmg');
      expect(store.resolve('gbc', 'g'), 'pocket-lcd-color');
      expect(store.resolve('gba', 'g'), 'pocket-lcd-color');
      expect(store.resolve('nds', 'g'), 'pocket-lcd-ds');
      expect(store.systemDefault('gb'), 'pocket-lcd-dmg');
    });

    test('another pick replaces it; Off for a system goes back to it', () {
      final store = ShaderStore(dir.path)..setSystem('gba', 'crt-geom');
      expect(store.resolve('gba', 'g'), 'crt-geom');
      store.setSystem('gba', '');
      expect(store.resolve('gba', 'g'), 'pocket-lcd-color');
      store.setGame('g', '');
      expect(store.resolve('gba', 'g'), '', reason: 'a game can still be Off');
    });

    test('intensity and palette are saved and clamped', () {
      final store = ShaderStore(dir.path);
      expect(store.lcdIntensity, defaultLcdIntensity);
      expect(store.lcdPalette, 0);
      store
        ..lcdIntensity = 0.35
        ..lcdPalette = 2
        ..setSystem('gb', 'lcd3x');
      final again = ShaderStore(dir.path);
      expect(again.lcdIntensity, closeTo(0.35, 1e-9));
      expect(again.lcdPalette, 2);
      expect(again.resolve('gb', 'x'), 'lcd3x', reason: 'other choices kept');
      again
        ..lcdIntensity = 3
        ..lcdPalette = 9;
      expect(again.lcdIntensity, 1);
      expect(again.lcdPalette, lcdPalettes.length - 1);
    });

    test("the shader list leaves out other systems' LCDs", () {
      final ids = shadersFor('gb').map((e) => e.shader.id).toList();
      expect(ids.first, 'pocket-lcd-dmg');
      expect(ids, isNot(contains('pocket-lcd-ds')));
      expect(ids, isNot(contains('pocket-lcd-color')));
    });
  });
}
