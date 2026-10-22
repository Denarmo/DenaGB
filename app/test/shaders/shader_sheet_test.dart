import 'dart:io';

import 'package:dena_emu/src/app.dart';
import 'package:dena_emu/src/shaders/shader_settings.dart';
import 'package:dena_emu/src/shaders/shader_sheet.dart';
import 'package:dena_emu/src/shaders/shader_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../session_screen_test.dart'
    show FakeGameApi, closeDb, firstGame, openPause, sessionApp;
import '../support/library_fixture.dart';
import '../support/screen_matrix.dart';

ShaderStore tempStore() {
  final dir = Directory.systemTemp.createTempSync('dena_shader_sheet');
  addTearDown(() => dir.deleteSync(recursive: true));
  return ShaderStore(dir.path);
}

Future<void> openShaders(WidgetTester tester) async {
  await openPause(tester);
  await tester.tap(find.text('Shader'));
  await tester.pumpAndSettle();
}

/// Taps the [name] entry of the open shader sheet, scrolling it into view.
Future<void> pick(WidgetTester tester, String name) async {
  final list = find
      .descendant(
        of: find.byType(ShaderSheet),
        matching: find.byType(Scrollable),
      )
      .last;
  tester.state<ScrollableState>(list).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(name), 50, scrollable: list);
  await tester.ensureVisible(find.text(name));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testScreens('shader sheet', (tester, screen, mode) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db); // a GBA game
    final store = tempStore()..setSystem('gba', 'lcd-grid');
    await tester.pumpWidget(
      sessionApp(db, game, FakeGameApi(), shaders: store),
    );
    await openShaders(tester);
    expect(find.byType(ShaderSheet), findsOneWidget);
    expect(find.text('All Game Boy Advance games'), findsOneWidget);
    expect(find.text('Suggested'), findsWidgets);
    await expectLater(
      find.byType(DenaApp),
      matchesGoldenFile(goldenName('shader_sheet', screen, mode)),
    );
    await closeDb(tester, db);
  });

  testWidgets('the saved shader is set before the game starts', (tester) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final store = tempStore()..setSystem('gba', 'lcd3x');
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api, shaders: store));
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    expect(api.calls.take(3), [
      'shader lcd3x',
      'latency 40',
      startsWith('start '),
    ]);
    expect(find.text('This shader could not be loaded'), findsNothing);
    await closeDb(tester, db);
  });

  testWidgets('no shader call when the game has none', (tester) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final store = tempStore()
      ..setSystem('gba', 'lcd3x')
      ..setGame(game.sha1, '');
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api, shaders: store));
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    expect(api.calls.first, 'latency 40');
    expect(api.calls[1], startsWith('start '));
    expect(api.calls.where((c) => c.startsWith('shader')), isEmpty);
    await closeDb(tester, db);
  });

  testWidgets('a shader that fails at start is reported and is Off', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final store = tempStore()..setSystem('gba', 'crt-geom');
    final api = FakeGameApi(shaderError: 'compile error');
    await tester.pumpWidget(sessionApp(db, game, api, shaders: store));
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    expect(api.calls.first, 'shader crt-geom');
    expect(find.text('This shader could not be loaded'), findsOneWidget);
    // The sheet shows Off as current; the saved choice is kept.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shader'));
    await tester.pumpAndSettle();
    final off = tester.widget<ListTile>(
      find.ancestor(of: find.text('Off'), matching: find.byType(ListTile)),
    );
    expect(off.selected, isTrue);
    expect(store.systemDefault('gba'), 'crt-geom');
    await closeDb(tester, db);
  });

  testWidgets('picking previews at once and saves to the chosen scope', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final store = tempStore();
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api, shaders: store));
    await openShaders(tester);

    // Default scope: every game of the system.
    await pick(tester, 'Dot matrix');
    expect(api.calls.last, 'shader dot-matrix');
    expect(store.systemDefault('gba'), 'dot-matrix');
    expect(store.hasGameOverride(game.sha1), isFalse);

    // This game only, including Off.
    await tester.tap(find.text('This game'));
    await tester.pumpAndSettle();
    await pick(tester, 'Off');
    expect(api.calls.last, 'shader ');
    expect(store.resolve('gba', game.sha1), '');
    expect(store.systemDefault('gba'), 'dot-matrix');

    // Back to all games drops the game's own choice.
    await tester.tap(find.text('All Game Boy Advance games'));
    await tester.pumpAndSettle();
    await pick(tester, 'LCD grid');
    expect(store.hasGameOverride(game.sha1), isFalse);
    expect(store.resolve('gba', game.sha1), 'lcd-grid');

    // B returns to the pause sheet.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ShaderSheet), findsNothing);
    expect(find.text('Resume'), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets('a shader failing in the sheet falls back to Off', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final store = tempStore();
    final api = FakeGameApi(shaderError: 'no GLES 3');
    await tester.pumpWidget(sessionApp(db, game, api, shaders: store));
    await openShaders(tester);
    await pick(tester, 'CRT (curved)');
    expect(api.calls.last, 'shader crt-geom');
    expect(find.text('This shader could not be loaded'), findsOneWidget);
    // Off for the system is its dot matrix LCD again.
    expect(store.systemDefault('gba'), 'pocket-lcd-color');
    await closeDb(tester, db);
  });

  testWidgets('the shader sheet is D-pad operable', (tester) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final store = tempStore();
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api, shaders: store));
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await openPause(tester);
    // Resume → Save → Load → Rewind → Cheats → Shader.
    for (var i = 0; i < 5; i++) {
      await dpad(tester, LogicalKeyboardKey.tab);
    }
    await dpad(tester, LogicalKeyboardKey.enter);
    expect(find.byType(ShaderSheet), findsOneWidget);
    // Off has focus; the next entry is the first suggested shader.
    await dpad(tester, LogicalKeyboardKey.arrowDown);
    await dpad(tester, LogicalKeyboardKey.enter);
    expect(api.calls.last, 'shader sharp-bilinear');
    expect(store.systemDefault('gba'), 'sharp-bilinear');
    await dpad(tester, LogicalKeyboardKey.escape);
    expect(find.byType(ShaderSheet), findsNothing);
    expect(find.text('Resume'), findsOneWidget);
    await closeDb(tester, db);
  });

  testScreens('shader settings', (tester, screen, mode) async {
    final db = await seededDb([]);
    final store = tempStore()
      ..setSystem('gba', 'crt-geom')
      ..setSystem('gb', 'dot-matrix');
    await tester.pumpWidget(shellApp(db, shaders: store));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      find.text('Shaders'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Shaders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shaders'));
    await tester.pumpAndSettle();
    expect(find.byType(ShaderSettingsPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Game Boy Advance'),
        matching: find.text('CRT (curved)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Game Boy'),
        matching: find.text('Dot matrix'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'DS'),
        matching: find.text('Dot matrix LCD'),
      ),
      findsOneWidget,
    );
    await expectLater(
      find.byType(DenaApp),
      matchesGoldenFile(goldenName('shader_settings', screen, mode)),
    );

    // A system opens the list in system scope; a pick updates the row.
    await tester.tap(find.text('DS'));
    await tester.pumpAndSettle();
    expect(find.text('DS shader and resolution'), findsOneWidget);
    expect(find.text('This game'), findsNothing);
    await pick(tester, 'Scanlines');
    expect(store.systemDefault('nds'), 'scanlines');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'DS'),
        matching: find.text('Scanlines'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });

  testWidgets('resolution: unsupported factors are disabled with a note', (
    tester,
  ) async {
    final store = tempStore();
    await tester.pumpWidget(
      DenaApp(
        home: Scaffold(
          body: ShaderSheet(store: store, system: 'gba'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Game Boy Advance draws at its native resolution only'),
      findsOneWidget,
    );
    await tester.tap(find.text('2x'));
    await tester.pumpAndSettle();
    expect(store.systemUpscale('gba'), 0);

    await tester.pumpWidget(
      DenaApp(
        home: Scaffold(
          body: ShaderSheet(store: store, system: 'psx'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PlayStation renders at 2x at most'), findsOneWidget);
    await tester.tap(find.text('4x'));
    await tester.pumpAndSettle();
    expect(store.systemUpscale('psx'), 0);
    await tester.tap(find.text('2x'));
    await tester.pumpAndSettle();
    expect(store.systemUpscale('psx'), 2);

    // GB and GBC go up to 4x through the xBRZ filter.
    await tester.pumpWidget(
      DenaApp(
        home: Scaffold(
          body: ShaderSheet(store: store, system: 'gbc'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Smoothed with the xBRZ pixel-art filter'),
      findsOneWidget,
    );
    await tester.tap(find.text('4x'));
    await tester.pumpAndSettle();
    expect(store.systemUpscale('gbc'), 4);

    // DS renders 3D at true 2x-4x on OpenGL ES 3.2.
    await tester.pumpWidget(
      DenaApp(
        home: Scaffold(
          body: ShaderSheet(store: store, system: 'nds'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('True 3D resolution, needs OpenGL ES 3.2'),
      findsOneWidget,
    );
    expect(find.text('Smoothed with the xBRZ pixel-art filter'), findsNothing);
    await tester.tap(find.text('3x'));
    await tester.pumpAndSettle();
    expect(store.systemUpscale('nds'), 3);
  });

  testWidgets('in a game the factor saves per scope and starts the core', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    await tester.runAsync(
      () => db.addGame(
        system: 'nds',
        title: 'Kart',
        fileName: 'Kart.nds',
        path: '/nowhere/nds',
        sha1: 'shaNds',
        size: 1,
        crc32: '0',
        addedAt: DateTime(2026, 2, 1),
      ),
    );
    final game = (await tester.runAsync(
      (db.select(db.games)..where((g) => g.system.equals('nds'))).getSingle,
    ))!;
    final store = tempStore()..setSystemUpscale('nds', 2);
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api, shaders: store));
    await openShaders(tester);
    expect(api.upscale, 2); // the system default, set before start
    await tester.tap(find.text('This game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4x'));
    await tester.pumpAndSettle();
    expect(
      find.text('The new resolution applies the next time the game starts'),
      findsOneWidget,
    );
    expect(store.resolveUpscale('nds', game.sha1), 4);
    expect(store.systemUpscale('nds'), 2);
    await closeDb(tester, db);
  });
}
