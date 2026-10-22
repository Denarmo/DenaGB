// SPDX-License-Identifier: GPL-3.0-or-later
// RetroAchievements screens: settings, the game page list, the session list
// and the unlock toasts. Spec: docs/specs/achievements.md
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../library/database.dart';
import '../library/games_tab.dart' show SectionLabel;
import 'retro_achievements.dart';
import '../ui/dena_icons.dart';

/// Settings tab row: who is signed in, opening [RetroAchievementsPage].
class RetroAchievementsTile extends StatelessWidget {
  const RetroAchievementsTile({super.key, required this.ra});

  final RetroAchievements ra;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ra,
      builder: (context, _) {
        final a = ra.account;
        return ListTile(
          leading: const Icon(DenaIcons.trophyOutline),
          title: const Text('RetroAchievements'),
          subtitle: Text(
            a == null
                ? 'Sign in to earn achievements'
                : '${a.name} · ${ra.hardcore ? 'Hardcore' : 'Softcore'}',
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RetroAchievementsPage(ra: ra),
            ),
          ),
        );
      },
    );
  }
}

/// Sign in or out, and the hardcore switch.
class RetroAchievementsPage extends StatefulWidget {
  const RetroAchievementsPage({super.key, required this.ra});

  final RetroAchievements ra;

  @override
  State<RetroAchievementsPage> createState() => _RetroAchievementsPageState();
}

class _RetroAchievementsPageState extends State<RetroAchievementsPage> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_user.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.ra.signIn(_user.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err == null) _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget group(Widget child) => Card.filled(
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('RetroAchievements')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.ra,
          builder: (context, _) {
            final a = widget.ra.account;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                const SectionLabel('Account'),
                if (a == null)
                  group(
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Use your retroachievements.org account. '
                              'Dena.emu keeps a sign-in token, not your '
                              'password.',
                              style: text.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _user,
                              enabled: !_busy,
                              autofocus: true,
                              autofillHints: const [AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _password,
                              enabled: !_busy,
                              obscureText: true,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => _signIn(),
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: text.bodySmall?.copyWith(
                                  color: scheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _busy ? null : _signIn,
                              child: Text(_busy ? 'Signing in…' : 'Sign in'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  group(
                    ListTile(
                      leading: _Avatar(url: a.avatar),
                      title: Text(a.name),
                      subtitle: Text(
                        '${a.score} hardcore points · '
                        '${a.softcoreScore} softcore',
                      ),
                      trailing: TextButton(
                        onPressed: widget.ra.signOut,
                        child: const Text('Sign out'),
                      ),
                    ),
                  ),
                const SectionLabel('Play'),
                group(
                  SwitchListTile(
                    secondary: const Icon(DenaIcons.flame),
                    title: const Text('Hardcore mode'),
                    subtitle: const Text(
                      'Earn hardcore points. Loading save states, rewind and '
                      'cheats are off, and games start from the battery save.',
                    ),
                    value: widget.ra.hardcore,
                    onChanged: (v) => widget.ra.hardcore = v,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final u = url;
    return CircleAvatar(
      foregroundImage: u == null ? null : NetworkImage(u),
      onForegroundImageError: u == null ? null : (_, _) {},
      child: const Icon(DenaIcons.person),
    );
  }
}

/// An achievement badge; the locked art (or a lock) until unlocked.
class RaBadge extends StatelessWidget {
  const RaBadge({super.key, required this.achievement, this.size = 48});

  final RaAchievement achievement;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = achievement.unlocked
        ? achievement.badge
        : achievement.badgeLocked;
    final fallback = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      child: Icon(
        achievement.unlocked ? DenaIcons.trophy : DenaIcons.lock,
        color: scheme.onSurfaceVariant,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? fallback
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class RaAchievementTile extends StatelessWidget {
  const RaAchievementTile({super.key, required this.achievement});

  final RaAchievement achievement;

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final scheme = Theme.of(context).colorScheme;
    final state = switch (a.unlock) {
      RaUnlock.hardcore => 'Unlocked in hardcore',
      RaUnlock.softcore => 'Unlocked',
      RaUnlock.locked => a.progress.isNotEmpty ? a.progress : null,
    };
    return ListTile(
      // Focusable for D-pad scrolling; nothing to open.
      onTap: () {},
      leading: RaBadge(achievement: a),
      title: Text(a.title),
      subtitle: Text(
        [a.description, ?state].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: state != null,
      trailing: Text(
        '${a.points}',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: a.unlocked ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Unlocked first, in list order otherwise.
List<RaAchievement> _sorted(List<RaAchievement> list) => [
  ...list.where((a) => a.unlocked),
  ...list.where((a) => !a.unlocked),
];

/// The game page's list (opened from the game sheet).
class GameAchievementsPage extends StatefulWidget {
  const GameAchievementsPage({super.key, required this.ra, required this.game});

  final RetroAchievements ra;
  final Game game;

  @override
  State<GameAchievementsPage> createState() => _GameAchievementsPageState();
}

class _GameAchievementsPageState extends State<GameAchievementsPage> {
  late Future<RaGameInfo> _info = _fetch();

  Future<RaGameInfo> _fetch() =>
      widget.ra.fetchGame(widget.game.path, widget.game.system);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.game.title)),
      body: SafeArea(
        child: FutureBuilder<RaGameInfo>(
          future: _info,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final err = snap.error;
            if (err != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        err is RaFetchError ? err.message : '$err',
                        textAlign: TextAlign.center,
                        style: text.bodyLarge,
                      ),
                      if (err is! RaFetchError || !err.unknown) ...[
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          autofocus: true,
                          onPressed: widget.ra.account == null
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        RetroAchievementsPage(ra: widget.ra),
                                  ),
                                )
                              : () => setState(() => _info = _fetch()),
                          child: Text(
                            widget.ra.account == null ? 'Sign in' : 'Try again',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }
            final info = snap.requireData;
            if (info.achievements.isEmpty) {
              return Center(
                child: Text(
                  'This game has no achievements yet',
                  style: text.bodyLarge,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _ProgressHeader(
                  unlocked: info.unlocked,
                  total: info.achievements.length,
                  subtitle:
                      '${info.pointsUnlocked} of ${info.points} points'
                      '${widget.ra.hardcoreFor(widget.game.system) ? ' · Hardcore on' : ''}',
                ),
                for (final a in _sorted(info.achievements))
                  RaAchievementTile(achievement: a),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.unlocked,
    required this.total,
    required this.subtitle,
  });

  final int unlocked, total;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$unlocked of $total unlocked', style: text.titleMedium),
          Text(subtitle, style: text.bodySmall),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: total == 0 ? 0 : unlocked / total),
        ],
      ),
    );
  }
}

/// The running game's achievements (pause sheet).
class SessionAchievementsSheet extends StatelessWidget {
  const SessionAchievementsSheet({super.key, required this.ra});

  final RetroAchievements ra;

  @override
  Widget build(BuildContext context) {
    final s = ra.session;
    final list = _sorted(ra.sessionAchievements());
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          children: [
            _ProgressHeader(
              unlocked: list.where((a) => a.unlocked).length,
              total: list.length,
              subtitle: [
                s?.title ?? '',
                if (s?.hardcore ?? false) 'Hardcore',
              ].where((t) => t.isNotEmpty).join(' · '),
            ),
            for (final a in list) RaAchievementTile(achievement: a),
          ],
        ),
      ),
    );
  }
}

/// Shows [RetroAchievements.notices] one at a time at the top of the game.
class RaToastLayer extends StatefulWidget {
  const RaToastLayer({super.key, required this.notices});

  final Stream<RaNotice> notices;

  @override
  State<RaToastLayer> createState() => _RaToastLayerState();
}

class _RaToastLayerState extends State<RaToastLayer> {
  final _queue = <RaNotice>[];
  RaNotice? _showing;
  late final StreamSubscription<RaNotice> _sub = widget.notices.listen((n) {
    _queue.add(n);
    _next();
  });
  Timer? _timer;

  static const shown = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _sub;
  }

  void _next() {
    if (_showing != null || _queue.isEmpty || !mounted) return;
    setState(() => _showing = _queue.removeAt(0));
    _timer = Timer(shown, () {
      if (!mounted) return;
      setState(() => _showing = null);
      _next();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _showing;
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: n == null
                ? const SizedBox.shrink()
                : Padding(
                    key: ObjectKey(n),
                    padding: const EdgeInsets.all(12),
                    child: _Toast(notice: n),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.notice});

  final RaNotice notice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (Widget leading, String title, String body) = switch (notice) {
      RaUnlockNotice(:final achievement, :final hardcore) => (
        RaBadge(achievement: achievement, size: 44),
        achievement.title,
        'Achievement unlocked · ${achievement.points} points'
            '${hardcore ? ' · Hardcore' : ''}',
      ),
      RaGameNotice(:final session) => (
        const Icon(DenaIcons.trophy, size: 32),
        session.title,
        session.total == 0
            ? 'No achievements yet'
            : '${session.unlocked} of ${session.total} achievements unlocked'
                  '${session.hardcore ? ' · Hardcore' : ''}',
      ),
      RaUnknownGameNotice() => (
        const Icon(DenaIcons.help, size: 32),
        'RetroAchievements',
        "This game file isn't recognised",
      ),
      RaMasteredNotice(:final title) => (
        const Icon(DenaIcons.premium, size: 32),
        title,
        'Every achievement unlocked!',
      ),
      RaOfflineNotice(:final offline) => (
        Icon(offline ? DenaIcons.cloudOff : DenaIcons.cloudDone, size: 32),
        'RetroAchievements',
        offline
            ? 'Offline: unlocks will be sent when the connection returns'
            : 'Back online: unlocks sent',
      ),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Material(
        color: scheme.inverseSurface,
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(
                data: IconThemeData(color: scheme.inversePrimary),
                child: leading,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        color: scheme.onInverseSurface,
                      ),
                    ),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onInverseSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
