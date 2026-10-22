// SPDX-License-Identifier: GPL-3.0-or-later
// Save-state slots: files and the slot picker sheet.
// Spec: docs/specs/save-states.md
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../ui/pixel.dart';
import '../ui/pixel_icons.dart';
import '../ui/pocket.dart';

/// One save-state slot of a game: the quick slot or slots 1–9.
class StateSlot {
  StateSlot({
    required this.id,
    required this.label,
    required this.statePath,
    required this.pngPath,
    this.savedAt,
  });

  /// `quick` or `slot<N>`.
  final String id;
  final String label;
  final String statePath;
  final String pngPath;

  /// When the slot was written, or null when it is empty.
  final DateTime? savedAt;

  bool get isEmpty => savedAt == null;
}

/// The quick slot and slots 1–9 under `states/<sha1>/` of [dataDir].
List<StateSlot> listSlots(String dataDir, String sha1) {
  final dir = p.posix.join(dataDir, 'states', sha1);
  StateSlot slot(String id, String label) {
    final state = p.posix.join(dir, '$id.state');
    final f = File(state);
    return StateSlot(
      id: id,
      label: label,
      statePath: state,
      pngPath: p.posix.join(dir, '$id.png'),
      savedAt: f.existsSync() ? f.lastModifiedSync() : null,
    );
  }

  return [
    slot('quick', 'Quick'),
    for (var n = 1; n <= 9; n++) slot('slot$n', 'Slot $n'),
  ];
}

String formatSlotTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

enum SlotMode { save, load }

/// Grid of slots; pops with the picked [StateSlot]. In [SlotMode.load] empty
/// slots are disabled. B (Back) closes without picking.
class SlotSheet extends StatelessWidget {
  const SlotSheet({
    super.key,
    required this.mode,
    required this.slots,
    required this.aspectRatio,
  });

  final SlotMode mode;
  final List<StateSlot> slots;

  /// The game's picture aspect ratio, for the thumbnails.
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 5 : (width >= 560 ? 4 : 2);
    bool enabled(StateSlot s) => mode == SlotMode.save || !s.isEmpty;
    final firstEnabled = slots.indexWhere(enabled);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InvertedBar(
              title: mode == SlotMode.save ? 'Save state' : 'Load state',
              glyph: mode == SlotMode.save
                  ? PixelGlyphs.floppy
                  : PixelGlyphs.load,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: aspectRatio * 0.82,
                children: [
                  for (final (i, s) in slots.indexed)
                    _SlotTile(
                      slot: s,
                      autofocus: i == firstEnabled,
                      enabled: enabled(s),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotTile extends StatefulWidget {
  const _SlotTile({
    required this.slot,
    required this.autofocus,
    required this.enabled,
  });

  final StateSlot slot;
  final bool autofocus;
  final bool enabled;

  @override
  State<_SlotTile> createState() => _SlotTileState();
}

/// A mini screenshot in an ink frame, its label underneath; brackets mark
/// the focused slot (pocket-lcd-ui.md).
class _SlotTileState extends State<_SlotTile> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final style = PocketStyle.of(context);
    final pal = style.palette, px = style.metrics.px;
    final text = Theme.of(context).textTheme;
    final slot = widget.slot;
    final png = File(slot.pngPath);
    final thumb = !slot.isEmpty && png.existsSync()
        ? Image.memory(
            png.readAsBytesSync(),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.none,
            gaplessPlayback: true,
          )
        : Dither(
            color: pal.light,
            child: Center(
              child: PixelIcon(
                PixelGlyphs.picture,
                size: 9 * px,
                color: pal.dark,
              ),
            ),
          );
    return InkWell(
      autofocus: widget.autofocus,
      onTap: widget.enabled ? () => Navigator.of(context).pop(slot) : null,
      onFocusChange: (f) => setState(() => focused = f),
      splashFactory: NoSplash.splashFactory,
      focusColor: Colors.transparent,
      highlightColor: pal.light,
      child: PixelBrackets(
        visible: focused,
        child: Padding(
          padding: EdgeInsets.all(2 * px),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      border: Border.all(color: pal.ink, width: px),
                    ),
                    child: ClipRect(child: thumb),
                  ),
                ),
                SizedBox(height: px),
                Text(slot.label, style: text.labelLarge),
                Text(
                  slot.isEmpty ? 'Empty' : formatSlotTime(slot.savedAt!),
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
