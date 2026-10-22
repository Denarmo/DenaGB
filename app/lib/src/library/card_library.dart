// SPDX-License-Identifier: GPL-3.0-or-later
// The handheld's library is the card's Roms/<system> folders: games copied
// there from a PC show up without an import step. Spec: docs/specs/sd-card.md
import 'dart:io';

import 'package:path/path.dart' as p;

import 'database.dart';
import 'importer.dart';

/// `$DENA_CARD/Roms`, or null when not running from a card.
Directory? cardRomsDir([Map<String, String>? env]) {
  final card = (env ?? Platform.environment)['DENA_CARD'];
  if (card == null || card.isEmpty) return null;
  return Directory(p.join(card, 'Roms'));
}

/// What a scan did.
class CardScan {
  int added = 0;
  int skipped = 0;
  final rejected = <String>[];
}

/// Adds every game file under [roms] that the library doesn't have yet, in
/// place (no copy). Files already in the library by path are not read again,
/// so later scans are quick. Hidden files (`._x` from macOS, `.x`) and
/// unsupported files are skipped.
Future<CardScan> scanCardRoms(
  Directory roms,
  LibraryDatabase db,
  Importer importer,
) async {
  final scan = CardScan();
  if (!await roms.exists()) return scan;
  final known = {for (final g in await db.allGames()) g.path};
  final files = <File>[];
  try {
    await for (final e in roms.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.split(p.relative(e.path, from: roms.path));
      if (rel.any((part) => part.startsWith('.'))) continue;
      if (known.contains(e.path)) continue;
      files.add(e);
    }
  } on FileSystemException {
    // A pulled card: keep what was found.
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    switch (await importer.importInPlace(f)) {
      case Imported():
        scan.added++;
      case Duplicate():
        scan.skipped++;
      case Rejected(:final source):
        scan.rejected.add(source);
    }
  }
  return scan;
}
