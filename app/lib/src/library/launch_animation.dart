// SPDX-License-Identifier: GPL-3.0-or-later
// Playing a game opens its box and loads the cartridge, disc or UMD while the
// core starts underneath, so the load hides behind the animation.
// Spec: docs/specs/launch-animation.md
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'database.dart';
import 'game_box_model.dart' show BoxHinge, boxSpecFor;
import 'game_media.dart';
import 'library_scope.dart';
import 'media_art.dart';
import '../ui/dena_icons.dart';
import '../ui/pixel.dart';
import '../ui/pocket.dart';

/// How a box opens.
enum BoxOpening {
  /// Cardboard: the top flap lifts and the media slides up out of the box.
  flap,

  /// Plastic case: the front swings open on its spine and the media lifts
  /// off the tray.
  clamshell,
}

/// The way [system]'s retail box opens (game_box_model.dart's hinge).
BoxOpening boxOpeningFor(String system) =>
    boxSpecFor(system).hinge == BoxHinge.left
    ? BoxOpening.clamshell
    : BoxOpening.flap;

/// Width / height and depth (fraction of the width) of [system]'s box, from
/// the library's box model (game-boxes.md).
({double aspect, double depth}) launchBoxSize(String system) {
  final spec = boxSpecFor(system);
  return (aspect: spec.aspect, depth: spec.depthMm / spec.widthMm);
}

/// Phases of the launch, as fractions of the route's duration ([LaunchRoute.duration]).
/// The launch plays as [frames] still frames, 12 a second, like an LCD
/// redrawing (pocket-lcd-ui.md, Launch).
abstract final class LaunchTimeline {
  /// Frames in the launch: 11 at 12 fps is just under a second.
  static const frames = 11;

  static const fly = Interval(0, 0.18, curve: Curves.easeOutCubic);
  static const open = Interval(0.2, 0.4, curve: Curves.easeInOutCubic);
  static const lift = Interval(0.38, 0.56, curve: Curves.easeOutCubic);
  static const boxAway = Interval(0.5, 0.62, curve: Curves.easeIn);

  /// The cartridge drops into the slot below the screen.
  static const insert = Interval(0.58, 0.72, curve: Curves.easeInCubic);

  /// One frame of the whole screen in ink, as the LCD powers on.
  static const invert = (0.72, 0.8);

  /// A centre-line wipe opens onto the game.
  static const reveal = Interval(0.8, 1);

  /// The session is hidden until the backdrop covers the library.
  static const sessionShownAt = 0.18;

  /// [t] held to the start of its frame.
  static double step(double t) =>
      t >= 1 ? 1 : (t * frames).floorToDouble() / frames;
}

/// Where the tapped box is on screen, so the launch starts from it. Wrap a
/// game's box in the grid with this.
class LaunchOrigin extends StatefulWidget {
  const LaunchOrigin({super.key, required this.game, required this.child});

  final Game game;
  final Widget child;

  static final _mounted = <String, List<_LaunchOriginState>>{};
  static _LaunchOriginState? _lastTouched;

  /// The on-screen rect of [game]'s box: the focused one, else the one last
  /// touched, else any that is showing.
  static Rect? rectOf(Game game) {
    final mounted = _mounted[game.sha1] ?? const <_LaunchOriginState>[];
    // With a D-pad the focused card is the one played.
    for (final s in mounted) {
      if (Focus.maybeOf(s.context)?.hasFocus ?? false) return s.rect;
    }
    final last = _lastTouched;
    if (last != null && last.mounted && last.widget.game.sha1 == game.sha1) {
      return last.rect;
    }
    for (final s in mounted) {
      final r = s.rect;
      if (r != null) return r;
    }
    return null;
  }

  @override
  State<LaunchOrigin> createState() => _LaunchOriginState();
}

class _LaunchOriginState extends State<LaunchOrigin> {
  late String _sha1;

  Rect? get rect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void initState() {
    super.initState();
    _sha1 = widget.game.sha1;
    LaunchOrigin._mounted.putIfAbsent(_sha1, () => []).add(this);
  }

  @override
  void didUpdateWidget(LaunchOrigin old) {
    super.didUpdateWidget(old);
    if (widget.game.sha1 == _sha1) return;
    _remove();
    _sha1 = widget.game.sha1;
    LaunchOrigin._mounted.putIfAbsent(_sha1, () => []).add(this);
  }

  void _remove() {
    final list = LaunchOrigin._mounted[_sha1];
    list?.remove(this);
    if (list != null && list.isEmpty) LaunchOrigin._mounted.remove(_sha1);
    if (LaunchOrigin._lastTouched == this) LaunchOrigin._lastTouched = null;
  }

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => LaunchOrigin._lastTouched = this,
    child: widget.child,
  );
}

/// The art the launch shows, loaded before the route starts so the first
/// frame has it.
class LaunchArt {
  const LaunchArt({this.cover, this.media});

  final ImageProvider? cover, media;

  /// Waits at most [wait] for each image; a slow download only means the
  /// launch shows the fallback this time.
  static Future<LaunchArt> load(
    LibraryScope scope,
    Game game, {
    Duration wait = const Duration(milliseconds: 350),
  }) async {
    Future<File?> quick(Future<File?>? f) => (f ?? Future.value(null))
        .timeout(wait, onTimeout: () => null)
        .then((f) => f, onError: (Object _) => null);
    final media = scope.media;
    final cached = media?.cachedFor(game);
    final (cover, art) = await (
      quick(scope.art?.coverFor(game)),
      cached != null ? Future.value(cached) : quick(media?.mediaFor(game)),
    ).wait;
    return LaunchArt(
      cover: cover == null ? null : FileImage(cover),
      media: art == null ? null : FileImage(art),
    );
  }
}

/// A full-screen route that plays the launch over [builder]'s page. The page
/// is built at once, so the core loads during the animation. A tap or any
/// button skips to the game; with reduced motion it is a short fade.
class LaunchRoute<T> extends PageRoute<T> {
  LaunchRoute({
    required this.builder,
    required this.game,
    this.art = const LaunchArt(),
    this.origin,
    this.reduceMotion = false,
    this.duration = defaultDuration,
  });

  final WidgetBuilder builder;
  final Game game;
  final LaunchArt art;

  /// The tapped box on screen; the centre when null.
  final Rect? origin;
  final bool reduceMotion;

  /// [LaunchTimeline.frames] frames at 12 fps.
  static const defaultDuration = Duration(
    milliseconds: LaunchTimeline.frames * 1000 ~/ 12,
  );

  /// Handhelds play the same frames (launch-animation.md, Handhelds).
  static const handheldDuration = defaultDuration;

  /// How long the launch runs; phases are fractions of it.
  final Duration duration;

  @override
  Duration get transitionDuration =>
      reduceMotion ? const Duration(milliseconds: 200) : duration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  /// Jumps to the end of the animation.
  void skip() {
    final c = controller;
    if (c != null && c.isAnimating && c.status == AnimationStatus.forward) {
      c.value = 1;
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion || animation.status == AnimationStatus.reverse) {
      return FadeTransition(opacity: animation, child: child);
    }
    return LaunchAnimation(
      animation: animation,
      game: game,
      art: art,
      origin: origin,
      onSkip: skip,
      child: child,
    );
  }
}

/// The launch drawn at [animation]'s value over [child] (the game page).
class LaunchAnimation extends StatelessWidget {
  const LaunchAnimation({
    super.key,
    required this.animation,
    required this.game,
    required this.child,
    this.art = const LaunchArt(),
    this.origin,
    this.onSkip,
  });

  final Animation<double> animation;
  final Game game;
  final LaunchArt art;
  final Rect? origin;
  final VoidCallback? onSkip;
  final Widget child;

  static const backdrop = Color(0xFF202024);
  static const gold = Color(0xFFF1C40F);

  @override
  Widget build(BuildContext context) {
    // The page stays in the tree from the first frame (its state loads the
    // core); it is only painted once the backdrop hides the library.
    final page = AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value >= LaunchTimeline.sessionShownAt ? 1 : 0,
        child: child,
      ),
      child: child,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        page,
        _SkipKeys(
          animation: animation,
          onSkip: onSkip,
          // Gone once the launch ends, so it never takes the game's touches.
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => animation.value >= 1
                ? const SizedBox.shrink()
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSkip,
                    child: _frame(context, animation.value),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _frame(BuildContext context, double raw) {
    final t = LaunchTimeline.step(raw);
    final style = PocketStyle.of(context);
    final pal = style.palette;
    final screen = MediaQuery.sizeOf(context);
    final box = launchBoxSize(game.system);
    final opening = boxOpeningFor(game.system);
    // The box at rest in the middle of the screen.
    final maxW = math.min(screen.width * 0.5, 320.0);
    final maxH = screen.height * 0.42;
    var w = maxW, h = maxW / box.aspect;
    if (h > maxH) {
      h = maxH;
      w = h * box.aspect;
    }
    final centre = Rect.fromCenter(
      center: screen.center(Offset.zero).translate(0, -screen.height * 0.04),
      width: w,
      height: h,
    );
    final from =
        origin ??
        Rect.fromCenter(center: centre.center, width: w * 0.6, height: h * 0.6);
    final fly = LaunchTimeline.fly.transform(t);
    final rect = Rect.lerp(from, centre, fly)!;
    final (inkFrom, inkTo) = LaunchTimeline.invert;
    if (t >= inkFrom && t < inkTo) return ColoredBox(color: pal.ink);
    if (t >= LaunchTimeline.reveal.begin) {
      return _Wipe(open: LaunchTimeline.reveal.transform(t), palette: pal);
    }
    final opened = _OpeningBox(
      rect: rect,
      t: t,
      game: game,
      art: art,
      opening: opening,
      depth: box.depth,
      screen: screen,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // Three dither frames hide the library, then plain paper.
        if (t < LaunchTimeline.sessionShownAt)
          Dither(
            color: pal.paper,
            density: t < LaunchTimeline.fly.end / 2
                ? DitherDensity.quarter
                : DitherDensity.half,
          )
        else
          ColoredBox(color: pal.paper),
        if (style.colourCovers)
          opened
        else
          ColorFiltered(colorFilter: lcdShadeFilter(pal), child: opened),
        // The slot the cartridge drops into.
        if (t >= LaunchTimeline.sessionShownAt)
          Positioned(
            left: screen.width * 0.25,
            right: screen.width * 0.25,
            bottom: screen.height * 0.06,
            height: style.metrics.px * 3,
            child: ColoredBox(color: pal.ink),
          ),
      ],
    );
  }
}

/// The LCD powering on: paper bars close off the screen and part from a
/// centre line as [open] goes from 0 to 1, showing the game between them.
class _Wipe extends StatelessWidget {
  const _Wipe({required this.open, required this.palette});

  final double open;
  final LcdPalette palette;

  @override
  Widget build(BuildContext context) {
    final px = PocketStyle.of(context).metrics.px;
    final edge = Container(height: px, color: palette.ink);
    final bar = Expanded(child: ColoredBox(color: palette.paper));
    // A one-pixel line first, then the band widens.
    final band = math.max(open, 0.01);
    return LayoutBuilder(
      builder: (context, c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar,
          edge,
          SizedBox(height: c.maxHeight * band),
          edge,
          bar,
        ],
      ),
    );
  }
}

/// Any key or button skips while the animation runs. A global handler, so
/// the game page keeps its own focus for when the launch ends.
class _SkipKeys extends StatefulWidget {
  const _SkipKeys({required this.animation, this.onSkip, required this.child});

  final Animation<double> animation;
  final VoidCallback? onSkip;
  final Widget child;

  @override
  State<_SkipKeys> createState() => _SkipKeysState();
}

class _SkipKeysState extends State<_SkipKeys> {
  bool _listening = false;

  bool _onKey(KeyEvent event) {
    if (widget.animation.value >= 1) {
      _stop();
      return false;
    }
    if (event is KeyDownEvent) widget.onSkip?.call();
    return true;
  }

  void _start() {
    if (_listening) return;
    _listening = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _stop() {
    if (!_listening) return;
    _listening = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  void _onStatus(AnimationStatus s) =>
      s == AnimationStatus.forward ? _start() : _stop();

  @override
  void initState() {
    super.initState();
    if (widget.animation.status == AnimationStatus.forward) _start();
    widget.animation.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _OpeningBox extends StatelessWidget {
  const _OpeningBox({
    required this.rect,
    required this.t,
    required this.game,
    required this.art,
    required this.opening,
    required this.depth,
    required this.screen,
  });

  final Rect rect;
  final double t;
  final Game game;
  final LaunchArt art;
  final BoxOpening opening;
  final double depth;
  final Size screen;

  @override
  Widget build(BuildContext context) {
    // A PICO-8 cart has no box lid to open.
    final open = boxSpecFor(game.system).hinge == BoxHinge.none
        ? 0.0
        : LaunchTimeline.open.transform(t);
    final lift = LaunchTimeline.lift.transform(t);
    final away = LaunchTimeline.boxAway.transform(t);
    final insert = LaunchTimeline.insert.transform(t);

    final aspect = mediaAspect(game.system);
    final isCart =
        mediaKindFor(game.system) == MediaKind.cartridge ||
        mediaKindFor(game.system) == MediaKind.pico8Cart;
    // The media rests where the box model seats it in the open box, at its
    // real size relative to the box, drawn at its own proportions.
    var seat = boxSpecFor(game.system).mediaRect;
    // Nothing seated (a PICO-8 cart is its own box): most of the face.
    if (seat.isEmpty) {
      seat = Rect.fromCenter(
        center: const Offset(0.5, 0.5),
        width: 0.7,
        height: 0.8,
      );
    }
    final slot = Rect.fromLTWH(
      rect.left + seat.left * rect.width,
      rect.top + seat.top * rect.height,
      seat.width * rect.width,
      seat.height * rect.height,
    );
    var mw = slot.width, mh = mw / aspect;
    if (mh > slot.height) {
      mh = slot.height;
      mw = mh * aspect;
    }
    final inBox = Rect.fromCenter(center: slot.center, width: mw, height: mh);
    // Out of the box: above it for cardboard, in front of it for a case.
    final lifted = opening == BoxOpening.flap
        ? inBox.shift(Offset(0, -rect.height * 0.62))
        : inBox.shift(Offset(rect.width * 0.08, -rect.height * 0.08));
    var mediaRect = Rect.lerp(inBox, lifted, lift)!;
    // Dropped straight down into the slot below the screen.
    final target = mediaRect.shift(Offset(0, screen.height));
    mediaRect = Rect.lerp(mediaRect, target, insert)!;
    final spin = isCart ? 0.0 : lift * 0.5;

    final media = Positioned.fromRect(
      rect: mediaRect,
      child: GameMedia(
        system: game.system,
        art: art.media,
        cover: art.cover,
        spin: spin,
      ),
    );

    final box = Positioned.fromRect(
      rect: rect,
      child: Opacity(
        opacity: 1 - away,
        child: opening == BoxOpening.flap
            ? _CardboardBox(cover: art.cover, open: open, depth: depth)
            : _CaseBox(cover: art.cover, open: open),
      ),
    );
    // Cardboard: the media rises from behind the front face. A case: it sits
    // on the tray, under the swinging front, and comes to the front once out.
    final mediaOnTop = opening == BoxOpening.clamshell
        ? open > 0.55
        : lift > 0.98;
    return Stack(
      fit: StackFit.expand,
      children: mediaOnTop ? [box, media] : [media, box],
    );
  }
}

Widget _coverFace(ImageProvider? cover) => cover == null
    ? const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3A3A40), Color(0xFF202024)],
          ),
        ),
        child: Center(
          child: Icon(
            DenaIcons.controller,
            color: LaunchAnimation.gold,
            size: 48,
          ),
        ),
      )
    : Image(
        image: cover,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF2A2A30)),
      );

/// A cardboard box seen slightly from above: the top flap hinges on the
/// back edge and swings up and over.
class _CardboardBox extends StatelessWidget {
  const _CardboardBox({
    required this.cover,
    required this.open,
    required this.depth,
  });

  final ImageProvider? cover;
  final double open;
  final double depth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final top = w * depth;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          // The open mouth of the box, seen once the flap lifts.
          Positioned(
            left: 0,
            right: 0,
            top: -top * 0.5,
            height: top * 0.5 + 2,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateX(-1.1),
              child: const ColoredBox(color: Color(0xFF15151A)),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: _coverFace(cover),
              ),
            ),
          ),
          // The flap: hinged at the top edge, lifts back and over.
          Positioned(
            left: 0,
            right: 0,
            top: -top * 0.5,
            height: top * 0.5,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateX(-1.1 + open * 2.6),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(const Color(0xFF3B3830), Colors.white, 0.1)!,
                      const Color(0xFF2A2822),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: w, height: h),
        ],
      );
    },
  );
}

/// A plastic case: the front swings open on its left spine, showing the
/// tray the media sits on.
class _CaseBox extends StatelessWidget {
  const _CaseBox({required this.cover, required this.open});

  final ImageProvider? cover;
  final double open;

  @override
  Widget build(BuildContext context) {
    final angle = -open * math.pi * 0.62;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        // The tray.
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2C2C33), Color(0xFF18181C)],
            ),
            border: Border.all(color: const Color(0x33FFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x88000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.82,
              heightFactor: 0.82,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x22FFFFFF), width: 2),
                ),
              ),
            ),
          ),
        ),
        // The front, hinged on the spine.
        Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(angle),
          child: angle < -math.pi / 2
              // Past edge-on we see the inside of the front.
              ? const DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xFF26262C)),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _coverFace(cover),
                      // The clear sleeve catches the light as it turns.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.06 + open * 0.2),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Opens [game]'s box and loads its media over [page]. Images come from
/// [scope]; the animation starts from the box last tapped.
Future<T?> pushLaunch<T>(
  NavigatorState navigator,
  LibraryScope scope,
  Game game, {
  required WidgetBuilder page,
  bool reduceMotion = false,
  Duration duration = LaunchRoute.defaultDuration,
}) async {
  final origin = LaunchOrigin.rectOf(game);
  final art = reduceMotion
      ? const LaunchArt()
      : await LaunchArt.load(scope, game);
  // Fetch genuine media art for next time when it isn't here yet.
  scope.media?.prefetch([game]);
  return navigator.push<T>(
    LaunchRoute<T>(
      builder: page,
      game: game,
      art: art,
      origin: origin,
      reduceMotion: reduceMotion,
      duration: duration,
    ),
  );
}
