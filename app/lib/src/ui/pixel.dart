// SPDX-License-Identifier: GPL-3.0-or-later
// Pocket LCD building blocks: dither fills, double-bordered windows, focus
// brackets, inverted header strips, the glass over the screen, and the
// putty-and-slate shell with its rubber keys.
// Spec: docs/specs/pocket-lcd-ui.md
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'pixel_icons.dart';
import 'pocket.dart';

/// How many cells of a dither fill are lit.
enum DitherDensity {
  /// One cell in four, the pause dim.
  quarter,

  /// A checkerboard, the shelves and the zoom plinth.
  half,
}

/// Fills its area with [color] in a [density] dither of [cell]-pixel cells.
class DitherPainter extends CustomPainter {
  const DitherPainter({
    required this.color,
    required this.cell,
    this.density = DitherDensity.half,
  });

  final Color color;
  final double cell;
  final DitherDensity density;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / cell).ceil(), rows = (size.height / cell).ceil();
    final quarter = density == DitherDensity.quarter;
    final points = <double>[];
    for (var y = 0; y < rows; y++) {
      if (quarter && y.isOdd) continue;
      for (var x = quarter ? 0 : y & 1; x < cols; x += 2) {
        points
          ..add((x + 0.5) * cell)
          ..add((y + 0.5) * cell);
      }
    }
    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.fromList(points),
      Paint()
        ..color = color
        ..strokeWidth = cell
        ..strokeCap = StrokeCap.square,
    );
  }

  @override
  bool shouldRepaint(DitherPainter old) =>
      old.color != color || old.cell != cell || old.density != density;
}

/// A dithered fill as a widget.
class Dither extends StatelessWidget {
  const Dither({
    super.key,
    this.color,
    this.density = DitherDensity.half,
    this.child,
  });

  final Color? color;
  final DitherDensity density;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    return CustomPaint(
      painter: DitherPainter(
        color: color ?? style.palette.light,
        cell: style.metrics.px,
        density: density,
      ),
      child: child ?? const SizedBox.expand(),
    );
  }
}

/// A double-bordered RPG window: a thick ink frame, a paper gap and a thin
/// inner line.
class PixelWindow extends StatelessWidget {
  const PixelWindow({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final px = style.metrics.px, p = style.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border.all(color: p.ink, width: px * 2),
      ),
      child: Padding(
        padding: EdgeInsets.all(px),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: p.ink, width: px),
          ),
          // Its own Material, so menu rows highlight over any route.
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: padding ?? EdgeInsets.all(px * 2),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pixel corner brackets around [child] when [visible]: the D-pad focus.
class PixelBrackets extends StatelessWidget {
  const PixelBrackets({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!visible) return child;
    final style = PocketStyle.of(context);
    return CustomPaint(
      foregroundPainter: _BracketPainter(style.palette.ink, style.metrics.px),
      child: child,
    );
  }
}

class _BracketPainter extends CustomPainter {
  _BracketPainter(this.ink, this.px);

  final Color ink;
  final double px;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final arm = (size.shortestSide * 0.22).clamp(5 * px, 10 * px);
    final w = px * 1.5;
    final paint = Paint()..color = ink;
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawRect(
        Rect.fromPoints(corner, corner + Offset(arm * dx, w * dy)),
        paint,
      );
      canvas.drawRect(
        Rect.fromPoints(corner, corner + Offset(w * dx, arm * dy)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.ink != ink || old.px != px;
}

/// An inverted strip: paper text on ink, like an LCD menu's header row.
class InvertedBar extends StatelessWidget {
  const InvertedBar({
    super.key,
    required this.title,
    this.trailing,
    this.glyph,
    this.large = false,
  });

  final String title;
  final String? trailing;
  final PixelGlyph? glyph;

  /// The screen header (Press Start 2P) rather than a section header.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette, m = style.metrics;
    final text = Theme.of(context).textTheme;
    final face = (large ? text.titleLarge : text.labelLarge)?.copyWith(
      color: p.paper,
    );
    return Semantics(
      header: true,
      child: Container(
        color: p.ink,
        padding: EdgeInsets.symmetric(horizontal: 4 * m.px, vertical: 2 * m.px),
        child: Row(
          children: [
            if (glyph case final g?) ...[
              PixelIcon(g, size: 9 * m.px, color: p.paper),
              SizedBox(width: 3 * m.px),
            ],
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: face,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing case final t?)
              Text(
                t.toUpperCase(),
                style: text.labelMedium?.copyWith(color: p.light),
              ),
          ],
        ),
      ),
    );
  }
}

/// The screen's glass: a faint pixel grid and a soft glare from the top
/// left. Paints over the screen, never takes touches.
class LcdGlass extends StatelessWidget {
  const LcdGlass({super.key, required this.child, this.grid = true});

  final Widget child;

  /// The grid only shows where a virtual pixel is several device pixels.
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    return CustomPaint(
      foregroundPainter: _GlassPainter(
        ink: style.palette.ink,
        px: style.metrics.px,
        grid: grid,
      ),
      child: child,
    );
  }
}

class _GlassPainter extends CustomPainter {
  _GlassPainter({required this.ink, required this.px, required this.grid});

  final Color ink;
  final double px;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (grid) {
      final line = Paint()
        ..color = ink.withValues(alpha: 0.05)
        ..strokeWidth = 0.5;
      for (var x = px; x < size.width; x += px) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
      for (var y = px; y < size.height; y += px) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width * 0.6, size.height * 0.45),
          [const Color(0x18FFFFFF), const Color(0x00FFFFFF)],
        ),
    );
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.ink != ink || old.px != px || old.grid != grid;
}

/// One tab of the shell's navigation.
class PocketDestination {
  const PocketDestination(this.glyph, this.label);

  final PixelGlyph glyph;
  final String label;
}

/// The phone as the console: the screen in an asymmetric slate bezel with a
/// power LED, the Dena.emu GB print and speaker slots, and the tabs as
/// chunky rubber keys with an LED on the active one.
class PocketBezel extends StatelessWidget {
  const PocketBezel({
    super.key,
    required this.screen,
    required this.destinations,
    required this.selected,
    required this.onSelect,
  });

  final Widget screen;
  final List<PocketDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFDEDAD1),
            PocketShell.putty,
            PocketShell.puttyShade,
          ],
          stops: [0, 0.55, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: PocketShell.slate,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(44),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x33000000),
                        offset: Offset(0, 2),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BezelLabel(),
                        Expanded(
                          child: DecoratedBox(
                            position: DecorationPosition.foreground,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: PocketShell.slateDark,
                                width: 2,
                              ),
                            ),
                            child: ClipRect(
                              child: Material(
                                color: p.paper,
                                child: LcdGlass(child: screen),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const _ShellPrint(),
            RubberKeyNav(
              destinations: destinations,
              selected: selected,
              onSelect: onSelect,
            ),
          ],
        ),
      ),
    );
  }
}

/// POWER with its LED on the left, pinstripes, DENA.EMU GB on the right.
class _BezelLabel extends StatelessWidget {
  const _BezelLabel();

  @override
  Widget build(BuildContext context) {
    const print = TextStyle(
      fontFamily: 'Nunito',
      fontSize: 8,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      letterSpacing: 1.2,
      color: Color(0xFFB5B6CC),
    );
    Widget stripe() => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 1, color: PocketShell.berry),
            const SizedBox(height: 2),
            Container(height: 1, color: const Color(0xFF7B7DA6)),
          ],
        ),
      ),
    );
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: PocketShell.led,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x99E8336B), blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 4),
          const Text('POWER', style: print),
          stripe(),
          const Text('DENA.EMU GB  POCKET LCD', style: print),
        ],
      ),
    );
  }
}

/// "Dena.emu GB" printed on the shell, with the speaker slots.
class _ShellPrint extends StatelessWidget {
  const _ShellPrint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'Dena.emu',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: PocketShell.print,
              height: 1,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'GB  POCKET',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 9,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              letterSpacing: 1.6,
              color: PocketShell.print,
              height: 1.6,
            ),
          ),
          const Spacer(),
          ExcludeSemantics(
            child: Transform(
              transform: Matrix4.skewX(-0.35),
              alignment: Alignment.bottomCenter,
              child: Row(
                children: [
                  for (var i = 0; i < 5; i++)
                    Container(
                      width: 4,
                      height: 18,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9E998F),
                        borderRadius: BorderRadius.circular(2),
                        border: const Border(
                          top: BorderSide(color: Color(0xFF7D786F)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tabs as rubber keys in recessed wells, with an LED by the active
/// tab's printed name. Keys drop 3 px while pressed.
class RubberKeyNav extends StatelessWidget {
  const RubberKeyNav({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelect,
  });

  final List<PocketDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          for (final (i, d) in destinations.indexed)
            Expanded(
              child: _RubberKey(
                destination: d,
                active: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _RubberKey extends StatefulWidget {
  const _RubberKey({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final PocketDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_RubberKey> createState() => _RubberKeyState();
}

class _RubberKeyState extends State<_RubberKey> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    const travel = 3.0;
    final active = widget.active;
    final face = active ? const Color(0xFF6A6B88) : PocketShell.rubber;
    final glyph = active ? const Color(0xFFF4B7CF) : const Color(0xFFE6E6F0);
    return Semantics(
      button: true,
      selected: active,
      label: widget.destination.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The recessed well.
              Container(
                height: 54,
                padding: const EdgeInsets.fromLTRB(5, 5, 5, 3),
                decoration: BoxDecoration(
                  color: PocketShell.puttyShade,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x22000000)),
                ),
                child: Stack(
                  children: [
                    // The key's side wall, seen below the cap.
                    Positioned.fill(
                      top: travel,
                      child: Container(
                        decoration: BoxDecoration(
                          color: PocketShell.slateDark,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 50),
                      left: 0,
                      right: 0,
                      top: _down ? travel : 0,
                      bottom: _down ? 0 : travel,
                      child: Container(
                        decoration: BoxDecoration(
                          color: face,
                          borderRadius: BorderRadius.circular(10),
                          border: const Border(
                            top: BorderSide(color: Color(0x40FFFFFF)),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: PixelIcon(
                          widget.destination.glyph,
                          size: 22,
                          color: glyph,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? PocketShell.led : const Color(0xFFA8A398),
                      boxShadow: active
                          ? const [
                              BoxShadow(
                                color: Color(0x99E8336B),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.destination.label.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1.4,
                      color: active ? PocketShell.berry : PocketShell.print,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tabs inside the screen, for the handheld and fullscreen desktop:
/// an inverted strip with L / R tabs, the active tab lit on paper.
class LcdTabStrip extends StatelessWidget {
  const LcdTabStrip({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelect,
    this.trailing,
  });

  final List<PocketDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette, px = style.metrics.px;
    final text = Theme.of(context).textTheme.labelLarge;
    Widget shoulder(String l) => Container(
      margin: EdgeInsets.symmetric(horizontal: 2 * px),
      padding: EdgeInsets.symmetric(horizontal: 2 * px),
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(2 * px)),
      ),
      child: Text(l, style: text?.copyWith(color: p.ink)),
    );
    return Container(
      color: p.ink,
      padding: EdgeInsets.symmetric(vertical: px),
      child: Row(
        children: [
          ExcludeSemantics(child: shoulder('L')),
          for (final (i, d) in destinations.indexed)
            Semantics(
              button: true,
              selected: i == selected,
              label: d.label,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: Container(
                  color: i == selected ? p.paper : p.ink,
                  padding: EdgeInsets.symmetric(
                    horizontal: 4 * px,
                    vertical: px,
                  ),
                  child: Row(
                    children: [
                      PixelIcon(
                        d.glyph,
                        size: 9 * px,
                        color: i == selected ? p.ink : p.paper,
                      ),
                      SizedBox(width: 2 * px),
                      Text(
                        d.label.toUpperCase(),
                        style: text?.copyWith(
                          color: i == selected ? p.ink : p.paper,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ExcludeSemantics(child: shoulder('R')),
          const Spacer(),
          if (trailing case final t?)
            Padding(
              padding: EdgeInsets.only(right: 4 * px),
              child: Text(t, style: text?.copyWith(color: p.light)),
            ),
        ],
      ),
    );
  }
}

/// A colour filter mapping any image onto the screen's shades: luminance
/// from [ink] to [paper], with a little extra contrast so cover art reads
/// in four tones.
ColorFilter lcdShadeFilter(LcdPalette p) {
  const contrast = 1.35;
  const lr = 0.299 * contrast, lg = 0.587 * contrast, lb = 0.114 * contrast;
  const bias = (1 - contrast) / 2; // keeps mid grey in place
  List<double> row(double ink, double paper) {
    final span = paper - ink;
    return [lr * span, lg * span, lb * span, 0, (ink + bias * span) * 255];
  }

  return ColorFilter.matrix([
    ...row(p.ink.r, p.paper.r),
    ...row(p.ink.g, p.paper.g),
    ...row(p.ink.b, p.paper.b),
    0,
    0,
    0,
    1,
    0,
  ]);
}

/// A two-cell pixel switch: OFF | ON, the chosen cell inverted.
class PixelSwitch extends StatelessWidget {
  const PixelSwitch({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette, px = style.metrics.px;
    final text = Theme.of(context).textTheme.labelMedium;
    Widget cell(String label, bool lit) => Container(
      color: lit ? p.ink : p.paper,
      padding: EdgeInsets.symmetric(horizontal: 2 * px, vertical: px),
      child: Text(label, style: text?.copyWith(color: lit ? p.paper : p.ink)),
    );
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: p.ink, width: px),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [cell('OFF', !value), cell('ON', value)],
        ),
      ),
    );
  }
}

/// A settings row with a [PixelSwitch]; A or a tap flips it.
class PixelSwitchTile extends StatelessWidget {
  const PixelSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.autofocus = false,
  });

  final Widget title;
  final Widget? subtitle, leading;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    child: ListTile(
      autofocus: autofocus,
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: PixelSwitch(value: value),
      onTap: () => onChanged(!value),
    ),
  );
}

/// One command in an RPG window: a pixel glyph and a label. Focus inverts
/// the row and shows the ▶ cursor; A or a tap runs [onPressed]. With no
/// [onPressed] the row is dimmed and skipped by the D-pad.
class PixelMenuItem extends StatefulWidget {
  const PixelMenuItem({
    super.key,
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.trailing,
    this.autofocus = false,
  });

  final PixelGlyph glyph;
  final String label;
  final String? trailing;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  State<PixelMenuItem> createState() => _PixelMenuItemState();
}

class _PixelMenuItemState extends State<PixelMenuItem> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette, px = style.metrics.px;
    final text = Theme.of(context).textTheme;
    final enabled = widget.onPressed != null;
    final fg = focused ? p.paper : (enabled ? p.ink : p.dark);
    return InkWell(
      autofocus: widget.autofocus,
      onTap: widget.onPressed,
      onFocusChange: (f) => setState(() => focused = f),
      splashFactory: NoSplash.splashFactory,
      focusColor: Colors.transparent,
      hoverColor: p.light.withValues(alpha: 0.5),
      highlightColor: p.light,
      child: Container(
        color: focused ? p.ink : null,
        constraints: BoxConstraints(minHeight: 14 * px),
        padding: EdgeInsets.symmetric(horizontal: px, vertical: 2 * px),
        child: Row(
          children: [
            SizedBox(
              width: 6 * px,
              child: focused
                  ? PixelIcon(PixelGlyphs.cursor, size: 9 * px, color: fg)
                  : null,
            ),
            PixelIcon(widget.glyph, size: 9 * px, color: fg),
            SizedBox(width: 3 * px),
            Expanded(
              child: Text(
                widget.label,
                style: text.labelLarge?.copyWith(color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.trailing case final t?)
              Text(t, style: text.labelMedium?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// A row of square cells, one lit: the 1X / 2X / 4X speed pick. Each cell
/// takes focus; brackets mark the focused one.
class PixelCells<T> extends StatelessWidget {
  const PixelCells({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette, px = style.metrics.px;
    final text = Theme.of(context).textTheme.labelLarge;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: p.ink, width: px),
      ),
      child: Row(
        children: [
          for (final (i, v) in values.indexed)
            Expanded(
              child: _Cell(
                label: labels[i],
                lit: v == selected,
                style: text,
                onTap: () => onSelected(v),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatefulWidget {
  const _Cell({
    required this.label,
    required this.lit,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool lit;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette, px = style.metrics.px;
    return Semantics(
      selected: widget.lit,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => focused = f),
        splashFactory: NoSplash.splashFactory,
        focusColor: Colors.transparent,
        highlightColor: p.light,
        child: PixelBrackets(
          visible: focused,
          child: Container(
            color: widget.lit ? p.ink : null,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(vertical: 3 * px),
            child: Text(
              widget.label,
              style: widget.style?.copyWith(
                color: widget.lit ? p.paper : p.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen pause backdrop: the game shows through a 25% ink dither
/// and [child] sits at the bottom. A tap on the dither calls [onDismiss].
class PocketDim extends StatelessWidget {
  const PocketDim({super.key, required this.child, required this.onDismiss});

  final Widget child;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = PocketStyle.of(context).palette;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: Dither(color: p.ink, density: DitherDensity.quarter),
          ),
        ),
        Align(alignment: Alignment.bottomCenter, child: child),
      ],
    );
  }
}
