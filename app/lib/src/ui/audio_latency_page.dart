// SPDX-License-Identifier: GPL-3.0-or-later
// Settings > Audio latency: the buffer target the audio path aims for.
// Spec: docs/specs/performance.md
import 'package:material_ui/material_ui.dart';

import '../library/games_tab.dart' show SectionLabel;
import '../shell/handheld.dart' show arrowsMoveFocus;
import 'app_theme.dart';

/// The choice's label ("Normal", "Low", ...), for the Settings row and page.
String audioLatencyLabel(int ms) => switch (ms) {
  30 => 'Low',
  20 => 'Lowest, may crackle',
  _ => 'Normal',
};

class AudioLatencyPage extends StatelessWidget {
  const AudioLatencyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = ThemeScope.of(context).notifier!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Audio latency')),
      body: SafeArea(
        top: false,
        child: RadioGroup<int>(
          groupValue: settings.audioLatencyMs,
          onChanged: (ms) {
            if (ms != null) settings.audioLatencyMs = ms;
          },
          child: Shortcuts(
            shortcuts: arrowsMoveFocus,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                const SectionLabel('Buffer'),
                Card.filled(
                  color: scheme.surfaceContainer,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final ms in audioLatencyOptions)
                        RadioListTile<int>(
                          value: ms,
                          // The D-pad starts on the current choice.
                          autofocus: ms == settings.audioLatencyMs,
                          dense: true,
                          title: Text(audioLatencyLabel(ms)),
                          subtitle: Text('$ms ms'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
