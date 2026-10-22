// SPDX-License-Identifier: GPL-3.0-or-later
// Settings > Files > USB storage on the single-card handheld system: asks
// dena-session for USB storage mode and closes the launcher.
// Spec: docs/specs/handheld-ui.md (USB storage), single-card.md
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'handheld.dart';
import '../ui/dena_icons.dart';

/// The launcher's side of USB storage mode: leave the request file and exit;
/// dena-session serves the games partition and starts the launcher again.
class UsbStorage {
  UsbStorage({
    required this.requestFile,
    this.beforeExit,
    void Function(int code)? exitApp,
  }) : _exit = exitApp ?? exit;

  /// `/run/dena/usb-storage`, which dena-session looks for after the launcher.
  final File requestFile;

  /// Closes what must be flushed before the process ends (the library db).
  final Future<void> Function()? beforeExit;

  final void Function(int code) _exit;

  /// The helper dena-session runs; only the single-card system has it. The
  /// stock-firmware boot hook has no session loop to come back to.
  static const helper = '/usr/lib/dena/system/dena-usb-storage';

  /// Where the kernel lists USB device controllers; none means the port
  /// can't act as a drive.
  static const udcs = '/sys/class/udc';

  /// Null unless the app is the launcher of the single-card system on a
  /// handheld whose USB port can act as a drive.
  static UsbStorage? detect({
    required bool handheld,
    Future<void> Function()? beforeExit,
    String helperPath = helper,
    String runDir = '/run/dena',
    String udcDir = udcs,
  }) {
    if (!handheld || !File(helperPath).existsSync()) return null;
    final udc = Directory(udcDir);
    try {
      if (!udc.existsSync() || udc.listSync().isEmpty) return null;
    } on FileSystemException {
      return null;
    }
    return UsbStorage(
      requestFile: File('$runDir/usb-storage'),
      beforeExit: beforeExit,
    );
  }

  /// Writes the request and exits; throws if the request can't be written
  /// (the launcher then stays up).
  Future<void> enter() async {
    await requestFile.parent.create(recursive: true);
    await requestFile.writeAsString('', flush: true);
    try {
      await beforeExit?.call();
    } on Object catch (e) {
      debugPrint('USB storage: closing before exit failed: $e');
    }
    _exit(0);
  }
}

/// The Settings tile that opens [UsbStoragePage].
class UsbStorageTile extends StatelessWidget {
  const UsbStorageTile({super.key, required this.usb});

  final UsbStorage usb;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(DenaIcons.usb),
    title: const Text('USB storage'),
    subtitle: const Text('Copy games from a computer over USB-C'),
    trailing: const Icon(DenaIcons.chevronRight),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => UsbStoragePage(usb: usb))),
  );
}

/// Confirms USB storage mode: what happens and how to come back.
class UsbStoragePage extends StatefulWidget {
  const UsbStoragePage({super.key, required this.usb});

  final UsbStorage usb;

  @override
  State<UsbStoragePage> createState() => _UsbStoragePageState();
}

class _UsbStoragePageState extends State<UsbStoragePage> {
  bool starting = false;
  String? error;

  Future<void> _start() async {
    setState(() {
      starting = true;
      error = null;
    });
    try {
      await widget.usb.enter();
    } on Object catch (e) {
      debugPrint('USB storage: $e');
      if (mounted) {
        setState(() {
          starting = false;
          error = 'Could not start USB storage. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget step(IconData icon, String line) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(line, style: text.bodyMedium)),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('USB storage')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            Card.filled(
              color: scheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    step(
                      DenaIcons.cable,
                      'Connect the handheld to a computer with a USB-C cable.',
                    ),
                    step(
                      DenaIcons.sdCard,
                      'Dena.emu closes and the games card shows up on the '
                      'computer as a drive. Copy games into Roms.',
                    ),
                    step(
                      DenaIcons.eject,
                      'To come back, eject the drive on the computer, unplug '
                      'the cable or press the power key. With no computer, '
                      'Dena.emu returns after 2 minutes.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (error case final e?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  e,
                  style: text.bodyMedium?.copyWith(color: scheme.error),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: starting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  autofocus: true,
                  onPressed: starting ? null : _start,
                  icon: const Icon(DenaIcons.usb),
                  label: Text(starting ? 'Starting…' : 'Start USB storage'),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: Handheld.of(context)
          ? const HintBar(
              hints: [
                ([HintButton.a], 'Select'),
                ([HintButton.b], 'Back'),
              ],
            )
          : null,
    );
  }
}
