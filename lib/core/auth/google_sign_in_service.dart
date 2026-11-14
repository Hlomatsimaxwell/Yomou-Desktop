import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

/// Google Sign-In client configured for the current platform.
///
/// Mobile (Android/iOS): uses the platform OAuth client declared in
/// `google-services.json` / `Info.plist` — no `clientId` needed here, matches
/// the existing mobile behaviour.
///
/// Desktop (Linux): uses the OAuth 2.0 Web client ID passed at build time via
/// `--dart-define=YOMOU_GOOGLE_CLIENT_ID=...`. The client secret is never used
/// by the client app — desktop opens the system browser and Google redirects
/// back with the auth code.
class GoogleSignInService {
  GoogleSignInService._();

  static GoogleSignIn? _instance;

  /// Scopes needed for Google Drive backup/restore.
  static const _scopes = <String>['https://www.googleapis.com/auth/drive.file'];

  /// Build (or reuse) the platform-appropriate [GoogleSignIn] client.
  static GoogleSignIn get instance {
    _instance ??= _build();
    return _instance!;
  }

  static GoogleSignIn _build() {
    final clientId = _clientId;

    // Desktop needs an explicit client ID; mobile relies on platform config.
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return GoogleSignIn(
        scopes: _scopes,
        clientId: clientId.isEmpty ? null : clientId,
      );
    }

    return GoogleSignIn(scopes: _scopes);
  }

  /// Whether a desktop client ID was provided at build time.
  static bool get isDesktopConfigured => _clientId.isNotEmpty &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  /// `YOMOU_GOOGLE_CLIENT_ID` from `--dart-define`, empty if not set.
  static String get _clientId =>
      String.fromEnvironment('YOMOU_GOOGLE_CLIENT_ID');

  static Future<void> dispose() async {
    try {
      await instance.signOut();
    } catch (_) {}
    _instance = null;
  }
}
