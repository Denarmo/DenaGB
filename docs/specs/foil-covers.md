# Foil covers

Library covers carry a subtle metallic foil reflection: a sharp warm-white glint with a soft sheen
and faint brushed grain that slides across the cover as the phone tilts, with the rest of the cover
dimmed slightly for contrast. Colour is only a hint of thin-film tint at the sheen's edges.

- **Tilt source:** one shared `FoilTilt` (Dart) fed by `TiltSensor` (Kotlin, EventChannel `app.dena/tilt`):
  game rotation vector, falling back to the accelerometer. The values are low-pass filtered and emitted at about 30 Hz as `[x, y]` in -1..1, where
  ±25° of roll, or of pitch around a 45° hold, is a full ±1 (one wrist turn sweeps the glint corner to corner).
- **No sensor** (or a non-Android platform, such as the handheld): every 6 s a glint glides across
  in 1.6 s (30 Hz timer), then rests off the cover; the value does not change while resting, so nothing repaints.
- **Lifecycle:** sensors and timers run only while at least one cover listens, the cover's
  tab is visible (`TickerMode`), and the app is resumed. Otherwise they are unregistered.
- **Rendering:** the Flutter fragment shader `shaders/foil.frag` (Impeller/Skia SkSL, the
  cross-platform equivalent of AGSL) draws the glint, sheen and shading, inside each cover's own
  `RepaintBoundary`, so a tilt repaints only the overlays. If the shader fails to load, a
  `LinearGradient` overlay is used instead.
- Only covers with art get foil; placeholders do not.
- **Tests:** `FoilTilt.animate = false` in `flutter_test_config.dart` (static sheen, no timers);
  the golden `game_card_cover_phone_touch.png` shows the overlay.

## Handhelds

With D-pad focus there is one cover in view at a time, so on the Linux handheld
only the focused cover follows the idle sweep; the others rest with the glint
off them and never repaint for it. This keeps the 640x480 library at 60 fps on
the Mali-G31.
