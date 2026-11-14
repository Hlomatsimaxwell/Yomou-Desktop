import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// One selectable launcher icon.
///
/// Assets live in `assets/app_icons/variant_<id>.png`, so adding a new icon is
/// just a matter of dropping a square PNG there (see `tool/sync_app_icons.sh`).
class AppIconOption {
  const AppIconOption({
    required this.id,
    required this.label,
    required this.asset,
  });

  final String id;
  final String label;
  final String asset;
}

/// Launcher icon switching.
///
/// Android rotates between the native activity aliases declared in the
/// manifest. Linux writes the chosen image into the user's icon directory and
/// rewrites the user-level desktop entry so the launcher picks it up without
/// touching the system package.
class AppIconService {
  AppIconService._();

  static const _channel = MethodChannel('com.hlomatsi.yomou/app_icon');
  static const _prefsKey = 'app_icon_variant';
  static const _appId = 'com.stunna.manga_reader';
  static const _assetPrefix = 'assets/app_icons/variant_';
  static const _defaultId = 'gold';

  /// The order the picker uses for variants that ship with the app. Unknown
  /// (newly added) variants follow alphabetically.
  ///
  /// Dark and light stay on disk as launcher-generation sources but are not
  /// offered in the picker: White and B&W already cover those theme looks.
  static const _preferredOrder = ['gold', 'blue', 'white', 'bw'];

  /// Bundled variants the picker deliberately hides.
  static const _pickerExcluded = {'dark', 'light'};

  /// Labels for ids whose raw spelling would read badly (`bw` would otherwise
  /// become "Bw").
  static const _labelOverrides = {'bw': 'B&W'};

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isLinux);

  /// Every icon this platform can actually apply.
  ///
  /// On Linux the list comes from the asset manifest, so a new
  /// `variant_<id>.png` shows up without a code change. Android is limited to
  /// the activity aliases present in the manifest.
  static Future<List<AppIconOption>> options() async {
    if (kIsWeb) return const [];

    if (Platform.isAndroid) {
      return const [
        AppIconOption(
          id: 'dark',
          label: 'Dark',
          asset: 'assets/app_icons/variant_dark.png',
        ),
        AppIconOption(
          id: 'light',
          label: 'Light',
          asset: 'assets/app_icons/variant_light.png',
        ),
      ];
    }

    if (Platform.isLinux) {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final ids = manifest
          .listAssets()
          .where(
            (asset) =>
                asset.startsWith(_assetPrefix) && asset.endsWith('.png'),
          )
          .map(
            (asset) =>
                asset.substring(_assetPrefix.length, asset.length - 4),
          )
          .where((id) => !_pickerExcluded.contains(id))
          .toSet()
          .toList()
        ..sort((a, b) {
          final ai = _preferredOrder.indexOf(a);
          final bi = _preferredOrder.indexOf(b);
          if (ai == -1 && bi == -1) return a.compareTo(b);
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        });

      return [
        for (final id in ids)
          AppIconOption(
            id: id,
            label: _label(id),
            asset: '$_assetPrefix$id.png',
          ),
      ];
    }

    return const [];
  }

  static Future<String> current() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final value = await _channel.invokeMethod<String>('getAlias');
        return value == 'light' ? 'light' : 'dark';
      } catch (_) {
        return 'dark';
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return _defaultId;

    final available = await options();
    return available.any((option) => option.id == saved)
        ? saved
        : _defaultId;
  }

  static Future<bool> set(String id) async {
    if (kIsWeb) return false;

    if (Platform.isAndroid) {
      if (id != 'dark' && id != 'light') return false;
      try {
        await _channel.invokeMethod<bool>('setAlias', {'alias': id});
        return true;
      } catch (_) {
        return false;
      }
    }

    if (Platform.isLinux) {
      final available = await options();
      AppIconOption? option;
      for (final candidate in available) {
        if (candidate.id == id) {
          option = candidate;
          break;
        }
      }
      if (option == null) return false;

      final applied = await _applyLinux(option);
      if (!applied) return false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, id);
      return true;
    }

    return false;
  }

  /// Re-applies the last chosen icon to the running window. Called once at
  /// startup so the title bar/task switcher matches the launcher even when the
  /// desktop did not pick up the user icon override.
  static Future<void> restoreWindowIcon() async {
    if (kIsWeb || !Platform.isLinux) return;
    final file = File(p.join(_dataHome(), _appId, 'app-icon.png'));
    if (!await file.exists()) return;
    await _setWindowIcon(file.path);
  }

  static Future<bool> _applyLinux(AppIconOption option) async {
    final data = await rootBundle.load(option.asset);
    final bytes = data.buffer.asUint8List();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return false;

    final dataHome = _dataHome();

    // Copy the selected variant over the per-user copy of the hicolor theme.
    // This is what the launcher uses for the `com.stunna.manga_reader` icon
    // name carried by the packaged desktop entry.
    for (final size in const [48, 128, 256, 512]) {
      final resized = img.copyResize(
        decoded,
        width: size,
        height: size,
        interpolation: img.Interpolation.average,
      );
      final file = File(
        p.join(
          dataHome,
          'icons',
          'hicolor',
          '${size}x$size',
          'apps',
          '$_appId.png',
        ),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(img.encodePng(resized), flush: true);
    }

    // A stable absolute path for the desktop entry and the live window icon.
    final iconFile = File(p.join(dataHome, _appId, 'app-icon.png'));
    await iconFile.parent.create(recursive: true);
    await iconFile.writeAsBytes(bytes, flush: true);

    await _writeDesktopEntry(iconFile.path);
    await _setWindowIcon(iconFile.path);
    return true;
  }

  /// Writes a per-user override of the packaged desktop entry. Using an
  /// absolute icon path here means the launcher shows the choice even on
  /// desktops that do not merge `~/.local/share/icons` into the hicolor
  /// theme lookup.
  static Future<void> _writeDesktopEntry(String iconPath) async {
    final applications = Directory(p.join(_dataHome(), 'applications'));
    await applications.create(recursive: true);

    final exec = _quoteExec(_launchTarget());
    final entry = File(p.join(applications.path, '$_appId.desktop'));
    await entry.writeAsString(
      '[Desktop Entry]\n'
      'Version=1.0\n'
      'Type=Application\n'
      'Name=Yomou\n'
      'Comment=Manga reader desktop build\n'
      'Exec=$exec %U\n'
      'Icon=$iconPath\n'
      'Terminal=false\n'
      'Categories=Graphics;Viewer;\n'
      'StartupNotify=true\n'
      'StartupWMClass=manga_reader\n'
      'MimeType=application/zip;application/x-tar;application/x-yomou-backup;\n',
      flush: true,
    );

    try {
      await Process.run('update-desktop-database', [applications.path]);
    } catch (_) {
      // Optional helper; the entry is already on disk.
    }

    final iconTheme = File(
      p.join(_dataHome(), 'icons', 'hicolor', 'index.theme'),
    );
    if (await iconTheme.exists()) {
      try {
        await Process.run('gtk-update-icon-cache', [
          '-f',
          '-t',
          p.join(_dataHome(), 'icons', 'hicolor'),
        ]);
      } catch (_) {
        // Same: only a cache warm-up.
      }
    }
  }

  /// AppImage runs from a temporary mount, so `resolvedExecutable` is not
  /// stable. The runtime exports `APPIMAGE` with the file the user launched.
  static String _launchTarget() {
    final appImage = Platform.environment['APPIMAGE'];
    if (appImage != null && appImage.isNotEmpty) return appImage;
    return Platform.resolvedExecutable;
  }

  static String _quoteExec(String path) {
    final escaped = path.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }

  static Future<void> _setWindowIcon(String path) async {
    try {
      await _channel.invokeMethod<void>('setWindowIcon', {'path': path});
    } catch (_) {
      // The native channel is Linux-only; on other platforms the icon is
      // already handled above.
    }
  }

  static String _dataHome() {
    final xdg = Platform.environment['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) return xdg;
    final home = Platform.environment['HOME'] ?? '';
    return p.join(home, '.local', 'share');
  }

  /// `moon_gold` -> `Moon Gold`.
  static String _label(String id) {
    final override = _labelOverrides[id];
    if (override != null) return override;
    return id
        .split(RegExp(r'[_\-\s]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}
