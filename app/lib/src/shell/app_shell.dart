// SPDX-License-Identifier: GPL-3.0-or-later
// Spec: docs/specs/m2-plan.md (package 10: app shell)
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../achievements/achievements_ui.dart';
import 'device_settings.dart';
import 'handheld.dart';
import 'network.dart';
import 'power_link.dart';
import 'usb_storage.dart';
import 'wifi_page.dart';
import '../library/database.dart';
import '../library/games_tab.dart';
import '../library/launch_animation.dart';
import '../library/library_scope.dart';
import '../session/session_screen.dart';
import '../shaders/lcd_settings.dart';
import '../shaders/shader_settings.dart';
import '../skins/skins_tab.dart';
import '../turbo/turbo.dart';
import '../ui/app_theme.dart';
import '../ui/audio_latency_page.dart';
import 'app_dirs.dart';
import '../ui/pixel.dart';
import '../ui/pixel_icons.dart';
import '../ui/pocket.dart';

/// Top-level navigation: Games / Settings. A NavigationBar on
/// narrow screens, a NavigationRail from 600 px. L1 / R1 switch tabs.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.onPlay});

  final PlayGame onPlay;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLaunchLink());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _openLaunchLink();
  }

  /// Opens the game of a `denagb://play/<sha1>` link (shortcuts.md). Dropped
  /// while a game is running so a tap can't end the session.
  Future<void> _openLaunchLink() async {
    if (!mounted) return;
    final scope = LibraryScope.of(context);
    final sha1 = await scope.links?.takeLaunchLink();
    if (sha1 == null || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final game = await scope.db.gameBySha1(sha1);
    if (!mounted) return;
    if (game == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That game is not in your library')),
      );
      return;
    }
    widget.onPlay(context, game);
  }

  /// Holds focus when a tab switch removes the focused widget, so L1 / R1
  /// keep working; the new tab's autofocus then picks its first item.
  final _shellFocus = FocusScopeNode(debugLabel: 'shell');

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shellFocus.dispose();
    super.dispose();
  }

  void _select(int i) {
    setState(() => index = i);
    // Forget the old tab's focus: autofocus only applies in a scope without
    // a focused child, so the D-pad never ends up nowhere after a switch.
    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && focused.enclosingScope == _shellFocus) {
      focused.unfocus();
    } else {
      _shellFocus.requestFocus();
    }
  }

  static const _destinations = [
    PocketDestination(PixelGlyphs.cart, 'Games'),
    PocketDestination(PixelGlyphs.gear, 'Settings'),
  ];

  void _go(int delta) => _select((index + delta) % _destinations.length);

  @override
  Widget build(BuildContext context) {
    final tab = _destinations[index.clamp(0, _destinations.length - 1)].label;
    final body = switch (tab) {
      'Games' => GamesTab(onPlay: widget.onPlay),
      _ => const _SettingsTab(),
    };
    final handheld = Handheld.of(context);
    // The phone is the console: the screen sits in the shell with rubber
    // keys for tabs. The handheld and wide screens are all screen, with the
    // tabs on an LCD strip (pocket-lcd-ui.md).
    final bezel = !handheld && MediaQuery.sizeOf(context).width < 600;
    final hints = handheld
        ? HintBar(
            hints: [
              ...switch (tab) {
                'Games' => const <ButtonHint>[
                  ([HintButton.a], 'Play'),
                  ([HintButton.y], 'Details'),
                ],
                _ => const <ButtonHint>[
                  ([HintButton.a], 'Open'),
                ],
              },
              ([HintButton.l1, HintButton.r1], 'Tabs'),
            ],
          )
        : null;
    final Widget shell;
    if (bezel) {
      shell = PocketBezel(
        destinations: _destinations,
        selected: index,
        onSelect: _select,
        screen: body,
      );
    } else {
      shell = Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: LcdGlass(
            grid: !handheld,
            child: Column(
              children: [
                LcdTabStrip(
                  destinations: _destinations,
                  selected: index,
                  onSelect: _select,
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.gameButtonLeft1): () =>
            _go(-1 + _destinations.length),
        const SingleActivator(LogicalKeyboardKey.gameButtonRight1): () =>
            _go(1),
      },
      child: FocusScope(
        node: _shellFocus,
        child: Scaffold(
          backgroundColor: PocketShell.putty,
          body: shell,
          bottomNavigationBar: hints,
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    final shaders = LibraryScope.of(context).shaders;
    // Real buttons, no touch screen, Android-only tools hidden (handheld-ui.md).
    final handheld = Handheld.of(context);
    // Online features stay out of navigation without Wi-Fi (network.dart),
    // so the D-pad never lands on one that can't work.
    final online = NetworkScope.of(context);
    // The tab's first item takes focus after L1 / R1.
    final device = switch ((
      PowerScope.of(context),
      PowerScope.deviceOf(context),
    )) {
      (final link?, final settings?) => DeviceSection(
        settings: settings,
        link: link,
        autofocus: true,
      ),
      _ => null,
    };
    // One long RPG-style menu: inverted section headers over plain rows.
    Widget group(Widget child) => child;
    final theme = ThemeScope.of(context).notifier!;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (device != null) ...[const SectionLabel('Device'), group(device)],
          if (NetworkScope.wifiOf(context) case final wifi?) ...[
            const SectionLabel('Network'),
            group(WifiTile(wifi: wifi)),
          ],
          const SectionLabel('Appearance'),
          LcdPaletteTile(
            store: shaders,
            settings: theme,
            autofocus: device == null,
          ),
          PixelSwitchTile(
            leading: const PixelIcon(PixelGlyphs.picture),
            title: const Text('Colour covers'),
            subtitle: const Text('Box art in full colour, not LCD shades'),
            value: theme.colourCovers,
            onChanged: (v) => theme.colourCovers = v,
          ),
          if (LibraryScope.of(context).achievements case final ra?
              when online) ...[
            const SectionLabel('Achievements'),
            group(RetroAchievementsTile(ra: ra)),
          ],
          if (!handheld)
            group(
              ListTile(
                leading: const PixelIcon(PixelGlyphs.palette),
                title: const Text('Skins'),
                subtitle: const Text('Controller skins per system, import'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SkinsPage()),
                ),
              ),
            ),
          if (shaders != null) ...[
            const SectionLabel('Display'),
            group(
              Column(
                children: [
                  LcdIntensityTile(store: shaders),
                  ListTile(
                    leading: const PixelIcon(PixelGlyphs.tv),
                    title: const Text('Shaders'),
                    subtitle: const Text(
                      'Dot matrix LCD or another filter per system',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ShaderSettingsPage(store: shaders),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SectionLabel('Controls'),
            group(
              ListTile(
                leading: const PixelIcon(PixelGlyphs.bolt),
                title: const Text('Turbo fire'),
                subtitle: Text(
                  turboSummary(TurboStore(shaders.dataDir).global),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        TurboSettingsPage(store: TurboStore(shaders.dataDir)),
                  ),
                ),
              ),
            ),
          ],
          if (!handheld) ...[
            const SectionLabel('Playback'),
            group(
              ListTile(
                leading: const PixelIcon(PixelGlyphs.speaker),
                title: const Text('Audio latency'),
                subtitle: Text(
                  audioLatencyLabel(
                    ThemeScope.of(context).notifier!.audioLatencyMs,
                  ),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AudioLatencyPage(),
                  ),
                ),
              ),
            ),
          ],
          if (PowerScope.usbOf(context) != null) const SectionLabel('Files'),
          if (PowerScope.usbOf(context) case final usb?)
            group(UsbStorageTile(usb: usb)),
        ],
      ),
    );
  }
}

/// The Skins tab as a Settings page (apps-tab.md).
class SkinsPage extends StatelessWidget {
  const SkinsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Skins')),
    body: const SkinsTab(),
  );
}

/// Opens [game] in a full-screen session (docs/specs/game-session.md), or
/// says its core is not in this build.
Future<void> playGame(BuildContext context, Game game) async {
  if (!coreLibraries.containsKey(game.system)) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(missingCoreMessage)));
    return;
  }
  final scope = LibraryScope.of(context);
  final db = scope.db;
  final navigator = Navigator.of(context);
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final handheld = Handheld.of(context);
  final links = scope.links;
  if (links != null) {
    // Recent-game shortcut (shortcuts.md); never blocks starting the game.
    shortcutIcon(scope, game).then((icon) => links.reportPlayed(game, icon));
  }
  final dataDir = (await appDataDir()).path;
  // The box opens and loads the media while the core starts underneath
  // (launch-animation.md).
  await pushLaunch<void>(
    navigator,
    scope,
    game,
    reduceMotion: reduceMotion,
    duration: handheld
        ? LaunchRoute.handheldDuration
        : LaunchRoute.defaultDuration,
    // Its own messenger: library messages (an import finishing) stay on the
    // library and never cover the game's touch controls.
    page: (_) => ScaffoldMessenger(
      child: SessionScreen(
        game: game,
        dataDir: dataDir,
        db: db,
        skins: scope.skins,
        shaders: scope.shaders,
        achievements: scope.achievements,
      ),
    ),
  );
}
