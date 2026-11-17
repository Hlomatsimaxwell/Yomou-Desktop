import 'package:flutter_test/flutter_test.dart';
import 'package:yomou/core/auth/desktop_google_auth.dart';

void main() {
  test('PKCE challenge matches the RFC 7636 test vector', () {
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    expect(
      buildCodeChallenge(verifier),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('auth URI carries the loopback redirect and PKCE params', () {
    final uri = buildAuthUri(
      clientId: 'test-id.apps.googleusercontent.com',
      redirectUri: 'http://127.0.0.1:12345/callback',
      state: 'abc123',
      challenge: 'challenge-value',
      scope: 'https://www.googleapis.com/auth/drive.file',
    );

    expect(uri.host, 'accounts.google.com');
    expect(uri.path, '/o/oauth2/v2/auth');
    expect(uri.queryParameters['client_id'],
        'test-id.apps.googleusercontent.com');
    expect(uri.queryParameters['redirect_uri'],
        'http://127.0.0.1:12345/callback');
    expect(uri.queryParameters['response_type'], 'code');
    expect(uri.queryParameters['access_type'], 'offline');
    expect(uri.queryParameters['prompt'], 'consent');
    expect(uri.queryParameters['state'], 'abc123');
    expect(uri.queryParameters['code_challenge'], 'challenge-value');
    expect(uri.queryParameters['code_challenge_method'], 'S256');
  });

  test('tokens survive a JSON round trip', () {
    final tokens = DesktopGoogleTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.parse('2026-11-17T12:00:00.000Z'),
      email: 'user@example.com',
      displayName: 'User',
    );

    final restored = DesktopGoogleTokens.fromJson(tokens.toJson());
    expect(restored.accessToken, 'access');
    expect(restored.refreshToken, 'refresh');
    expect(restored.expiresAt, tokens.expiresAt);
    expect(restored.email, 'user@example.com');
    expect(restored.displayName, 'User');
    expect(restored.authHeaders, {'Authorization': 'Bearer access'});
  });
}
