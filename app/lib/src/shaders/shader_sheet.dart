// SPDX-License-Identifier: GPL-3.0-or-later
// Shader picker: Off and every bundled shader, saved per game or per system.
// Spec: docs/specs/shaders.md (App)
import 'package:material_ui/material_ui.dart';

import '../session/cheat_codes.dart' show systemLabel;
import '../shell/handheld.dart';
import 'shader_catalog.dart';
import 'shader_store.dart';
import '../ui/dena_icons.dart';

/// Applies [id] to the running game ("" = Off); false when it failed to load.
typedef ApplyShader = Future<bool> Function(String id);

class ShaderSheet extends StatefulWidget {
  const ShaderSheet({
    super.key,
    required this.store,
    required this.system,
    this.gameSha1,
    this.current,
    this.onApply,
  });

  final ShaderStore store;
  final String system;

  /// The paused game; null on Settings, where only the system default is set.
  final String? gameSha1;

  /// The shader showing now (it may differ from the saved one after a load
  /// failure); read from [store] when null.
  final String? current;

  /// Previews a pick behind the sheet; none on Settings.
  final ApplyShader? onApply;

  @override
  State<ShaderSheet> createState() => _ShaderSheetState();
}

class _ShaderSheetState extends State<ShaderSheet> {
  late String selected =
      widget.current ??
      (widget.gameSha1 == null
          ? widget.store.systemDefault(widget.system)
          : widget.store.resolve(widget.system, widget.gameSha1!));

  /// Saving for this game only (true) or for every game of the system.
  late bool gameScope =
      widget.gameSha1 != null && widget.store.hasGameOverride(widget.gameSha1!);

  late int upscale = widget.gameSha1 == null
      ? widget.store.systemUpscale(widget.system)
      : widget.store.resolveUpscale(widget.system, widget.gameSha1!);
  late final int _upscaleAtOpen = upscale;

  /// Saved with the same scope as the shader; the core reads it at start.
  void _pickUpscale(int factor) {
    setState(() => upscale = factor);
    final sha1 = widget.gameSha1;
    if (gameScope && sha1 != null) {
      widget.store.setGameUpscale(sha1, factor);
    } else {
      widget.store.setSystemUpscale(widget.system, factor);
      if (sha1 != null) widget.store.clearGameUpscale(sha1);
    }
  }

  Future<void> _pick(String id) async {
    setState(() => selected = id);
    final ok = await widget.onApply?.call(id) ?? true;
    if (!mounted) return;
    if (!ok) {
      // The session fell back to Off; the saved choice stays as it was.
      setState(() => selected = '');
      return;
    }
    final sha1 = widget.gameSha1;
    if (gameScope && sha1 != null) {
      widget.store.setGame(sha1, id);
    } else {
      widget.store.setSystem(widget.system, id);
      // So the game shows what was picked: drop its own choice.
      if (sha1 != null) widget.store.clearGame(sha1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = systemLabel(widget.system);
    final entries = shadersFor(widget.system);
    final handheld = Handheld.of(context);
    // The game stays visible above the sheet for the preview.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    final sheet = SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(switch ((widget.gameSha1 == null, handheld)) {
              (true, false) => '$label shader and resolution',
              (true, true) => '$label shader',
              (false, false) => 'Shader and resolution',
              (false, true) => 'Shader',
            }, style: text.titleMedium),
            if (widget.gameSha1 != null) ...[
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: true, label: Text('This game')),
                  ButtonSegment(
                    value: false,
                    label: Text(
                      'All $label games',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {gameScope},
                onSelectionChanged: (s) => setState(() => gameScope = s.first),
              ),
            ],
            // The launcher draws at native resolution: handheld GPUs have
            // no headroom for more (handheld-session.md).
            if (!handheld) ...[
              const SizedBox(height: 8),
              _ResolutionRow(
                system: widget.system,
                label: label,
                factor: upscale,
                restartNote:
                    widget.gameSha1 != null && upscale != _upscaleAtOpen,
                onChanged: _pickUpscale,
              ),
            ],
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _ShaderTile(
                    name: 'Off',
                    description: 'The plain picture',
                    selected: selected.isEmpty,
                    onTap: () => _pick(''),
                  ),
                  for (final e in entries)
                    _ShaderTile(
                      name: e.shader.name,
                      description: e.shader.description,
                      suggested: e.suggested,
                      selected: selected == e.shader.id,
                      onTap: () => _pick(e.shader.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight.clamp(260, 640)),
      child: !Handheld.of(context)
          ? sheet
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: sheet),
                const HintBar(
                  hints: [
                    ([HintButton.a], 'Select'),
                    ([HintButton.b], 'Back'),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Internal resolution (shaders.md, Upscale): Auto (the core's default), 2x,
/// 3x, 4x, with the
/// factors the system's core can't do disabled and a note saying so, that
/// the system is upscaled by the filter, or that it renders true resolution
/// on a GPU renderer with a requirement (DS).
class _ResolutionRow extends StatelessWidget {
  const _ResolutionRow({
    required this.system,
    required this.label,
    required this.factor,
    required this.restartNote,
    required this.onChanged,
  });

  final String system;
  final String label;
  final int factor;
  final bool restartNote;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final max = maxUpscale(system);
    final String? note = max < 2
        ? '$label draws at its native resolution only'
        : restartNote
        ? 'The new resolution applies the next time the game starts'
        : max < 4
        ? '$label renders at 2x at most'
        : filterUpscale(system)
        ? 'Smoothed with the xBRZ pixel-art filter'
        : upscaleRequirement(system) != null
        ? 'True 3D resolution, needs ${upscaleRequirement(system)}'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Resolution', style: text.labelLarge),
            const SizedBox(width: 12),
            Expanded(
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  const ButtonSegment(
                    value: 0,
                    label: Text('Auto', maxLines: 1, softWrap: false),
                  ),
                  for (final f in const [2, 3, 4])
                    ButtonSegment(
                      value: f,
                      label: Text('${f}x'),
                      enabled: f <= max,
                    ),
                ],
                selected: {factor},
                onSelectionChanged: (s) => onChanged(s.first),
              ),
            ),
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              note,
              style: text.bodySmall?.copyWith(color: muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

class _ShaderTile extends StatelessWidget {
  const _ShaderTile({
    required this.name,
    required this.description,
    required this.selected,
    required this.onTap,
    this.suggested = false,
  });

  final String name;
  final String description;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      // The current shader takes focus first, so A on open keeps it.
      autofocus: selected,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: selected,
      selectedTileColor: scheme.secondaryContainer,
      selectedColor: scheme.onSecondaryContainer,
      leading: Icon(selected ? DenaIcons.radioOn : DenaIcons.radioOff),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(description, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: suggested ? const _SuggestedBadge() : null,
      onTap: onTap,
    );
  }
}

class _SuggestedBadge extends StatelessWidget {
  const _SuggestedBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Suggested',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: scheme.onTertiaryContainer),
      ),
    );
  }
}
