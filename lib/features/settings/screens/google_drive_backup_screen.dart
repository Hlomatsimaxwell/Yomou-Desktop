import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomou/core/auth/desktop_google_auth.dart';
import 'package:yomou/core/auth/google_sign_in_service.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:yomou/core/backup/backup_restore.dart';
import 'package:yomou/core/backup/kotatsu_backup.dart';
import 'package:yomou/core/database/database_helper.dart';
import 'package:yomou/features/history/providers/history_provider.dart';
import 'package:yomou/features/library/providers/favorites_provider.dart';
import 'package:yomou/core/widgets/responsive.dart';
import 'package:yomou/l10n/generated/app_localizations.dart';
import 'package:yomou/widgets/m3_components.dart';

/// Cloud backup via Google Drive.
///
/// Uses OAuth to obtain a Drive-scoped token, then the Drive v3 REST API to
/// upload/download backup files in the user's own Drive.
///
/// - Android/iOS: the existing `google_sign_in` plugin (platform OAuth client).
/// - Linux desktop: [DesktopGoogleAuth], a native installed-app OAuth flow.
///   `google_sign_in` has no Linux implementation, so using it there throws
///   `MissingPluginException`.
class GoogleDriveBackupScreen extends ConsumerStatefulWidget {
  const GoogleDriveBackupScreen({super.key});

  @override
  ConsumerState<GoogleDriveBackupScreen> createState() =>
      _GoogleDriveBackupScreenState();
}

class _GoogleDriveBackupScreenState
    extends ConsumerState<GoogleDriveBackupScreen> {
  _AccountInfo? _account;
  drive.DriveApi? _drive;
  bool _busy = false;
  String? _status;
  List<drive.File> _remoteFiles = const [];

  bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// Human-readable config hint; null when the platform is set up correctly.
  String? get _configHint {
    if (!_isDesktop || DesktopGoogleAuth.isConfigured) return null;
    return 'Google Sign-In not configured for desktop yet.\n'
        'Rebuild with --dart-define=YOMOU_GOOGLE_CLIENT_ID=...';
  }

  @override
  void initState() {
    super.initState();
    _tryRestore();
  }

  Future<void> _tryRestore() async {
    try {
      if (_isDesktop) {
        final tokens = await DesktopGoogleAuth.restore();
        if (tokens == null || !mounted) return;
        _applyAccount(
          email: tokens.email ?? 'Google account',
          displayName: tokens.displayName,
          authHeaders: DesktopGoogleAuth.authHeaders,
        );
        return;
      }
      final account = await GoogleSignInService.instance.signInSilently();
      if (account == null || !mounted) return;
      _applyAccount(
        email: account.email,
        displayName: account.displayName,
        authHeaders: () => account.authHeaders,
      );
    } catch (_) {
      // Not signed in; leave the sign-in button visible.
    }
  }

  void _applyAccount({
    required String email,
    String? displayName,
    required Future<Map<String, String>> Function() authHeaders,
  }) {
    if (!mounted) return;
    setState(() {
      _account = _AccountInfo(
        email: email,
        displayName: displayName,
        authHeaders: authHeaders,
      );
      _drive = drive.DriveApi(_AuthedClient(authHeaders));
      _status = 'Signed in as $email';
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      if (_isDesktop) {
        final tokens = await DesktopGoogleAuth.signIn();
        if (tokens == null) {
          if (mounted) setState(() => _status = 'Sign-in not configured');
          return;
        }
        _applyAccount(
          email: tokens.email ?? 'Google account',
          displayName: tokens.displayName,
          authHeaders: DesktopGoogleAuth.authHeaders,
        );
        return;
      }
      final account = await GoogleSignInService.instance.signIn();
      if (account == null) {
        if (mounted) setState(() => _status = 'Sign-in cancelled');
        return;
      }
      _applyAccount(
        email: account.email,
        displayName: account.displayName,
        authHeaders: () => account.authHeaders,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Sign-in error: $e');
      // Surface the error so it is not missed (e.g. missing OAuth client
      // config shows up as a PlatformException here).
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign-in failed'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_isDesktop) {
      await DesktopGoogleAuth.signOut();
    } else {
      await GoogleSignInService.instance.signOut();
    }
    if (!mounted) return;
    setState(() {
      _account = null;
      _drive = null;
      _remoteFiles = const [];
      _status = 'Signed out';
    });
  }

  Future<void> _listRemote() async {
    final driveApi = _drive;
    if (driveApi == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final res = await driveApi.files.list(
        q: "name contains 'yomou' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id,name,modifiedTime,size)',
      );
      if (!mounted) return;
      setState(() {
        _remoteFiles = res.files ?? const [];
        _status = 'Found ${_remoteFiles.length} remote file(s)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'List error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupNow() async {
    final driveApi = _drive;
    if (driveApi == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final favorites = await DatabaseHelper.instance.getFavorites();
      final bookmarks = await DatabaseHelper.instance.getAllBookmarks();
      final progress = await DatabaseHelper.instance.getAllReadingProgress();

      final result = KotatsuBackupCodec.export(
        favorites: favorites,
        bookmarks: bookmarks,
        readingProgress: progress,
      );
      if (result.exported == 0) {
        if (!mounted) return;
        setState(() => _status = 'Nothing to back up');
        return;
      }

      final name = 'yomou-${DateTime.now().millisecondsSinceEpoch}.bk.zip';
      final media = drive.Media(
        Stream.value(result.bytes),
        result.bytes.length,
        contentType: 'application/zip',
      );
      final file = drive.File()..name = name;
      await driveApi.files.create(file, uploadMedia: media);
      if (!mounted) return;
      setState(() => _status = 'Uploaded $name');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Backup error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(drive.File f) async {
    final driveApi = _drive;
    if (driveApi == null || f.id == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final media = await driveApi.files.get(
        f.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      if (!mounted) return;
      final parsed = KotatsuBackupCodec.import(Uint8List.fromList(bytes));
      final container = ProviderScope.containerOf(context, listen: false);
      await BackupRestore.applyTachiyomi(parsed);
      bumpHistoryRevision(container);
      bumpFavoritesRevision(container);
      if (!mounted) return;
      setState(() => _status = 'Restored ${f.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Restore error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatDate(DateTime dt) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: SettingsAppBar(title: l.googleDriveBackup, contentMargin: 24),
      body: CappedContentWidth(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
          children: [
            Text(
              'Sign in with your Google account. Backups are stored in your '
              'own Drive (appDataFolder scope).',
              style: TextStyle(fontSize: 13, color: color.onSurfaceVariant),
            ),
            if (_configHint != null) ...[
              const SizedBox(height: 8),
              Text(
                _configHint!,
                style: TextStyle(
                  fontSize: 12,
                  color: color.error,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_account == null)
              FilledButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.account_circle),
                title: Text(_account!.displayName ?? _account!.email),
                subtitle: Text(_account!.email),
                trailing: TextButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text('Sign out'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _busy ? null : _listRemote,
                      child: const Text('List files'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _backupNow,
                      child: const Text('Back up now'),
                    ),
                  ),
                ],
              ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Text(_status!, style: TextStyle(color: color.onSurfaceVariant)),
              ],
              if (_remoteFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Remote backups',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                for (final f in _remoteFiles)
                  ListTile(
                    title: Text(f.name ?? ''),
                    subtitle: f.modifiedTime == null
                        ? null
                        : Text(
                            _formatDate(f.modifiedTime!),
                            style: TextStyle(
                              fontSize: 12,
                              color: color.onSurfaceVariant,
                            ),
                          ),
                    trailing: TextButton(
                      onPressed: _busy ? null : () => _restore(f),
                      child: const Text('Restore'),
                    ),
                  ),
              ],
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// http.Client that injects the signed-in account's auth headers.
class _AuthedClient extends http.BaseClient {
  _AuthedClient(this._authHeaders);

  final Future<Map<String, String>> Function() _authHeaders;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(await _authHeaders());
    return _inner.send(request);
  }
}

/// Signed-in account details shared by the mobile plugin and desktop OAuth.
class _AccountInfo {
  const _AccountInfo({
    required this.email,
    required this.displayName,
    required this.authHeaders,
  });

  final String email;
  final String? displayName;
  final Future<Map<String, String>> Function() authHeaders;
}
