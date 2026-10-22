// SPDX-License-Identifier: GPL-3.0-or-later
// Cheat database browser: popular and searchable cheats for the running game.
// Spec: docs/specs/cheats.md (Cheat database)
import 'package:material_ui/material_ui.dart';

import '../library/database.dart';
import 'cheat_database.dart';
import 'cheats_sheet.dart';
import '../ui/dena_icons.dart';

class CheatBrowserSheet extends StatefulWidget {
  const CheatBrowserSheet({
    super.key,
    required this.db,
    required this.game,
    required this.database,
    required this.apply,
    this.clock = DateTime.now,
  });

  final LibraryDatabase db;
  final Game game;
  final CheatDatabase database;
  final ApplyCheats apply;
  final DateTime Function() clock;

  @override
  State<CheatBrowserSheet> createState() => _CheatBrowserSheetState();
}

class _CheatBrowserSheetState extends State<CheatBrowserSheet> {
  late Future<CheatLookup> _lookup = widget.database.cheatsFor(widget.game);
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Cheat? _stored(List<Cheat> mine, DbCheat c) {
    for (final m in mine) {
      if (m.name == c.name && m.code == c.code) return m;
    }
    return null;
  }

  Future<void> _turnOn(DbCheat c) async {
    final mine = await widget.db.cheatsFor(widget.game.id);
    for (final x in [...(await _lookup).mastersOf(c), c]) {
      final have = _stored(mine, x);
      if (have == null) {
        await widget.db.addCheat(
          gameId: widget.game.id,
          name: x.name,
          code: x.code,
          format: x.format,
          createdAt: widget.clock(),
        );
      } else if (!have.enabled) {
        await widget.db.setCheatEnabled(have.id, true);
      }
    }
  }

  Future<void> _toggle(DbCheat c, bool on) async {
    if (on) {
      await _turnOn(c);
    } else {
      final have = _stored(await widget.db.cheatsFor(widget.game.id), c);
      if (have != null) await widget.db.deleteCheat(have.id);
    }
    await widget.apply(await enabledCheatCodes(widget.db, widget.game.id));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cheat database', style: text.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(DenaIcons.search),
                  hintText: 'Search cheats',
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: FutureBuilder<CheatLookup>(
                  future: _lookup,
                  builder: (context, snap) {
                    if (snap.hasError) return _error(text);
                    final lookup = snap.data;
                    if (lookup == null) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (lookup.cheats.isEmpty) {
                      return _message(
                        text,
                        'No cheats for this game in the database.',
                      );
                    }
                    return StreamBuilder<List<Cheat>>(
                      stream: widget.db.watchCheats(widget.game.id),
                      builder: (context, mineSnap) =>
                          _list(text, lookup, mineSnap.data ?? const []),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cheats from libretro-database (CC-BY-SA 4.0)',
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(TextTheme text, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(message, style: text.bodyMedium),
  );

  Widget _error(TextTheme text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            "Couldn't download cheats. Check your connection.",
            style: text.bodyMedium,
          ),
        ),
        FilledButton.tonalIcon(
          autofocus: true,
          icon: const Icon(DenaIcons.refresh),
          label: const Text('Retry'),
          onPressed: () => setState(() {
            _lookup = widget.database.cheatsFor(widget.game);
          }),
        ),
      ],
    ),
  );

  Widget _list(TextTheme text, CheatLookup lookup, List<Cheat> mine) {
    final q = _query.toLowerCase();
    final popular = q.isEmpty ? lookup.popularCheats : const <DbCheat>[];
    final all = [
      for (final c in lookup.cheats)
        if (q.isEmpty || c.name.toLowerCase().contains(q)) c,
    ];
    final rows = <Widget>[
      if (popular.isNotEmpty) _header(text, DenaIcons.starOutline, 'Popular'),
      for (final (i, c) in popular.indexed)
        _tile(c, mine, autofocus: i == 0, key: 'popular'),
      _header(text, DenaIcons.list, 'All cheats (${all.length})'),
      for (final (i, c) in all.indexed)
        _tile(c, mine, autofocus: popular.isEmpty && q.isEmpty && i == 0),
      if (all.isEmpty) _message(text, 'No cheats match "$_query".'),
    ];
    return ListView.builder(
      shrinkWrap: true,
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  Widget _header(TextTheme text, IconData icon, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label, style: text.titleSmall),
      ],
    ),
  );

  Widget _tile(
    DbCheat c,
    List<Cheat> mine, {
    bool autofocus = false,
    String key = 'all',
  }) {
    final on = _stored(mine, c)?.enabled ?? false;
    return SwitchListTile(
      key: ValueKey('$key:${identityHashCode(c)}'),
      autofocus: autofocus,
      dense: true,
      contentPadding: const EdgeInsets.only(left: 4, right: 8),
      title: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(c.format, maxLines: 1, overflow: TextOverflow.ellipsis),
      value: on,
      onChanged: (v) => _toggle(c, v),
    );
  }
}
