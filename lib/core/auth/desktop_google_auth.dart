import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// A signed-in desktop Google account, stored under the app's data dir.
class DesktopGoogleTokens {
  const DesktopGoogleTokens({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    this.email,
    this.displayName,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String? email;
  final String? displayName;

  Map<String, String> get authHeaders => {
        'Authorization': 'Bearer $accessToken',
      };

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
        'email': email,
        'displayName': displayName,
      };

  factory DesktopGoogleTokens.fromJson(Map<String, dynamic> json) {
    return DesktopGoogleTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
    );
  }
}

/// OAuth 2.0 installed-app flow for the Linux desktop build.
///
/// `google_sign_in` has no Linux implementation (its platform list is
/// android/ios/macos/web only), so calling it on Linux throws
/// `MissingPluginException`. This class implements the standard loopback
/// redirect flow instead: open the system browser via `url_launcher`, receive
/// the auth code on a local `HttpServer`, then exchange it with PKCE.
///
/// Configuration is supplied at build time:
///
///   flutter build linux --release \
///     --dart-define=YOMOU_GOOGLE_CLIENT_ID=YOUR_ID.apps.googleusercontent.com \
///     --dart-define=YOMOU_GOOGLE_CLIENT_SECRET=YOUR_SECRET
///
/// The secret is optional for public clients and can also be supplied at
/// runtime via the `YOMOU_GOOGLE_CLIENT_SECRET` environment variable. Neither
/// value is ever hardcoded in this file.
class DesktopGoogleAuth {
  DesktopGoogleAuth._();

  static const _scope = 'https://www.googleapis.com/auth/drive.file';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _userInfoEndpoint =
      'https://www.googleapis.com/oauth2/v3/userinfo';
  static const _tokenFileName = 'google_tokens.json';
  static const _signInTimeout = Duration(minutes: 5);

  /// OAuth Web/Desktop client ID from --dart-define or the environment.
  ///
  /// `fromEnvironment` must be used in a `const` context — a bare call is
  /// evaluated at runtime and silently returns the empty default.
  static String get clientId {
    const define = String.fromEnvironment('YOMOU_GOOGLE_CLIENT_ID');
    if (define.isNotEmpty) return define;
    return Platform.environment['YOMOU_GOOGLE_CLIENT_ID'] ?? '';
  }

  /// OAuth client secret from --dart-define or the environment.
  static String get clientSecret {
    const define = String.fromEnvironment('YOMOU_GOOGLE_CLIENT_SECRET');
    if (define.isNotEmpty) return define;
    return Platform.environment['YOMOU_GOOGLE_CLIENT_SECRET'] ?? '';
  }

  static bool get isConfigured => clientId.isNotEmpty;

  static String get _tokenPath {
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : '${Platform.environment['HOME'] ?? ''}/.local/share';
    return '$base/com.stunna.manga_reader/$_tokenFileName';
  }

  /// Load the saved tokens, refreshing them if they are close to expiry.
  static Future<DesktopGoogleTokens?> restore() async {
    final file = File(_tokenPath);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final tokens = DesktopGoogleTokens.fromJson(json);
      if (tokens.expiresAt.isBefore(
        DateTime.now().add(const Duration(minutes: 2)),
      )) {
        final refreshed = await _refresh(tokens);
        if (refreshed == null) {
          await signOut();
          return null;
        }
        await _save(refreshed);
        return refreshed;
      }
      if (tokens.email == null) {
        final enriched = await _withUserInfo(tokens);
        if (enriched != tokens) await _save(enriched);
        return enriched;
      }
      return tokens;
    } catch (_) {
      await signOut();
      return null;
    }
  }

  /// Run the browser flow, exchange the code, and persist the tokens.
  static Future<DesktopGoogleTokens?> signIn() async {
    if (!isConfigured) return null;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/callback';
    final state = _randomUrlSafe(24);
    final verifier = _randomUrlSafe(32);

    final completer = Completer<_AuthResult?>();
    final timer = Timer(_signInTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Google Sign-In was not completed in time'),
        );
      }
    });

    server.listen((request) async {
      if (request.uri.path != '/callback') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final code = request.uri.queryParameters['code'];
      final returnedState = request.uri.queryParameters['state'];
      final error = request.uri.queryParameters['error'];

      request.response.headers.contentType = ContentType.html;
      request.response.write(
        error != null
            ? '<h1>Sign-in failed</h1><p>$error</p>'
            : '<h1>Signed in</h1><p>You can close this window and return to Yomou.</p>',
      );
      await request.response.close();

      if (completer.isCompleted) return;
      if (error != null) {
        completer.completeError(StateError('Google Sign-In error: $error'));
      } else if (code == null) {
        completer.completeError(StateError('Missing authorization code'));
      } else if (returnedState != state) {
        completer.completeError(StateError('OAuth state mismatch'));
      } else {
        completer.complete(
          _AuthResult(
            code: code,
            redirectUri: redirectUri,
            verifier: verifier,
          ),
        );
      }
    });

    var launched = false;
    try {
      final url = buildAuthUri(
        clientId: clientId,
        redirectUri: redirectUri,
        state: state,
        challenge: buildCodeChallenge(verifier),
        scope: _scope,
      );
      launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw StateError('Could not open the system browser');
      }

      final result = await completer.future;
      if (result == null) {
        throw StateError('Google Sign-In was cancelled');
      }
      final tokens = await _withUserInfo(await _exchangeCode(result));
      await _save(tokens);
      return tokens;
    } finally {
      timer.cancel();
      await server.close(force: true);
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Headers for Drive API calls; refreshes the token when needed.
  static Future<Map<String, String>> authHeaders() async {
    final tokens = await restore();
    if (tokens == null) throw StateError('Not signed in to Google');
    return tokens.authHeaders;
  }

  static Future<void> signOut() async {
    final file = File(_tokenPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<DesktopGoogleTokens> _exchangeCode(_AuthResult result) async {
    final body = <String, String>{
      'code': result.code,
      'client_id': clientId,
      'redirect_uri': result.redirectUri,
      'grant_type': 'authorization_code',
      'code_verifier': result.verifier,
    };
    final secret = clientSecret;
    if (secret.isNotEmpty) body['client_secret'] = secret;

    final response = await http.post(
      Uri.parse(_tokenEndpoint),
      body: body,
      headers: {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw StateError('Token exchange failed (${response.statusCode})');
    }
    return _tokensFromTokenResponse(response.body);
  }

  static Future<DesktopGoogleTokens?> _refresh(
    DesktopGoogleTokens tokens,
  ) async {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return null;

    final body = <String, String>{
      'client_id': clientId,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    };
    final secret = clientSecret;
    if (secret.isNotEmpty) body['client_secret'] = secret;

    final response = await http.post(
      Uri.parse(_tokenEndpoint),
      body: body,
      headers: {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) return null;

    final fresh = _tokensFromTokenResponse(response.body);
    return DesktopGoogleTokens(
      accessToken: fresh.accessToken,
      refreshToken: fresh.refreshToken ?? refreshToken,
      expiresAt: fresh.expiresAt,
      email: tokens.email,
      displayName: tokens.displayName,
    );
  }

  static DesktopGoogleTokens _tokensFromTokenResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final accessToken = json['accessToken'] as String? ??
        json['access_token'] as String?;
    if (accessToken == null) {
      throw FormatException('Missing access token in response');
    }
    final expiresIn = (json['expiresIn'] as num? ?? json['expires_in'] as num? ?? 3600)
        .toInt();
    return DesktopGoogleTokens(
      accessToken: accessToken,
      refreshToken: json['refreshToken'] as String? ??
          json['refresh_token'] as String?,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  static Future<DesktopGoogleTokens> _withUserInfo(
    DesktopGoogleTokens tokens,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(_userInfoEndpoint),
        headers: tokens.authHeaders,
      );
      if (response.statusCode != 200) return tokens;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return DesktopGoogleTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresAt: tokens.expiresAt,
        email: json['email'] as String?,
        displayName: json['name'] as String?,
      );
    } catch (_) {
      return tokens;
    }
  }

  static Future<void> _save(DesktopGoogleTokens tokens) async {
    final file = File(_tokenPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(tokens.toJson()), flush: true);
    if (!Platform.isWindows) {
      // 0600 — the tokens are only readable by the current user.
      await Process.run('chmod', ['600', file.path]);
    }
  }

  static String _randomUrlSafe(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// PKCE S256 challenge — base64url(SHA256(verifier)) without padding.
@visibleForTesting
String buildCodeChallenge(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}

/// Build the Google consent-screen URL for the loopback redirect.
@visibleForTesting
Uri buildAuthUri({
  required String clientId,
  required String redirectUri,
  required String state,
  required String challenge,
  required String scope,
}) {
  return Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'scope': scope,
    'access_type': 'offline',
    'prompt': 'consent',
    'state': state,
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
  });
}

class _AuthResult {
  const _AuthResult({
    required this.code,
    required this.redirectUri,
    required this.verifier,
  });

  final String code;
  final String redirectUri;
  final String verifier;
}
