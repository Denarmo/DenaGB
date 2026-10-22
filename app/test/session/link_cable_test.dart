import 'package:dena_emu/src/session/link_cable.dart';
import 'package:dena_emu/src/session/session_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class FakeLink implements LinkCable {
  LinkState current = LinkState.off;
  bool isHost = true;
  bool scanning = false;
  String lastError = '';
  List<LinkHost> found = [];
  final calls = <String>[];

  @override
  bool host(String name) {
    calls.add('host $name');
    current = LinkState.waiting;
    isHost = true;
    return true;
  }

  @override
  bool join(String address, {int port = 0}) {
    calls.add('join $address:$port');
    current = LinkState.waiting;
    isHost = false;
    return true;
  }

  @override
  void stop() {
    calls.add('stop');
    current = LinkState.off;
  }

  @override
  LinkState get state => current;
  @override
  bool get hosting => isHost;
  @override
  String get error => lastError;
  @override
  String get peer => '192.168.1.7';
  @override
  String get localAddress => '192.168.1.5';
  @override
  bool startScan() => scanning = true;
  @override
  void stopScan() => scanning = false;
  @override
  List<LinkHost> get hosts => found;
}

Widget sheet(LinkCable link) => MaterialApp(
  home: Scaffold(
    body: LinkCableSheet(
      link: link,
      gameTitle: 'Pocket Monsters',
      poll: const Duration(milliseconds: 50),
    ),
  ),
);

void main() {
  test('scan results parse into hosts; junk lines are dropped', () {
    expect(
      parseHosts('Game A\t192.168.1.2\t47320\nbad line\nB\t10.0.0.3\tx\n'),
      [(name: 'Game A', address: '192.168.1.2', port: 47320)],
    );
    expect(parseHosts(''), isEmpty);
  });

  testWidgets('hosting shows this device and can be cancelled', (tester) async {
    final link = FakeLink();
    await tester.pumpWidget(sheet(link));
    expect(link.scanning, isTrue);
    expect(find.text('Not connected'), findsOneWidget);
    await tester.tap(find.text('Host'));
    await tester.pump();
    expect(link.calls, ['host Pocket Monsters']);
    expect(find.text('Waiting for another device'), findsOneWidget);
    expect(find.text('This device: 192.168.1.5'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(link.calls.last, 'stop');
    expect(find.text('Host'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(link.scanning, isFalse);
  });

  testWidgets('a found host joins on tap; typed addresses join too', (
    tester,
  ) async {
    final link = FakeLink()
      ..found = [
        (name: 'Pocket Monsters', address: '192.168.1.9', port: 47320),
      ];
    await tester.pumpWidget(sheet(link));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('192.168.1.9'));
    await tester.pump();
    expect(link.calls, ['join 192.168.1.9:47320']);
    expect(find.text('Connecting…'), findsOneWidget);

    link.current = LinkState.connected;
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Connected to 192.168.1.7'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);

    link.current = LinkState.off;
    await tester.pump(const Duration(milliseconds: 60));
    await tester.enterText(find.byType(TextField), ' 10.0.0.4 ');
    await tester.tap(find.text('Join'));
    await tester.pump();
    expect(link.calls.last, 'join 10.0.0.4:0');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a dropped link shows why', (tester) async {
    final link = FakeLink()
      ..current = LinkState.failed
      ..lastError = 'the other device disconnected';
    await tester.pumpWidget(sheet(link));
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('the other device disconnected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the pause sheet offers the link only when given one', (
    tester,
  ) async {
    Widget pause(LinkCable? link) => MaterialApp(
      home: Scaffold(
        body: PauseSheet(title: 'T', speed: 1, onSpeed: (_) {}, link: link),
      ),
    );
    await tester.pumpWidget(pause(null));
    expect(find.text('Link cable'), findsNothing);
    await tester.pumpWidget(pause(FakeLink()));
    expect(find.text('Link cable'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });
}
