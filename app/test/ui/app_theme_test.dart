import 'dart:io';

import 'package:dena_emu/src/app.dart';
import 'package:dena_emu/src/shell/platform_features.dart';
import 'package:dena_emu/src/ui/app_theme.dart';
import 'package:dena_emu/src/shaders/lcd_settings.dart';
import 'package:dena_emu/src/ui/pocket.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('schemes', () {
    test('Dena gold: gold is the dark primary and the light container', () {
      final dark = denaScheme(Brightness.dark);
      final light = denaScheme(Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(dark.primary, denaAccent);
      expect(light.primaryContainer, denaAccent);
      // On white, light-mode primary must not be the bright gold itself.
      expect(light.primary, isNot(denaAccent));
    });

    final palettes = [denaPalette, for (final t in consoleThemes) t.id];
    for (final id in palettes) {
      for (final b in Brightness.values) {
        test('$id ${b.name}: text stays readable (WCAG AA)', () {
          final s = paletteScheme(id, b);
          expect(s.brightness, b);
          void aa(Color fg, Color bg, String what, [double min = 4.5]) =>
              expect(
                contrastRatio(fg, bg),
                greaterThanOrEqualTo(min),
                reason: '$what on $id ${b.name}',
              );
          aa(s.onSurface, s.surface, 'onSurface');
          aa(s.onSurfaceVariant, s.surfaceContainer, 'onSurfaceVariant');
          aa(s.primary, s.surface, 'primary text');
          aa(s.primary, s.surfaceContainer, 'primary text on cards');
          aa(s.onPrimary, s.primary, 'onPrimary');
          aa(s.onPrimaryContainer, s.primaryContainer, 'onPrimaryContainer');
          aa(s.onSecondaryContainer, s.secondaryContainer, 'nav indicator');
          aa(s.onTertiaryContainer, s.tertiaryContainer, 'tertiaryContainer');
          aa(s.onErrorContainer, s.errorContainer, 'errorContainer');
          // Focus rings and outlines: non-text contrast 3:1.
          aa(s.primary, s.surfaceContainerHigh, 'focus ring', 3);
        });
      }
    }

    test(
      'Material You falls back to Dena gold without a wallpaper palette',
      () {
        expect(
          paletteScheme(dynamicPalette, Brightness.dark).primary,
          denaAccent,
        );
        final wall = ColorScheme.fromSeed(seedColor: const Color(0xFF00AA55));
        expect(
          paletteScheme(dynamicPalette, Brightness.light, dynamic: wall),
          same(wall),
        );
      },
    );

    test('every console theme names a bundled skin edition', () {
      final ids = consoleThemes.map((t) => t.id).toSet();
      expect(ids.length, consoleThemes.length);
      for (final t in consoleThemes) {
        expect(t.id == t.system || t.id.startsWith('${t.system}_'), isTrue);
      }
    });
  });

  group('ThemeSettings', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('theme'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('defaults to dark Dena gold and round-trips the file', () {
      final file = File('${dir.path}/theme.json');
      final s = ThemeSettings.load(file);
      expect(s.mode, ThemeMode.dark);
      expect(s.palette, denaPalette);
      s
        ..mode = ThemeMode.light
        ..palette = 'gbc_berry';
      final again = ThemeSettings.load(file);
      expect(again.mode, ThemeMode.light);
      expect(again.palette, 'gbc_berry');
    });

    test('a damaged file or unknown palette gives the defaults', () {
      final file = File('${dir.path}/theme.json')..writeAsStringSync('{"mode"');
      expect(ThemeSettings.load(file).mode, ThemeMode.dark);
      file.writeAsStringSync('{"mode":"system","palette":"nope"}');
      final s = ThemeSettings.load(file);
      expect(s.mode, ThemeMode.system);
      expect(s.palette, denaPalette);
      s.palette = 'nope';
      expect(s.palette, denaPalette);
    });
  });

  // Dena.emu GB draws every screen on the Pocket LCD (pocket-lcd-ui.md).
  testWidgets('the app starts on the Olive LCD with pixel fonts', (
    tester,
  ) async {
    await tester.pumpWidget(const DenaApp(home: Scaffold()));
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.colorScheme.surface, const Color(0xFFC5D48A));
    expect(theme.colorScheme.onSurface, const Color(0xFF1B2E17));
    expect(theme.textTheme.titleLarge?.fontFamily, pocketTitleFont);
    expect(theme.textTheme.bodyMedium?.fontFamily, pocketBodyFont);
    expect(
      PocketStyle.of(tester.element(find.byType(Scaffold))).colourCovers,
      isFalse,
    );
  });

  testWidgets('choosing an LCD palette restyles the app', (tester) async {
    final settings = ThemeSettings();
    await tester.pumpWidget(
      DenaApp(
        theme: settings,
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                LcdPaletteTile(settings: ThemeScope.of(context).notifier!),
          ),
        ),
      ),
    );
    await tester.tap(find.text('LCD palette'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backlit amber'));
    await tester.pumpAndSettle();
    expect(settings.palette, 'amber');
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.colorScheme.surface, const Color(0xFFFFB63B));
    expect(find.text('Backlit amber'), findsOneWidget);
  });

  test('palette ids map to the shader palette index', () {
    expect(lcdUiPaletteIndex('olive'), 0);
    expect(lcdUiPaletteIndex('inverted'), 3);
    expect(lcdUiPaletteIndex('dena'), 0);
    expect(lcdUiPalette('inverted').inverted, isTrue);
    expect(lcdUiPalette('nope').id, 'olive');
  });

  test('colour covers round-trip the file', () {
    final dir = Directory.systemTemp.createTempSync('dena_theme');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/theme.json');
    ThemeSettings.load(file).colourCovers = true;
    expect(ThemeSettings.load(file).colourCovers, isTrue);
  });

  group('without the Android shell (Linux handheld)', () {
    setUp(() => hasAndroidShell = false);
    tearDown(() => hasAndroidShell = true);

    testWidgets('the LCD palette, and no platform palette is asked for', (
      tester,
    ) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('io.material.plugins/dynamic_color'),
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      final settings = ThemeSettings()..palette = 'grey';
      await tester.pumpWidget(DenaApp(theme: settings, home: const Scaffold()));
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.colorScheme.surface, const Color(0xFFCDCEC5));
      expect(calls, isEmpty);
    });
  });
}
