// SPDX-License-Identifier: GPL-3.0-or-later
// Metallic foil reflection on library covers. Spec: docs/specs/foil-covers.md
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../shell/handheld.dart';

/// One tilt source shared by every cover. Listens to the phone's motion
/// sensors only while at least one visible cover listens and the app is in
/// the foreground; otherwise (or with no sensor) a slow time-based sweep.
class FoilTilt extends ValueNotifier<Offset> with WidgetsBindingObserver {
  FoilTilt._() : super(Offset.zero);

  static final FoilTilt instance = FoilTilt._();
  static const _channel = EventChannel('app.dena/tilt');

  /// Off in tests: the sheen then stays still (no sensors, no timers).
  static bool animate = true;

  StreamSubscription<dynamic>? _sub;
  Timer? _sweep;
  bool _noSensor = false;
  bool _observing = false;
  bool _foreground = true;
  int _users = 0;
  final _clock = Stopwatch();

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_users++ == 0) _start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (--_users == 0) _stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    fg ? _start() : _stop();
  }

  void _start() {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (_users == 0 || !_foreground || !animate) return;
    if (!_noSensor && defaultTargetPlatform == TargetPlatform.android) {
      _sub ??= _channel.receiveBroadcastStream().listen(
        (e) {
          final l = e as List;
          value = Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
        },
        onError: (_) {
          _noSensor = true;
          _sub?.cancel();
          _sub = null;
          _startSweep();
        },
      );
    } else {
      _startSweep();
    }
  }

  /// No sensor: every [_sweepPeriod] a glint glides across the covers in
  /// [_glide], then rests off the cover until the next pass.
  static const _sweepPeriod = 6.0;
  static const _glide = 1.6;

  void _startSweep() {
    _clock.start();
    _sweep ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      value = sweepAt(_clock.elapsedMilliseconds / 1000.0);
    });
  }

  /// Where the idle sweep rests between passes: the glint is off the cover.
  static const rest = Offset(1.4, 0);

  /// The idle sweep's tilt at [seconds]; unchanged while resting, so the
  /// covers do not repaint between passes.
  @visibleForTesting
  static Offset sweepAt(double seconds) {
    final phase = (seconds % _sweepPeriod) / _glide;
    if (phase >= 1) return rest;
    final e = phase * phase * (3 - 2 * phase);
    return Offset(-1.4 + 2.8 * e, 0);
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _sweep?.cancel();
    _sweep = null;
    _clock.stop();
  }
}

ui.FragmentProgram? _program;
bool _programTried = false;

/// Loads the foil shader once; until (or unless) it loads, covers use a
/// gradient overlay.
Future<void> loadFoilShader() async {
  if (_programTried) return;
  _programTried = true;
  try {
    _program = await ui.FragmentProgram.fromAsset('shaders/foil.frag');
  } catch (_) {}
}

/// Paints the foil sheen above [child]. Only repaints its own layer, and
/// only follows the tilt while ticker mode is on (the tab is visible).
class FoilOverlay extends StatefulWidget {
  const FoilOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<FoilOverlay> createState() => _FoilOverlayState();
}

class _FoilOverlayState extends State<FoilOverlay> {
  ui.FragmentShader? _shader;
  bool _listening = false;

  /// Handhelds sweep only the focused cover (foil-covers.md, Handhelds); the
  /// others rest with the glint off them.
  bool _resting = false;

  @override
  void initState() {
    super.initState();
    loadFoilShader().then((_) {
      if (mounted && _program != null) {
        setState(() => _shader = _program!.fragmentShader());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    final resting =
        Handheld.of(context) && !(Focus.maybeOf(context)?.hasFocus ?? false);
    final listening = visible && !resting;
    if (listening == _listening && resting == _resting) return;
    _listening = listening;
    _resting = resting;
    // RepaintBoundary + CustomPaint(repaint:) does the listening; flip a
    // rebuild so the painter attaches or detaches.
    setState(() {});
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _FoilPainter(
                _listening ? FoilTilt.instance : null,
                _shader,
                resting: _resting,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _FoilPainter extends CustomPainter {
  _FoilPainter(this.tilt, this.shader, {this.resting = false})
    : super(repaint: tilt);

  final FoilTilt? tilt;
  final ui.FragmentShader? shader;
  final bool resting;

  @override
  void paint(Canvas canvas, Size size) {
    final t = resting ? FoilTilt.rest : tilt?.value ?? FoilTilt.instance.value;
    final rect = Offset.zero & size;
    final s = shader;
    if (s != null) {
      s
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, t.dx)
        ..setFloat(3, t.dy);
      canvas.drawRect(rect, Paint()..shader = s);
      return;
    }
    final shift = t.dx * 0.75 + t.dy * 0.35;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment(-1 + shift * 2, -1),
          end: Alignment(1 + shift * 2, 1),
          colors: const [
            Color(0x00FFFFFF),
            Color(0x0FFFF8E0),
            Color(0x40FFF8E0),
            Color(0x0FFFF8E0),
            Color(0x00FFFFFF),
          ],
          stops: const [0.3, 0.45, 0.5, 0.55, 0.7],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_FoilPainter old) =>
      old.tilt != tilt || old.shader != shader || old.resting != resting;
}
