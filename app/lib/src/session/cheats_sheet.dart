// SPDX-License-Identifier: GPL-3.0-or-later
// Cheats sheet: list, toggle, add and delete a game's cheats.
// Spec: docs/specs/cheats.md
import 'package:material_ui/material_ui.dart';

import '../library/database.dart';
import 'cheat_browser.dart';
import 'cheat_codes.dart';
import 'cheat_database.dart';
import '../ui/dena_icons.dart';

/// Sends the enabled cheats (in core form) to the running core.
typedef ApplyCheats = Future<void> Function(List<String> codes);

/// The enabled cheats of [gameId] in the form the core wants.
Future<List<String>> enabledCheatCodes(LibraryDatabase db, int gameId) async =>
    [
      for (final c in await db.cheatsFor(gameId))
        if (c.enabled) coreCode(c.code),
    ];

class CheatsSheet extends StatelessWidget {
  const CheatsSheet({
    super.key,
    required this.db,
    required this.game,
    required this.apply,
    this.database,
    this.clock = DateTime.now,
  });

  final LibraryDatabase db;
  final Game game;
  final ApplyCheats apply;

  /// The cheat database to browse; no **Browse** button when null or when the
  /// system has no database cheats.
  final CheatDatabase? database;
  final DateTime Function() clock;

  Future<void> _changed() async => apply(await enabledCheatCodes(db, game.id));

  Future<void> _add(BuildContext context) async {
    final added = await showDialog<ParsedCheat>(
      context: context,
      builder: (_) => _AddCheatDialog(system: game.system, onSave: _save),
    );
    if (added != null) await _changed();
  }

  Future<void> _browse(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CheatBrowserSheet(
      db: db,
      game: game,
      database: database!,
      apply: apply,
      clock: clock,
    ),
  );

  Future<void> _save(String name, ParsedCheat cheat) => db.addCheat(
    gameId: game.id,
    name: name,
    code: cheat.stored,
    format: cheat.format,
    createdAt: clock(),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Cheats', style: text.titleMedium)),
                if (database != null &&
                    cheatDbSystems.containsKey(game.system)) ...[
                  FilledButton.tonalIcon(
                    icon: const Icon(DenaIcons.globe),
                    label: const Text('Browse'),
                    onPressed: () => _browse(context),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton.tonalIcon(
                  icon: const Icon(DenaIcons.add),
                  label: const Text('Add cheat'),
                  onPressed: () => _add(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: StreamBuilder<List<Cheat>>(
                stream: db.watchCheats(game.id),
                builder: (context, snap) {
                  final cheats = snap.data ?? const <Cheat>[];
                  if (cheats.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No cheats yet. Add a Game Genie, Action Replay, '
                        'GameShark or raw code.',
                        style: text.bodyMedium,
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final (i, c) in cheats.indexed)
                        _CheatTile(
                          cheat: c,
                          autofocus: i == 0,
                          onToggle: (on) async {
                            await db.setCheatEnabled(c.id, on);
                            await _changed();
                          },
                          onDelete: () async {
                            await db.deleteCheat(c.id);
                            await _changed();
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheatTile extends StatelessWidget {
  const _CheatTile({
    required this.cheat,
    required this.autofocus,
    required this.onToggle,
    required this.onDelete,
  });

  final Cheat cheat;
  final bool autofocus;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final lines = cheat.code.split('\n');
    final summary = lines.length == 1
        ? lines.first
        : '${lines.first} (+${lines.length - 1})';
    return Row(
      children: [
        Expanded(
          child: SwitchListTile(
            autofocus: autofocus,
            dense: true,
            contentPadding: const EdgeInsets.only(left: 4, right: 8),
            title: Text(
              cheat.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${cheat.format} · $summary',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            value: cheat.enabled,
            onChanged: onToggle,
          ),
        ),
        IconButton(
          tooltip: 'Delete ${cheat.name}',
          icon: const Icon(DenaIcons.trash),
          onPressed: onDelete,
        ),
      ],
    );
  }
}

class _AddCheatDialog extends StatefulWidget {
  const _AddCheatDialog({required this.system, required this.onSave});

  final String system;
  final Future<void> Function(String name, ParsedCheat cheat) onSave;

  @override
  State<_AddCheatDialog> createState() => _AddCheatDialogState();
}

class _AddCheatDialogState extends State<_AddCheatDialog> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final parsed = parseCheat(widget.system, _code.text);
    if (parsed == null) {
      setState(
        () => _error =
            "This doesn't look like a ${systemLabel(widget.system)} code",
      );
      return;
    }
    final name = _name.text.trim().isEmpty
        ? parsed.lines.first
        : _name.text.trim();
    await widget.onSave(name, parsed);
    if (mounted) Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add cheat'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Code',
              helperText: 'One code per line',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
