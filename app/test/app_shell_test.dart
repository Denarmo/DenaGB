import 'package:dena_emu/src/library/database.dart';
import 'package:dena_emu/src/library/games_tab.dart';
import 'package:flutter/services.dart';
import 'package:dena_emu/src/ui/pixel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/library_fixture.dart';
import 'support/screen_matrix.dart';

const _titles = ['Alpha Quest', 'Beta Racer', 'Gamma Golf'];

/// Unmounts the app so Drift's stream-cancel timers run, then closes the db.
Future<void> finish(WidgetTester tester, LibraryDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.runAsync(db.close);
}

Future<void> settle(WidgetTester tester) async {
  // Drift streams resolve asynchronously; let them deliver, then settle.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

/// The primary outline a focused [GameCard] draws around its box in D-pad
/// mode.
/// The pixel corner brackets a focused card draws in D-pad mode.
bool _hasRing(WidgetTester tester, Finder card) => tester
    .widget<PixelBrackets>(
      find.descendant(of: card, matching: find.byType(PixelBrackets)),
    )
    .visible;

void main() {
  testScreens('focused game card shows a ring only in D-pad mode', (
    tester,
    screen,
    mode,
  ) async {
    final db = await seededDb(_titles);
    await tester.pumpWidget(shellApp(db));
    await settle(tester);
    final first = find.byType(GameCard).first;
    expect(_hasRing(tester, first), mode == InputMode.focus);
    await finish(tester, db);
  }, sizes: const [handheld4x3]);

  testScreens('empty library', (tester, screen, mode) async {
    final db = await seededDb([]);
    await tester.pumpWidget(shellApp(db));
    await settle(tester);
    expect(find.text('No games yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(goldenName('games_empty', screen, mode)),
    );
    await finish(tester, db);
  });

  testScreens('library with games', (tester, screen, mode) async {
    final db = await seededDb(_titles);
    await tester.pumpWidget(shellApp(db));
    await settle(tester);
    expect(find.byType(GameCard), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(goldenName('games_three', screen, mode)),
    );
    await finish(tester, db);
  });

  testScreens('large library scrolls without overflow', (
    tester,
    screen,
    mode,
  ) async {
    final db = await seededDb([for (var i = 0; i < 40; i++) 'Game number $i']);
    await tester.pumpWidget(shellApp(db));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await finish(tester, db);
  }, modes: const [InputMode.touch]);

  testWidgets('search and system chips filter the grid', (tester) async {
    final db = await seededDb(_titles); // gba, snes, nes
    await tester.pumpWidget(shellApp(db));
    await settle(tester);
    await tester.enterText(find.byType(SearchBar), 'beta');
    await settle(tester);
    expect(find.byType(GameCard), findsOneWidget);
    await tester.enterText(find.byType(SearchBar), '');
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'NES'));
    await settle(tester);
    expect(find.byType(GameCard), findsOneWidget);
    expect(find.text('Gamma Golf'), findsOneWidget);
    await finish(tester, db);
  });

  testWidgets('D-pad: A plays the focused game, Y opens its sheet', (
    tester,
  ) async {
    played = [];
    final db = await seededDb(_titles);
    await tester.pumpWidget(shellApp(db));
    await settle(tester);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await settle(tester);
    expect(find.text('Play'), findsOneWidget, reason: 'details sheet is open');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(played, hasLength(1));
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    await finish(tester, db);
  });

  testWidgets('a play link opens its game; unknown links say so', (
    tester,
  ) async {
    played = [];
    final db = await seededDb(_titles);
    final links = FakeLinks()..pending = 'sha1';
    await tester.pumpWidget(shellApp(db, links: links));
    await settle(tester);
    expect(played.single.title, 'Beta Racer');
    links.pending = 'nope';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(played, hasLength(1));
    expect(find.text('That game is not in your library'), findsOneWidget);
    await finish(tester, db);
  });

  testWidgets('a link is dropped while another screen is on top', (
    tester,
  ) async {
    played = [];
    final db = await seededDb(_titles);
    final links = FakeLinks();
    await tester.pumpWidget(shellApp(db, links: links));
    await settle(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const Text('game')));
    await settle(tester);
    links.pending = 'sha0';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(played, isEmpty);
    expect(links.pending, isNull);
    await finish(tester, db);
  });

  testWidgets('the game sheet pins a home-screen shortcut', (tester) async {
    final db = await seededDb(_titles);
    final links = FakeLinks();
    await tester.pumpWidget(shellApp(db, links: links));
    await settle(tester);
    await tester.longPress(find.text('Alpha Quest'));
    await settle(tester);
    await tester.tap(find.text('Add to home screen'));
    await settle(tester);
    expect(links.pinned, ['sha0']);
    links.canPin = false;
    await tester.longPress(find.text('Alpha Quest'));
    await settle(tester);
    await tester.tap(find.text('Add to home screen'));
    await settle(tester);
    expect(find.text("This home screen can't pin shortcuts"), findsOneWidget);
    await finish(tester, db);
  });

  testWidgets('R1 switches to Settings', (tester) async {
    final db = await seededDb([]);
    await tester.pumpWidget(shellApp(db));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await settle(tester);
    expect(find.text('LCD palette'), findsOneWidget);
    await finish(tester, db);
  });
}
