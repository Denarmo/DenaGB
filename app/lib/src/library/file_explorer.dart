// SPDX-License-Identifier: GPL-3.0-or-later
// In-app file explorer for Add games / Add a folder. Spec:
// docs/specs/file-explorer.md
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../shell/app_dirs.dart';
import '../shell/handheld.dart';
import '../ui/dena_icons.dart';
import 'library_scope.dart';

/// A place the explorer starts from: the games card, a USB drive, shared
/// storage.
class ExplorerRoot {
  const ExplorerRoot(this.label, this.path, this.icon, {this.start});

  final String label;
  final String path;
  final IconData icon;

  /// The folder to open first inside [path] (the card's `Roms`), if any.
  final String? start;

  @override
  bool operator ==(Object other) =>
      other is ExplorerRoot && other.label == label && other.path == path;

  @override
  int get hashCode => Object.hash(label, path);
}

/// Mount points of removable or extra storage in a `/proc/mounts` text:
/// USB drives, a second card slot, NVMe. Leaves out the system, boot
/// partitions and [exclude] (the games card, listed on its own).
List<({String device, String dir})> removableMounts(
  String mounts, {
  String? exclude,
}) {
  final out = <({String device, String dir})>[];
  for (final line in const LineSplitter().convert(mounts)) {
    final f = line.split(' ');
    if (f.length < 2) continue;
    final dev = f[0];
    final dir = _unescape(f[1]);
    if (!(dev.startsWith('/dev/sd') ||
        dev.startsWith('/dev/mmcblk') ||
        dev.startsWith('/dev/nvme'))) {
      continue;
    }
    if (dir == '/' || dir.startsWith('/boot')) continue;
    if (exclude != null &&
        (dir == exclude ||
            p.isWithin(dir, exclude) ||
            p.isWithin(exclude, dir))) {
      continue;
    }
    if (!out.any((m) => m.dir == dir)) out.add((device: dev, dir: dir));
  }
  return out;
}

/// `/proc/mounts` writes spaces and tabs in paths as octal escapes.
String _unescape(String s) => s.replaceAllMapped(
  RegExp(r'\\([0-7]{3})'),
  (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)),
);

/// The roots on this device ([handheld] true on the Linux card, else the
/// Android fallback). [env], [mounts] and [storage] stand in for the real
/// environment, `/proc/mounts` and `/storage` in tests.
Future<List<ExplorerRoot>> explorerRoots({
  required bool handheld,
  Map<String, String>? env,
  String? mounts,
  Directory? storage,
}) async {
  final roots = <ExplorerRoot>[];
  if (handheld) {
    final card = (env ?? Platform.environment)['DENA_CARD'];
    if (card != null && card.isNotEmpty) {
      final roms = p.join(card, 'Roms');
      roots.add(
        ExplorerRoot(
          'Games card',
          card,
          DenaIcons.sdCard,
          start: await Directory(roms).exists() ? roms : null,
        ),
      );
    }
    String text;
    try {
      text = mounts ?? await File('/proc/mounts').readAsString();
    } on FileSystemException {
      text = '';
    }
    final extra = removableMounts(
      text,
      exclude: card == null || card.isEmpty ? null : card,
    );
    final usbCount = extra.where((m) => m.device.startsWith('/dev/sd')).length;
    var usbIndex = 0;
    for (final m in extra) {
      final usb = m.device.startsWith('/dev/sd');
      if (usb) usbIndex++;
      roots.add(
        ExplorerRoot(
          usb
              ? (usbCount == 1 ? 'USB drive' : 'USB drive $usbIndex')
              : p.basename(m.dir),
          m.dir,
          usb ? DenaIcons.usb : DenaIcons.sdCard,
        ),
      );
    }
    return roots;
  }
  final base = storage ?? Directory('/storage');
  final shared = p.join(base.path, 'emulated', '0');
  if (await Directory(shared).exists()) {
    roots.add(ExplorerRoot('Internal storage', shared, DenaIcons.folder));
  }
  try {
    await for (final e in base.list()) {
      final name = p.basename(e.path);
      if (e is! Directory || name == 'emulated' || name == 'self') continue;
      roots.add(ExplorerRoot(name, e.path, DenaIcons.sdCard));
    }
  } on FileSystemException {
    // No /storage listing without permission; shared storage is enough.
  }
  return roots;
}

/// Whether [name] ends with one of [extensions] (lower-cased, with dot).
bool matchesExtension(String name, List<String> extensions) {
  final lower = name.toLowerCase();
  return extensions.any(lower.endsWith);
}

/// One row of a folder listing.
class ExplorerEntry {
  const ExplorerEntry(this.path, {required this.isFolder});

  final String path;
  final bool isFolder;

  String get name => p.basename(path);
}

/// The folders and (matching, unless [allFiles]) files directly in [dir],
/// folders first, by name. Hidden entries are left out. Throws
/// [FileSystemException] when [dir] can't be read.
Future<List<ExplorerEntry>> listFolder(
  Directory dir,
  List<String> extensions, {
  bool allFiles = false,
}) async {
  final folders = <ExplorerEntry>[];
  final files = <ExplorerEntry>[];
  await for (final e in dir.list(followLinks: true)) {
    final name = p.basename(e.path);
    if (name.startsWith('.')) continue;
    if (e is Directory) {
      folders.add(ExplorerEntry(e.path, isFolder: true));
    } else if (e is File && (allFiles || matchesExtension(name, extensions))) {
      files.add(ExplorerEntry(e.path, isFolder: false));
    }
  }
  int byName(ExplorerEntry a, ExplorerEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return [...folders..sort(byName), ...files..sort(byName)];
}

/// Every file under [dir] whose name matches [extensions], down to
/// [maxDepth] folder levels and at most [limit] files. Unreadable folders
/// are skipped.
Future<List<String>> collectGames(
  Directory dir,
  List<String> extensions, {
  int maxDepth = 8,
  int limit = 5000,
}) async {
  final out = <String>[];
  Future<void> walk(Directory d, int depth) async {
    if (depth > maxDepth || out.length >= limit) return;
    final List<FileSystemEntity> children;
    try {
      children = await d.list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }
    children.sort((a, b) => a.path.compareTo(b.path));
    for (final e in children) {
      if (out.length >= limit) return;
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        await walk(e, depth + 1);
      } else if (e is File && matchesExtension(name, extensions)) {
        out.add(e.path);
      }
    }
  }

  await walk(dir, 0);
  return out;
}

/// Remembers the last folder the explorer had open, in `<data>/explorer.json`.
class ExplorerMemory {
  ExplorerMemory(this.file);

  final File file;

  /// The app's own memory file in the data folder.
  static Future<ExplorerMemory> load() async =>
      ExplorerMemory(File(p.join((await appDataDir()).path, 'explorer.json')));

  Future<String?> last() async {
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map && json['last'] is String
          ? json['last'] as String
          : null;
    } on Object {
      return null;
    }
  }

  Future<void> remember(String path) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'last': path}));
    } on FileSystemException catch (e) {
      debugPrint('Explorer: could not save last folder: $e');
    }
  }
}

/// Opens a picker and returns the paths to import (library.md, Import).
typedef GamePicker = Future<List<String>> Function(
  BuildContext context, {
  required bool folder,
  required List<String> extensions,
});

/// Add games / Add a folder. With [StorageAccess] granted (Android, asked
/// for here once per run) [explorer], the in-app file explorer; else the
/// system picker of [files] when it has one, and [explorer] when there is
/// none or it fails to start.
Future<List<String>> pickGamePaths(
  BuildContext context,
  GameFileSource files, {
  required bool folder,
  GamePicker explorer = pickWithExplorer,
}) async {
  if (files case final StorageAccess storage) {
    if (await _storageAccess(context, storage)) {
      if (!context.mounted) return const [];
      return explorer(context, folder: folder, extensions: importExtensions);
    }
  }
  if (!context.mounted) return const [];
  if (files.hasPicker) {
    try {
      return folder
          ? await files.pickFolder(importExtensions)
          : await files.pickFiles();
    } on PlatformException catch (e) {
      // No system picker (e.g. no DocumentsUI): use the in-app explorer.
      debugPrint('System picker unavailable: $e');
    }
  }
  if (!context.mounted) return const [];
  return explorer(context, folder: folder, extensions: importExtensions);
}

/// Sources whose user chose the system picker over storage access this run.
final _pickerChosen = Expando<bool>();

/// Whether [storage] can be browsed: granted already, or granted now after
/// the FILE ACCESS dialog. Asks once per run; a refusal keeps the picker.
Future<bool> _storageAccess(BuildContext context, StorageAccess storage) async {
  try {
    if (await storage.hasStorageAccess()) return true;
    if (_pickerChosen[storage] ?? false) return false;
    if (!context.mounted) return false;
    final allow = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('File access'),
        content: const Text(
          'To browse your game folders, Dena.emu GB needs All files access. '
          'Turn on "Allow access" on the next screen, then go back. '
          'Games you add are copied into the library; nothing else is read.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('System picker'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (allow ?? false) {
      if (await storage.requestStorageAccess()) return true;
    }
    _pickerChosen[storage] = true;
    return false;
  } on PlatformException catch (e) {
    debugPrint('Storage access unavailable: $e');
    return false;
  }
}

/// Opens the explorer and returns the paths to import: the checked files
/// ([folder] false) or every matching file under the chosen folder. Empty
/// when the user backs out.
Future<List<String>> pickWithExplorer(
  BuildContext context, {
  required bool folder,
  required List<String> extensions,
  List<ExplorerRoot>? roots,
  ExplorerMemory? memory,
}) async {
  final handheld = Handheld.of(context);
  final navigator = Navigator.of(context);
  final found =
      roots ?? await explorerRoots(handheld: handheld || !Platform.isAndroid);
  var mem = memory;
  if (mem == null) {
    try {
      mem = await ExplorerMemory.load();
    } on Object catch (e) {
      debugPrint('Explorer: no data folder to remember the last folder: $e');
    }
  }
  final result = await navigator.push<List<String>>(
    MaterialPageRoute(
      builder: (_) => FileExplorerPage(
        roots: found,
        folderMode: folder,
        extensions: extensions,
        memory: mem,
      ),
    ),
  );
  return result ?? const [];
}

/// The explorer screen. Pops with the paths to import.
class FileExplorerPage extends StatefulWidget {
  const FileExplorerPage({
    super.key,
    required this.roots,
    required this.folderMode,
    required this.extensions,
    this.memory,
  });

  final List<ExplorerRoot> roots;

  /// Add a folder (true) or Add games (false).
  final bool folderMode;
  final List<String> extensions;
  final ExplorerMemory? memory;

  @override
  State<FileExplorerPage> createState() => _FileExplorerPageState();
}

class _FileExplorerPageState extends State<FileExplorerPage> {
  /// The open folder; null shows the list of roots.
  String? dir;
  ExplorerRoot? root;
  List<ExplorerEntry> entries = const [];
  bool loading = true;
  bool unreadable = false;
  bool allFiles = false;
  bool collecting = false;
  final checked = <String>{};

  /// Bumped on every folder change so the list starts at the top again.
  int generation = 0;

  /// The first row, focused after every folder change so the D-pad starts
  /// there.
  final firstRow = FocusNode(debugLabel: 'explorer first row');

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    firstRow.dispose();
    super.dispose();
  }

  void _focusFirst() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && firstRow.context != null) firstRow.requestFocus();
  });

  Future<void> _start() async {
    final last = await widget.memory?.last();
    if (last != null) {
      for (final r in widget.roots) {
        if ((last == r.path || p.isWithin(r.path, last)) &&
            await Directory(last).exists()) {
          return _open(r, last, remember: false);
        }
      }
    }
    if (widget.roots.length == 1) {
      final r = widget.roots.single;
      return _open(r, r.start ?? r.path, remember: false);
    }
    _showRoots();
  }

  void _showRoots() {
    if (!mounted) return;
    setState(() {
      dir = null;
      root = null;
      entries = const [];
      loading = false;
      unreadable = false;
      generation++;
    });
    _focusFirst();
  }

  Future<void> _open(
    ExplorerRoot r,
    String path, {
    bool remember = true,
  }) async {
    setState(() {
      loading = true;
      root = r;
      dir = path;
    });
    List<ExplorerEntry> list;
    var failed = false;
    try {
      list = await listFolder(
        Directory(path),
        widget.extensions,
        allFiles: allFiles,
      );
    } on FileSystemException {
      list = const [];
      failed = true;
    }
    if (!mounted || dir != path) return;
    setState(() {
      entries = list;
      unreadable = failed;
      loading = false;
      generation++;
    });
    _focusFirst();
    if (remember && !failed) await widget.memory?.remember(path);
  }

  /// Whether B goes up a level instead of closing the explorer.
  bool get canGoUp {
    final d = dir;
    final r = root;
    if (d == null || r == null) return false;
    return d != r.path || widget.roots.length > 1;
  }

  void _up() {
    final d = dir;
    final r = root;
    if (d == null || r == null) return;
    if (d == r.path) {
      _showRoots();
    } else {
      _open(r, p.dirname(d));
    }
  }

  void _toggleFilter() {
    setState(() => allFiles = !allFiles);
    if (root case final r? when dir != null) _open(r, dir!, remember: false);
  }

  void _toggleAll() {
    final files = [
      for (final e in entries)
        if (!e.isFolder) e.path,
    ];
    if (files.isEmpty) return;
    setState(() {
      if (files.every(checked.contains)) {
        checked.removeAll(files);
      } else {
        checked.addAll(files);
      }
    });
  }

  Future<void> _confirm() async {
    if (widget.folderMode) {
      final d = dir;
      if (d == null || collecting) return;
      setState(() => collecting = true);
      final games = await collectGames(Directory(d), widget.extensions);
      await widget.memory?.remember(d);
      if (mounted) Navigator.of(context).pop(games);
    } else {
      if (checked.isEmpty) return;
      if (dir case final d?) await widget.memory?.remember(d);
      if (mounted) Navigator.of(context).pop(checked.toList());
    }
  }

  void _activate(ExplorerEntry e) {
    if (e.isFolder) {
      _open(root!, e.path);
    } else if (!widget.folderMode) {
      setState(
        () => checked.contains(e.path)
            ? checked.remove(e.path)
            : checked.add(e.path),
      );
    }
  }

  String get _title => widget.folderMode ? 'Add a folder' : 'Add games';

  String get _confirmLabel => widget.folderMode
      ? (collecting ? 'Finding games…' : 'Use this folder')
      : checked.length == 1
      ? 'Add 1 game'
      : 'Add ${checked.length} games';

  bool get _canConfirm =>
      widget.folderMode ? dir != null && !collecting : checked.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final handheld = Handheld.of(context);
    return PopScope(
      canPop: !canGoUp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.gameButtonStart): _confirm,
          const SingleActivator(LogicalKeyboardKey.gameButtonSelect): _confirm,
          const SingleActivator(LogicalKeyboardKey.gameButtonY): _toggleFilter,
          if (!widget.folderMode)
            const SingleActivator(LogicalKeyboardKey.gameButtonX): _toggleAll,
        },
        // Holds focus when the folder has nothing focusable, so B and Start
        // still reach the shortcuts above.
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(_title),
              actions: [
                if (dir != null)
                  IconButton(
                    tooltip: allFiles ? 'Show games only' : 'Show all files',
                    isSelected: allFiles,
                    onPressed: _toggleFilter,
                    icon: const Icon(DenaIcons.sort),
                    selectedIcon: const Icon(DenaIcons.list),
                  ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  _PathBar(root: root, dir: dir),
                  Expanded(child: _body(scheme)),
                  if (!handheld || !widget.folderMode || dir != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          if (!widget.folderMode)
                            Expanded(
                              child: Text(
                                checked.isEmpty
                                    ? 'Press A on a game to check it'
                                    : '${checked.length} checked',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            )
                          else
                            const Spacer(),
                          FilledButton.icon(
                            onPressed: _canConfirm ? _confirm : null,
                            icon: Icon(
                              widget.folderMode
                                  ? DenaIcons.folderAdd
                                  : DenaIcons.fileAdd,
                            ),
                            label: Text(_confirmLabel),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            bottomNavigationBar: handheld
                ? HintBar(
                    hints: [
                      (
                        [HintButton.a],
                        widget.folderMode ? 'Open' : 'Open/Check',
                      ),
                      ([HintButton.b], canGoUp ? 'Up' : 'Close'),
                      if (!widget.folderMode && dir != null)
                        ([HintButton.x], 'All'),
                      if (dir != null)
                        ([HintButton.y], allFiles ? 'Games only' : 'All files'),
                      if (_canConfirm)
                        (
                          [HintButton.start],
                          widget.folderMode ? 'Use folder' : 'Add',
                        ),
                    ],
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (dir == null) {
      if (widget.roots.isEmpty) {
        return const _Message(
          icon: DenaIcons.folder,
          text: 'No storage to browse',
        );
      }
      return ListView(
        key: ValueKey(generation),
        children: [
          for (final (i, r) in widget.roots.indexed)
            ListTile(
              focusNode: i == 0 ? firstRow : null,
              leading: Icon(r.icon, color: scheme.primary),
              title: Text(r.label),
              subtitle: Text(r.path),
              onTap: () => _open(r, r.start ?? r.path),
            ),
        ],
      );
    }
    if (unreadable) {
      return _Message(
        icon: DenaIcons.lock,
        text: "Can't open this folder",
        action: canGoUp ? _up : null,
      );
    }
    if (entries.isEmpty) {
      return _Message(
        icon: DenaIcons.folder,
        text: allFiles ? 'This folder is empty' : 'No games in this folder',
        action: canGoUp ? _up : null,
      );
    }
    return ListView.builder(
      key: ValueKey(generation),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final isChecked = checked.contains(e.path);
        final selectable = e.isFolder || !widget.folderMode;
        return ListTile(
          focusNode: i == 0 ? firstRow : null,
          dense: true,
          enabled: selectable,
          selected: isChecked,
          leading: Icon(
            e.isFolder ? DenaIcons.folder : DenaIcons.cartOutline,
            color: e.isFolder ? scheme.primary : null,
          ),
          title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: e.isFolder
              ? const Icon(DenaIcons.chevronRight)
              : widget.folderMode
              ? null
              : Icon(
                  isChecked ? DenaIcons.radioOn : DenaIcons.radioOff,
                  color: isChecked ? scheme.primary : null,
                ),
          onTap: selectable ? () => _activate(e) : null,
        );
      },
    );
  }
}

/// Where the explorer is: the root's name and the path inside it.
class _PathBar extends StatelessWidget {
  const _PathBar({required this.root, required this.dir});

  final ExplorerRoot? root;
  final String? dir;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final r = root;
    final d = dir;
    final inside = r == null || d == null || d == r.path
        ? ''
        : p.relative(d, from: r.path);
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(r?.icon ?? DenaIcons.sdCard, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: r?.label ?? 'Choose storage',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (inside.isNotEmpty) TextSpan(text: '  /  $inside'),
                ],
              ),
              style: text.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(text, style: Theme.of(context).textTheme.bodyLarge),
          if (action != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              autofocus: true,
              onPressed: action,
              icon: const Icon(DenaIcons.expandLess),
              label: const Text('Up a level'),
            ),
          ],
        ],
      ),
    );
  }
}
