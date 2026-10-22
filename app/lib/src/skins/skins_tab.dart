// SPDX-License-Identifier: GPL-3.0-or-later
// Skins tab: built-in and imported skins per system, import and delete.
// Spec: docs/specs/skins.md (8b)
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../library/import_rules.dart';
import '../library/library_scope.dart';
import '../session/cheat_codes.dart' show systemLabel;
import '../shell/handheld.dart' show arrowsMoveFocus;
import 'deltaskin.dart';
import 'skin_store.dart';
import '../ui/dena_icons.dart';

final _systems = [
  for (final s in GameSystem.values)
    if (s.playable) s.id,
];

class SkinsTab extends StatefulWidget {
  const SkinsTab({super.key});

  @override
  State<SkinsTab> createState() => _SkinsTabState();
}

class _SkinsTabState extends State<SkinsTab> {
  List<InstalledSkin> installed = [];
  Map<String, String?> active = {};
  bool loaded = false;

  SkinStore? get store => LibraryScope.of(context).skins;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) _reload();
  }

  Future<void> _reload() async {
    final s = store;
    if (s == null) return;
    final list = await s.list();
    final ids = await s.activeIds();
    final known = {for (final i in list) i.skin.identifier};
    final act = <String, String?>{
      for (final sys in _systems)
        sys: known.contains(ids[sys]) ? ids[sys] : null,
    };
    if (!mounted) return;
    setState(() {
      installed = list;
      active = act;
      loaded = true;
    });
  }

  Future<void> _import() async {
    final scope = LibraryScope.of(context);
    final s = store;
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final paths = await scope.files.pickFiles();
    var added = 0;
    String? error;
    for (final path in paths) {
      if (!path.toLowerCase().endsWith('.deltaskin')) {
        error = 'Only .deltaskin files can be imported here';
        continue;
      }
      try {
        final skin = await s.install(File(path));
        added++;
        // A newly imported skin becomes active for its systems.
        for (final sys in skinSystems(skin.skin.gameType)) {
          await s.setActive(sys, skin.skin.identifier);
        }
      } on SkinFormatException catch (e) {
        error = e.message;
      }
    }
    await scope.files.clearCache();
    await _reload();
    if (added > 0 || error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error ?? (added == 1 ? 'Skin imported' : '$added skins imported'),
          ),
        ),
      );
    }
  }

  Future<void> _choose(String system, String? id) async {
    await store?.setActive(system, id);
    await _reload();
  }

  Future<void> _delete(InstalledSkin s) async {
    await store?.delete(s);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Touch controls appear when you play without a controller.',
                style: text.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              icon: const Icon(DenaIcons.document),
              label: const Text('Import skin'),
              onPressed: store == null ? null : _import,
            ),
          ],
        ),
        for (final sys in _systems) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
            child: Text(systemLabel(sys), style: text.titleSmall),
          ),
          Card.filled(
            color: Theme.of(context).colorScheme.surfaceContainer,
            clipBehavior: Clip.antiAlias,
            child: RadioGroup<String?>(
              groupValue: active[sys],
              onChanged: (id) => _choose(sys, id),
              child: Shortcuts(
                shortcuts: arrowsMoveFocus,
                child: Column(
                  children: [
                    const RadioListTile<String?>(
                      value: null,
                      title: Text('Built-in'),
                      dense: true,
                    ),
                    for (final s in installed.where(
                      (s) => skinSystems(s.skin.gameType).contains(sys),
                    ))
                      RadioListTile<String?>(
                        value: s.skin.identifier,
                        title: Text(s.skin.name),
                        dense: true,
                        subtitle: s.bundled
                            ? const Text('Console style')
                            : null,
                        secondary: s.bundled
                            ? null
                            : IconButton(
                                tooltip: 'Delete ${s.skin.name}',
                                icon: const Icon(DenaIcons.trash),
                                onPressed: () => _delete(s),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
