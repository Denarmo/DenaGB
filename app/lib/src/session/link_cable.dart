// SPDX-License-Identifier: GPL-3.0-or-later
// Link cable over Wi-Fi for Game Boy, Game Boy Color and Game Boy Advance:
// the native transport (host/src/link.c) and the pause-menu sheet.
// Spec: docs/specs/link-cable.md
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:material_ui/material_ui.dart';

import '../shell/host_library.dart';
import '../ui/dena_icons.dart';

/// Systems whose core speaks the link cable.
const systemsWithLink = {'gb', 'gbc', 'gba'};

enum LinkState { off, waiting, connected, failed }

/// A host the scan heard.
typedef LinkHost = ({String name, String address, int port});

/// The native link (one per process). Tests use a fake.
abstract interface class LinkCable {
  bool host(String name);
  bool join(String address, {int port = 0});
  void stop();
  LinkState get state;

  /// True when this device hosts (the first player, GBA parent).
  bool get hosting;
  String get error;
  String get peer;
  String get localAddress;
  bool startScan();
  void stopScan();
  List<LinkHost> get hosts;
}

/// Parses `name\taddress\tport\n` lines from `dena_link_scan_results`.
List<LinkHost> parseHosts(String text) => [
  for (final line in text.split('\n'))
    if (line.split('\t') case [final name, final address, final port])
      if (int.tryParse(port) case final p?)
        (name: name, address: address, port: p),
];

/// Calls the `dena_link_*` functions in the native library over dart:ffi.
class FfiLinkCable implements LinkCable {
  FfiLinkCable._(DynamicLibrary lib)
    : _host = lib
          .lookupFunction<
            Int32 Function(Int32, Pointer<Utf8>),
            int Function(int, Pointer<Utf8>)
          >('dena_link_host'),
      _join = lib
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Int32),
            int Function(Pointer<Utf8>, int)
          >('dena_link_join'),
      _stop = lib.lookupFunction<Void Function(), void Function()>(
        'dena_link_stop',
      ),
      _state = lib.lookupFunction<Int32 Function(), int Function()>(
        'dena_link_state',
      ),
      _role = lib.lookupFunction<Int32 Function(), int Function()>(
        'dena_link_role',
      ),
      _error = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'dena_link_error',
          ),
      _peer = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'dena_link_peer',
          ),
      _scanStart = lib.lookupFunction<Int32 Function(), int Function()>(
        'dena_link_scan_start',
      ),
      _scanStop = lib.lookupFunction<Void Function(), void Function()>(
        'dena_link_scan_stop',
      ),
      _scanResults = lib
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Int32),
            int Function(Pointer<Utf8>, int)
          >('dena_link_scan_results'),
      _local = lib
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Int32),
            int Function(Pointer<Utf8>, int)
          >('dena_link_local_address');

  final int Function(int, Pointer<Utf8>) _host;
  final int Function(Pointer<Utf8>, int) _join;
  final void Function() _stop;
  final int Function() _state;
  final int Function() _role;
  final Pointer<Utf8> Function() _error;
  final Pointer<Utf8> Function() _peer;
  final int Function() _scanStart;
  final void Function() _scanStop;
  final int Function(Pointer<Utf8>, int) _scanResults;
  final int Function(Pointer<Utf8>, int) _local;

  static FfiLinkCable? _instance;

  /// Null where the native library is not available (desktop, tests).
  static FfiLinkCable? open() {
    if (_instance != null) return _instance;
    try {
      final DynamicLibrary lib;
      final host = openHostLibrary();
      if (host == null) return null;
      lib = host;
      return _instance = FfiLinkCable._(lib);
    } on ArgumentError {
      return null;
    }
  }

  @override
  bool host(String name) =>
      using((a) => _host(0, name.toNativeUtf8(allocator: a)) == 0);

  @override
  bool join(String address, {int port = 0}) =>
      using((a) => _join(address.toNativeUtf8(allocator: a), port) == 0);

  @override
  void stop() => _stop();

  @override
  LinkState get state => LinkState.values[_state().clamp(0, 3)];

  @override
  bool get hosting => _role() == 0;

  @override
  String get error => _error().toDartString();

  @override
  String get peer => _peer().toDartString();

  String _read(int Function(Pointer<Utf8>, int) fn, int size) => using((a) {
    final buf = a<Uint8>(size).cast<Utf8>();
    fn(buf, size);
    return buf.toDartString();
  });

  @override
  String get localAddress => _read(_local, 64);

  @override
  bool startScan() => _scanStart() == 0;

  @override
  void stopScan() => _scanStop();

  @override
  List<LinkHost> get hosts => parseHosts(_read(_scanResults, 2048));
}

/// One-line status for the pause sheet.
String linkSummary(LinkCable link) => switch (link.state) {
  LinkState.off => 'Not connected',
  LinkState.waiting =>
    link.hosting ? 'Waiting for another device' : 'Connecting…',
  LinkState.connected => 'Connected to ${link.peer}',
  LinkState.failed => 'Disconnected',
};

/// Host, find or join a link. Both devices must be on the same Wi-Fi.
class LinkCableSheet extends StatefulWidget {
  const LinkCableSheet({
    super.key,
    required this.link,
    required this.gameTitle,
    this.poll = const Duration(milliseconds: 500),
  });

  final LinkCable link;
  final String gameTitle;
  final Duration poll;

  @override
  State<LinkCableSheet> createState() => _LinkCableSheetState();
}

class _LinkCableSheetState extends State<LinkCableSheet> {
  Timer? _timer;
  List<LinkHost> _hosts = const [];
  final _address = TextEditingController();

  LinkCable get link => widget.link;

  @override
  void initState() {
    super.initState();
    if (link.state != LinkState.connected) link.startScan();
    _timer = Timer.periodic(widget.poll, (_) => _refresh());
    _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _hosts = link.state == LinkState.connected ? const [] : link.hosts;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    link.stopScan();
    _address.dispose();
    super.dispose();
  }

  void _join(String address, int port) {
    link.join(address, port: port);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final state = link.state;
    final section = text.labelLarge?.copyWith(color: scheme.onSurfaceVariant);
    final busy = state == LinkState.waiting || state == LinkState.connected;
    final local = link.localAddress;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Link cable', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Trade and battle with another device running Dena.emu on the '
              'same Wi-Fi. Open the game on both, host on one and join from '
              'the other.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                state == LinkState.connected
                    ? DenaIcons.link
                    : DenaIcons.linkOff,
                color: state == LinkState.connected ? scheme.primary : null,
              ),
              title: Text(linkSummary(link)),
              subtitle: switch (state) {
                LinkState.failed when link.error.isNotEmpty => Text(link.error),
                LinkState.waiting when link.hosting && local.isNotEmpty => Text(
                  'This device: $local',
                ),
                _ => null,
              },
            ),
            const SizedBox(height: 8),
            if (busy)
              FilledButton.tonalIcon(
                autofocus: true,
                icon: const Icon(DenaIcons.linkOff),
                label: Text(
                  state == LinkState.connected ? 'Disconnect' : 'Cancel',
                ),
                onPressed: () {
                  link.stop();
                  link.startScan();
                  _refresh();
                },
              )
            else ...[
              FilledButton.icon(
                autofocus: true,
                icon: const Icon(DenaIcons.broadcast),
                label: const Text('Host'),
                onPressed: () {
                  link.stopScan();
                  link.host(widget.gameTitle);
                  _refresh();
                },
              ),
              const SizedBox(height: 16),
              Text('Devices nearby', style: section),
              const SizedBox(height: 4),
              if (_hosts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Looking for a device that is hosting…',
                    style: text.bodyMedium,
                  ),
                ),
              for (final h in _hosts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(DenaIcons.cart),
                  title: Text(h.name),
                  subtitle: Text(h.address),
                  trailing: const Icon(DenaIcons.chevronRight),
                  onTap: () => _join(h.address, h.port),
                ),
              const SizedBox(height: 12),
              Text('Join by address', style: section),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _address,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: '192.168.1.20',
                        isDense: true,
                      ),
                      onSubmitted: (v) => _join(v.trim(), 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () => _join(_address.text.trim(), 0),
                    child: const Text('Join'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
