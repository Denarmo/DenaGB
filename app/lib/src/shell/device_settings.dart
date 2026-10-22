// SPDX-License-Identifier: GPL-3.0-or-later
// Handheld device settings kept on the SD card. Spec: docs/specs/handheld-ui.md
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'power_link.dart';
import '../ui/dena_icons.dart';

/// `Dena/user/settings.json` on the card (survives updates, sd-card.md), or
/// null when not running from a card.
File? deviceSettingsFile([Map<String, String>? env]) {
  final card = (env ?? Platform.environment)['DENA_CARD'];
  if (card == null || card.isEmpty) return null;
  return File(p.join(card, 'Dena', 'user', 'settings.json'));
}

/// The settings the device keeps; unknown keys in the file are kept as is.
class DeviceSettings {
  DeviceSettings(this.file, this._values);

  final File file;
  final Map<String, Object?> _values;

  static const defaultBrightness = 100;

  static Future<DeviceSettings> load(File file) async {
    try {
      final v = jsonDecode(await file.readAsString());
      if (v is Map<String, Object?>) return DeviceSettings(file, v);
    } on Object {
      // Missing or damaged: start from the defaults.
    }
    return DeviceSettings(file, {});
  }

  int get brightness {
    final v = _values['brightness'];
    return v is int ? v.clamp(1, 100) : defaultBrightness;
  }

  Future<void> setBrightness(int percent) {
    _values['brightness'] = percent.clamp(1, 100);
    return _save();
  }

  Future<void> _saving = Future.value();

  /// One write at a time, each to a temporary file first so a pulled card
  /// never leaves half a file behind.
  Future<void> _save() =>
      _saving = _saving.then((_) => _write()).catchError((Object _) {});

  Future<void> _write() async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_values), flush: true);
    await tmp.rename(file.path);
  }
}

/// Settings > Device on handhelds: screen brightness.
class DeviceSection extends StatefulWidget {
  const DeviceSection({
    super.key,
    required this.settings,
    required this.link,
    this.autofocus = false,
  });

  final DeviceSettings settings;
  final PowerLink link;
  final bool autofocus;

  @override
  State<DeviceSection> createState() => _DeviceSectionState();
}

class _DeviceSectionState extends State<DeviceSection> {
  late int brightness =
      (widget.settings.brightness / 5).round().clamp(1, 20) * 5;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(DenaIcons.brightness),
    title: const Text('Brightness'),
    // Directional mode: left / right change the slider, up / down leave it
    // (in the default mode they change it too and trap the D-pad).
    subtitle: MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(navigationMode: NavigationMode.directional),
      child: Slider(
        autofocus: widget.autofocus,
        value: brightness.toDouble(),
        min: 5,
        max: 100,
        divisions: 19,
        label: '$brightness%',
        semanticFormatterCallback: (v) => '${v.round()}%',
        onChanged: (v) {
          setState(() => brightness = v.round());
          widget.link.brightness(brightness);
          widget.settings.setBrightness(brightness);
        },
      ),
    ),
  );
}
