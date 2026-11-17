import 'package:google_sign_in/google_sign_in.dart';

/// Mobile-only GoogleSignIn client.
///
/// `google_sign_in` has no Linux implementation (its platform list is
/// android/ios/macos/web only), so it must never be instantiated on desktop.
/// The Linux build uses [DesktopGoogleAuth] instead — see
/// `lib/core/auth/desktop_google_auth.dart`.
class GoogleSignInService {
  GoogleSignInService._();

  static GoogleSignIn? _instance;

  static const _scopes = <String>['https://www.googleapis.com/auth/drive.file'];

  static GoogleSignIn get instance {
    _instance ??= GoogleSignIn(scopes: _scopes);
    return _instance!;
  }

  static Future<void> dispose() async {
    try {
      await instance.signOut();
    } catch (_) {}
    _instance = null;
  }
}
