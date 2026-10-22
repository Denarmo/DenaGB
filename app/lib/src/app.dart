// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'shell/handheld.dart';
import 'shell/platform_features.dart';
import 'shell/power_link.dart';
import 'ui/app_theme.dart';
import 'ui/dena_icons.dart';
import 'ui/onscreen_keyboard.dart';
import 'ui/plastic.dart';
import 'ui/pocket.dart';

/// The app theme: a moulded console look over Material 3. Rounded Nunito
/// type, key-cap buttons, bevelled panels, Dena Icons and a strong focus
/// colour for D-pad use (docs/specs/ui-look-and-feel.md).
ThemeData denaTheme(ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  final base = ThemeData(
    colorScheme: scheme,
    // Denser than the M3 default: we design for 640x480 first (CLAUDE.md §5).
    visualDensity: VisualDensity.compact,
    fontFamily: denaFont,
    fontFamilyFallback: const ['Roboto'],
    // Keys travel and panels press in: no Material ink ripples.
    splashFactory: NoSplash.splashFactory,
  );
  final text = base.textTheme;
  TextStyle? weight(TextStyle? s, FontWeight w, [double? spacing]) =>
      s?.copyWith(fontWeight: w, letterSpacing: spacing);
  const panel = BevelBorder();
  // The well a selected tab sits in: dark in dark mode, the gold fill in
  // light mode where a dark well would read as a hole.
  final well = dark ? scheme.surfaceContainerLowest : scheme.primaryContainer;
  final onWell = dark ? scheme.primary : scheme.onPrimaryContainer;
  return base.copyWith(
    textTheme: text.copyWith(
      displaySmall: weight(text.displaySmall, FontWeight.w800),
      headlineMedium: weight(text.headlineMedium, FontWeight.w800),
      headlineSmall: weight(text.headlineSmall, FontWeight.w800),
      titleLarge: weight(text.titleLarge, FontWeight.w800),
      titleMedium: weight(text.titleMedium, FontWeight.w700),
      titleSmall: weight(text.titleSmall, FontWeight.w700),
      bodyLarge: weight(text.bodyLarge, FontWeight.w500),
      bodyMedium: weight(text.bodyMedium, FontWeight.w500),
      bodySmall: weight(text.bodySmall, FontWeight.w600),
      labelLarge: weight(text.labelLarge, FontWeight.w700, 0.2),
      labelMedium: weight(text.labelMedium, FontWeight.w700, 0.3),
      labelSmall: weight(text.labelSmall, FontWeight.w700, 0.4),
    ),
    focusColor: scheme.primary.withValues(alpha: 0.16),
    // Moulded plastic: bevelled panels, key-cap buttons.
    cardTheme: const CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: Colors.black,
      shape: panel,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: plasticButtonStyle(text.labelLarge),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: plasticButtonStyle(text.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: plasticButtonStyle(
        text.labelLarge,
        face: scheme.surfaceContainerHighest,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: plasticButtonStyle(
        text.labelLarge,
        face: scheme.surfaceContainerHigh,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: plasticIconButtonStyle()),
    segmentedButtonTheme: SegmentedButtonThemeData(
      selectedIcon: const Icon(DenaIcons.check),
      style: ButtonStyle(
        splashFactory: NoSplash.splashFactory,
        textStyle: WidgetStatePropertyAll(
          weight(text.labelLarge, FontWeight.w800),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: Colors.black.withValues(alpha: 0.35), width: 1.5),
        ),
        // Raised keys; the chosen one sits pressed into the well, lit.
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? well
              : scheme.surfaceContainerHigh,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? onWell : scheme.onSurface,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onWell
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    // Icons are moulded into the plastic.
    iconTheme: base.iconTheme.copyWith(shadows: debossShadows),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(DenaIcons.arrowBack),
      closeButtonIconBuilder: (_) => const Icon(DenaIcons.close),
      drawerButtonIconBuilder: (_) => const Icon(DenaIcons.menu),
      endDrawerButtonIconBuilder: (_) => const Icon(DenaIcons.menu),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: weight(
        text.titleLarge,
        FontWeight.w800,
      )?.copyWith(color: scheme.onSurface),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(
        dark ? scheme.surfaceContainerLowest : scheme.surfaceContainerHigh,
      ),
      // Set into the shell like a screen window.
      shape: const WidgetStatePropertyAll(
        BevelBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          sunken: true,
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const BevelBorder(
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      side: BorderSide.none,
      showCheckmark: false,
      elevation: 2,
      pressElevation: 0,
      shadowColor: Colors.black,
      backgroundColor: scheme.surfaceContainerHigh,
      labelStyle: weight(text.labelLarge, FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      elevation: 8,
      shadowColor: Colors.black,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? onWell
              : scheme.onSurfaceVariant,
          shadows: debossShadows,
        ),
      ),
      // The selected tab sits pressed into the bar, lit like an LED.
      indicatorColor: well,
      indicatorShape: const BevelBorder(
        borderRadius: BorderRadius.all(Radius.circular(999)),
        sunken: true,
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium?.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: well,
      indicatorShape: const BevelBorder(
        borderRadius: BorderRadius.all(Radius.circular(999)),
        sunken: true,
      ),
      selectedIconTheme: IconThemeData(color: onWell, shadows: debossShadows),
      selectedLabelTextStyle: text.labelMedium?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      unselectedLabelTextStyle: text.labelMedium,
    ),
    dividerTheme: DividerThemeData(
      color: Colors.black.withValues(alpha: dark ? 0.45 : 0.18),
      space: 1,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      shape: const BevelBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: const BevelBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      titleTextStyle: weight(
        text.headlineSmall,
        FontWeight.w800,
      )?.copyWith(color: scheme.onSurface),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: BevelBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 4,
      focusElevation: 6,
      hoverElevation: 6,
      highlightElevation: 1,
      shape: const BevelBorder(),
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => Icon(
          states.contains(WidgetState.selected)
              ? DenaIcons.check
              : DenaIcons.close,
          size: 14,
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      // Gold glyphs mark each setting, like a console's system menu.
      iconColor: scheme.primary,
      titleTextStyle: weight(
        text.titleMedium,
        FontWeight.w700,
      )?.copyWith(color: scheme.onSurface),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
  );
}

class DenaApp extends StatefulWidget {
  const DenaApp({super.key, required this.home, this.theme});

  /// The first screen; tests mount any screen inside the real app theme.
  final Widget home;

  /// The saved theme choices (theming.md); null keeps the defaults (dark,
  /// Dena gold) for the session.
  final ThemeSettings? theme;

  @override
  State<DenaApp> createState() => _DenaAppState();
}

class _DenaAppState extends State<DenaApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  /// The handheld power daemon (power-daemon.md); null elsewhere.
  PowerLink? _power;

  late final ThemeSettings _theme = widget.theme ?? ThemeSettings();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final link = PowerScope.of(context);
    if (link == _power) return;
    _releasePower();
    _power = link?..onBatteryLow = _batteryLow;
    if (link != null) HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _batteryLow() => _messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Battery low: plug in soon. Your game saves first.'),
      ),
    );

  /// Any button keeps the idle-sleep timer from running out.
  bool _onKey(KeyEvent event) {
    _power?.activity();
    return false;
  }

  void _releasePower() {
    final link = _power;
    if (link == null) return;
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (link.onBatteryLow == _batteryLow) link.onBatteryLow = null;
  }

  @override
  void dispose() {
    _releasePower();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only Android has a wallpaper palette; elsewhere Material You falls
    // back to Dena gold without asking the platform (theming.md).
    if (!hasAndroidShell) return _themed(null, null);
    return DynamicColorBuilder(builder: _themed);
  }

  Widget _themed(ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => ThemeScope(
        settings: _theme,
        dynamicAvailable: lightDynamic != null && darkDynamic != null,
        child: _app(
          paletteScheme(
            _theme.palette,
            Brightness.light,
            dynamic: lightDynamic,
          ),
          paletteScheme(_theme.palette, Brightness.dark, dynamic: darkDynamic),
        ),
      ),
    );
  }

  Widget _app(ColorScheme light, ColorScheme dark) {
    // Dena.emu GB draws every screen on the Pocket LCD (pocket-lcd-ui.md);
    // the palette is the LCD palette from Settings.
    final palette = lcdUiPalette(_theme.palette);
    ThemeData pocket(PocketMetrics m) =>
        pocketTheme(palette, m, colourCovers: _theme.colourCovers);
    return MaterialApp(
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      title: 'Dena.emu GB',
      debugShowCheckedModeBanner: false,
      theme: pocket(const PocketMetrics(2)),
      themeMode: ThemeMode.light,
      // B goes back everywhere (handheld-ui.md); A activates by default.
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.gameButtonB):
            const BackIntent(),
      },
      actions: {
        ...WidgetsApp.defaultActions,
        BackIntent: CallbackAction<BackIntent>(
          onInvoke: (_) => _navigator.currentState?.maybePop(),
        ),
      },
      // One virtual LCD pixel is 2 or 3 logical pixels, by screen class.
      builder: (context, child) {
        final handheld = Handheld.of(context);
        final px = pocketPixelFor(
          MediaQuery.sizeOf(context),
          handheld: handheld,
        );
        return Theme(
          data: pocket(PocketMetrics(px)),
          child: handheld
              ? Shortcuts(
                  shortcuts: handheldArrows,
                  child: HandheldTextEntry(child: child!),
                )
              : child!,
        );
      },
      home: widget.home,
    );
  }
}
