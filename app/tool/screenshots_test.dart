// Renders the README screenshots with the app's own fonts and made-up game
// names (no box art, no ROMs). Not part of CI:
//   flutter test tool/screenshots_test.dart --update-goldens
// then copy the shots from tool/screenshots/ to docs/screenshots/.
import 'dart:io';

import 'package:dena_emu/src/app.dart';
import 'package:dena_emu/src/library/database.dart';
import 'package:dena_emu/src/library/file_explorer.dart';
import 'package:dena_emu/src/library/library_scope.dart';
import 'package:dena_emu/src/shell/handheld.dart';
import 'package:dena_emu/src/ui/dena_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../test/session_screen_test.dart' show FakeGameApi, sessionApp;
import '../test/support/library_fixture.dart';

/// Loads a font bundled with the app (assets/fonts/...).
Future<void> loadAppFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()),
      ),
    );
  }
  await loader.load();
}

/// Lets real file I/O finish, then rebuilds.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() async {
    await loadAppFont('Roboto', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
        'roboto/Roboto-$w.ttf',
    ]);
    await loadAppFont('Nunito', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'])
        'nunito/Nunito-$w.ttf',
    ]);
    await loadAppFont('PressStart2P', [
      'press_start_2p/PressStart2P-Regular.ttf',
    ]);
    await loadAppFont('Silkscreen', [
      'silkscreen/Silkscreen-Regular.ttf',
      'silkscreen/Silkscreen-Bold.ttf',
    ]);
    await loadAppFont('DenaIcons', ['dena_icons/DenaIcons.otf']);
  });

  Future<void> shoot(
    WidgetTester tester,
    Widget app,
    String name, {
    Size size = const Size(412, 915),
    double ratio = 2.625,
    Future<void> Function()? before,
  }) async {
    // flutter_test draws shadows as black outlines unless this is off.
    debugDisableShadows = false;
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await before?.call();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp).first,
      matchesGoldenFile('screenshots/$name.png'),
    );
    debugDisableShadows = true; // the test binding checks it is restored
  }

  // Made-up games, one system each in turn.
  const titles = [
    'Moonlight Quest',
    'Pixel Garden',
    'Star Courier',
    'Twin Lantern',
    'Moss Runner',
    'Bubble Garden',
    'Tiny Tactics',
    'Cave Runner',
    'Neon Golf',
    'Robo Rally',
  ];
  const systems = ['gb', 'gbc', 'gba', 'nds'];

  Future<LibraryDatabase> library() async {
    final db = await seededDb(titles);
    for (final (i, t) in titles.indexed) {
      await db.customStatement(
        "UPDATE games SET system = '${systems[i % systems.length]}' "
        "WHERE title = '$t'",
      );
    }
    return db;
  }

  Future<void> close(WidgetTester tester, LibraryDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  }

  testWidgets('library', (tester) async {
    final db = await library();
    await shoot(tester, shellApp(db), 'library');
    await close(tester, db);
  });

  testWidgets('settings', (tester) async {
    final db = await library();
    await shoot(
      tester,
      shellApp(db),
      'settings',
      before: () async {
        await tester.tap(find.text('SETTINGS'));
        await settle(tester);
      },
    );
    await close(tester, db);
  });

  testWidgets('LCD palette picker', (tester) async {
    final db = await library();
    await shoot(
      tester,
      shellApp(db),
      'palette',
      before: () async {
        await tester.tap(find.text('SETTINGS'));
        await settle(tester);
        await tester.tap(find.text('LCD palette'));
        await tester.pumpAndSettle();
      },
    );
    await close(tester, db);
  });

  testWidgets('file browser', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('shots');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final roms = p.join(tmp.path, 'Roms');
    for (final f in [
      'Moonlight Quest.gb',
      'Pixel Garden.gbc',
      'Star Courier.gba',
      'Twin Lantern.nds',
      'Moss Runner.gbc',
      'Neon Golf.gba',
    ]) {
      File(p.join(roms, f))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    Directory(p.join(roms, 'Homebrew')).createSync();
    await shoot(
      tester,
      DenaApp(
        home: Handheld(
          enabled: false,
          child: FileExplorerPage(
            roots: [ExplorerRoot('Games card', tmp.path, DenaIcons.folder)],
            folderMode: false,
            extensions: importExtensions,
          ),
        ),
      ),
      'file-browser',
      before: () async {
        await settle(tester);
        await tester.tap(find.text('Roms'));
        await settle(tester);
      },
    );
  });

  testWidgets('pause menu', (tester) async {
    final db = await seededDb(['Moonlight Quest']);
    await db.customStatement("UPDATE games SET system = 'gb'");
    final game = await db.select(db.games).getSingle();
    await shoot(
      tester,
      sessionApp(db, game, FakeGameApi()),
      'pause-menu',
      before: () async {
        await tester.tap(find.text('library'));
        await tester.pumpAndSettle();
        await systemBack(tester);
        await tester.pumpAndSettle();
      },
    );
    await close(tester, db);
  });
}

/// Presses the system back button (the session opens its pause menu).
Future<void> systemBack(WidgetTester tester) =>
    // tool/ isn't test/, so the analyzer doesn't treat this as a test.
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    tester.binding.handlePopRoute();
