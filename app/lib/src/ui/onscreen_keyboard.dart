// SPDX-License-Identifier: GPL-3.0-or-later
// Text entry with the D-pad on handhelds, which have no keyboard.
// Spec: docs/specs/handheld-ui.md (On-screen keyboard)
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../shell/handheld.dart';

/// Opens a full-screen keyboard and returns the text, or null when the user
/// goes back. [accept] decides when Done is allowed; [hint] says why not.
Future<String?> showOnScreenKeyboard(
  BuildContext context, {
  required String title,
  String initial = '',
  bool obscure = false,
  bool Function(String text)? accept,
  String? hint,
}) => Navigator.of(context).push<String>(
  MaterialPageRoute<String>(
    builder: (_) => OnScreenKeyboard(
      title: title,
      initial: initial,
      obscure: obscure,
      accept: accept,
      hint: hint,
    ),
  ),
);

enum _Layer { lower, upper, symbols }

const _letters = ['1234567890', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
const _symbols = ['1234567890', '!@#\$%^&*()', '-_=+[]{};:', '\'",.<>/?\\|`~'];

class OnScreenKeyboard extends StatefulWidget {
  const OnScreenKeyboard({
    super.key,
    required this.title,
    this.initial = '',
    this.obscure = false,
    this.accept,
    this.hint,
  });

  final String title;
  final String initial;
  final bool obscure;
  final bool Function(String text)? accept;
  final String? hint;

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  late String text = widget.initial;
  late bool hidden = widget.obscure;
  _Layer layer = _Layer.lower;

  bool get _ok => widget.accept?.call(text) ?? text.isNotEmpty;

  void _type(String c) => setState(() {
    text += c;
    // Shift is for one letter, like a phone keyboard.
    if (layer == _Layer.upper) layer = _Layer.lower;
  });

  void _backspace() {
    if (text.isEmpty) return;
    setState(
      () => text = String.fromCharCodes(text.runes.toList()..removeLast()),
    );
  }

  void _shift() => setState(
    () => layer = layer == _Layer.lower ? _Layer.upper : _Layer.lower,
  );

  void _symbolsToggle() => setState(
    () => layer = layer == _Layer.symbols ? _Layer.lower : _Layer.symbols,
  );

  void _done() {
    if (_ok) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rows = layer == _Layer.symbols ? _symbols : _letters;
    final shown = hidden ? '•' * text.runes.length : text;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.gameButtonX): _backspace,
        const SingleActivator(LogicalKeyboardKey.gameButtonY): () => _type(' '),
        const SingleActivator(LogicalKeyboardKey.gameButtonLeft1): _shift,
        const SingleActivator(LogicalKeyboardKey.gameButtonRight1):
            _symbolsToggle,
        const SingleActivator(LogicalKeyboardKey.gameButtonStart): _done,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (widget.obscure)
              IconButton(
                tooltip: hidden ? 'Show' : 'Hide',
                icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => hidden = !hidden),
              ),
          ],
        ),
        bottomNavigationBar: Handheld.of(context)
            ? const HintBar(
                hints: [
                  ([HintButton.x], 'Delete'),
                  ([HintButton.y], 'Space'),
                  ([HintButton.l1], 'Shift'),
                  ([HintButton.r1], 'Symbols'),
                  ([HintButton.start], 'Done'),
                ],
              )
            : null,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    shown.isEmpty ? ' ' : shown,
                    key: const ValueKey('osk-text'),
                    style: textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.hint case final hint? when !_ok)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      hint,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: FocusTraversalGroup(
                    child: Column(
                      children: [
                        for (final (r, row) in rows.indexed)
                          _row([
                            for (final (i, c) in row.split('').indexed)
                              _Key(
                                label: layer == _Layer.upper
                                    ? c.toUpperCase()
                                    : c,
                                autofocus: r == 1 && i == 0,
                                onPressed: () => _type(
                                  layer == _Layer.upper ? c.toUpperCase() : c,
                                ),
                              ),
                          ]),
                        _row([
                          _Key(
                            label: 'Shift',
                            icon: Icons.keyboard_capslock,
                            selected: layer == _Layer.upper,
                            flex: 2,
                            onPressed: _shift,
                          ),
                          _Key(
                            label: layer == _Layer.symbols ? 'abc' : '?123',
                            flex: 2,
                            onPressed: _symbolsToggle,
                          ),
                          _Key(
                            label: 'Space',
                            icon: Icons.space_bar,
                            flex: 3,
                            onPressed: () => _type(' '),
                          ),
                          _Key(
                            label: 'Delete',
                            icon: Icons.backspace_outlined,
                            flex: 2,
                            onPressed: _backspace,
                          ),
                          _Key(
                            label: 'Done',
                            icon: Icons.check,
                            flex: 2,
                            primary: true,
                            onPressed: _ok ? _done : null,
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> keys) => Expanded(
    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: keys),
  );
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onPressed,
    this.icon,
    this.flex = 1,
    this.autofocus = false,
    this.selected = false,
    this.primary = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final int flex;
  final bool autofocus;
  final bool selected;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      backgroundColor: primary || selected
          ? scheme.primary
          : scheme.surfaceContainerHigh,
      foregroundColor: primary || selected
          ? scheme.onPrimary
          : scheme.onSurface,
    );
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: FilledButton(
          autofocus: autofocus,
          style: style,
          onPressed: onPressed,
          child: icon == null
              ? Text(label, style: Theme.of(context).textTheme.titleMedium)
              : Semantics(
                  label: label,
                  child: ExcludeSemantics(child: Icon(icon, size: 20)),
                ),
        ),
      ),
    );
  }
}

/// On handhelds, A on a focused text field opens the on-screen keyboard with
/// its text and writes the result back, so every field in the app (cheats,
/// sign-ins, servers, searches) can be typed in (handheld-ui.md). Wrap the
/// app's routes with this.
class HandheldTextEntry extends StatelessWidget {
  const HandheldTextEntry({super.key, required this.child});

  final Widget child;

  static KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.gameButtonA) {
      return KeyEventResult.ignored;
    }
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return KeyEventResult.ignored;
    final field = context.widget is EditableText
        ? context.widget as EditableText
        : context.findAncestorWidgetOfExactType<EditableText>();
    if (field == null || field.readOnly) return KeyEventResult.ignored;
    final decoration = context
        .findAncestorWidgetOfExactType<TextField>()
        ?.decoration;
    _type(
      context,
      field,
      decoration?.labelText ?? decoration?.hintText ?? 'Type',
    );
    return KeyEventResult.handled;
  }

  static Future<void> _type(
    BuildContext context,
    EditableText field,
    String title,
  ) async {
    final text = await showOnScreenKeyboard(
      context,
      title: title,
      initial: field.controller.text,
      obscure: field.obscureText,
      accept: (_) => true,
    );
    if (text == null) return;
    field.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    field.onChanged?.call(text);
    // Search and submit fields act on Done, as they would on Enter.
    if (const {
      TextInputAction.search,
      TextInputAction.done,
      TextInputAction.go,
      TextInputAction.send,
    }.contains(field.textInputAction)) {
      field.onSubmitted?.call(text);
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: child,
  );
}
