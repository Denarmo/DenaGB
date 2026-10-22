// SPDX-License-Identifier: GPL-3.0-or-later
// Spec: docs/specs/library.md (Screens, D-pad and focus)
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:material_ui/material_ui.dart';

import '../shell/handheld.dart';
import '../ui/app_theme.dart';
import '../ui/onscreen_keyboard.dart';
import '../ui/system_palette.dart';
import 'database.dart';
import 'file_explorer.dart';
import 'foil.dart';
import 'game_box.dart';
import 'game_box_menu.dart';
import 'import_rules.dart';
import 'launch_animation.dart';
import 'library_scope.dart';
import 'stash_view.dart';
import '../ui/dena_icons.dart';
import '../ui/pixel.dart';
import '../ui/pixel_icons.dart';
import '../ui/pocket.dart';

/// Called when the user chooses Play on a game.
typedef PlayGame = void Function(BuildContext context, Game game);

class GamesTab extends StatefulWidget {
  const GamesTab({super.key, required this.onPlay});

  final PlayGame onPlay;

  @override
  State<GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<GamesTab> with WidgetsBindingObserver {
  String? system;
  String query = '';
  LibrarySort sort = LibrarySort.recentlyPlayed;
  final search = TextEditingController();
  bool _checkedShares = false;
  bool _importingShares = false;
  bool _stashLocal = false;

  /// The game whose box has D-pad focus; the strip under the shelves shows it.
  int? _focused;

  /// The saved view choice (theme.json), or a session-only one without it.
  ThemeSettings? get _settings =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
  bool get _stash => _settings?.stash ?? _stashLocal;
  void _toggleView() => setState(() {
    final s = _settings;
    if (s != null) {
      s.stash = !s.stash;
    } else {
      _stashLocal = !_stashLocal;
    }
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedShares) {
      _checkedShares = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _importShared());
    }
  }

  /// A share sent while the app is already open arrives as a new intent just
  /// before the app resumes (library.md, Import).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _importShared();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    super.dispose();
  }

  Future<void> _importShared() async {
    if (_importingShares || !mounted) return;
    _importingShares = true;
    try {
      final scope = LibraryScope.of(context);
      final paths = await scope.files.takeSharedFiles();
      if (paths.isNotEmpty && mounted) await _runImport(paths);
    } finally {
      _importingShares = false;
    }
  }

  Future<void> _addGames({required bool folder}) async {
    final scope = LibraryScope.of(context);
    final paths = await pickGamePaths(context, scope.files, folder: folder);
    if (paths.isNotEmpty && mounted) await _runImport(paths);
  }

  Future<void> _runImport(List<String> paths) async {
    final messenger = ScaffoldMessenger.of(context);
    final scope = LibraryScope.of(context);
    final progress = ValueNotifier('Importing 0 of ${paths.length}');
    messenger.showSnackBar(
      SnackBar(
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (_, v, _) => Text(v),
        ),
        duration: const Duration(days: 1),
      ),
    );
    final summary = await importPaths(
      scope,
      paths,
      onProgress: (d, t) => progress.value = 'Importing $d of $t',
    );
    messenger.hideCurrentSnackBar();
    final parts = [
      '${summary.added} added',
      if (summary.duplicates > 0) '${summary.duplicates} already in library',
      if (summary.rejected.isNotEmpty)
        '${summary.rejected.length} not imported',
    ];
    messenger.showSnackBar(
      SnackBar(
        content: Text(parts.join(', ')),
        action: summary.rejected.isEmpty
            ? null
            : SnackBarAction(
                label: 'Details',
                onPressed: () => _showRejected(summary),
              ),
      ),
    );
  }

  void _showRejected(ImportSummary summary) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (final r in summary.rejected)
            ListTile(title: Text(r.source), subtitle: Text(r.reason)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = LibraryScope.of(context).db;
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Game>>(
          stream: db.watchGames(system: system, query: query, sort: sort),
          builder: (context, snap) {
            final games = snap.data ?? const <Game>[];
            final empty =
                snap.hasData &&
                games.isEmpty &&
                system == null &&
                query.isEmpty;
            if (empty) return _EmptyLibrary(onAdd: _addGames);
            if (_stash) {
              return Column(
                children: [
                  _header(db),
                  Expanded(
                    child: StashView(
                      games: games,
                      onPlay: (g) => widget.onPlay(context, g),
                      onDetails: (g) =>
                          showGameSheet(context, g, widget.onPlay),
                    ),
                  ),
                ],
              );
            }
            final px = PocketMetrics.of(context).px;
            final phone = MediaQuery.sizeOf(context).width < 600;
            final shown = _focusedGame(games);
            return Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: InvertedBar(
                          large: true,
                          glyph: PixelGlyphs.cart,
                          title: 'LIBRARY',
                          trailing: games.length == 1
                              ? '1 game'
                              : '${games.length} games',
                        ),
                      ),
                      SliverToBoxAdapter(child: _header(db)),
                      if (query.isEmpty && system == null)
                        SliverToBoxAdapter(
                          child: StreamBuilder<Game?>(
                            stream: db.watchLastPlayed(),
                            builder: (context, s) => s.data == null
                                ? const SizedBox.shrink()
                                : _ContinueCard(
                                    game: s.data!,
                                    onPlay: widget.onPlay,
                                  ),
                          ),
                        ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          2 * px,
                          4 * px,
                          2 * px,
                          44 * px,
                        ),
                        // Boxes stand on dithered pixel shelves: three across
                        // on the phone, long shelves on bigger screens.
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: phone ? 120 : 64 * px,
                                childAspectRatio: 0.78,
                              ),
                          itemCount: games.length,
                          itemBuilder: (context, i) => GameCard(
                            game: games[i],
                            autofocus: i == 0,
                            onFocus: (f) => setState(
                              () => _focused = f ? games[i].id : _focused,
                            ),
                            onPlay: () => widget.onPlay(context, games[i]),
                            onDetails: (from) => showGameSheet(
                              context,
                              games[i],
                              widget.onPlay,
                              from: from,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (shown != null)
                  _FocusStrip(
                    game: shown,
                    position: games.indexOf(shown) + 1,
                    count: games.length,
                    onPlay: () => widget.onPlay(context, shown),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The focused game, else the first one (the most recently played).
  Game? _focusedGame(List<Game> games) {
    if (games.isEmpty) return null;
    return games.where((g) => g.id == _focused).firstOrNull ?? games.first;
  }

  Widget _header(LibraryDatabase db) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SearchBar(
                  controller: search,
                  hintText: 'Search games',
                  leading: const PixelIcon(PixelGlyphs.search),
                  constraints: const BoxConstraints(minHeight: 36),
                  onChanged: (v) => setState(() => query = v),
                  trailing: [
                    if (query.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(DenaIcons.close),
                        onPressed: () => setState(() {
                          search.clear();
                          query = '';
                        }),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _stash ? 'Grid view' : 'Stash view',
                icon: _stash
                    ? const Icon(DenaIcons.grid)
                    : const PixelIcon(PixelGlyphs.shuffle),
                onPressed: _toggleView,
              ),
              _AddButton(onAdd: _addGames),
              PopupMenuButton<LibrarySort>(
                tooltip: 'Sort',
                icon: const Icon(DenaIcons.sort),
                initialValue: sort,
                onSelected: (s) => setState(() => sort = s),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: LibrarySort.recentlyPlayed,
                    child: Text('Recently played'),
                  ),
                  PopupMenuItem(value: LibrarySort.title, child: Text('Title')),
                  PopupMenuItem(
                    value: LibrarySort.recentlyAdded,
                    child: Text('Recently added'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          StreamBuilder<List<String>>(
            stream: db.watchSystems(),
            builder: (context, s) {
              final systems = [...?s.data]..sort(_systemOrder);
              if (systems.length < 2) return const SizedBox.shrink();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip('All', null),
                    for (final id in systems) _chip(_shortName(id), id),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? id) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: ChoiceChip(
      label: Text(label),
      selected: system == id,
      onSelected: (_) => setState(() => system = id),
    ),
  );
}

int _systemOrder(String a, String b) => _index(a).compareTo(_index(b));
int _index(String id) {
  final i = GameSystem.values.indexWhere((s) => s.id == id);
  return i < 0 ? 99 : i;
}

String _shortName(String id) =>
    GameSystem.values
        .where((s) => s.id == id)
        .map((s) => s.shortName)
        .firstOrNull ??
    id;

/// One game in the grid, drawn as its console's real box (game_box.dart)
/// standing on a shelf. A / Enter plays; Y / long-press opens the details
/// sheet. With a D-pad the focused box grows and gets a primary outline.
class GameCard extends StatefulWidget {
  const GameCard({
    super.key,
    required this.game,
    required this.onPlay,
    required this.onDetails,
    this.autofocus = false,
    this.onFocus,
  });

  final Game game;
  final VoidCallback onPlay;

  /// Told when the box gains or loses focus.
  final ValueChanged<bool>? onFocus;

  /// Opens the details, given where the box stands on screen.
  final ValueChanged<Rect?> onDetails;
  final bool autofocus;

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard>
    with SingleTickerProviderStateMixin {
  bool focused = false;
  final _stage = GlobalKey();

  /// The HOLD meter: fills while a finger rests on the box, over the time a
  /// long press takes (pocket-lcd-ui.md).
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: kLongPressTimeout,
  );

  void _holdStart() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _hold.forward(from: 0);
  }

  void _holdEnd() => _hold.value = 0;

  void _details() {
    _holdEnd();
    final box = _stage.currentContext?.findRenderObject();
    widget.onDetails(
      box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    _hold.dispose();
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) {
    if (focused) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final style = PocketStyle.of(context);
    final p = style.palette, px = style.metrics.px;
    final text = Theme.of(context).textTheme;
    final ring =
        focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.gameButtonY): _details,
        const SingleActivator(LogicalKeyboardKey.contextMenu): _details,
      },
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          autofocus: widget.autofocus,
          onTap: () {
            _holdEnd();
            widget.onPlay();
          },
          onTapDown: (_) => _holdStart(),
          onTapCancel: _holdEnd,
          onLongPress: _details,
          onFocusChange: (f) {
            setState(() => focused = f);
            widget.onFocus?.call(f);
          },
          // Pixel corner brackets show focus; no wash over the shelf.
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(3 * px, 3 * px, 3 * px, 0),
                  child: PixelBrackets(
                    visible: ring,
                    child: Padding(
                      padding: EdgeInsets.all(2 * px),
                      child: Stack(
                        key: _stage,
                        fit: StackFit.expand,
                        children: [
                          GameBox(game: game),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _HoldMeter(hold: _hold),
                          ),
                          if (game.favorite)
                            Positioned(
                              bottom: px,
                              left: px,
                              child: Container(
                                color: p.paper,
                                padding: EdgeInsets.all(px),
                                child: PixelIcon(
                                  PixelGlyphs.star,
                                  size: 9 * px,
                                  color: p.ink,
                                  label: 'Favourite',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // The shelf plank: an ink edge over a dithered board.
              Container(height: px, color: p.ink),
              SizedBox(height: 3 * px, child: const Dither()),
              Padding(
                padding: EdgeInsets.fromLTRB(2 * px, px, 2 * px, 2 * px),
                child: Text(
                  game.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "HOLD" and a stepped bar that fills while a finger rests on a box; hidden
/// for quick taps.
class _HoldMeter extends StatelessWidget {
  const _HoldMeter({required this.hold});

  final Animation<double> hold;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette, px = style.metrics.px;
    final text = Theme.of(context).textTheme.labelSmall;
    return AnimatedBuilder(
      animation: hold,
      builder: (context, _) {
        // Shows after a fifth of the wait, in eight steps.
        final v = ((hold.value - 0.2) / 0.8).clamp(0.0, 1.0);
        if (v <= 0 || v >= 1) return const SizedBox.shrink();
        final steps = (v * 8).ceil() / 8;
        return ExcludeSemantics(
          child: Container(
            color: p.ink,
            padding: EdgeInsets.all(px),
            child: Row(
              children: [
                Text('HOLD', style: text?.copyWith(color: p.paper)),
                SizedBox(width: 2 * px),
                Expanded(
                  child: Container(
                    height: 3 * px,
                    color: p.dark,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: steps,
                      child: Container(color: p.paper),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The inverted strip under the shelves: the focused game's title, system
/// and playtime, with the buttons that matter.
class _FocusStrip extends StatelessWidget {
  const _FocusStrip({
    required this.game,
    required this.position,
    required this.count,
    required this.onPlay,
  });

  final Game game;
  final int position, count;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette, px = style.metrics.px;
    final text = Theme.of(context).textTheme;
    final hours = game.playSeconds ~/ 3600;
    final minutes = game.playSeconds ~/ 60 % 60;
    final played = game.playSeconds == 0
        ? 'not played yet'
        : hours > 0
        ? '${hours}h played'
        : '${minutes}m played';
    return Semantics(
      container: true,
      label: 'Selected game',
      child: GestureDetector(
        onTap: onPlay,
        child: Container(
          color: p.ink,
          padding: EdgeInsets.fromLTRB(4 * px, 3 * px, 4 * px, 3 * px),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: p.paper),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          game.title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge?.copyWith(color: p.paper),
                        ),
                      ),
                    ),
                    if (game.favorite)
                      PixelIcon(PixelGlyphs.star, size: 9 * px, color: p.paper),
                  ],
                ),
                Text(
                  '${_shortName(game.system)} · $played',
                  style: text.labelMedium?.copyWith(color: p.light),
                ),
                SizedBox(height: px),
                Row(
                  children: [
                    _Glyph('A'),
                    SizedBox(width: 2 * px),
                    Text(
                      'PLAY  ·  HOLD ZOOM',
                      style: text.labelMedium?.copyWith(color: p.paper),
                    ),
                    const Spacer(),
                    Text(
                      '$position/$count',
                      style: text.labelMedium?.copyWith(color: p.light),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round pixel button glyph (A, B, X, Y) for hints.
class _Glyph extends StatelessWidget {
  const _Glyph(this.letter);

  final String letter;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final p = style.palette, px = style.metrics.px;
    return Container(
      width: 8 * px,
      height: 8 * px,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.paper, shape: BoxShape.circle),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: p.ink, height: 1),
      ),
    );
  }
}

/// Cover stand-in: a gradient in the system's accent with its short name.
class SystemPlaceholder extends StatelessWidget {
  const SystemPlaceholder({super.key, required this.system});

  final String system;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sys = systemScheme(system, scheme);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            sys.primaryContainer,
            Color.lerp(sys.primaryContainer, sys.primary, 0.3)!,
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final side = box.biggest.shortestSide;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                right: -side * 0.18,
                bottom: -side * 0.18,
                child: Icon(
                  DenaIcons.controller,
                  size: side * 0.8,
                  color: sys.onPrimaryContainer.withValues(alpha: 0.08),
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.all(side * 0.12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _shortName(system),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: sys.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// An inverted section header strip, like an LCD menu's (pocket-lcd-ui.md).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final px = PocketMetrics.of(context).px;
    return Padding(
      padding: EdgeInsets.only(top: 4 * px, bottom: 2 * px),
      child: InvertedBar(title: label),
    );
  }
}

/// A game's cover from [LibraryScope.art], or [placeholder] while loading or
/// when there is none.
class GameCover extends StatefulWidget {
  const GameCover({
    super.key,
    required this.game,
    required this.placeholder,
    this.onAspect,
  });

  final Game game;
  final Widget placeholder;

  /// Told the cover image's width / height once it has loaded.
  final ValueChanged<double>? onAspect;

  @override
  State<GameCover> createState() => _GameCoverState();
}

class _GameCoverState extends State<GameCover> {
  File? file;
  bool hack = false;
  String? loadedKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(GameCover old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final key = '${widget.game.sha1}|${widget.game.customArtPath}';
    if (key == loadedKey) return;
    loadedKey = key;
    final art = LibraryScope.of(context).art;
    if (art == null) return;
    art.coverFor(widget.game).then((f) async {
      final standIn = f != null && await art.isHackStandIn(widget.game);
      if (mounted && loadedKey == key) {
        setState(() {
          file = f;
          hack = standIn;
        });
        if (f != null) _measure(f, key);
      }
    });
  }

  void _measure(File f, String key) {
    final onAspect = widget.onAspect;
    if (onAspect == null) return;
    final stream = FileImage(f).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      final w = info.image.width, h = info.image.height;
      info.dispose();
      if (mounted && loadedKey == key && h > 0) onAspect(w / h);
    }, onError: (_, _) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    // The launch animation starts from here (launch-animation.md).
    return LaunchOrigin(game: widget.game, child: _cover());
  }

  Widget _cover() {
    final f = file;
    if (f == null) return widget.placeholder;
    final cover = FoilOverlay(
      child: Image.file(
        f,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => widget.placeholder,
      ),
    );
    if (!hack) return cover;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        cover,
        const Positioned(left: 4, bottom: 4, child: HackBadge()),
      ],
    );
  }
}

/// Marks a base game's cover standing in for a romhack (box-art.md).
class HackBadge extends StatelessWidget {
  const HackBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Romhack, base game cover',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xE6202024),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFF1C40F), width: 1),
        ),
        child: const Text(
          'HACK',
          style: TextStyle(
            color: Color(0xFFF1C40F),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.game, required this.onPlay});

  final Game game;
  final PlayGame onPlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Card.filled(
        color: scheme.primaryContainer,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onPlay(context, game),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 44,
                    height: 56,
                    child: GameCover(
                      game: game,
                      placeholder: SystemPlaceholder(system: game.system),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue playing',
                        style: text.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.75,
                          ),
                        ),
                      ),
                      Text(
                        game.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PixelIcon(
                  PixelGlyphs.play,
                  size: 27,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onAdd});

  final Future<void> Function({required bool folder}) onAdd;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(DenaIcons.fileAdd),
          onPressed: () => onAdd(folder: false),
          child: const Text('Add games'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(DenaIcons.folderAdd),
          onPressed: () => onAdd(folder: true),
          child: const Text('Add a folder'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Add games',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const PixelIcon(PixelGlyphs.plus),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onAdd});

  final Future<void> Function({required bool folder}) onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _EmptyIcon(icon: DenaIcons.controller),
            const SizedBox(height: 16),
            Text('No games yet', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Add your own game files. Dena.emu does not include games.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  autofocus: true,
                  onPressed: () => onAdd(folder: false),
                  icon: const Icon(DenaIcons.fileAdd),
                  label: const Text('Add games'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => onAdd(folder: true),
                  icon: const Icon(DenaIcons.folderAdd),
                  label: const Text('Add a folder'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A large icon in a tonal circle, for empty states.
class _EmptyIcon extends StatelessWidget {
  const _EmptyIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 44, color: scheme.onPrimaryContainer),
    );
  }
}

/// Details: the game's box zooms toward the viewer with its options
/// (game_box_menu.dart). [from] is the box's place on screen, if known.
Future<void> showGameSheet(
  BuildContext context,
  Game game,
  PlayGame onPlay, {
  Rect? from,
}) => showGameBoxMenu(context, game, onPlay, from: from);

/// Asks for a new title; null when cancelled.
Future<String?> askGameName(BuildContext context, String current) {
  // Handhelds type on the D-pad keyboard (handheld-ui.md).
  if (Handheld.of(context)) {
    return showOnScreenKeyboard(
      context,
      title: 'Rename',
      initial: current,
      accept: (t) => t.trim().isNotEmpty,
    );
  }
  final c = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(controller: c, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(d, c.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Asks before deleting [game]; the D-pad starts on Cancel.
Future<bool> confirmGameDelete(BuildContext context, Game game) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete ${game.title}?'),
        content: const Text(
          'This removes the game, its saves and its save states from Dena.emu.',
        ),
        actions: [
          TextButton(
            // The D-pad starts on the safe choice.
            autofocus: true,
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;
