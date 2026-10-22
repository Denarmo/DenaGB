import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:dena_android/dena_android.dart';
import 'package:dena_emu/src/achievements/retro_achievements.dart';
import 'package:dena_emu/src/app.dart';
import 'package:dena_emu/src/library/database.dart';
import 'package:dena_emu/src/session/session_screen.dart';
import 'package:dena_emu/src/shell/handheld.dart';
import 'package:dena_emu/src/shaders/shader_catalog.dart';
import 'package:dena_emu/src/shaders/shader_store.dart';
import 'package:dena_emu/src/skins/touch_controls.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dena_emu/src/shell/power_link.dart';

import 'support/fake_power.dart';
import 'support/library_fixture.dart';
import 'support/screen_matrix.dart';

class FakeGameApi extends GameHostApi {
  FakeGameApi({this.result, this.loadError, this.shaderError});

  final StartResult? result;
  final String? loadError;

  /// Returned by setShader for any shader but Off.
  final String? shaderError;
  final calls = <String>[];

  /// Holds start() open until completed, like a slow core load.
  Completer<void>? startGate;

  @override
  Future<StartResult> start(
    String coreLibrary,
    String romPath,
    String srmPath,
    String statePath,
  ) async {
    calls.add('start $coreLibrary $romPath $srmPath $statePath');
    if (startGate != null) await startGate!.future;
    return result ?? StartResult(outcome: StartOutcome.fresh);
  }

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> setSpeed(int speed) async => calls.add('speed $speed');
  @override
  Future<void> setAudioLatency(int ms) async => calls.add('latency $ms');
  @override
  Future<void> configureRewind(bool enabled, bool l2Hold) async =>
      calls.add('rewind config $enabled $l2Hold');
  @override
  Future<void> setRewinding(bool on) async => calls.add('rewinding $on');
  @override
  Future<void> setAnalogMode(bool on) async => calls.add('analog $on');
  @override
  Future<void> setDisplayAspect(double aspect) async =>
      calls.add('aspect ${aspect.toStringAsFixed(3)}');
  @override
  Future<void> saveNow() async => calls.add('saveNow');
  @override
  Future<String?> saveState(String statePath, String pngPath) async {
    calls.add('saveState $statePath $pngPath');
    return null;
  }

  @override
  Future<String?> loadState(String statePath) async {
    calls.add('loadState $statePath');
    return loadError;
  }

  @override
  Future<void> setTouchMode(bool on) async => calls.add('touch $on');

  @override
  Future<String?> captureScreenshot(String name) async {
    calls.add('capture $name');
    return null;
  }

  @override
  Future<void> setCheats(List<String> codes) async =>
      calls.add('cheats ${codes.join('|')}');

  @override
  Future<void> setUpscale(int factor) async {
    upscale = factor;
  }

  /// The last setUpscale factor (kept out of [calls]).
  int? upscale;

  @override
  Future<String?> setShader(String id) async {
    calls.add('shader $id');
    return id.isEmpty ? null : shaderError;
  }

  /// Shader parameters by id (kept out of [calls]).
  final params = <String, double>{};

  @override
  Future<void> setShaderParameter(String id, double value) async {
    params[id] = value;
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

/// A home page that opens the session, so Quit has somewhere to return to.
Widget sessionApp(
  LibraryDatabase db,
  Game game,
  GameHostApi api, {
  DateTime Function()? clock,
  String dataDir = '/data',
  void Function(GameEventsApi?)? registerEvents,
  ShaderStore? shaders,
  RetroAchievements? achievements,
}) => DenaApp(
  home: Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionScreen(
              game: game,
              dataDir: dataDir,
              db: db,
              api: api,
              gameView: const ColoredBox(color: Color(0xff3a7d6b)),
              clock: clock ?? DateTime.now,
              registerEvents: registerEvents ?? (_) {},
              shaders: shaders,
              achievements: achievements,
            ),
          ),
        ),
        child: const Text('library'),
      ),
    ),
  ),
);

Future<void> closeDb(WidgetTester tester, LibraryDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.runAsync(db.close);
}

/// A 4×3 red PNG, standing in for a game thumbnail.
final thumbPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGM4YWMDRww4OQArRg8Bc3oMDAAAAABJRU5ErkJggg==',
);

/// A data dir whose game `sha0` has slot 2 filled.
Directory slotDir() {
  final dir = Directory.systemTemp.createTempSync('dena_slots');
  final states = Directory(p.join(dir.path, 'states', 'sha0'))
    ..createSync(recursive: true);
  File(p.join(states.path, 'slot2.state'))
    ..writeAsBytesSync([1, 2, 3])
    ..setLastModifiedSync(DateTime(2026, 10, 16, 18, 49));
  File(p.join(states.path, 'slot2.png')).writeAsBytesSync(thumbPng);
  return dir;
}

Future<Game> firstGame(WidgetTester tester, LibraryDatabase db) async =>
    (await tester.runAsync(db.select(db.games).getSingle))!;

/// Opens the session and its pause sheet.
Future<void> openPause(WidgetTester tester) async {
  await tester.tap(find.text('library'));
  await tester.pumpAndSettle();
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> addCheat(WidgetTester tester, String name, String code) async {
  await tester.tap(find.text('Add cheat'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Name'), name);
  await tester.enterText(find.widgetWithText(TextField, 'Code'), code);
  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

Future<void> openCheats(WidgetTester tester) async {
  await openPause(tester);
  await tester.tap(find.text('Cheats'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('leaving while the core loads still stops it', (tester) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket: Quest'])))!;
    final game = await firstGame(tester, db);
    final api = FakeGameApi()..startGate = Completer<void>();
    await tester.pumpWidget(sessionApp(db, game, api));
    await tester.tap(find.text('library'));
    for (var i = 0; i < 50 && api.calls.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(api.calls.last, startsWith('start '));
    await tester.pumpWidget(const SizedBox());
    api.startGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(api.calls.last, 'stop');
    await closeDb(tester, db);
  });

  testWidgets('the dot matrix LCD is on from the first frame', (tester) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api));
    await openPause(tester);
    final start = api.calls.indexWhere((c) => c.startsWith('start '));
    final lcd = api.calls.indexOf('shader ${lcdFilterFor(game.system)}');
    expect(lcd, isNonNegative);
    expect(lcd, lessThan(start));
    expect(api.params['intensity'], closeTo(defaultLcdIntensity, 1e-9));
    expect(api.params['palette'], 0);
    await closeDb(tester, db);
  });

  testWidgets('Capture saves a named screenshot and keeps the sheet open', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket: Quest'])))!;
    final game = await firstGame(tester, db);
    final api = FakeGameApi();
    await tester.pumpWidget(
      sessionApp(db, game, api, clock: () => DateTime(2026, 10, 16, 18, 5, 9)),
    );
    await openPause(tester);
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'capture Pocket_ Quest 2026-10-16 18.05.09');
    expect(find.text('Screenshot saved'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets('the pause sheet is D-pad operable in order', (tester) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    await tester.pumpWidget(sessionApp(db, game, FakeGameApi()));
    await openPause(tester);
    String? focusedLabel() {
      final f = FocusManager.instance.primaryFocus?.context;
      if (f == null) return null;
      final texts = find.descendant(
        of: find.byWidget(f.widget),
        matching: find.byType(Text),
      );
      return texts.evaluate().isEmpty
          ? null
          : (texts.evaluate().first.widget as Text).data;
    }

    final order = <String?>[focusedLabel()];
    for (var i = 0; i < 7; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(focusedLabel());
    }
    expect(order, [
      'Resume',
      'Save',
      'Load',
      'Rewind',
      'Cheats',
      'Shader',
      'Capture',
      'Quit',
    ]);
    await closeDb(tester, db);
  });

  testWidgets('Rewind plays backwards until a tap', (tester) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = (await tester.runAsync(db.select(db.games).getSingle))!;
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api));
    await openPause(tester);
    api.calls.clear();
    await tester.tap(find.text('Rewind'));
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsNothing);
    expect(api.calls, ['resume', 'rewinding true']);
    expect(find.text('Rewinding · tap to stop'), findsOneWidget);

    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'rewinding false');
    expect(find.text('Rewinding · tap to stop'), findsNothing);
    await closeDb(tester, db);
  });

  testScreens('cheats sheet', (tester, screen, mode) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    await tester.runAsync(() async {
      await db.addCheat(
        gameId: game.id,
        name: 'Infinite lives',
        code: '82003DF4 0063',
        format: 'CodeBreaker',
        createdAt: DateTime(2026),
      );
      final id = await db.addCheat(
        gameId: game.id,
        name: 'Max money',
        code: '12345678 9ABCDEF0\n02000000 00000063',
        format: 'GameShark / Action Replay',
        createdAt: DateTime(2026),
      );
      await db.setCheatEnabled(id, false);
    });
    await tester.pumpWidget(sessionApp(db, game, FakeGameApi()));
    await openCheats(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Infinite lives'), findsOneWidget);
    await expectLater(
      find.byType(DenaApp),
      matchesGoldenFile(goldenName('cheats_sheet', screen, mode)),
    );
    await closeDb(tester, db);
  });

  testWidgets('adding, toggling and deleting cheats updates the core', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db); // a GBA game
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api));
    await openCheats(tester);
    expect(find.textContaining('No cheats yet'), findsOneWidget);

    await addCheat(tester, 'Bad', 'SXIOPO');
    expect(
      find.text("This doesn't look like a Game Boy Advance code"),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await addCheat(tester, 'Lives', '82003df4 0063');
    expect(api.calls.last, 'cheats 82003DF4 0063');
    expect(find.text('Lives'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(api.calls.last, 'cheats ');

    await tester.tap(find.byTooltip('Delete Lives'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lives'), findsNothing);
    await closeDb(tester, db);
  });

  testWidgets('enabled cheats are applied when the game starts', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    await tester.runAsync(
      () => db.addCheat(
        gameId: game.id,
        name: 'L',
        code: '82003DF4 0063\n12345678 9ABCDEF0',
        format: 'Mixed',
        createdAt: DateTime(2026),
      ),
    );
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api));
    await tester.tap(find.text('library'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(api.calls, contains('cheats 82003DF4 0063+12345678 9ABCDEF0'));
    await closeDb(tester, db);
  });

  testScreens('pause sheet with two controllers', (tester, screen, mode) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    GameEventsApi? events;
    await tester.pumpWidget(
      sessionApp(db, game, FakeGameApi(), registerEvents: (e) => events = e),
    );
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    events!.onPlayersChanged([
      'Xbox Wireless Controller',
      '8BitDo SN30 Pro',
      '',
      '',
    ]);
    events!.onMenuRequested();
    await tester.pumpAndSettle();
    expect(find.text('P1 · Xbox Wireless Controller'), findsOneWidget);
    expect(find.text('P2 · 8BitDo SN30 Pro'), findsOneWidget);
    await expectLater(
      find.byType(DenaApp),
      matchesGoldenFile(goldenName('pause_sheet_players', screen, mode)),
    );
    await closeDb(tester, db);
  });

  testWidgets('an external display takes the picture; the skin stays', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final api = FakeGameApi();
    GameEventsApi? events;
    await tester.pumpWidget(
      sessionApp(db, game, api, registerEvents: (e) => events = e),
    );
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    events!.onExternalDisplayChanged('TV');
    await tester.pump();
    expect(find.text('Playing on TV'), findsOneWidget);
    expect(find.byType(SkinView), findsOneWidget);
    events!.onExternalDisplayChanged(null);
    await tester.pump();
    expect(find.text('Playing on TV'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await closeDb(tester, db);
  });

  testWidgets('the system bars stay hidden in both orientations', (
    tester,
  ) async {
    final modes = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(896, 414);
    addTearDown(tester.view.reset);
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    await tester.pumpWidget(sessionApp(db, game, FakeGameApi()));
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    expect(modes.last, 'SystemUiMode.immersiveSticky');
    tester.view.physicalSize = const Size(414, 896);
    await tester.pumpAndSettle();
    expect(modes.last, 'SystemUiMode.immersiveSticky');
    // Leaving the game gives the bars back.
    await tester.pumpWidget(const SizedBox());
    expect(modes.last, 'SystemUiMode.edgeToEdge');
    await closeDb(tester, db);
  });

  testWidgets('a controller disconnect pauses with a message', (tester) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final api = FakeGameApi();
    GameEventsApi? events;
    await tester.pumpWidget(
      sessionApp(db, game, api, registerEvents: (e) => events = e),
    );
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    events!.onControllerDisconnected(1, '8BitDo SN30 Pro');
    await tester.pumpAndSettle();
    expect(api.calls.last, 'pause');
    expect(find.text('Controller 2 disconnected'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    // A second event while the sheet is open does not stack another sheet.
    events!.onMenuRequested();
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(events, isNull);
    await closeDb(tester, db);
  });

  testScreens('load-state slot sheet', (tester, screen, mode) async {
    final dir = slotDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    await tester.pumpWidget(
      sessionApp(db, game, FakeGameApi(), dataDir: dir.path),
    );
    await openPause(tester);
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    // Let the thumbnail decode.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DenaApp),
      matchesGoldenFile(goldenName('slot_sheet_load', screen, mode)),
    );
    await closeDb(tester, db);
  });

  testWidgets('saving to a slot writes state and thumbnail, then resumes', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api));
    await openPause(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Empty'), findsNWidgets(10));
    await tester.tap(find.text('Slot 3'));
    await tester.pumpAndSettle();
    expect(api.calls.sublist(api.calls.length - 2), [
      'saveState /data/states/sha0/slot3.state /data/states/sha0/slot3.png',
      'resume',
    ]);
    expect(find.text('Saved to slot 3'), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets('empty slots cannot be loaded; a filled one loads', (
    tester,
  ) async {
    final dir = slotDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api, dataDir: dir.path));
    await openPause(tester);
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slot 1'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'pause');
    await tester.tap(find.text('Slot 2'));
    await tester.pumpAndSettle();
    expect(api.calls.sublist(api.calls.length - 2), [
      'loadState ${p.posix.join(dir.path, 'states', 'sha0', 'slot2.state')}',
      'resume',
    ]);
    expect(find.text('Loaded slot 2'), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets('a failed load keeps the game paused', (tester) async {
    final dir = slotDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final api = FakeGameApi(loadError: 'Wrong core version');
    await tester.pumpWidget(sessionApp(db, game, api, dataDir: dir.path));
    await openPause(tester);
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slot 2'));
    await tester.pumpAndSettle();
    expect(api.calls.last, startsWith('loadState'));
    expect(find.text('Wrong core version'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await closeDb(tester, db);
  });

  testScreens('pause sheet', (tester, screen, mode) async {
    final db = await tester.runAsync(() => seededDb(['Pocket Quest']));
    final game = (await tester.runAsync(db!.select(db.games).getSingle))!;
    await tester.pumpWidget(sessionApp(db, game, FakeGameApi()));
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    await expectLater(
      find.byType(DenaApp),
      matchesGoldenFile(goldenName('pause_sheet', screen, mode)),
    );
    await closeDb(tester, db);
  });

  testWidgets('starts with save paths, pauses on Back, resumes on B', (
    tester,
  ) async {
    final db = await tester.runAsync(() => seededDb(['Pocket Quest']));
    final game = (await tester.runAsync(db!.select(db.games).getSingle))!;
    final api = FakeGameApi();
    await tester.pumpWidget(sessionApp(db, game, api));
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    expect(api.calls, [
      'shader pocket-lcd-color',
      'latency 40',
      'start libmgba_libretro.so /nowhere/0 /data/saves/sha0.srm '
          '/data/states/sha0/auto.state',
      'touch true',
      'rewind config true true',
      'analog false',
      'aspect 1.500',
    ]);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(api.calls.last, 'pause');
    expect(find.text('Resume'), findsOneWidget);

    // B (Escape on a keyboard) closes the sheet and resumes.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(api.calls.last, 'resume');
    expect(find.text('Resume'), findsNothing);
    await closeDb(tester, db);
  });

  testWidgets('speed and quit by D-pad record play time', (tester) async {
    final db = await tester.runAsync(() => seededDb(['Pocket Quest']));
    final game = (await tester.runAsync(db!.select(db.games).getSingle))!;
    final api = FakeGameApi();
    var now = DateTime(2026, 5, 1, 12);
    await tester.pumpWidget(sessionApp(db, game, api, clock: () => now));
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    now = now.add(const Duration(minutes: 3));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('2X'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'speed 2');

    await tester.tap(find.text('Quit'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'stop');
    expect(find.text('library'), findsOneWidget);
    final after = (await tester.runAsync(db.select(db.games).getSingle))!;
    expect(after.playSeconds, 180);
    expect(after.lastPlayedAt, now);
    await closeDb(tester, db);
  });

  testWidgets('a rejected auto-save says the game starts fresh', (
    tester,
  ) async {
    final db = await tester.runAsync(() => seededDb(['Pocket Quest']));
    final game = (await tester.runAsync(db!.select(db.games).getSingle))!;
    final api = FakeGameApi(
      result: StartResult(outcome: StartOutcome.badState),
    );
    await tester.pumpWidget(sessionApp(db, game, api));
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    expect(find.textContaining("couldn't be restored"), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets('a start error offers the way back', (tester) async {
    final db = await tester.runAsync(() => seededDb(['Pocket Quest']));
    final game = (await tester.runAsync(db!.select(db.games).getSingle))!;
    final api = FakeGameApi(result: StartResult(error: 'bad ROM'));
    await tester.pumpWidget(sessionApp(db, game, api));
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    expect(find.text('bad ROM'), findsOneWidget);
    await tester.tap(find.text('Back to library'));
    await tester.pumpAndSettle();
    expect(find.text('library'), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets('handheld sleep saves the game; waking opens the pause sheet', (
    tester,
  ) async {
    final db = await tester.runAsync(() => seededDb(['Pocket Quest']));
    final game = (await tester.runAsync(db!.select(db.games).getSingle))!;
    final api = FakeGameApi();
    final ch = FakePowerChannel();
    final link = PowerLink(ch);
    await tester.pumpWidget(
      PowerScope(link: link, child: sessionApp(db, game, api)),
    );
    // In the library, a sleep has nothing to save.
    ch.incoming.add('save');
    await tester.pump();
    await tester.pump();
    expect(ch.sent, ['saved']);
    expect(api.calls, isEmpty);

    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    api.calls.clear();
    ch.incoming.add('save');
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(api.calls, ['pause', 'saveNow']);
    expect(ch.sent, ['saved', 'saved']);

    ch.incoming.add('resumed');
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'resume');
    await tester.runAsync(link.close);
    await closeDb(tester, db);
  });

  testWidgets('handhelds never show a touch skin', (tester) async {
    final db = (await tester.runAsync(() => seededDb(['Pocket Quest'])))!;
    final game = await firstGame(tester, db);
    final api = FakeGameApi();
    GameEventsApi? events;
    await tester.pumpWidget(
      Handheld(
        enabled: true,
        child: sessionApp(db, game, api, registerEvents: (e) => events = e),
      ),
    );
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    expect(find.byType(SkinView), findsNothing);
    expect(api.calls, contains('touch false'));
    // A tap on the screen does not bring a skin back.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(SkinView), findsNothing);
    // The launcher reports no players: the built-in controls are player 1.
    events!.onMenuRequested();
    await tester.pumpAndSettle();
    expect(find.textContaining('Built-in controls'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await closeDb(tester, db);
  });

  test('cutoutInsets pushes the edge nearest each cutout', () {
    const size = Size(400, 800);
    expect(
      cutoutInsets(
        const [
          DisplayFeature(
            bounds: Rect.fromLTWH(180, 0, 40, 36),
            type: DisplayFeatureType.cutout,
            state: DisplayFeatureState.unknown,
          ),
        ],
        EdgeInsets.zero,
        size,
      ),
      const EdgeInsets.only(top: 36),
    );
    expect(
      cutoutInsets(const [], const EdgeInsets.only(top: 24), size),
      const EdgeInsets.only(top: 24),
    );
  });
}
