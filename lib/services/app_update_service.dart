import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:pc_pos/utils/common.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:window_manager/window_manager.dart';

const _appcastUrl = 'http://103.159.59.15:8082/api/version/check-version-xml';

final appUpdateNavigatorKey = GlobalKey<NavigatorState>();

class AppUpdateService with UpdaterListener {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  final ShorebirdUpdater _shorebirdUpdater = ShorebirdUpdater();
  bool _started = false;
  bool _showingUpdateDialog = false;
  bool _showingPatchDialog = false;
  bool _userAcceptedUpdate = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    unawaited(_checkShorebirdPatch());
    unawaited(_checkInstallerUpdate());
  }

  Future<void> _checkInstallerUpdate() async {
    if (!Platform.isWindows && !Platform.isMacOS) {
      await writeLog('AUTO UPDATER SKIPPED: unsupported platform');
      return;
    }

    try {
      autoUpdater.addListener(this);
      await autoUpdater.setFeedURL(_appcastUrl);
      await autoUpdater.setScheduledCheckInterval(0);
      await writeLog('AUTO UPDATER READY: $_appcastUrl');

      await autoUpdater.checkForUpdates(inBackground: true);
    } catch (e) {
      await writeLog('AUTO UPDATER START ERROR: $e');
    }
  }

  Future<void> _checkShorebirdPatch() async {
    try {
      if (!_shorebirdUpdater.isAvailable) {
        await writeLog('SHOREBIRD UPDATE SKIPPED: updater unavailable');
        return;
      }

      final currentPatch = await _shorebirdUpdater.readCurrentPatch();
      final status = await _shorebirdUpdater.checkForUpdate();
      await writeLog(
        'SHOREBIRD UPDATE STATUS: $status, currentPatch=${currentPatch?.number}',
      );

      if (status == UpdateStatus.outdated) {
        await _shorebirdUpdater.update();
        final nextPatch = await _shorebirdUpdater.readNextPatch();
        await writeLog(
          'SHOREBIRD UPDATE DOWNLOADED: patch=${nextPatch?.number}',
        );
        await _showPatchRestartDialog(nextPatch);
      } else if (status == UpdateStatus.restartRequired) {
        final nextPatch = await _shorebirdUpdater.readNextPatch();
        await writeLog(
          'SHOREBIRD UPDATE RESTART REQUIRED: patch=${nextPatch?.number}',
        );
        await _showPatchRestartDialog(nextPatch);
      }
    } catch (e) {
      await writeLog('SHOREBIRD UPDATE ERROR: $e');
    }
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    unawaited(writeLog('AUTO UPDATER ERROR: ${error?.message}'));
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    unawaited(writeLog('AUTO UPDATER CHECKING'));
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    unawaited(writeLog(
      'AUTO UPDATER UPDATE AVAILABLE: '
      'version=${_versionLabel(appcastItem)}, url=${appcastItem?.fileURL}',
    ));

    if (_userAcceptedUpdate) return;
    unawaited(_showUpdateDialog(appcastItem));
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    unawaited(writeLog('AUTO UPDATER UPDATE NOT AVAILABLE'));
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    unawaited(writeLog(
      'AUTO UPDATER UPDATE DOWNLOADED: version=${_versionLabel(appcastItem)}',
    ));
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    unawaited(writeLog('AUTO UPDATER BEFORE QUIT FOR UPDATE'));
  }

  Future<void> _showUpdateDialog(AppcastItem? item) async {
    if (_showingUpdateDialog) return;

    final context = appUpdateNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      await writeLog('AUTO UPDATER DIALOG SKIPPED: navigator unavailable');
      return;
    }

    _showingUpdateDialog = true;
    try {
      final version = _versionLabel(item);
      final shouldUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Co ban cap nhat moi'),
            content: Text(
              version.isEmpty
                  ? 'Ban co muon cap nhat ung dung ngay bay gio khong?'
                  : 'Phien ban $version da san sang. Ban co muon cap nhat ngay bay gio khong?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('De sau'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Cap nhat'),
              ),
            ],
          );
        },
      );

      if (shouldUpdate != true) {
        await writeLog('AUTO UPDATER USER CANCELLED');
        return;
      }

      _userAcceptedUpdate = true;
      await writeLog('AUTO UPDATER USER ACCEPTED');

      // This starts the native WinSparkle flow. WinSparkle downloads the
      // installer from the appcast enclosure URL, verifies the signature, runs
      // the installer, quits this process, and restarts the app when supported.
      await autoUpdater.checkForUpdates(inBackground: false);
    } catch (e) {
      await writeLog('AUTO UPDATER DIALOG ERROR: $e');
    } finally {
      _showingUpdateDialog = false;
    }
  }

  String _versionLabel(AppcastItem? item) {
    return item?.displayVersionString ?? item?.versionString ?? '';
  }

  Future<void> _showPatchRestartDialog(Patch? patch) async {
    if (_showingPatchDialog) return;

    final context = appUpdateNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      await writeLog('SHOREBIRD RESTART DIALOG SKIPPED: navigator unavailable');
      return;
    }

    _showingPatchDialog = true;
    try {
      final shouldRestart = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(
            title: const Text('Co ban va moi'),
            content: Text(
              patch == null
                  ? 'Ban va moi da tai xong. Khoi dong lai ung dung de ap dung.'
                  : 'Ban va #${patch.number} da tai xong. Khoi dong lai ung dung de ap dung.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('De sau'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Khoi dong lai'),
              ),
            ],
          );
        },
      );

      if (shouldRestart == true) {
        await writeLog('SHOREBIRD USER ACCEPTED RESTART');
        await _restartApp();
      } else {
        await writeLog('SHOREBIRD USER POSTPONED RESTART');
      }
    } catch (e) {
      await writeLog('SHOREBIRD RESTART DIALOG ERROR: $e');
    } finally {
      _showingPatchDialog = false;
    }
  }

  Future<void> _restartApp() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await writeLog('SHOREBIRD RESTART SKIPPED: mobile platform');
      return;
    }

    final exe = Platform.resolvedExecutable.replaceAll("'", "''");

    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-WindowStyle',
        'Hidden',
        '-Command',
        "Start-Sleep -Milliseconds 800; Start-Process -FilePath '$exe'",
      ],
      mode: ProcessStartMode.detached,
    );

    await windowManager.close();
    exit(0);
  }
}
