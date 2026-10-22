// SPDX-License-Identifier: GPL-3.0-or-later
// Handheld mode and the button-hint bar. Spec: docs/specs/handheld-ui.md
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Whether the app runs as the launcher of a Linux handheld (no touch, D-pad
/// only). The SD-card launcher sets `DENA_HANDHELD=1`.
bool detectHandheld() =>
    Platform.isLinux && Platform.environment['DENA_HANDHELD'] == '1';

/// Tells screens they run on a handheld.
class Handheld extends InheritedWidget {
  const Handheld({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Handheld>()?.enabled ?? false;

  @override
  bool updateShouldNotify(Handheld old) => enabled != old.enabled;
}

/// A face or shoulder button shown in a hint.
enum HintButton {
  a('A'),
  b('B'),
  x('X'),
  y('Y'),
  l1('L1'),
  r1('R1'),
  start('START');

  const HintButton(this.glyph);
  final String glyph;
}

/// One hint: buttons (shown together, e.g. L1/R1) and what they do.
typedef ButtonHint = (List<HintButton>, String);

/// The bottom bar of hints on handhelds (CLAUDE.md §5).
class HintBar extends StatelessWidget {
  const HintBar({super.key, required this.hints});

  final List<ButtonHint> hints;

  static const height = 30.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.labelMedium;
    return Material(
      color: scheme.surfaceContainer,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final (i, (buttons, label)) in hints.indexed) ...[
                if (i > 0) const SizedBox(width: 16),
                for (final b in buttons) ...[
                  _Glyph(button: b),
                  const SizedBox(width: 3),
                ],
                const SizedBox(width: 3),
                Text(label, style: text),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.button});

  final HintButton button;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final round = button.glyph.length == 1;
    return Container(
      height: 20,
      constraints: BoxConstraints(minWidth: round ? 20 : 28),
      padding: EdgeInsets.symmetric(horizontal: round ? 0 : 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.onSurface,
        borderRadius: BorderRadius.circular(round ? 10 : 6),
      ),
      child: Text(
        button.glyph,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: scheme.surface, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// B goes back on every screen: pops the top route (sheet, dialog, page).
class BackIntent extends Intent {
  const BackIntent();
}

/// Arrow keys that only move focus. Put inside a [RadioGroup] so the D-pad
/// moves between options and A picks one: the group's own arrow keys pick
/// every option they pass and never leave the group.
const arrowsMoveFocus = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
    TraversalDirection.up,
  ),
  SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
    TraversalDirection.down,
  ),
  SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
    TraversalDirection.left,
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
    TraversalDirection.right,
  ),
};

/// On handhelds the D-pad always moves focus, also out of a text field
/// (there is no keyboard to move its cursor with). The app puts these below
/// the text-editing shortcuts so they win; sliders and radio groups nearer
/// the focus keep their own.
const handheldArrows = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
    TraversalDirection.up,
    ignoreTextFields: false,
  ),
  SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
    TraversalDirection.down,
    ignoreTextFields: false,
  ),
  SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
    TraversalDirection.left,
    ignoreTextFields: false,
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
    TraversalDirection.right,
    ignoreTextFields: false,
  ),
};
