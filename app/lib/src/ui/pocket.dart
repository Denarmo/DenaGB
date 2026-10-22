// SPDX-License-Identifier: GPL-3.0-or-later
// The Pocket LCD look: the whole app drawn on a four-shade pocket screen
// inside a putty-and-slate shell.
// Spec: docs/specs/pocket-lcd-ui.md
import 'package:material_ui/material_ui.dart';

import 'dena_icons.dart';

/// One LCD palette: four shades from the screen's paper to its ink. The
/// same shades as the dot matrix shader's palettes (pocket-lcd.glsl).
class LcdPalette {
  const LcdPalette(
    this.id,
    this.name,
    this.paper,
    this.light,
    this.dark,
    this.ink,
  );

  final String id, name;

  /// Lightest to darkest.
  final Color paper, light, dark, ink;

  /// Whether the screen is dark with light ink (Inverted).
  bool get inverted => paper.computeLuminance() < ink.computeLuminance();
}

/// The palettes, in the order of the shader's `palette` parameter.
const lcdUiPalettes = <LcdPalette>[
  LcdPalette(
    'olive',
    'Olive',
    Color(0xFFC5D48A),
    Color(0xFF8DA24A),
    Color(0xFF46652E),
    Color(0xFF1B2E17),
  ),
  LcdPalette(
    'grey',
    'Pocket grey',
    Color(0xFFCDCEC5),
    Color(0xFF979990),
    Color(0xFF5A5C55),
    Color(0xFF232420),
  ),
  LcdPalette(
    'amber',
    'Backlit amber',
    Color(0xFFFFB63B),
    Color(0xFFD87308),
    Color(0xFF803300),
    Color(0xFF2E1000),
  ),
  LcdPalette(
    'inverted',
    'Inverted',
    Color(0xFF1B2E17),
    Color(0xFF46652E),
    Color(0xFF8DA24A),
    Color(0xFFC5D48A),
  ),
];

/// The palette for a saved id; anything else (older theme ids) is Olive.
LcdPalette lcdUiPalette(String id) =>
    lcdUiPalettes.firstWhere((p) => p.id == id, orElse: () => lcdUiPalettes[0]);

/// The palette's index, which is also the shader's `palette` value.
int lcdUiPaletteIndex(String id) {
  final i = lcdUiPalettes.indexWhere((p) => p.id == id);
  return i < 0 ? 0 : i;
}

/// The moulded shell around the screen.
abstract final class PocketShell {
  /// Matte putty plastic.
  static const putty = Color(0xFFD4D0C7);
  static const puttyShade = Color(0xFFB9B4AA);

  /// The slate screen bezel.
  static const slate = Color(0xFF4F5067);
  static const slateDark = Color(0xFF3A3B4E);

  /// Rubber keys and the convex A/B domes.
  static const rubber = Color(0xFF5B5C75);
  static const berry = Color(0xFFA01F55);

  /// Lettering printed on the shell.
  static const print = Color(0xFF3A3B57);

  /// The power LED.
  static const led = Color(0xFFE8336B);
}

/// Title and header face (8 px grid).
const String pocketTitleFont = 'PressStart2P';

/// List, metadata and hint face (8 px grid).
const String pocketBodyFont = 'Silkscreen';

/// Sizes in logical pixels for one screen class. [px] is one virtual LCD
/// pixel: 2 on phones and the 640x480 handheld (authored at 320x240), 3 on
/// a desktop or TV fullscreen.
class PocketMetrics {
  const PocketMetrics(this.px);

  final double px;

  /// Press Start 2P cap line: one glyph is 8 virtual pixels.
  double get title => 8 * px;

  /// Silkscreen list and body text.
  double get body => 8 * px;

  /// Small print: metadata, hints.
  double get small => px >= 3 ? 6 * px : 12;

  static PocketMetrics of(BuildContext context) =>
      Theme.of(context).extension<PocketStyle>()?.metrics ??
      const PocketMetrics(2);
}

/// The virtual pixel size for a screen of [size]; [handheld] is the 640x480
/// D-pad device, integer-doubled.
double pocketPixelFor(Size size, {required bool handheld}) {
  if (handheld) return 2;
  return size.shortestSide >= 700 && size.width >= 1200 ? 3 : 2;
}

/// The palette and metrics, for widgets that draw pixels themselves.
class PocketStyle extends ThemeExtension<PocketStyle> {
  const PocketStyle({
    required this.palette,
    required this.metrics,
    this.colourCovers = false,
  });

  final LcdPalette palette;
  final PocketMetrics metrics;

  /// Show cover art in full colour instead of the screen's four shades.
  final bool colourCovers;

  static PocketStyle of(BuildContext context) =>
      Theme.of(context).extension<PocketStyle>() ??
      PocketStyle(palette: lcdUiPalettes[0], metrics: const PocketMetrics(2));

  @override
  PocketStyle copyWith({
    LcdPalette? palette,
    PocketMetrics? metrics,
    bool? colourCovers,
  }) => PocketStyle(
    palette: palette ?? this.palette,
    metrics: metrics ?? this.metrics,
    colourCovers: colourCovers ?? this.colourCovers,
  );

  @override
  PocketStyle lerp(PocketStyle? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// The colour scheme drawn from [p]: paper surfaces, ink text, and the two
/// middle shades for containers and outlines.
ColorScheme pocketScheme(LcdPalette p) {
  final mid = Color.lerp(p.paper, p.light, 0.5)!;
  return ColorScheme(
    brightness: p.inverted ? Brightness.dark : Brightness.light,
    primary: p.ink,
    onPrimary: p.paper,
    primaryContainer: p.light,
    onPrimaryContainer: p.ink,
    secondary: p.dark,
    onSecondary: p.paper,
    secondaryContainer: mid,
    onSecondaryContainer: p.ink,
    tertiary: p.dark,
    onTertiary: p.paper,
    tertiaryContainer: p.light,
    onTertiaryContainer: p.ink,
    error: p.ink,
    onError: p.paper,
    errorContainer: p.light,
    onErrorContainer: p.ink,
    surface: p.paper,
    onSurface: p.ink,
    onSurfaceVariant: p.dark,
    surfaceDim: mid,
    surfaceBright: p.paper,
    surfaceContainerLowest: p.paper,
    surfaceContainerLow: p.paper,
    surfaceContainer: p.paper,
    surfaceContainerHigh: Color.lerp(p.paper, p.light, 0.25)!,
    surfaceContainerHighest: mid,
    outline: p.dark,
    outlineVariant: p.light,
    shadow: p.ink,
    scrim: p.ink,
    inverseSurface: p.ink,
    onInverseSurface: p.paper,
    inversePrimary: p.paper,
    surfaceTint: Colors.transparent,
  );
}

/// Square pixel corners with a [width]-pixel ink line.
OutlinedBorder pixelBorder(Color ink, double width) => RoundedRectangleBorder(
  borderRadius: BorderRadius.zero,
  side: BorderSide(color: ink, width: width),
);

/// The Pocket LCD theme: four shades, square corners, two-pixel ink lines,
/// pixel fonts, no shadows or ripples.
ThemeData pocketTheme(
  LcdPalette palette,
  PocketMetrics m, {
  bool colourCovers = false,
}) {
  final scheme = pocketScheme(palette);
  final ink = palette.ink, paper = palette.paper;
  final px = m.px;
  final base = ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
    fontFamily: pocketBodyFont,
    fontFamilyFallback: const ['Nunito', 'Roboto'],
    splashFactory: NoSplash.splashFactory,
    scaffoldBackgroundColor: paper,
    canvasColor: paper,
  );
  TextStyle title(double size) => TextStyle(
    fontFamily: pocketTitleFont,
    fontSize: size,
    height: 1.4,
    color: ink,
    letterSpacing: 0,
  );
  TextStyle body(double size, [Color? color]) => TextStyle(
    fontFamily: pocketBodyFont,
    fontSize: size,
    height: 1.3,
    color: color ?? ink,
    letterSpacing: 0.5,
  );
  final text = base.textTheme.copyWith(
    displayLarge: title(m.title * 3),
    displayMedium: title(m.title * 2.5),
    displaySmall: title(m.title * 2),
    headlineLarge: title(m.title * 2),
    headlineMedium: title(m.title * 1.5),
    headlineSmall: title(m.title * 1.5),
    titleLarge: title(m.title),
    titleMedium: body(m.body),
    titleSmall: body(m.body),
    bodyLarge: body(m.body),
    bodyMedium: body(m.body),
    bodySmall: body(m.small, palette.dark),
    labelLarge: body(m.body),
    labelMedium: body(m.small),
    labelSmall: body(m.small),
  );
  final line = BorderSide(color: ink, width: px);
  final square = pixelBorder(ink, px);
  final buttonText = WidgetStatePropertyAll(text.labelLarge);
  ButtonStyle button({required bool filled}) => ButtonStyle(
    splashFactory: NoSplash.splashFactory,
    elevation: const WidgetStatePropertyAll(0),
    textStyle: buttonText,
    shape: WidgetStatePropertyAll(square),
    side: WidgetStatePropertyAll(line),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 6 * px, vertical: 3 * px),
    ),
    // Focus and press invert the key, like a selected menu line.
    backgroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return paper;
      final hot =
          s.contains(WidgetState.focused) ||
          s.contains(WidgetState.pressed) ||
          s.contains(WidgetState.selected);
      if (filled) return hot ? palette.dark : ink;
      return hot ? ink : paper;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return palette.light;
      final hot =
          s.contains(WidgetState.focused) ||
          s.contains(WidgetState.pressed) ||
          s.contains(WidgetState.selected);
      return filled || hot ? paper : ink;
    }),
    iconColor: WidgetStateProperty.resolveWith((s) {
      final hot =
          s.contains(WidgetState.focused) ||
          s.contains(WidgetState.pressed) ||
          s.contains(WidgetState.selected);
      return filled || hot ? paper : ink;
    }),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );
  return base.copyWith(
    textTheme: text,
    primaryTextTheme: text,
    extensions: [
      PocketStyle(palette: palette, metrics: m, colourCovers: colourCovers),
    ],
    focusColor: palette.light,
    hoverColor: palette.light.withValues(alpha: 0.5),
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    iconTheme: IconThemeData(color: ink, size: 9 * px + 2),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: paper,
      shape: square,
    ),
    filledButtonTheme: FilledButtonThemeData(style: button(filled: true)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: button(filled: true)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: button(filled: false)),
    textButtonTheme: TextButtonThemeData(
      style: button(filled: false)
          .copyWith(side: const WidgetStatePropertyAll(BorderSide.none)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        splashFactory: NoSplash.splashFactory,
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused) ? paper : ink,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused) ? ink : Colors.transparent,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      selectedIcon: const Icon(DenaIcons.check),
      style: button(filled: false).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ink : paper,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? paper : ink,
        ),
      ),
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(DenaIcons.arrowBack),
      closeButtonIconBuilder: (_) => const Icon(DenaIcons.close),
      drawerButtonIconBuilder: (_) => const Icon(DenaIcons.menu),
      endDrawerButtonIconBuilder: (_) => const Icon(DenaIcons.menu),
    ),
    // Page titles sit on an inverted strip, like the LCD's header row.
    appBarTheme: AppBarTheme(
      backgroundColor: ink,
      foregroundColor: paper,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      toolbarHeight: 14 * px + 8,
      iconTheme: IconThemeData(color: paper),
      actionsIconTheme: IconThemeData(color: paper),
      titleTextStyle: text.titleLarge?.copyWith(color: paper),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(paper),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: WidgetStatePropertyAll(square),
      side: WidgetStatePropertyAll(line),
      textStyle: WidgetStatePropertyAll(text.bodyLarge),
      hintStyle: WidgetStatePropertyAll(
        text.bodyLarge?.copyWith(color: palette.dark),
      ),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4 * px)),
    ),
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(),
      side: BorderSide.none,
      showCheckmark: false,
      elevation: 0,
      pressElevation: 0,
      backgroundColor: paper,
      selectedColor: ink,
      labelStyle: text.labelLarge,
      secondaryLabelStyle: text.labelLarge?.copyWith(color: paper),
      padding: EdgeInsets.symmetric(horizontal: 2 * px),
      labelPadding: EdgeInsets.symmetric(horizontal: 2 * px),
    ),
    dividerTheme: DividerThemeData(color: ink, thickness: px, space: 4 * px),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: paper,
      modalBackgroundColor: paper,
      elevation: 0,
      modalElevation: 0,
      dragHandleColor: palette.dark,
      shape: Border(
        top: BorderSide(color: ink, width: px * 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: paper,
      elevation: 0,
      shape: pixelBorder(ink, px * 2),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: paper,
      elevation: 0,
      shape: square,
      textStyle: text.bodyLarge,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(paper),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(square),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        textStyle: buttonText,
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused) ? paper : ink,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused) ? paper : ink,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused) ? ink : paper,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: paper),
      actionTextColor: palette.light,
      elevation: 0,
      shape: pixelBorder(paper, px),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: ink,
      foregroundColor: paper,
      focusColor: palette.dark,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: pixelBorder(paper, px),
    ),
    // Two-cell pixel switches: a square knob in a square track.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? paper : ink,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? ink : paper,
      ),
      trackOutlineColor: WidgetStatePropertyAll(ink),
      trackOutlineWidth: WidgetStatePropertyAll(px),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(),
      side: line,
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? ink : paper,
      ),
      checkColor: WidgetStatePropertyAll(paper),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(ink)),
    // Segmented pixel bars.
    sliderTheme: SliderThemeData(
      trackHeight: 4 * px,
      activeTrackColor: ink,
      inactiveTrackColor: palette.light,
      activeTickMarkColor: paper,
      inactiveTickMarkColor: paper,
      tickMarkShape: _GapTickShape(px),
      trackShape: const RectangularSliderTrackShape(),
      thumbColor: ink,
      thumbShape: _SquareThumbShape(px),
      overlayShape: SliderComponentShape.noOverlay,
      valueIndicatorColor: ink,
      valueIndicatorTextStyle: text.labelLarge?.copyWith(color: paper),
      showValueIndicator: ShowValueIndicator.never,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: ink,
      linearTrackColor: palette.light,
      circularTrackColor: palette.light,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: ink,
      textColor: ink,
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodySmall,
      selectedColor: paper,
      selectedTileColor: ink,
      shape: const RoundedRectangleBorder(),
      minLeadingWidth: 10 * px,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: line,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: line,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: line.copyWith(width: px * 2),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: ink,
      selectionColor: palette.light,
      selectionHandleColor: ink,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: ink),
      textStyle: text.labelMedium?.copyWith(color: paper),
    ),
  );
}

/// A square slider knob, one cell taller than the bar.
class _SquareThumbShape extends SliderComponentShape {
  const _SquareThumbShape(this.px);

  final double px;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size(4 * px, 8 * px);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final r = Rect.fromCenter(center: center, width: 4 * px, height: 8 * px);
    final canvas = context.canvas;
    canvas.drawRect(r, Paint()..color = sliderTheme.thumbColor!);
    canvas.drawRect(
      r.deflate(px),
      Paint()..color = sliderTheme.activeTickMarkColor!,
    );
    canvas.drawRect(
      r.deflate(px * 2),
      Paint()..color = sliderTheme.thumbColor!,
    );
  }
}

/// Splits the bar into segments with one-pixel gaps.
class _GapTickShape extends SliderTickMarkShape {
  const _GapTickShape(this.px);

  final double px;

  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) => Size(px, 4 * px);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required bool isEnabled,
    required TextDirection textDirection,
  }) {
    context.canvas.drawRect(
      Rect.fromCenter(center: center, width: px, height: 4 * px),
      Paint()..color = sliderTheme.activeTickMarkColor!,
    );
  }
}
