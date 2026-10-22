// SPDX-License-Identifier: GPL-3.0-or-later
// Full-screen game session with a minimal pause sheet.
// Spec: docs/specs/game-session.md, docs/specs/shaders.md
import 'dart:async';

import 'package:dena_android/dena_android.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, SystemChrome, SystemUiMode;
import 'package:path/path.dart' as p;

import '../achievements/achievements_ui.dart';
import '../achievements/retro_achievements.dart';
import '../library/box_art.dart';
import '../library/database.dart';

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import '../shaders/shader_sheet.dart';
import '../shaders/shader_store.dart';
import '../turbo/turbo.dart';
import '../shell/handheld.dart';
import '../shell/network.dart';
import '../shell/host_library.dart';
import '../shell/platform_features.dart';
import '../shell/power_link.dart';
import '../skins/builtin_skins.dart';
import '../skins/deltaskin.dart';
import '../skins/skin_layout.dart';
import '../skins/skin_store.dart';
import '../skins/touch_controls.dart';
import '../skins/touch_sink.dart';
import '../ui/app_theme.dart';
import '../ui/plastic.dart';
import 'cheat_database.dart';
import 'cheats_sheet.dart';
import 'link_cable.dart';
import 'pointer_area.dart';
import 'state_slots.dart';
import '../ui/dena_icons.dart';
import '../ui/pixel.dart';
import '../ui/pixel_icons.dart';
import '../ui/pocket.dart';

/// Core library per system. Only packaged cores are listed; a system without
/// one cannot start (game-session.md, Cores per system).
const coreLibraries = {
  'gb': 'libmgba_libretro.so',
  'gbc': 'libmgba_libretro.so',
  'gba': 'libmgba_libretro.so',
  'nds': 'libmelonds_libretro.so',
};

/// The launcher's external texture for the game picture on Linux handhelds
/// (handheld-session.md).
const handheldGameTexture = 1;

/// The game picture: Android's SurfaceView, the launcher's texture on Linux
/// handhelds, the runner's texture on Windows and desktop Linux
/// (desktop-shell.md). [desktopTexture] is for tests.
Widget defaultGameView({ShellProfile? profile, int? desktopTexture}) =>
    switch (profile ?? shellProfile) {
      ShellProfile.handheld => const Texture(
        textureId: handheldGameTexture,
        filterQuality: FilterQuality.none,
      ),
      // -1 (no host library) shows nothing, like an unregistered texture.
      ShellProfile.desktop => Texture(
        textureId: desktopTexture ?? desktopGameTexture() ?? -1,
        filterQuality: FilterQuality.none,
      ),
      _ => const EmulatorSurfaceView(),
    };

/// Systems whose games use L2, so it can't double as hold-to-rewind.
const systemsWithL2 = {'psx', 'n64'};

/// Systems whose games read analog sticks (n64.md).
const analogSystems = {'n64', 'psp'};

/// Systems whose core can't restore a save state faithfully: no Save/Load,
/// rewind or auto-resume; the game restarts (pico8.md).
const systemsWithoutStates = {'pico8'};

/// Display aspect ratio of each system's picture.
const systemAspect = {
  'nes': 4 / 3,
  'snes': 4 / 3,
  'gb': 10 / 9,
  'gbc': 10 / 9,
  'gba': 3 / 2,
  'nds': 256 / 384, // both screens stacked (ds.md)
  'psx': 4 / 3,
  'n64': 4 / 3,
  'psp': 480 / 272,
  'pico8': 1.0,
  'genesis': 4 / 3,
};

const missingCoreMessage = "This system's core is not included in this build";

const shaderFailedMessage = 'This shader could not be loaded';

/// Battery save and auto-save state paths for [game] under [dataDir]
/// (POSIX: the session runs on Android, Linux and iOS only).
({String srm, String state}) sessionFiles(String dataDir, Game game) => (
  srm: p.posix.join(dataDir, 'saves', '${game.sha1}.srm'),
  state: p.posix.join(dataDir, 'states', game.sha1, 'auto.state'),
);

enum PauseAction {
  resume,
  saveState,
  loadState,
  rewind,
  cheats,
  shader,
  achievements,
  link,
  quit,
}

class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.game,
    required this.dataDir,
    required this.db,
    this.api,
    this.gameView,
    this.clock = DateTime.now,
    this.registerEvents = GameEventsApi.setUp,
    this.touchSink,
    this.skins,
    this.shaders,
    this.turbo,
    this.cheatDb,
    this.achievements,
    this.link,
  });

  final Game game;

  /// App-private directory holding `saves/` and `states/`.
  final String dataDir;
  final LibraryDatabase db;

  /// Injectable for tests; defaults to the platform implementation.
  final GameHostApi? api;

  /// Replaces the native surface in tests.
  final Widget? gameView;
  final DateTime Function() clock;

  /// Registers the handler for controller events (gamepads.md); tests capture it.
  final void Function(GameEventsApi? handler) registerEvents;

  /// Where touch-control masks go; the dart:ffi sink when null.
  final TouchSink? touchSink;

  /// Imported skins; built-in controls only when null.
  final SkinStore? skins;

  /// Shader choices; `<dataDir>/shaders.json` when null (shaders.md).
  final ShaderStore? shaders;

  /// Turbo buttons; `<dataDir>/turbo.json` when null (turbo.md).
  final TurboStore? turbo;

  /// The cheat database to browse (cheats.md); `<dataDir>/cheats/` when null.
  final CheatDatabase? cheatDb;

  /// RetroAchievements (achievements.md); none when null.
  final RetroAchievements? achievements;

  /// The link cable (link-cable.md); the native one when null.
  final LinkCable? link;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    implements GameEventsApi {
  late final GameHostApi api = widget.api ?? GameHostApi();
  late final AppLifecycleListener _lifecycle;
  bool running = false;
  bool sheetOpen = false;
  int speed = 1;

  /// Playing backwards until the player taps (rewind.md).
  bool rewinding = false;
  String? error;
  late DateTime _startedAt;

  /// Device name per port; empty for a free port.
  List<String> players = const ['', '', '', ''];

  /// The external display showing the picture, or null (external-display.md).
  String? externalDisplay;

  /// Touch controls are showing (skins.md, last input wins).
  bool skinVisible = true;

  /// Handhelds have real buttons and no touch screen: never a skin
  /// (handheld-ui.md).
  bool _handheld = false;
  late final TouchSink? _touch = widget.touchSink ?? FfiTouchSink.open();
  InstalledSkin? _importedSkin;

  late final ShaderStore _shaders =
      widget.shaders ?? ShaderStore(widget.dataDir);

  late final TurboStore _turboStore =
      widget.turbo ?? TurboStore(widget.dataDir);

  /// The turbo setup in effect for this game (turbo.md).
  late TurboConfig turbo = _turboStore.resolve(widget.game.sha1);

  void _applyTurbo() =>
      _touch?.setTurbo(turbo.mask, turboHalfFrames(turbo.rate));

  /// Only for systems with a link port; ends with the session.
  late final LinkCable? _link = systemsWithLink.contains(widget.game.system)
      ? widget.link ?? FfiLinkCable.open()
      : null;

  late final CheatDatabase _cheatDb =
      widget.cheatDb ??
      CheatDatabase(
        widget.dataDir,
        loadIndex: CheatDbIndex.load,
        loadNames: BoxArtIndex.load,
      );

  /// The shader showing ("" = Off); Off for the rest of the session after
  /// one fails to load (shaders.md).
  String shader = '';

  /// The handheld power daemon (power-daemon.md); null elsewhere.
  PowerLink? _power;

  /// This session reports to RetroAchievements (achievements.md).
  RetroAchievements? get _ra =>
      widget.achievements?.supports(widget.game.system) ?? false
      ? widget.achievements
      : null;

  /// Hardcore: no state loads, rewind or cheats (achievements.md).
  bool _hardcore = false;

  void _onRaChanged() {
    final h = _ra?.session?.hardcore ?? false;
    if (mounted && h != _hardcore) setState(() => _hardcore = h);
  }

  /// The status and navigation bars are hidden while playing, in both
  /// orientations (skins.md).
  bool _barsHidden = false;

  void _syncSystemBars() {
    if (_barsHidden) return;
    _barsHidden = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSystemBars();
    _handheld = Handheld.of(context);
    if (_handheld) skinVisible = false;
    final link = PowerScope.of(context);
    if (link == _power) return;
    _releasePower();
    _power = link
      ?..onSave = _saveForPower
      ..onResumed = _openPauseSheet;
  }

  /// Before sleep or power off: stop frames and write the saves.
  Future<void> _saveForPower() async {
    if (!running) return;
    _touch?.setButtons(0);
    await api.pause();
    await api.saveNow();
  }

  void _releasePower() {
    final link = _power;
    if (link == null) return;
    if (link.onSave == _saveForPower) link.onSave = null;
    if (link.onResumed == _openPauseSheet) link.onResumed = null;
  }

  @override
  void initState() {
    super.initState();
    // The plastic grain never sits over the game frame. Not during build.
    scheduleMicrotask(() => plasticGrainVisible.value = false);
    widget.registerEvents(this);
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (running) api.pause();
      },
      onShow: () {
        if (running && !sheetOpen) api.resume();
      },
    );
    _start();
  }

  Future<void> _start() async {
    final core = coreLibraries[widget.game.system];
    if (core == null) {
      setState(() => error = missingCoreMessage);
      return;
    }
    _importedSkin = await widget.skins?.active(widget.game.system);
    if (!mounted) return;
    final files = sessionFiles(widget.dataDir, widget.game);
    final states = !systemsWithoutStates.contains(widget.game.system);
    // The dot matrix LCD's settings, kept by the host for whichever shader
    // declares them (dot-matrix.md).
    await api.setShaderParameter('intensity', _shaders.lcdIntensity);
    await api.setShaderParameter('palette', _shaders.lcdPalette.toDouble());
    // Set before start so the shader applies from the first frame.
    final saved = _shaders.resolve(widget.game.system, widget.game.sha1);
    final shaderOk = saved.isEmpty || await _applyShader(saved, report: false);
    // Internal resolution is a core option, read when the game loads.
    await api.setUpscale(
      _shaders.resolveUpscale(widget.game.system, widget.game.sha1),
    );
    if (!mounted) return;
    // The audio buffer target is applied when audio opens at start
    // (performance.md), so set it before the game runs.
    await api.setAudioLatency(ThemeScope.of(context).notifier!.audioLatencyMs);
    // Hardcore never resumes the auto-save state (achievements.md).
    final resume =
        states &&
        !(widget.achievements?.hardcoreFor(widget.game.system) ?? false);
    final r = await api.start(
      core,
      widget.game.path,
      files.srm,
      resume ? files.state : '',
    );
    if (!mounted) {
      // Left while the core was loading: dispose() saw running == false, so
      // stop here or the core keeps running and blocks the next launch.
      if (r.outcome != null) await api.stop();
      return;
    }
    if (r.outcome == null) {
      setState(() => error = r.error ?? 'The game could not start');
      return;
    }
    _startedAt = widget.clock();
    setState(() => running = true);
    _ra?.addListener(_onRaChanged);
    await _ra?.beginSession(widget.game.path, widget.game.system);
    await api.setTouchMode(!_handheld);
    _applyTurbo();
    // A held L2 rewinds unless the system has an L2 button (rewind.md).
    await api.configureRewind(
      states,
      !systemsWithL2.contains(widget.game.system),
    );
    await api.setAnalogMode(analogSystems.contains(widget.game.system));
    await api.setDisplayAspect(systemAspect[widget.game.system] ?? 4 / 3);
    // The runner refuses cheats once hardcore is confirmed.
    final cheats = await enabledCheatCodes(widget.db, widget.game.id);
    if (cheats.isNotEmpty) await api.setCheats(cheats);
    if (!mounted) return;
    if (!shaderOk) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(shaderFailedMessage)));
    }
    if (r.outcome == StartOutcome.badState) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "The last session couldn't be restored; starting fresh.",
          ),
        ),
      );
    }
  }

  Future<void> _openPauseSheet() async {
    if (!running || sheetOpen) return;
    sheetOpen = true;
    _touch?.setButtons(0);
    await api.pause();
    // The sheet reopens after a cancelled slot pick or a failed load.
    while (true) {
      if (!mounted) return;
      final action = await showModalBottomSheet<PauseAction>(
        context: context,
        // Full height: the window floats on a dithered dim of the game.
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        constraints: const BoxConstraints(),
        builder: (context) => PocketDim(
          onDismiss: () => Navigator.of(context).pop(PauseAction.resume),
          child: PauseSheet(
            title: widget.game.title,
            // The launcher reads the built-in buttons itself and reports no
            // players (handheld-session.md).
            players: _handheld && players.every((p) => p.isEmpty)
                ? const ['Built-in controls', '', '', '']
                : players,
            onCapture: _capture,
            states: !systemsWithoutStates.contains(widget.game.system),
            hardcore: _hardcore,
            achievements: _ra?.session,
            // The link cable plays over Wi-Fi (network.dart).
            link:
                systemsWithLink.contains(widget.game.system) &&
                    NetworkScope.read(context)
                ? _link
                : null,
            speed: speed,
            onSpeed: (s) {
              speed = s;
              api.setSpeed(s);
            },
            turbo: turbo,
            onTurbo: (c) {
              turbo = c;
              _turboStore.setGame(widget.game.sha1, c);
              _applyTurbo();
            },
          ),
        ),
      );
      if (!mounted) return;
      switch (action) {
        case PauseAction.quit:
          sheetOpen = false;
          await _quit();
          return;
        case PauseAction.saveState || PauseAction.loadState:
          final done = await _pickSlot(
            action == PauseAction.saveState ? SlotMode.save : SlotMode.load,
          );
          if (!done) continue;
        case PauseAction.cheats:
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => CheatsSheet(
              db: widget.db,
              game: widget.game,
              apply: api.setCheats,
              database: _cheatDb,
            ),
          );
          continue;
        case PauseAction.shader:
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            // Keeps the preview behind the sheet undimmed.
            barrierColor: Colors.transparent,
            builder: (_) => ShaderSheet(
              store: _shaders,
              system: widget.game.system,
              gameSha1: widget.game.sha1,
              current: shader,
              onApply: _applyShader,
            ),
          );
          continue;
        case PauseAction.achievements:
          final ra = _ra;
          if (ra != null) {
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => SessionAchievementsSheet(ra: ra),
            );
          }
          continue;
        case PauseAction.link:
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) =>
                LinkCableSheet(link: _link!, gameTitle: widget.game.title),
          );
          continue;
        case PauseAction.rewind:
          sheetOpen = false;
          await api.resume();
          await _setRewinding(true);
          return;
        case PauseAction.resume || null:
          break;
      }
      sheetOpen = false;
      await api.resume();
      return;
    }
  }

  /// Shows [id] ("" = Off). On a load error the session falls back to Off
  /// and, when [report], says so; returns whether [id] is showing.
  Future<bool> _applyShader(String id, {bool report = true}) async {
    final err = await api.setShader(id);
    if (err == null) {
      shader = id;
      return true;
    }
    // A failed load keeps the previous picture path; turn that one off too.
    if (shader.isNotEmpty) await api.setShader('');
    shader = '';
    if (report && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(shaderFailedMessage)));
    }
    return false;
  }

  /// Saves to or loads from a slot the player picks. False when nothing
  /// happened (cancelled, or the load failed), so the pause sheet comes back.
  Future<bool> _pickSlot(SlotMode mode) async {
    final slot = await showModalBottomSheet<StateSlot>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SlotSheet(
        mode: mode,
        slots: listSlots(widget.dataDir, widget.game.sha1),
        aspectRatio: systemAspect[widget.game.system] ?? 4 / 3,
      ),
    );
    if (slot == null || !mounted) return false;
    final err = mode == SlotMode.save
        ? await api.saveState(slot.statePath, slot.pngPath)
        : await api.loadState(slot.statePath);
    if (!mounted) return false;
    final message =
        err ??
        (mode == SlotMode.save
            ? 'Saved to ${slot.label.toLowerCase()}'
            : 'Loaded ${slot.label.toLowerCase()}');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    return err == null;
  }

  Future<void> _setRewinding(bool on) async {
    if (!mounted || rewinding == on) return;
    setState(() => rewinding = on);
    await api.setRewinding(on);
  }

  Future<void> _capture() async {
    final t = widget.clock();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}.${two(t.minute)}.${two(t.second)}';
    final title = widget.game.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final err = await api.captureScreenshot('$title $stamp');
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(err ?? 'Screenshot saved')));
  }

  /// Before the core stops.
  void _endAchievements() {
    _ra?.removeListener(_onRaChanged);
    _ra?.endSession();
  }

  Future<void> _quit() async {
    setState(() => running = false);
    _endAchievements();
    await api.stop();
    final now = widget.clock();
    await widget.db.recordPlay(
      widget.game.id,
      at: now,
      seconds: now.difference(_startedAt).inSeconds,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    scheduleMicrotask(() => plasticGrainVisible.value = true);
    widget.registerEvents(null);
    _releasePower();
    _lifecycle.dispose();
    if (_barsHidden) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _link?.stop();
    if (running) {
      _endAchievements();
      api.stop();
    }
    super.dispose();
  }

  /// PICO-8 keeps its picture and controls clear of camera cutouts
  /// (pico8.md): the game area is inset by the cutout's edges.
  Widget _cutoutSafe(Size size, double aspect) {
    if (widget.game.system != 'pico8') return _gameArea(size, aspect);
    final inset = cutoutInsets(
      MediaQuery.displayFeaturesOf(context),
      MediaQuery.viewPaddingOf(context),
      size,
    );
    return Padding(
      padding: inset,
      child: _gameArea(inset.deflateSize(size), aspect),
    );
  }

  Widget _gameArea(Size size, double aspect) {
    Widget view = running
        ? (widget.gameView ?? defaultGameView())
        : const SizedBox.shrink();
    final external = externalDisplay;
    if (running && external != null) {
      // The picture is on the external display; the phone keeps the controls.
      view = Stack(
        fit: StackFit.expand,
        children: [
          view,
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: Text(
                'Playing on $external',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Colors.white70),
              ),
            ),
          ),
        ],
      );
    }
    if (running && widget.game.system == 'nds') {
      // The lower screen is a touch screen (ds.md).
      view = PointerArea(
        onPointer: (x, y, down) => _touch?.setPointer(x, y, down),
        child: view,
      );
    }
    final fold = tabletopFold(MediaQuery.displayFeaturesOf(context));
    if (!skinVisible) {
      final picture = Center(
        child: AspectRatio(aspectRatio: aspect, child: view),
      );
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _showSkin(),
        // Tabletop: the picture stays on the upright half (adaptive.md).
        child: fold == null
            ? picture
            : Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: size.width,
                  height: fold.top,
                  child: picture,
                ),
              ),
      );
    }
    final imported = _importedSkin;
    final rep = imported?.skin.pick(size, tablet: size.shortestSide >= 600);
    if (imported != null && rep != null) {
      return SkinView(
        layout: rep.layout,
        game: view,
        artwork: _SkinArtwork(store: widget.skins!, skin: imported, rep: rep),
        paintItems: imported.skin.debug,
        onMask: (m) => _touch?.setButtons(m),
        onAnalog: _onAnalog,
        onMenu: _openPauseSheet,
      );
    }
    return SkinView(
      layout: builtinSkin(widget.game.system, size, aspect, fold: fold),
      game: view,
      onMask: (m) => _touch?.setButtons(m),
      onAnalog: _onAnalog,
      onMenu: _openPauseSheet,
    );
  }

  void _onAnalog(int stick, Offset tilt) => _touch?.setAnalog(
    stick,
    (tilt.dx * 0x7fff).round(),
    (tilt.dy * 0x7fff).round(),
  );

  @override
  void onMenuRequested() => _openPauseSheet();

  @override
  void onPlayersChanged(List<String> names) {
    if (mounted) setState(() => players = List.of(names));
  }

  @override
  void onGamepadUsed() {
    if (!mounted) return;
    _touch?.setButtons(0);
    setState(() => skinVisible = false);
  }

  void _showSkin() {
    if (skinVisible || !running || _handheld) return;
    setState(() => skinVisible = true);
    api.setTouchMode(true);
  }

  @override
  void onExternalDisplayChanged(String? name) {
    if (mounted) setState(() => externalDisplay = name);
  }

  @override
  void onControllerDisconnected(int port, String name) {
    if (!mounted) return;
    _showSkin();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Controller ${port + 1} disconnected')),
      );
    _openPauseSheet();
  }

  @override
  Widget build(BuildContext context) {
    final aspect = systemAspect[widget.game.system] ?? 4 / 3;
    final err = error;
    return PopScope(
      canPop: !running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openPauseSheet();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: err != null
            ? _StartError(message: err)
            : LayoutBuilder(
                builder: (context, box) => Stack(
                  fit: StackFit.expand,
                  children: [
                    _cutoutSafe(box.biggest, aspect),
                    if (rewinding)
                      _RewindOverlay(onStop: () => _setRewinding(false)),
                    if (_ra case final ra?)
                      Positioned.fill(child: RaToastLayer(notices: ra.notices)),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Covers the game while rewinding; a tap, click or A stops (rewind.md).
class _RewindOverlay extends StatelessWidget {
  const _RewindOverlay({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) onStop();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onStop,
        child: Align(
          alignment: const Alignment(0, -0.9),
          child: Chip(
            avatar: Icon(
              DenaIcons.fastRewind,
              color: scheme.onSecondaryContainer,
            ),
            label: const Text('Rewinding · tap to stop'),
            backgroundColor: scheme.secondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _StartError extends StatelessWidget {
  const _StartError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to library'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pause menu as a Pocket LCD command window (pocket-lcd-ui.md): two
/// columns of commands, the speed cells, turbo, link cable and players. Pops
/// with the chosen [PauseAction]; Back (B) resumes.
class PauseSheet extends StatefulWidget {
  const PauseSheet({
    super.key,
    required this.title,
    required this.speed,
    required this.onSpeed,
    this.players = const ['', '', '', ''],
    this.onCapture,
    this.states = true,
    this.turbo,
    this.onTurbo,
    this.hardcore = false,
    this.achievements,
    this.link,
  });

  final String title;

  /// The link cable, for systems that have one (link-cable.md).
  final LinkCable? link;

  /// Offer Save, Load and Rewind (false where states don't work, pico8.md).
  final bool states;

  /// RetroAchievements hardcore: Save only, no Load, Rewind or Cheats.
  final bool hardcore;

  /// The game RetroAchievements identified; shows the Achievements row.
  final RaSession? achievements;
  final int speed;
  final ValueChanged<int> onSpeed;

  /// This game's turbo setup (turbo.md); the section hides when null.
  final TurboConfig? turbo;
  final ValueChanged<TurboConfig>? onTurbo;

  /// Device name per port (gamepads.md); empty for a free port.
  final List<String> players;

  /// Saves a screenshot; the sheet stays open (pause-menu.md).
  final VoidCallback? onCapture;

  @override
  State<PauseSheet> createState() => _PauseSheetState();
}

class _PauseSheetState extends State<PauseSheet> {
  late int speed = widget.speed;
  late TurboConfig? turbo = widget.turbo;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final px = style.metrics.px;
    final section = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: style.palette.dark);
    void pop(PauseAction a) => Navigator.of(context).pop(a);
    Widget label(String t) => Padding(
      padding: EdgeInsets.only(top: 4 * px, bottom: 2 * px),
      child: Text(t, style: section),
    );
    final commands = [
      (PixelGlyphs.play, 'Resume', PauseAction.resume),
      if (widget.states) ...[
        (PixelGlyphs.floppy, 'Save', PauseAction.saveState),
        if (!widget.hardcore) ...[
          (PixelGlyphs.load, 'Load', PauseAction.loadState),
          (PixelGlyphs.rewind, 'Rewind', PauseAction.rewind),
        ],
      ],
      if (!widget.hardcore) (PixelGlyphs.key, 'Cheats', PauseAction.cheats),
      (PixelGlyphs.tv, 'Shader', PauseAction.shader),
      (PixelGlyphs.camera, 'Capture', null),
      (PixelGlyphs.power, 'Quit', PauseAction.quit),
    ];
    // Two columns like an RPG command window; Tab and the D-pad walk them
    // row by row.
    final rows = <Widget>[
      for (var i = 0; i < commands.length; i += 2)
        Row(
          children: [
            for (final (glyph, name, action) in commands.skip(i).take(2))
              Expanded(
                child: PixelMenuItem(
                  glyph: glyph,
                  label: name,
                  autofocus: action == PauseAction.resume,
                  onPressed: action == null
                      ? widget.onCapture
                      : () => pop(action),
                ),
              ),
            if (i + 1 >= commands.length) const Spacer(),
          ],
        ),
    ];
    final sheet = SafeArea(
      child: Padding(
        padding: EdgeInsets.all(4 * px),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: PixelWindow(
            padding: EdgeInsets.all(px),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InvertedBar(title: widget.title, glyph: PixelGlyphs.cart),
                  SizedBox(height: 2 * px),
                  ...rows,
                  if (widget.achievements case final a?)
                    PixelMenuItem(
                      glyph: PixelGlyphs.trophy,
                      label: '${a.unlocked} of ${a.total} achievements',
                      trailing: a.hardcore ? 'Hardcore' : null,
                      onPressed: () => pop(PauseAction.achievements),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2 * px),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        label('Speed'),
                        PixelCells<int>(
                          values: const [1, 2, 4],
                          labels: const ['1X', '2X', '4X'],
                          selected: speed,
                          onSelected: (s) {
                            setState(() => speed = s);
                            widget.onSpeed(s);
                          },
                        ),
                        if (turbo case final t?) ...[
                          label('Turbo'),
                          TurboEditor(
                            value: t,
                            onChanged: (c) {
                              setState(() => turbo = c);
                              widget.onTurbo?.call(c);
                            },
                          ),
                        ],
                        if (widget.link case final link?) ...[
                          label('Link cable'),
                          PixelMenuItem(
                            glyph: PixelGlyphs.link,
                            label: linkSummary(link),
                            onPressed: () => pop(PauseAction.link),
                          ),
                        ],
                        label('Controllers'),
                        _ControllerRow(players: widget.players),
                        SizedBox(height: 2 * px),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!Handheld.of(context)) return sheet;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: sheet),
        const HintBar(
          hints: [
            ([HintButton.a], 'Select'),
            ([HintButton.b], 'Resume'),
          ],
        ),
      ],
    );
  }
}

/// One line per connected player: "P1 · Xbox Wireless Controller".
class _ControllerRow extends StatelessWidget {
  const _ControllerRow({required this.players});

  final List<String> players;

  @override
  Widget build(BuildContext context) {
    final px = PocketStyle.of(context).metrics.px;
    final text = Theme.of(context).textTheme.bodySmall;
    final used = [
      for (final (i, name) in players.indexed)
        if (name.isNotEmpty) (i, name),
    ];
    if (used.isEmpty) {
      return Text(
        'No controller yet: press a button on one to join.',
        style: text,
      );
    }
    return Wrap(
      spacing: 6 * px,
      runSpacing: px,
      children: [
        for (final (i, name) in used)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelIcon(PixelGlyphs.pad, size: 9 * px),
              SizedBox(width: 2 * px),
              Flexible(
                child: Text(
                  'P${i + 1} · $name',
                  style: text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// An imported skin's artwork for the current size (PDFs rasterised once).
class _SkinArtwork extends StatefulWidget {
  const _SkinArtwork({
    required this.store,
    required this.skin,
    required this.rep,
  });

  final SkinStore store;
  final InstalledSkin skin;
  final DeltaRepresentation rep;

  @override
  State<_SkinArtwork> createState() => _SkinArtworkState();
}

class _SkinArtworkState extends State<_SkinArtwork> {
  /// Files already found, so a pressed key's copy of the art (touch_controls)
  /// shows on its first frame.
  static final _found = <(String, String?, Size), File>{};

  File? file;
  Size? loadedFor;

  void _load(Size px) {
    if (loadedFor == px) return;
    loadedFor = px;
    final key = (
      widget.skin.dir.path,
      widget.rep.pdf ?? widget.rep.bestPng,
      px,
    );
    final known = _found[key];
    if (known != null) {
      file = known;
      return;
    }
    widget.store
        .artwork(widget.skin, widget.rep, px.width.round(), px.height.round())
        .then((f) {
          if (f != null) _found[key] = f;
          if (mounted) setState(() => file = f);
        });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        _load(box.biggest * ratio);
        final f = file;
        return f == null
            ? const SizedBox.shrink()
            : Image.file(f, fit: BoxFit.fill, gaplessPlayback: true);
      },
    );
  }
}

/// The edges a camera cutout takes from a [size] screen: each cutout in
/// [features] pushes the edge it is nearest to, falling back to the
/// [viewPadding] Android reports for the cutout when no feature is given.
EdgeInsets cutoutInsets(
  List<DisplayFeature> features,
  EdgeInsets viewPadding,
  Size size,
) {
  var l = 0.0, t = 0.0, r = 0.0, b = 0.0;
  var any = false;
  for (final f in features) {
    if (f.type != DisplayFeatureType.cutout) continue;
    any = true;
    final c = f.bounds;
    final near = [c.top, size.height - c.bottom, c.left, size.width - c.right];
    final m = near.reduce((a, b) => a < b ? a : b);
    if (m == near[0]) {
      t = math.max(t, c.bottom);
    } else if (m == near[1]) {
      b = math.max(b, size.height - c.top);
    } else if (m == near[2]) {
      l = math.max(l, c.right);
    } else {
      r = math.max(r, size.width - c.left);
    }
  }
  return any ? EdgeInsets.fromLTRB(l, t, r, b) : viewPadding;
}
