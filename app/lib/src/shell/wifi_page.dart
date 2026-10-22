// SPDX-License-Identifier: GPL-3.0-or-later
// Settings > Wi-Fi on the handheld. Spec: docs/specs/handheld-ui.md (Wi-Fi)
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../library/games_tab.dart' show SectionLabel;
import '../ui/onscreen_keyboard.dart';
import 'wifi.dart';

/// The Settings tile that opens [WifiPage].
class WifiTile extends StatelessWidget {
  const WifiTile({super.key, required this.wifi});

  final WifiControl wifi;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.wifi),
    title: const Text('Wi-Fi'),
    subtitle: const Text('Join a network, saved networks'),
    onTap: () => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => WifiPage(wifi: wifi))),
  );
}

/// The networks around, the saved ones and the connection, refreshed every
/// few seconds while open.
class WifiPage extends StatefulWidget {
  const WifiPage({
    super.key,
    required this.wifi,
    this.refreshEvery = const Duration(seconds: 3),
  });

  final WifiControl wifi;
  final Duration refreshEvery;

  @override
  State<WifiPage> createState() => _WifiPageState();
}

class _WifiPageState extends State<WifiPage> {
  WifiStatus? status;
  List<WifiNetwork> networks = const [];
  List<SavedNetwork> saved = const [];
  bool loaded = false;
  bool running = true;
  String? busy;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scan();
    _timer = Timer.periodic(widget.refreshEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    try {
      await widget.wifi.scan();
    } on Object catch (e) {
      debugPrint('Wi-Fi scan: $e');
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await widget.wifi.status();
      final n = await widget.wifi.networks();
      final k = await widget.wifi.saved();
      if (!mounted) return;
      setState(() {
        status = s;
        networks = n;
        saved = k;
        loaded = true;
        running = true;
      });
    } on Object catch (e) {
      debugPrint('Wi-Fi: $e');
      if (mounted) {
        setState(() {
          loaded = true;
          running = false;
        });
      }
    }
  }

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _join(String ssid, {String? password}) async {
    setState(() => busy = ssid);
    try {
      await widget.wifi.connect(ssid, password: password);
      _say('Connecting to $ssid…');
    } on Object catch (e) {
      debugPrint('Wi-Fi connect: $e');
      _say("Couldn't join $ssid");
    }
    if (mounted) setState(() => busy = null);
    await _refresh();
  }

  Future<void> _tapNetwork(WifiNetwork n) async {
    if (status?.connected == true && status?.ssid == n.ssid) {
      return _say('Already connected to ${n.ssid}');
    }
    final known = saved.any((s) => s.ssid == n.ssid);
    if (known || !n.secured) return _join(n.ssid);
    final password = await _askPassword(n.ssid);
    if (password != null) await _join(n.ssid, password: password);
  }

  Future<String?> _askPassword(String ssid) => showOnScreenKeyboard(
    context,
    title: 'Password for $ssid',
    obscure: true,
    accept: validPassword,
    hint: '8 to 63 characters',
  );

  Future<void> _tapSaved(SavedNetwork n) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(n.ssid),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('forget'),
            child: const Text('Forget'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('password'),
            child: const Text('New password'),
          ),
          FilledButton.tonal(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop('connect'),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'connect':
        await _join(n.ssid);
      case 'password':
        final password = await _askPassword(n.ssid);
        if (password != null) await _join(n.ssid, password: password);
      case 'forget':
        try {
          await widget.wifi.forget(n);
          _say('Forgot ${n.ssid}');
        } on Object catch (e) {
          debugPrint('Wi-Fi forget: $e');
          _say("Couldn't forget ${n.ssid}");
        }
        await _refresh();
    }
  }

  static IconData _barsIcon(int bars) => switch (bars) {
    4 => Icons.signal_wifi_4_bar,
    3 => Icons.network_wifi_3_bar,
    2 => Icons.network_wifi_2_bar,
    1 => Icons.network_wifi_1_bar,
    _ => Icons.signal_wifi_0_bar,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget group(List<Widget> children) => Card.filled(
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
    final current = status?.connected == true ? status?.ssid : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            group([
              ListTile(
                leading: Icon(current != null ? Icons.wifi : Icons.wifi_off),
                title: Text(
                  !loaded
                      ? 'Checking…'
                      : running
                      ? status!.summary
                      : "Wi-Fi isn't running",
                ),
                subtitle: running
                    ? (status?.ip == null ? null : Text(status!.ip!))
                    : const Text('Restart the device to try again'),
              ),
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.refresh),
                title: const Text('Look for networks'),
                onTap: _scan,
              ),
            ]),
            if (running && loaded) ...[
              const SectionLabel('Networks'),
              if (networks.isEmpty)
                group([const ListTile(title: Text('No networks found yet'))])
              else
                group([
                  for (final n in networks)
                    ListTile(
                      leading: Icon(_barsIcon(n.bars)),
                      title: Text(n.ssid),
                      subtitle: Text(
                        n.ssid == current
                            ? 'Connected'
                            : busy == n.ssid
                            ? 'Connecting…'
                            : saved.any((s) => s.ssid == n.ssid)
                            ? 'Saved'
                            : n.secured
                            ? 'Password needed'
                            : 'Open',
                      ),
                      trailing: n.secured
                          ? const Icon(Icons.lock_outline, size: 18)
                          : null,
                      onTap: busy == null ? () => _tapNetwork(n) : null,
                    ),
                ]),
              if (saved.isNotEmpty) ...[
                const SectionLabel('Saved networks'),
                group([
                  for (final n in saved)
                    ListTile(
                      leading: const Icon(Icons.bookmark_outline),
                      title: Text(n.ssid),
                      subtitle: n.current ? const Text('In use') : null,
                      onTap: busy == null ? () => _tapSaved(n) : null,
                    ),
                ]),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
