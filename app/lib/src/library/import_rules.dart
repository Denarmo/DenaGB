// SPDX-License-Identifier: GPL-3.0-or-later
// Spec: docs/specs/library.md (Import)

/// Pure import rules from the game-library spec (docs/specs/library.md,
/// "Import" items 1, 2 and 4).
///
/// Everything here is a pure function over file names (and, for `.bin`, a byte
/// header) so it has no Flutter or I/O dependencies and can run inside the
/// background import isolate and be unit tested in isolation.
library;

/// A console system the library can import.
enum GameSystem {
  nes,
  snes,
  gb,
  gbc,
  gba,
  nds,
  psx,
  n64,
  psp,
  pico8,
  genesis;

  /// Stable identifier persisted in the database; equal to the enum name.
  String get id => name;

  /// Short label shown on the box-art placeholder and filter chips.
  String get shortName => switch (this) {
    GameSystem.nes => 'NES',
    GameSystem.snes => 'SNES',
    GameSystem.gb => 'GB',
    GameSystem.gbc => 'GBC',
    GameSystem.gba => 'GBA',
    GameSystem.nds => 'DS',
    GameSystem.psx => 'PS1',
    GameSystem.n64 => 'N64',
    GameSystem.psp => 'PSP',
    GameSystem.pico8 => 'PICO-8',
    GameSystem.genesis => 'Genesis',
  };

  /// Whether a core ships for this system. Genesis is recognised but has no
  /// core yet (deferred by the user, docs/specs/m2-plan.md), so it can't be
  /// imported and has no skin.
  bool get playable => supportedSystems.contains(this);
}

/// Dena.emu GB plays only the Game Boy family and the DS (docs/dev/gb-fork.md).
/// Other systems stay in the enum so the database and upstream merges keep
/// their ids, but they are never imported.
const supportedSystems = {
  GameSystem.gb,
  GameSystem.gbc,
  GameSystem.gba,
  GameSystem.nds,
};

/// The four ASCII bytes `SEGA` expected at offset `0x100` in a Genesis ROM.
const List<int> _genesisMagic = [0x53, 0x45, 0x47, 0x41];

/// The offset of the Genesis signature inside a `.bin` file.
const int _genesisMagicOffset = 0x100;

/// The exclusive end offset of the Genesis signature.
const int _genesisMagicEnd = 0x104;

/// Detects the [GameSystem] for [fileName] from its (lower-cased) extension.
///
/// `.nes` → [GameSystem.nes]; `.sfc`/`.smc` → [GameSystem.snes]; `.gb` →
/// [GameSystem.gb]; `.gbc` → [GameSystem.gbc]; `.gba` → [GameSystem.gba];
/// `.nds` → [GameSystem.nds]; `.chd`/`.pbp` → [GameSystem.psx];
/// `.z64`/`.n64`/`.v64` → [GameSystem.n64]; `.iso`/`.cso` → [GameSystem.psp];
/// `.p8`/`.p8.png` → [GameSystem.pico8];
/// `.md`/`.gen`/`.smd` → [GameSystem.genesis].
///
/// `.bin` is ambiguous, so it maps to [GameSystem.genesis] only when [header]
/// is supplied, is at least `0x104` bytes long and carries the ASCII `SEGA`
/// signature at offset `0x100`; otherwise it is rejected as unknown.
///
/// Any unrecognised extension (or none) returns `null`.
GameSystem? detectSystem(String fileName, {List<int>? header}) {
  final system = _detectAnySystem(fileName, header: header);
  return supportedSystems.contains(system) ? system : null;
}

GameSystem? _detectAnySystem(String fileName, {List<int>? header}) {
  // PICO-8 PNG carts carry a double extension (pico8.md).
  if (_baseName(fileName).toLowerCase().endsWith('.p8.png')) {
    return GameSystem.pico8;
  }
  switch (_extension(fileName)) {
    case 'p8':
      return GameSystem.pico8;
    case 'nes':
      return GameSystem.nes;
    case 'sfc':
    case 'smc':
      return GameSystem.snes;
    case 'gb':
      return GameSystem.gb;
    case 'gbc':
      return GameSystem.gbc;
    case 'gba':
      return GameSystem.gba;
    case 'nds':
      return GameSystem.nds;
    case 'z64':
    case 'n64':
    case 'v64':
      return GameSystem.n64;
    case 'iso':
    case 'cso':
      return GameSystem.psp;
    case 'chd':
    case 'pbp':
      return GameSystem.psx;
    case 'md':
    case 'gen':
    case 'smd':
      return GameSystem.genesis;
    case 'bin':
      return _hasGenesisHeader(header) ? GameSystem.genesis : null;
    default:
      return null;
  }
}

/// Cleans a title out of [fileName] (docs/specs/library.md, "Import" item 4).
///
/// Strips directory parts and the last extension, removes every `(...)` and
/// `[...]` tag, collapses runs of whitespace and underscores to single spaces
/// and trims the result. If nothing is left, returns the bare name without its
/// extension (so `(Proto).nes` becomes `(Proto)`).
String cleanTitle(String fileName) {
  var base = _baseName(fileName);
  final dot = base.lastIndexOf('.');
  if (dot > 0) {
    base = base.substring(0, dot);
  }
  final cleaned = base
      .replaceAll(RegExp(r'\([^)]*\)'), '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .replaceAll(RegExp(r'[\s_]+'), ' ')
      .trim();
  return cleaned.isEmpty ? base : cleaned;
}

/// The outcome of picking a ROM out of a `.zip` archive's entry list.
sealed class ZipChoice {
  const ZipChoice();
}

/// Exactly one entry was recognised.
class ZipPick extends ZipChoice {
  const ZipPick(this.entryName, this.system);

  /// The archive-relative path of the chosen entry.
  final String entryName;

  /// The system detected for [entryName].
  final GameSystem system;
}

/// No entry in the archive was a recognised game.
class ZipNoGame extends ZipChoice {
  const ZipNoGame();
}

/// More than one entry was recognised, so the archive is ambiguous.
class ZipAmbiguous extends ZipChoice {
  const ZipAmbiguous(this.entries);

  /// The recognised entry names, in archive order.
  final List<String> entries;
}

/// Picks the single game entry from a `.zip`'s [entryNames] (spec "Import"
/// item 1).
///
/// Directory entries (ending `/`) and macOS `__MACOSX` metadata entries are
/// ignored, as are entries whose extension [detectSystem] does not recognise
/// (notably header-less `.bin` files). Exactly one surviving entry yields a
/// [ZipPick]; none yields [ZipNoGame]; several yield [ZipAmbiguous].
ZipChoice chooseZipEntry(List<String> entryNames) {
  final matches = <String>[];
  var system = GameSystem.nes;
  for (final name in entryNames) {
    if (_isIgnoredZipEntry(name)) continue;
    final detected = detectSystem(name);
    if (detected == null) continue;
    matches.add(name);
    system = detected;
  }
  if (matches.isEmpty) return const ZipNoGame();
  if (matches.length == 1) return ZipPick(matches.single, system);
  return ZipAmbiguous(matches);
}

/// The file name part of [path], with `/` and `\` both treated as separators.
String _baseName(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final index = slash > backslash ? slash : backslash;
  return index < 0 ? path : path.substring(index + 1);
}

/// The lower-cased extension of [fileName], without the dot; `''` if none.
String _extension(String fileName) {
  final base = _baseName(fileName);
  final dot = base.lastIndexOf('.');
  return dot < 0 ? '' : base.substring(dot + 1).toLowerCase();
}

/// Whether [header] starts with the Genesis `SEGA` signature at `0x100`.
bool _hasGenesisHeader(List<int>? header) {
  if (header == null || header.length < _genesisMagicEnd) return false;
  for (var i = 0; i < _genesisMagic.length; i++) {
    if (header[_genesisMagicOffset + i] != _genesisMagic[i]) return false;
  }
  return true;
}

/// Whether a zip entry is a directory or macOS metadata and must be ignored.
bool _isIgnoredZipEntry(String entry) {
  if (entry.endsWith('/')) return true;
  return entry.split('/').contains('__MACOSX');
}
