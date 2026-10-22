// SPDX-License-Identifier: GPL-3.0-or-later
// Long-press on a game: its box steps up onto a dithered plinth and an RPG
// window offers Play, Rename, Add to home screen, Achievements, ...
// Spec: docs/specs/game-boxes.md (Zoom and options)
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../achievements/achievements_ui.dart';
import '../achievements/retro_achievements.dart';
import '../ui/pixel.dart';
import '../ui/pixel_icons.dart';
import '../ui/pocket.dart';
import 'database.dart';
import 'game_box.dart';
import 'games_tab.dart';
import 'importer.dart';
import 'import_rules.dart';
import 'library_scope.dart';

/// Opens [game]'s zoomed box with its options. [from] is the box's stage on
/// screen (global coordinates); without it the box grows from the middle.
Future<void> showGameBoxMenu(
  BuildContext context,
  Game game,
  PlayGame onPlay, {
  Rect? from,
}) {
  final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Close',
      transitionDuration: Duration(milliseconds: reduce ? 0 : 420),
      reverseTransitionDuration: Duration(milliseconds: reduce ? 0 : 260),
      pageBuilder: (routeContext, animation, _) => _BoxMenu(
        game: game,
        from: from,
        animation: animation,
        // Actions run against the library's context, which outlives the menu.
        host: context,
        onPlay: onPlay,
      ),
    ),
  );
}

class _BoxMenu extends StatelessWidget {
  const _BoxMenu({
    required this.game,
    required this.from,
    required this.animation,
    required this.host,
    required this.onPlay,
  });

  final Game game;
  final Rect? from;
  final Animation<double> animation;
  final BuildContext host;
  final PlayGame onPlay;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final area = pad.deflateRect(Offset.zero & size);
    final wide = area.width > area.height * 1.1;
    // Box on the left (handheld, landscape) or on top (phone).
    final boxArea = wide
        ? Rect.fromLTWH(area.left, area.top, area.width * 0.46, area.height)
        : Rect.fromLTWH(area.left, area.top, area.width, area.height * 0.46);
    final panelArea = wide
        ? Rect.fromLTRB(boxArea.right, area.top, area.right, area.bottom)
        : Rect.fromLTRB(area.left, boxArea.bottom, area.right, area.bottom);
    final side = math.min(boxArea.width, boxArea.height) * 0.88;
    final target = Rect.fromCenter(
      center: boxArea.center,
      width: side,
      height: side,
    );
    final start =
        from ??
        Rect.fromCenter(
          center: target.center,
          width: side * 0.4,
          height: side * 0.4,
        );
    final move = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    final panelIn = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0, 0.6, curve: Curves.easeIn),
    );
    final style = PocketStyle.of(context);
    final ink = style.palette.ink, px = style.metrics.px;
    return CallbackShortcuts(
      // B is the app's Back already; Escape closes too.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Stack(
        children: [
          // The shelf dims under a 25% ink dither; a tap outside closes
          // the menu.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) => animation.value < 0.05
                    ? const SizedBox.expand()
                    : Dither(color: ink, density: DitherDensity.quarter),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: move,
            builder: (context, child) {
              // Steps at 12 fps like an LCD redraw, snapped to whole pixels.
              final t = lcdStep(move.value);
              final r = Rect.lerp(start, target, t)!;
              final rect = Rect.fromLTWH(
                (r.left / px).roundToDouble() * px,
                (r.top / px).roundToDouble() * px,
                (r.width / px).roundToDouble() * px,
                (r.height / px).roundToDouble() * px,
              );
              return Positioned.fromRect(rect: rect, child: child!);
            },
            child: IgnorePointer(
              child: _Plinth(
                animation: animation,
                child: _Float(
                  animation: animation,
                  child: GameBox(game: game, alignment: Alignment.bottomCenter),
                ),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: panelArea,
            child: FadeTransition(
              opacity: panelIn.drive(_stepTween),
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 4 * px : 8 * px,
                    vertical: 4 * px,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _Options(game: game, host: host, onPlay: onPlay),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opacity in four steps, like an LCD fading a window in.
final _stepTween = _StepTween(4);

class _StepTween extends Animatable<double> {
  _StepTween(this.steps);

  final int steps;

  @override
  double transform(double t) => (t * steps).floorToDouble() / steps;
}

/// [value] held to the 12 fps frames of the 420 ms zoom (pocket-lcd-ui.md),
/// so the box moves in visible steps.
double lcdStep(double value) {
  const frames = 5;
  if (value >= 1 || value <= 0) return value;
  return (value * frames).roundToDouble() / frames;
}

/// The box stands on a dithered plinth, and a dithered foil sheen sweeps
/// across it once as it arrives.
class _Plinth extends StatelessWidget {
  const _Plinth({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette, px = style.metrics.px;
    return Column(
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) => CustomPaint(
              foregroundPainter: _SheenPainter(
                // Sweeps over the second half of the zoom, in steps.
                ((animation.value - 0.4) / 0.6 * 6).floorToDouble() / 6,
                p.paper,
                px,
              ),
              child: child,
            ),
            child: child,
          ),
        ),
        // Top face, dithered front and ink base: a slab under the box.
        Container(height: px, color: p.ink),
        Container(height: 2 * px, color: p.paper),
        Container(
          height: 5 * px,
          color: p.light,
          child: Dither(color: p.dark, density: DitherDensity.half),
        ),
        Container(height: 2 * px, color: p.ink),
      ],
    );
  }
}

class _SheenPainter extends CustomPainter {
  _SheenPainter(this.t, this.color, this.px);

  final double t;
  final Color color;
  final double px;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    // A diagonal band of half-dither pixels from bottom left to top right.
    final band = size.shortestSide * 0.18;
    final x0 = -band + (size.width + size.height + band) * t;
    final paint = Paint()..color = color.withValues(alpha: 0.7);
    for (var y = 0.0; y < size.height; y += px) {
      for (var x = 0.0; x < size.width; x += px) {
        final d = x + (size.height - y) - x0;
        if (d < 0 || d > band) continue;
        if (((x / px).round() + (y / px).round()).isOdd) continue;
        canvas.drawRect(Rect.fromLTWH(x, y, px, px), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.t != t || old.color != color;
}

/// A slow idle bob once the box has arrived, in whole pixels.
class _Float extends StatefulWidget {
  const _Float({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_Float> createState() => _FloatState();
}

class _FloatState extends State<_Float> with SingleTickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_status);
  }

  void _status(AnimationStatus s) {
    if (s == AnimationStatus.completed && !_disabled) {
      _idle.repeat(reverse: true);
    } else if (s == AnimationStatus.reverse) {
      _idle.stop();
    }
  }

  bool get _disabled =>
      !TickerMode.valuesOf(context).enabled ||
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
      !FloatAnimation.enabled;

  @override
  void dispose() {
    widget.animation.removeStatusListener(_status);
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _idle,
    builder: (context, child) {
      // Whole LCD pixels only: the box hops 0, 1, 2 pixels and back.
      final px = PocketStyle.of(context).metrics.px;
      final t = Curves.easeInOut.transform(_idle.value);
      return Transform.translate(
        offset: Offset(0, -px * (t * 2).roundToDouble()),
        child: child,
      );
    },
    child: widget.child,
  );
}

/// Switch for the idle bob; off in tests so goldens and pumpAndSettle stay
/// deterministic.
abstract final class FloatAnimation {
  static bool enabled = true;
}

/// The options as an RPG command window: title, Play, then the rest.
class _Options extends StatelessWidget {
  const _Options({
    required this.game,
    required this.host,
    required this.onPlay,
  });

  final Game game;
  final BuildContext host;
  final PlayGame onPlay;

  @override
  Widget build(BuildContext context) {
    final scope = LibraryScope.of(host);
    final db = scope.db;
    final text = Theme.of(context).textTheme;
    final style = PocketStyle.of(context);
    final pal = style.palette, px = style.metrics.px;
    final played = game.playSeconds == 0
        ? 'Not played yet'
        : 'Played ${(game.playSeconds / 60).ceil()} min';
    void close() => Navigator.of(context).pop();

    final keys = <Widget>[
      PixelMenuItem(
        glyph: PixelGlyphs.pencil,
        label: 'Rename',
        onPressed: () async {
          final name = await askGameName(context, game.title);
          if (name != null && name.trim().isNotEmpty) {
            await db.rename(game.id, name.trim());
          }
          if (context.mounted) close();
        },
      ),
      PixelMenuItem(
        glyph: PixelGlyphs.star,
        label: game.favorite ? 'Unfavourite' : 'Favourite',
        onPressed: () async {
          await db.setFavorite(game.id, !game.favorite);
          if (context.mounted) close();
        },
      ),
      if (scope.links case final links?)
        PixelMenuItem(
          glyph: PixelGlyphs.home,
          label: 'Add to home screen',
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(host);
            final ok = await links.pin(game, await shortcutIcon(scope, game));
            if (!ok) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text("This home screen can't pin shortcuts"),
                ),
              );
            }
            if (context.mounted) close();
          },
        ),
      if (scope.achievements case final ra?
          when raConsoleIds.containsKey(game.system))
        PixelMenuItem(
          glyph: PixelGlyphs.trophy,
          label: 'Achievements',
          onPressed: () {
            close();
            Navigator.of(host).push(
              MaterialPageRoute<void>(
                builder: (_) => GameAchievementsPage(ra: ra, game: game),
              ),
            );
          },
        ),
      if (scope.art case final art?)
        PixelMenuItem(
          glyph: PixelGlyphs.picture,
          label: 'Choose cover',
          onPressed: () async {
            final picked = await scope.files.pickFiles();
            final image = picked.where(
              (f) => const {
                '.png',
                '.jpg',
                '.jpeg',
                '.webp',
              }.contains(p.extension(f).toLowerCase()),
            );
            if (image.isNotEmpty) {
              final path = await art.storeCustom(game, File(image.first));
              await db.setCustomArt(game.id, path);
            }
            await scope.files.clearCache();
            if (context.mounted) close();
          },
        ),
      PixelMenuItem(
        glyph: PixelGlyphs.info,
        label: 'Game info',
        onPressed: () => _showInfo(context, game),
      ),
      PixelMenuItem(
        glyph: PixelGlyphs.trash,
        label: 'Delete',
        onPressed: () async {
          if (await confirmGameDelete(context, game)) {
            final g = await db.deleteGame(game.id);
            if (g != null) {
              await deleteGameFiles(
                g,
                dataDir: scope.importer.gamesDir.parent.path,
              );
              await scope.art?.forget(g);
              await scope.links?.remove(g.sha1);
            }
            if (context.mounted) close();
          }
        },
      ),
    ];

    return FocusTraversalGroup(
      child: PixelWindow(
        padding: EdgeInsets.all(px),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InvertedBar(title: game.title, glyph: PixelGlyphs.box),
            Padding(
              padding: EdgeInsets.fromLTRB(2 * px, 2 * px, 2 * px, px),
              child: Text(
                '${systemShortName(game.system)} · $played',
                style: text.bodySmall?.copyWith(color: pal.dark),
              ),
            ),
            PixelMenuItem(
              glyph: PixelGlyphs.play,
              label: 'Play',
              autofocus: true,
              onPressed: () {
                close();
                onPlay(host, game);
              },
            ),
            Container(
              height: px,
              margin: EdgeInsets.symmetric(vertical: px),
              color: pal.dark,
            ),
            ...keys,
          ],
        ),
      ),
    );
  }
}

Future<void> _showInfo(BuildContext context, Game game) {
  String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  final mb = game.size / (1024 * 1024);
  final rows = [
    ('System', systemShortName(game.system)),
    ('File', game.fileName),
    (
      'Size',
      mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${game.size ~/ 1024} KB',
    ),
    ('Added', date(game.addedAt)),
    (
      'Last played',
      game.lastPlayedAt == null ? 'Never' : date(game.lastPlayedAt!),
    ),
    ('Play time', '${(game.playSeconds / 60).ceil()} min'),
    ('CRC-32', game.crc32.toUpperCase()),
    ('SHA-1', game.sha1),
  ];
  return showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(game.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(k, style: Theme.of(d).textTheme.labelLarge),
                    ),
                    Expanded(child: SelectableText(v)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(d),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// The short name of a system id for labels.
String systemShortName(String id) =>
    GameSystem.values
        .where((s) => s.id == id)
        .map((s) => s.shortName)
        .firstOrNull ??
    id;
