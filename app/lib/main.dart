// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:dena_android/dena_android.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'src/achievements/ra_native.dart';
import 'src/achievements/retro_achievements.dart';
import 'src/app.dart';
import 'src/library/android_files.dart';
import 'src/library/box_art.dart';
import 'src/library/media_art.dart';
import 'src/library/card_files.dart';
import 'src/library/card_library.dart';
import 'src/library/database.dart';
import 'src/library/foil.dart';
import 'src/library/importer.dart';
import 'src/library/library_scope.dart';
import 'src/shaders/shader_store.dart';
import 'src/shell/app_shell.dart';
import 'src/shell/device_settings.dart';
import 'src/shell/handheld.dart';
import 'src/shell/host_library.dart';
import 'src/shell/network.dart';
import 'src/shell/wifi.dart';
import 'src/shell/usb_storage.dart';
import 'src/shell/platform_features.dart';
import 'src/shell/power_link.dart';
import 'src/skins/skin_store.dart';
import 'src/third_party_licenses.dart';
import 'src/ui/app_theme.dart';
import 'src/ui/plastic.dart';
import 'src/shell/app_dirs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  final support = await appDataDir();
  // Windows and desktop Linux: Bios, Screenshots and cores under the storage
  // root (desktop-shell.md).
  if (desktopRoot() case final root?) configureDesktopHost(root);
  final db = LibraryDatabase.open();
  final skins = SkinStore(
    support.path,
    // Only the Android shell rasterizes PDF skin art; elsewhere skins use
    // their PNG art (skins.md).
    rasterize: hasAndroidShell
        ? (pdf, w, h, out) => LibraryHostApi().rasterizePdf(pdf, w, h, out)
        : null,
  );
  try {
    await skins.installBundled(
      (asset) async => (await rootBundle.load(asset)).buffer.asUint8List(),
    );
  } on Object catch (e) {
    // The built-in controls still work without them.
    debugPrint('Bundled skins not installed: $e');
  }
  final handheld = detectHandheld();
  if (handheld) {
    // Handheld GPUs (a one-core Mali-G31 on the H700) redraw the screen at a
    // fraction of a phone's speed: no full-screen grain pass and no endless
    // decorative animations (foil sweep) repainting the library.
    plasticGrainEnabled = false;
    FoilTilt.animate = false;
  }
  final channel = handheld ? await SocketPowerChannel.connect() : null;
  final power = channel == null ? null : PowerLink(channel);
  final settingsFile = handheld ? deviceSettingsFile() : null;
  final device = settingsFile == null
      ? null
      : await DeviceSettings.load(settingsFile);
  if (device != null) power?.brightness(device.brightness);
  // Handhelds without Wi-Fi hardware hide every online feature.
  final online = detectNetwork(handheld: handheld);
  final importer = Importer(db, Directory(p.join(support.path, 'games')));
  // Handhelds: games copied into the card's Roms folders join the library
  // in the background (sd-card.md, Card library).
  if (handheld) {
    if (cardRomsDir() case final roms?) {
      unawaited(
        scanCardRoms(roms, db, importer).then(
          (s) => debugPrint(
            'Card scan: ${s.added} added, ${s.rejected.length} skipped',
          ),
          onError: (Object e) => debugPrint('Card scan failed: $e'),
        ),
      );
    }
  }
  final raNative = FfiRaNative.open();
  final achievements = raNative == null || !online
      ? null
      : RetroAchievements(native: raNative, dataDir: support.path);
  runApp(
    LibraryScope(
      db: db,
      importer: importer,
      // The handheld has no system picker, share sheet or shortcuts:
      // Add games opens the in-app explorer (file_explorer.dart) and
      // games also join in place from the card (card_library.dart).
      files: hasAndroidShell ? AndroidGameFiles() : const CardGameFiles(),
      links: hasAndroidShell ? AndroidGameLinks() : null,
      art: BoxArtCache(support.path, loadIndex: BoxArtIndex.load),
      media: MediaArtCache(
        support.path,
        source: ScreenScraperSource.fromEnvironment(),
        index: BoxArtIndex.load,
      ),
      skins: skins,
      shaders: ShaderStore(support.path),
      achievements: achievements,
      child: Handheld(
        enabled: handheld,
        child: NetworkScope(
          online: online,
          wifi: handheld && online ? WifiControl() : null,
          child: PowerScope(
            link: power,
            device: device,
            usb: UsbStorage.detect(handheld: handheld, beforeExit: db.close),
            child: DenaApp(
              theme: ThemeSettings.load(
                File(p.join(support.path, 'theme.json')),
              ),
              home: const AppShell(onPlay: playGame),
            ),
          ),
        ),
      ),
    ),
  );
}
