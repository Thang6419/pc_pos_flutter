import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:pc_pos/utils/common.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

const _appcastUrl = 'http://103.159.59.15:8082/api/version/check-version-xml';

final appUpdateNavigatorKey = GlobalKey<NavigatorState>();

class AppUpdateService with UpdaterListener {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  final ShorebirdUpdater _shorebirdUpdater = ShorebirdUpdater();
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await writeLog('APP UPDATE SERVICE STARTED');

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
      } else if (status == UpdateStatus.restartRequired) {
        final nextPatch = await _shorebirdUpdater.readNextPatch();
        await writeLog(
          'SHOREBIRD UPDATE WAITING FOR APP RESTART: patch=${nextPatch?.number}',
        );
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

  String _versionLabel(AppcastItem? item) {
    return item?.displayVersionString ?? item?.versionString ?? '';
  }
}
