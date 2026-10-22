// SPDX-License-Identifier: GPL-3.0-or-later
// Spec: docs/specs/library.md (Import)
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'database.dart';
import 'import_rules.dart';

/// Outcome for one source file.
sealed class ImportOutcome {
  const ImportOutcome(this.source);
  final String source;
}

class Imported extends ImportOutcome {
  const Imported(super.source, this.gameId, this.title);
  final int gameId;
  final String title;
}

class Duplicate extends ImportOutcome {
  const Duplicate(super.source);
}

class Rejected extends ImportOutcome {
  const Rejected(super.source, this.reason);
  final String reason;
}

/// A ROM ready to store: bytes are already unzipped.
class PreparedRom {
  PreparedRom({
    required this.system,
    required this.title,
    required this.fileName,
    required this.extension,
    required this.bytes,
  }) : sha1 = sha1Hex(bytes),
       crc32 = getCrc32(bytes).toRadixString(16).padLeft(8, '0');

  final GameSystem system;
  final String title;
  final String fileName;
  final String extension;
  final Uint8List bytes;
  final String sha1;
  final String crc32;
}

String sha1Hex(List<int> bytes) => sha1.convert(bytes).toString();

/// Disc images can be hundreds of megabytes: they are streamed (hashed while
/// copied) instead of read into memory (psx.md).
const streamedExtensions = {'.chd', '.pbp', '.iso', '.cso', '.nds'};

/// Copies [src] to [tmp] while hashing it; returns (sha1, crc32, size).
Future<(String, String, int)> _copyHashing(File src, File tmp) async {
  final digest = _DigestSink();
  final hasher = sha1.startChunkedConversion(digest);
  var crc = 0, size = 0;
  final out = tmp.openWrite();
  try {
    await for (final chunk in src.openRead()) {
      hasher.add(chunk);
      crc = getCrc32(chunk, crc);
      size += chunk.length;
      out.add(chunk);
    }
    await out.flush();
  } finally {
    await out.close();
  }
  hasher.close();
  return (digest.value.toString(), crc.toRadixString(16).padLeft(8, '0'), size);
}

/// Hashes [src] without copying it; returns (sha1, crc32, size).
Future<(String, String, int)> _hashOnly(File src) async {
  final digest = _DigestSink();
  final hasher = sha1.startChunkedConversion(digest);
  var crc = 0, size = 0;
  await for (final chunk in src.openRead()) {
    hasher.add(chunk);
    crc = getCrc32(chunk, crc);
    size += chunk.length;
  }
  hasher.close();
  return (digest.value.toString(), crc.toRadixString(16).padLeft(8, '0'), size);
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Reads [file] and applies the import rules. Returns a [PreparedRom] or a
/// [Rejected] reason. Pure apart from reading the file, so it can run in an
/// isolate.
Future<Object> prepare(File file) async {
  final name = p.basename(file.path);
  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } on FileSystemException catch (e) {
    return Rejected(
      name,
      'Could not read the file (${e.osError?.message ?? e.message})',
    );
  }
  if (p.extension(name).toLowerCase() == '.zip') {
    // ZipDecoder accepts some garbage as an empty archive, so check the
    // local-file-header signature first.
    final isZip =
        bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    if (!isZip) return Rejected(name, 'The zip file is damaged');
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      return Rejected(name, 'The zip file is damaged');
    }
    final entries = {
      for (final f in archive.files)
        if (f.isFile) f.name: f,
    };
    switch (chooseZipEntry(entries.keys.toList())) {
      case ZipNoGame():
        return Rejected(name, 'The zip has no game file in it');
      case ZipAmbiguous(:final entries):
        return Rejected(
          name,
          'The zip has several games in it (${entries.length})',
        );
      case ZipPick(:final entryName, :final system):
        final data = entries[entryName]!.content;
        final inner = p.basename(entryName);
        return PreparedRom(
          system: system,
          title: cleanTitle(inner),
          fileName: name,
          extension: p.extension(inner).toLowerCase(),
          bytes: Uint8List.fromList(data),
        );
    }
  }
  final header = bytes.length >= 0x104 ? bytes.sublist(0, 0x104) : bytes;
  final system = detectSystem(name, header: header);
  if (system == null) return Rejected(name, 'Not a supported game file');
  if (!system.playable) {
    return Rejected(name, "${system.shortName} games aren't supported yet");
  }
  return PreparedRom(
    system: system,
    title: cleanTitle(name),
    fileName: name,
    extension: p.extension(name).toLowerCase(),
    bytes: bytes,
  );
}

/// Imports files into [db], copying ROMs to `<gamesDir>/<system>/<sha1><ext>`.
/// Each file is independent: a failure rejects that file and the batch goes on.
class Importer {
  Importer(this.db, this.gamesDir);

  final LibraryDatabase db;
  final Directory gamesDir;

  Stream<ImportOutcome> importAll(List<File> files) async* {
    for (final f in files) {
      yield await importOne(f);
    }
  }

  Future<ImportOutcome> importOne(File file) async {
    final name = p.basename(file.path);
    final ext = p.extension(name).toLowerCase();
    if (streamedExtensions.contains(ext)) return _importStreamed(file, ext);
    final prepared = await prepare(file);
    if (prepared is Rejected) return prepared;
    final rom = prepared as PreparedRom;
    final dest = File(
      p.join(gamesDir.path, rom.system.id, '${rom.sha1}${rom.extension}'),
    );
    try {
      await dest.parent.create(recursive: true);
      if (!await dest.exists()) await dest.writeAsBytes(rom.bytes, flush: true);
    } on FileSystemException {
      return Rejected(rom.fileName, 'Not enough space to store the game');
    }
    final id = await db.addGame(
      system: rom.system.id,
      title: rom.title,
      fileName: rom.fileName,
      path: dest.path,
      sha1: rom.sha1,
      size: rom.bytes.length,
      crc32: rom.crc32,
    );
    if (id == null) return Duplicate(rom.fileName);
    return Imported(rom.fileName, id, rom.title);
  }
}

/// Adds a game file where it lies, without a copy: the handheld's own
/// `Roms/<system>` folders (sd-card.md, Card library). Zips still go through
/// [Importer.importOne], since cores read the extracted ROM.
extension InPlaceImport on Importer {
  Future<ImportOutcome> importInPlace(File file) async {
    final name = p.basename(file.path);
    if (p.extension(name).toLowerCase() == '.zip') return importOne(file);
    List<int> header;
    try {
      header = await file
          .openRead(0, 0x104)
          .fold<List<int>>([], (a, b) => a..addAll(b));
    } on FileSystemException catch (e) {
      return Rejected(
        name,
        'Could not read the file (${e.osError?.message ?? e.message})',
      );
    }
    final system = detectSystem(name, header: header);
    if (system == null) return Rejected(name, 'Not a supported game file');
    if (!system.playable) {
      return Rejected(name, "${system.shortName} games aren't supported yet");
    }
    final String sha, crc;
    final int size;
    try {
      (sha, crc, size) = await _hashOnly(file);
    } on FileSystemException catch (e) {
      return Rejected(
        name,
        'Could not read the file (${e.osError?.message ?? e.message})',
      );
    }
    final id = await db.addGame(
      system: system.id,
      title: cleanTitle(name),
      fileName: name,
      path: file.path,
      sha1: sha,
      size: size,
      crc32: crc,
    );
    if (id == null) return Duplicate(name);
    return Imported(name, id, cleanTitle(name));
  }
}

extension on Importer {
  Future<ImportOutcome> _importStreamed(File file, String ext) async {
    final name = p.basename(file.path);
    final system = detectSystem(name);
    if (system == null || !system.playable) {
      return Rejected(name, 'Not a supported game file');
    }
    final dir = Directory(p.join(gamesDir.path, system.id));
    final tmp = File(
      p.join(dir.path, '.import-${DateTime.now().microsecondsSinceEpoch}$ext'),
    );
    final String sha, crc;
    final int size;
    try {
      await dir.create(recursive: true);
      (sha, crc, size) = await _copyHashing(file, tmp);
    } on FileSystemException catch (e) {
      if (await tmp.exists()) await tmp.delete();
      final reading = e.path == file.path;
      return Rejected(
        name,
        reading
            ? 'Could not read the file (${e.osError?.message ?? e.message})'
            : 'Not enough space to store the game',
      );
    }
    final dest = File(p.join(dir.path, '$sha$ext'));
    if (await dest.exists()) {
      await tmp.delete();
    } else {
      await tmp.rename(dest.path);
    }
    final id = await db.addGame(
      system: system.id,
      title: cleanTitle(name),
      fileName: name,
      path: dest.path,
      sha1: sha,
      size: size,
      crc32: crc,
    );
    if (id == null) return Duplicate(name);
    return Imported(name, id, cleanTitle(name));
  }
}

/// Removes a deleted game's files: the ROM copy and, under [dataDir], its
/// battery save and every save state (game-session.md, save-states.md).
Future<void> deleteGameFiles(Game game, {String? dataDir}) async {
  final rom = File(game.path);
  if (await rom.exists()) await rom.delete();
  if (dataDir == null) return;
  final srm = File(p.join(dataDir, 'saves', '${game.sha1}.srm'));
  if (await srm.exists()) await srm.delete();
  final states = Directory(p.join(dataDir, 'states', game.sha1));
  if (await states.exists()) await states.delete(recursive: true);
}
