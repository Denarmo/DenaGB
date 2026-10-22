// SPDX-License-Identifier: GPL-3.0-or-later
// Settings > Shaders: each system's default shader and resolution.
// Spec: docs/specs/shaders.md (App)
import 'package:material_ui/material_ui.dart';

import '../session/cheat_codes.dart' show systemLabel;
import '../session/session_screen.dart' show coreLibraries;
import '../shell/handheld.dart';
import 'shader_catalog.dart';
import 'shader_sheet.dart';
import 'shader_store.dart';
import '../ui/dena_icons.dart';

class ShaderSettingsPage extends StatefulWidget {
  const ShaderSettingsPage({super.key, required this.store});

  final ShaderStore store;

  @override
  State<ShaderSettingsPage> createState() => _ShaderSettingsPageState();
}

class _ShaderSettingsPageState extends State<ShaderSettingsPage> {
  Future<void> _open(String system) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShaderSheet(store: widget.store, system: system),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shaders')),
      body: SafeArea(
        child: ListView(
          children: [
            for (final (i, system) in coreLibraries.keys.indexed)
              ListTile(
                autofocus: i == 0,
                dense: true,
                title: Text(systemLabel(system)),
                subtitle: Text(
                  [
                    shaderName(widget.store.systemDefault(system)),
                    if (widget.store.systemUpscale(system) > 1 &&
                        !Handheld.of(context))
                      '${widget.store.systemUpscale(system)}x resolution',
                  ].join(' · '),
                ),
                trailing: const Icon(DenaIcons.chevronRight),
                onTap: () => _open(system),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Handheld.of(context)
          ? const HintBar(
              hints: [
                ([HintButton.a], 'Open'),
                ([HintButton.b], 'Back'),
              ],
            )
          : null,
    );
  }
}
