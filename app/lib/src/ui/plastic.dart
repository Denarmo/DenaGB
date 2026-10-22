// SPDX-License-Identifier: GPL-3.0-or-later
// The feel of holding a handheld console: the fine matte stipple of its
// moulded shell over the whole UI, lit from above, and key-cap buttons that
// press in.
// Spec: docs/specs/ui-look-and-feel.md
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Corner radius of plastic buttons, matching the pause menu's buttons.
const double plasticButtonRadius = 16;

/// Whether the grain is drawn. The game screen turns it off so it never
/// sits over the emulator frame.
final ValueNotifier<bool> plasticGrainVisible = ValueNotifier(true);

/// Whether the grain exists at all. Off on handhelds: its overlay blend over
/// the whole screen is a second pass on every frame, too much for their GPUs.
bool plasticGrainEnabled = true;

const int _tile = 160;

ui.Image? _grainTile;

/// A [_tile]-pixel square of the fine, even stipple moulded into handheld
/// shells (an EDM matte finish): thousands of soft, tiny bumps, each lit on
/// one side. Drawn once with a fixed seed so goldens are stable.
///
/// The soft bumps are computed here, pixel by pixel, and the tile is drawn
/// as plain one-pixel squares: thousands of mask-blurred circles made
/// Impeller (Vulkan) allocate an offscreen pass each and run phones out of
/// memory within seconds of launch.
ui.Image _grain() {
  final cached = _grainTile;
  if (cached != null) return cached;
  // Premultiplied grey (white or black specks only) and alpha per pixel.
  final grey = Float64List(_tile * _tile);
  final alpha = Float64List(_tile * _tile);
  final rnd = Random(0xDE7A);
  // A small disc of radius r blurred by sigma 0.4 and sampled at pixel
  // centres is close to a Gaussian holding the disc's area.
  void bump(double cx, double cy, double r, double a, double v) {
    final s2 = 0.16 + 1 / 12 + r * r / 4;
    final peak = min(1.0, r * r / (2 * s2));
    for (var py = (cy - 2).floor(); py <= (cy + 2).ceil(); py++) {
      for (var px = (cx - 2).floor(); px <= (cx + 2).ceil(); px++) {
        final dx = px + 0.5 - cx, dy = py + 0.5 - cy;
        final cov = peak * exp(-(dx * dx + dy * dy) / (2 * s2));
        if (cov < 0.004) continue;
        // Wrapped so the tile repeats.
        final i = (py % _tile) * _tile + (px % _tile);
        final s = a * cov;
        grey[i] = s * v + grey[i] * (1 - s);
        alpha[i] = s + alpha[i] * (1 - s);
      }
    }
  }

  for (var i = 0; i < 9000; i++) {
    final x = rnd.nextDouble() * _tile, y = rnd.nextDouble() * _tile;
    final r = 0.35 + rnd.nextDouble() * 0.35;
    final a = 0.18 + rnd.nextDouble() * 0.22;
    // Each bump: a lit upper-left and a shaded lower-right, like light
    // falling on a stippled surface from above.
    bump(x - 0.3, y - 0.3, r, a, 1);
    bump(x + 0.3, y + 0.3, r, a, 0);
  }
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final paint = Paint();
  for (var i = 0; i < grey.length; i++) {
    final a = alpha[i];
    if (a < 1 / 255) continue;
    final c = (grey[i] / a * 255).round().clamp(0, 255);
    paint.color = Color.fromARGB((a * 255).round(), c, c, c);
    canvas.drawRect(
      Rect.fromLTWH((i % _tile).toDouble(), (i ~/ _tile).toDouble(), 1, 1),
      paint,
    );
  }
  return _grainTile = rec.endRecording().toImageSync(_tile, _tile);
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.dark);

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ImageShader(
          _grain(),
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..color = Color.fromRGBO(0, 0, 0, dark ? 0.45 : 0.35)
        ..blendMode = BlendMode.softLight,
    );
    // The shell is lit from above: a soft sheen at the top falling to shade
    // at the bottom and the edges, like a console held under a lamp.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [
            Colors.white.withValues(alpha: dark ? 0.05 : 0.10),
            Colors.transparent,
            Colors.black.withValues(alpha: dark ? 0.12 : 0.05),
          ],
          [0, 0.45, 1],
        ),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          size.longestSide * 0.75,
          [
            Colors.transparent,
            Colors.black.withValues(alpha: dark ? 0.18 : 0.06),
          ],
          [0.6, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.dark != dark;
}

/// Lays the plastic grain over [child] (the whole app), ignoring touches.
class PlasticGrain extends StatelessWidget {
  const PlasticGrain({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: plasticGrainVisible,
              builder: (context, visible, _) => visible && plasticGrainEnabled
                  ? RepaintBoundary(
                      child: CustomPaint(painter: _GrainPainter(dark)),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

/// How far a key cap travels when pressed, in logical pixels: the height of
/// its side wall at rest.
const double plasticTravel = 4;

/// A key cap moulded in plastic, drawn over the button's own fill. At rest the
/// cap stands on a shaded side wall [plasticTravel] high: a convex face lit
/// from above with the shell's stipple, a bright chamfer along its top edge
/// and a crisp shadow line where the face meets the wall. Pressed ([t] 1) the
/// face travels down into the wall: the wall disappears, the housing's rim
/// shades the top of the face and the label sinks with it.
class _KeycapPainter extends CustomPainter {
  const _KeycapPainter({
    required this.radius,
    required this.t,
    required this.strength,
  });

  final double radius;

  /// 0 at rest, 1 fully pressed.
  final double t;

  /// 1 for a live button, lower when disabled.
  final double strength;

  Color _w(double a) => Colors.white.withValues(alpha: a * strength);
  Color _b(double a) => Colors.black.withValues(alpha: a * strength);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = min(radius, size.shortestSide / 2);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(r));
    final wall = min(plasticTravel, size.height * 0.14) * (1 - t);
    final sink = min(plasticTravel, size.height * 0.14) * t;
    final face = RRect.fromRectAndRadius(
      Rect.fromLTRB(0, sink, size.width, size.height - wall),
      Radius.circular(r),
    );
    canvas.save();
    canvas.clipRRect(rr);
    // The side wall below the face, darker towards the base.
    if (wall > 0.2) {
      canvas.drawRect(
        Rect.fromLTRB(0, size.height - wall - r, size.width, size.height),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, size.height - wall),
            rect.bottomCenter,
            [_b(0.34), _b(0.5)],
          ),
      );
    }
    // The housing's rim shades the top of a sunken face.
    if (sink > 0.2) {
      canvas.drawRect(
        Rect.fromLTRB(0, 0, size.width, sink + 3),
        Paint()
          ..shader = ui.Gradient.linear(rect.topCenter, Offset(0, sink + 3), [
            _b(0.55),
            _b(0),
          ]),
      );
    }
    canvas.save();
    canvas.clipRRect(face);
    // Convex face: lit top, a soft dip, shade towards the lower edge.
    canvas.drawRect(
      face.outerRect,
      Paint()
        ..shader = ui.Gradient.linear(
          face.outerRect.topCenter,
          face.outerRect.bottomCenter,
          [
            _w(0.26 - 0.18 * t),
            _w(0.05),
            Colors.transparent,
            _b(0.16 + 0.1 * t),
          ],
          [0, 0.38, 0.6, 1],
        ),
    );
    // The stipple of the moulded cap.
    canvas.drawRect(
      face.outerRect,
      Paint()
        ..shader = ImageShader(
          _grain(),
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..color = Color.fromRGBO(0, 0, 0, 0.55 * strength)
        ..blendMode = BlendMode.softLight,
    );
    // Specular glint across the top of the face.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          r * 0.5,
          face.top + 1.6,
          size.width - r * 0.5,
          face.top + face.height * 0.32,
        ),
        Radius.circular(r),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, face.top),
          Offset(0, face.top + face.height * 0.32),
          [_w(0.16 * (1 - t)), Colors.transparent],
        ),
    );
    canvas.restore();
    // Chamfer: bright where the face turns towards the light.
    canvas.drawRRect(
      face.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = ui.Gradient.linear(
          face.outerRect.topCenter,
          face.outerRect.bottomCenter,
          [_w(0.42 * (1 - t) + 0.06), _w(0.04), Colors.transparent],
          [0, 0.3, 1],
        ),
    );
    // The crisp line where the face meets the wall.
    if (wall > 0.2) {
      canvas.drawRRect(
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = ui.Gradient.linear(
            face.outerRect.topCenter,
            face.outerRect.bottomCenter,
            [Colors.transparent, Colors.transparent, _b(0.55)],
            [0, 0.6, 1],
          ),
      );
    }
    canvas.restore();
    // Outer rim of the whole key.
    canvas.drawRRect(
      rr.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _b(0.35),
    );
  }

  @override
  bool shouldRepaint(_KeycapPainter old) =>
      old.t != t || old.strength != strength || old.radius != radius;
}

/// A label pressed into plastic: a dark edge above and a lit edge below.
const List<Shadow> debossShadows = [
  Shadow(offset: Offset(0, -0.6), color: Color(0x66000000)),
  Shadow(offset: Offset(0, 0.8), color: Color(0x2EFFFFFF)),
];

/// A button's key cap around its label: the cap travels down over 70 ms when
/// pressed and springs back up when released, carrying the label with it.
class _Keycap extends StatelessWidget {
  const _Keycap({required this.states, required this.child});

  final Set<WidgetState> states;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final pressed = states.contains(WidgetState.pressed);
    final strength = states.contains(WidgetState.disabled) ? 0.35 : 1.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: pressed ? 1 : 0),
      duration: Duration(milliseconds: pressed ? 50 : 110),
      curve: pressed ? Curves.easeOut : Curves.easeOutBack,
      child: child,
      builder: (context, t, child) => CustomPaint(
        painter: _KeycapPainter(
          radius: plasticButtonRadius,
          t: t.clamp(0.0, 1.0),
          strength: strength,
        ),
        child: Transform.translate(
          // Centred on the face: up by half the wall at rest, down when sunk.
          offset: Offset(0, -plasticTravel / 2 + plasticTravel * t * 0.9),
          child: child,
        ),
      ),
    );
  }
}

WidgetStateProperty<double> _depth({double rest = 2, double raised = 5}) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return 0;
      if (states.contains(WidgetState.pressed)) return 0;
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return raised;
      }
      return rest;
    });

/// Key caps for filled, tonal, elevated, outlined and text buttons. [face]
/// gives buttons with no fill of their own (outlined, text) a cap colour.
ButtonStyle plasticButtonStyle(TextStyle? label, {Color? face}) {
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(plasticButtonRadius)),
  );
  return ButtonStyle(
    shape: const WidgetStatePropertyAll(shape),
    side: const WidgetStatePropertyAll(BorderSide.none),
    backgroundColor: face == null
        ? null
        : WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? face.withValues(alpha: 0.5)
                : face,
          ),
    shadowColor: const WidgetStatePropertyAll(Colors.black),
    elevation: _depth(),
    // A key moves instead of rippling.
    splashFactory: NoSplash.splashFactory,
    textStyle: WidgetStatePropertyAll(
      label?.copyWith(fontWeight: FontWeight.w800, shadows: debossShadows),
    ),
    backgroundBuilder: (context, states, child) =>
        _Keycap(states: states, child: child),
  );
}

/// Icon buttons sink into the shell as a round dimple when pressed.
ButtonStyle plasticIconButtonStyle() => ButtonStyle(
  shadowColor: const WidgetStatePropertyAll(Colors.black),
  splashFactory: NoSplash.splashFactory,
  backgroundBuilder: (context, states, child) {
    // Plain icon buttons have no fill: only the pressed dimple shows.
    return states.contains(WidgetState.pressed)
        ? CustomPaint(
            painter: _DimplePainter(),
            child: Transform.translate(
              offset: const Offset(0, 1),
              child: child,
            ),
          )
        : child ?? const SizedBox.shrink();
  },
);

class _DimplePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawOval(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [
            Colors.black.withValues(alpha: 0.38),
            Colors.black.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.10),
          ],
          [0, 0.5, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_DimplePainter old) => false;
}

/// A rounded outline moulded into the shell. Raised (cards, dialogs, sheets,
/// chips): a bright chamfer along the top edge and a shaded lip along the
/// bottom, like a panel standing proud of the case. Sunken (search bar,
/// selected navigation item): the reverse, like a window set into the case.
///
/// The bevel is painted over the shape's contents, so it stays visible over
/// cover art; [side] is kept for [copyWith] callers but not drawn.
class BevelBorder extends OutlinedBorder {
  const BevelBorder({
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.sunken = false,
    super.side,
  });

  final BorderRadiusGeometry borderRadius;
  final bool sunken;

  RRect _rrect(Rect rect, TextDirection? textDirection) =>
      borderRadius.resolve(textDirection).toRRect(rect);

  @override
  BevelBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
    bool? sunken,
  }) => BevelBorder(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
    sunken: sunken ?? this.sunken,
  );

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect, textDirection));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect, textDirection));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty) return;
    final rr = _rrect(rect, textDirection);
    final light = Colors.white.withValues(alpha: 0.22);
    final shade = Colors.black.withValues(alpha: 0.5);
    canvas.drawRRect(
      rr.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          sunken
              ? [shade, Colors.transparent, light]
              : [light, Colors.transparent, shade],
          [0, 0.5, 1],
        ),
    );
    // A second, softer chamfer inside the first: the moulded edge's width.
    canvas.drawRRect(
      rr.deflate(2.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          sunken
              ? [
                  Colors.black.withValues(alpha: 0.22),
                  Colors.transparent,
                  Colors.transparent,
                ]
              : [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.18),
                ],
          [0, 0.5, 1],
        ),
    );
  }

  @override
  ShapeBorder scale(double t) => BevelBorder(
    side: side.scale(t),
    borderRadius: borderRadius * t,
    sunken: sunken,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is BevelBorder && a.sunken == sunken) {
      return BevelBorder(
        side: BorderSide.lerp(a.side, side, t),
        borderRadius: BorderRadiusGeometry.lerp(
          a.borderRadius,
          borderRadius,
          t,
        )!,
        sunken: sunken,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is BevelBorder && b.sunken == sunken) {
      return BevelBorder(
        side: BorderSide.lerp(side, b.side, t),
        borderRadius: BorderRadiusGeometry.lerp(
          borderRadius,
          b.borderRadius,
          t,
        )!,
        sunken: sunken,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) =>
      other is BevelBorder &&
      other.side == side &&
      other.borderRadius == borderRadius &&
      other.sunken == sunken;

  @override
  int get hashCode => Object.hash(side, borderRadius, sunken);
}
