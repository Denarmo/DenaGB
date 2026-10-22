import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dena_emu/src/library/database.dart';
import 'package:dena_emu/src/library/importer.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late LibraryDatabase db;
  late Importer importer;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tmp = await Directory.systemTemp.createTemp('dena_import');
    db = LibraryDatabase(NativeDatabase.memory());
    importer = Importer(db, Directory(p.join(tmp.path, 'games')));
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  File write(String name, List<int> bytes) => File(p.join(tmp.path, 'in', name))
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  Uint8List zip(Map<String, List<int>> entries) {
    final a = Archive();
    entries.forEach((n, b) => a.addFile(ArchiveFile.bytes(n, b)));
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  test('imports a plain ROM into app storage with hashes', () async {
    final out = await importer.importOne(
      write('Hero Quest (USA).gb', [1, 2, 3]),
    );
    expect(out, isA<Imported>());
    final g = (await db.watchGames().first).single;
    expect(g.title, 'Hero Quest');
    expect(g.system, 'gb');
    expect(g.sha1, '7037807198c22a7d2b0807371d763779a84fdfcf');
    expect(g.crc32, '55bc801d');
    expect(File(g.path).readAsBytesSync(), [1, 2, 3]);
    expect(p.split(g.path), containsAllInOrder(['games', 'gb']));
  });

  test('second copy of the same content is a duplicate', () async {
    await importer.importOne(write('a.gba', [9, 9]));
    expect(await importer.importOne(write('b.gba', [9, 9])), isA<Duplicate>());
    expect(await db.watchGames().first, hasLength(1));
  });

  test('zip with one game is unpacked', () async {
    final out = await importer.importOne(
      write(
        'pack.zip',
        zip({
          'Some Game [!].gbc': [5, 6],
          'readme.txt': [0],
        }),
      ),
    );
    expect(out, isA<Imported>());
    final g = (await db.watchGames().first).single;
    expect(g.system, 'gbc');
    expect(g.title, 'Some Game');
    expect(File(g.path).readAsBytesSync(), [5, 6]);
  });

  test('rejections carry a reason and do not stop the batch', () async {
    final results = await importer.importAll([
      write('notes.txt', [1]),
      write(
        'two.zip',
        zip({
          'a.gb': [1],
          'b.gb': [2],
        }),
      ),
      write(
        'none.zip',
        zip({
          'a.txt': [1],
        }),
      ),
      write('broken.zip', [1, 2, 3, 4]),
      write('rom.bin', List.filled(0x200, 0)),
      write('ok.gb', [7]),
    ]).toList();
    expect(results.map((r) => r.runtimeType.toString()), [
      'Rejected',
      'Rejected',
      'Rejected',
      'Rejected',
      'Rejected',
      'Imported',
    ]);
    expect((results[1] as Rejected).reason, contains('several'));
    expect((results[3] as Rejected).reason, contains('damaged'));
  });

  test('DS carts are streamed: same hashes, stored once', () async {
    final disc = List<int>.generate(3 * 1024 * 1024 + 7, (i) => i * 31 & 0xff);
    final r = await importer.importOne(write('Moon Cart (USA).nds', disc));
    expect(r, isA<Imported>());
    final g = (await db.watchGames().first).single;
    expect(g.system, 'nds');
    expect(g.title, 'Moon Cart');
    expect(g.sha1, sha1Hex(disc));
    expect(g.size, disc.length);
    expect(File(g.path).readAsBytesSync(), disc);
    expect(p.basename(g.path), '${g.sha1}.nds');
    expect(await importer.importOne(write('copy.nds', disc)), isA<Duplicate>());
    final leftovers = Directory(p.dirname(g.path))
        .listSync()
        .where((f) => p.basename(f.path).startsWith('.import-'));
    expect(leftovers, isEmpty);
  });

  test('systems outside the GB family and DS are not imported', () async {
    final result = await importer.importOne(write('hero.nes', [1, 2]));
    expect(result, isA<Rejected>());
    expect(await db.watchGames().first, isEmpty);
  });

  test('deleting a game removes its ROM, battery save and states', () async {
    final dir = Directory.systemTemp.createTempSync('dena_delete');
    addTearDown(() => dir.deleteSync(recursive: true));
    final rom = File(p.join(dir.path, 'games', 'g.gba'))
      ..createSync(recursive: true);
    final srm = File(p.join(dir.path, 'saves', 'abc.srm'))
      ..createSync(recursive: true);
    final slot = File(p.join(dir.path, 'states', 'abc', 'slot1.state'))
      ..createSync(recursive: true);
    final other = File(p.join(dir.path, 'states', 'def', 'auto.state'))
      ..createSync(recursive: true);
    final game = Game(
      id: 1,
      system: 'gba',
      title: 'G',
      searchTitle: 'g',
      fileName: 'g.gba',
      path: rom.path,
      sha1: 'abc',
      size: 0,
      crc32: '0',
      addedAt: DateTime(2026),
      playSeconds: 0,
      favorite: false,
    );
    await deleteGameFiles(game, dataDir: dir.path);
    expect(rom.existsSync(), isFalse);
    expect(srm.existsSync(), isFalse);
    expect(slot.parent.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
  });
}
