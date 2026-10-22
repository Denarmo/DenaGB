import 'package:dena_emu/src/library/database.dart';
import 'package:dena_emu/src/library/game_media.dart';
import 'package:dena_emu/src/library/launch_animation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'media_art_test.dart' show game;

/// Counts how often the page under the launch starts.
class _Page extends StatefulWidget {
  const _Page(this.started);

  final List<int> started;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    widget.started.add(1);
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Colors.black,
    child: Center(child: Text('game')),
  );
}

void main() {
  late List<int> started;
  late NavigatorState nav;

  Future<void> launch(
    WidgetTester tester,
    Game g, {
    bool reduceMotion = false,
  }) async {
    started = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            nav = Navigator.of(context);
            return const Scaffold(body: Text('library'));
          },
        ),
      ),
    );
    nav.push(
      LaunchRoute<void>(
        builder: (_) => _Page(started),
        game: g,
        reduceMotion: reduceMotion,
        origin: const Rect.fromLTWH(10, 10, 80, 110),
      ),
    );
    await tester.pump();
  }

  testWidgets('the game starts loading on the first frame', (tester) async {
    await launch(tester, game());
    expect(started, [1]);
    // The library still shows while the box flies in.
    expect(find.text('library'), findsOneWidget);
    await tester.pump(LaunchRoute.defaultDuration ~/ 2);
    expect(find.byType(GameMedia), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(GameMedia), findsNothing);
    expect(find.text('game'), findsOneWidget);
    expect(started, [1]);
  });

  testWidgets('a tap skips to the game', (tester) async {
    await launch(tester, game());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    await tester.pump();
    expect(find.byType(GameMedia), findsNothing);
    expect(find.text('game'), findsOneWidget);
    // Taps reach the game afterwards.
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('a button skips to the game', (tester) async {
    await launch(tester, game(system: 'psx'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(find.byType(GameMedia), findsNothing);
  });

  testWidgets('reduced motion is a short fade', (tester) async {
    await launch(tester, game(), reduceMotion: true);
    expect(started, [1]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(GameMedia), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('game'), findsOneWidget);
  });

  for (final system in [
    'nes',
    'snes',
    'n64',
    'gba',
    'nds',
    'psx',
    'psp',
    'pico8',
  ]) {
    testWidgets('every frame draws for $system', (tester) async {
      await launch(tester, game(system: system));
      for (var i = 0; i < 20; i++) {
        await tester.pump(LaunchRoute.defaultDuration ~/ 20);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
    });
  }

  testWidgets('LaunchOrigin reports where the box is', (tester) async {
    final g = game();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned(
              left: 30,
              top: 40,
              width: 100,
              height: 140,
              child: LaunchOrigin(game: g, child: const SizedBox.expand()),
            ),
          ],
        ),
      ),
    );
    expect(LaunchOrigin.rectOf(g), const Rect.fromLTWH(30, 40, 100, 140));
    expect(LaunchOrigin.rectOf(game(sha1: 'other')), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(LaunchOrigin.rectOf(g), isNull);
  });

  testWidgets('media draws with and without art', (tester) async {
    for (final system in ['gb', 'gbc', 'genesis', '3ds', 'psx', 'psp']) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 200, child: GameMedia(system: system)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
