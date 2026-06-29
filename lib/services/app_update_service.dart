import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pc_pos/utils/common.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:xml/xml.dart';

const _appcastUrl = 'http://103.159.59.15:8082/api/version/check-version-xml';

final appUpdateNavigatorKey = GlobalKey<NavigatorState>();
final appUpdatePromptVisible = ValueNotifier<bool>(false);

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  final ShorebirdUpdater _shorebirdUpdater = ShorebirdUpdater();
  bool _started = false;
  bool _checkingAndroidApk = false;
  bool _installingAndroidApk = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await writeLog('APP UPDATE SERVICE STARTED');

    unawaited(_checkShorebirdPatch());

    if (Platform.isWindows || Platform.isMacOS) {
      await _checkInstallerUpdate();
    } else if (Platform.isAndroid) {
      await _checkAndroidApkUpdate();
    } else {
      await writeLog('APP UPDATE INSTALLER SKIPPED: unsupported platform');
    }
  }

  Future<void> _checkAndroidApkUpdate() async {
    if (!Platform.isAndroid) return;
    if (_checkingAndroidApk) return;

    _checkingAndroidApk = true;

    try {
      await writeLog('ANDROID APK UPDATE CHECK START: $_appcastUrl');
      final info = await _fetchAndroidApkUpdateInfo();
      if (info == null) {
        await writeLog('ANDROID APK UPDATE SKIPPED: invalid xml');
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      await writeLog(
        'ANDROID APK UPDATE VERSION: current=${packageInfo.version}+$currentBuild, '
        'remote=${info.version}+$info.buildNumber, url=${info.apkUrl}',
      );

      if (info.buildNumber <= currentBuild) {
        await writeLog('ANDROID APK UPDATE NOT AVAILABLE');
        return;
      }

      final shouldInstall = await _confirmAndroidApkUpdate(info);
      if (shouldInstall != true) {
        await writeLog('ANDROID APK UPDATE DECLINED');
        return;
      }

      await _downloadAndOpenAndroidApk(info);
    } catch (e, s) {
      await writeLog('ANDROID APK UPDATE ERROR: $e');
      await writeLog(s);
    } finally {
      _checkingAndroidApk = false;
    }
  }

  Future<_AndroidApkUpdateInfo?> _fetchAndroidApkUpdateInfo() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_appcastUrl));
      final response = await request.close();
      final body = await utf8.decodeStream(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await writeLog(
          'ANDROID APK UPDATE HTTP ERROR: status=${response.statusCode}',
        );
        return null;
      }

      final document = XmlDocument.parse(body);
      final item = document.findAllElements('item').firstOrNull;
      if (item == null) return null;

      final version = item.getElement('version')?.innerText.trim() ?? '';
      final buildNumber =
          int.tryParse(item.getElement('buildNumber')?.innerText.trim() ?? '');
      final apkUrl = item.getElement('url')?.innerText.trim() ?? '';
      final title = item.getElement('title')?.innerText.trim() ?? version;

      if (buildNumber == null || apkUrl.isEmpty) return null;

      return _AndroidApkUpdateInfo(
        title: title,
        version: version,
        buildNumber: buildNumber,
        apkUrl: apkUrl,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<bool?> _confirmAndroidApkUpdate(_AndroidApkUpdateInfo info) async {
    final context = appUpdateNavigatorKey.currentContext;
    if (context == null) {
      await writeLog('ANDROID APK UPDATE PROMPT SKIPPED: no navigator context');
      return true;
    }

    appUpdatePromptVisible.value = true;

    try {
      await Future.delayed(const Duration(milliseconds: 150));
      final dialogContext = appUpdateNavigatorKey.currentContext;

      if (dialogContext == null) {
        await writeLog(
          'ANDROID APK UPDATE PROMPT SKIPPED: no navigator after webview hide',
        );
        return true;
      }

      return await showDialog<bool>(
        // ignore: use_build_context_synchronously
        context: dialogContext,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Update available'),
            content: Text(
              '${info.title}\nVersion: ${info.version}+${info.buildNumber}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Update'),
              ),
            ],
          );
        },
      );
    } finally {
      appUpdatePromptVisible.value = false;
    }
  }

  Future<void> _downloadAndOpenAndroidApk(_AndroidApkUpdateInfo info) async {
    if (_installingAndroidApk) return;
    _installingAndroidApk = true;

    HttpClient? client;
    IOSink? sink;

    try {
      final directory = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final file = File(
        '${directory.path}/pc_pos_${info.version}_${info.buildNumber}.apk',
      );

      await writeLog('ANDROID APK DOWNLOAD START: ${info.apkUrl}');
      client = HttpClient();
      final request = await client.getUrl(Uri.parse(info.apkUrl));
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Download APK failed: ${response.statusCode}',
          uri: Uri.parse(info.apkUrl),
        );
      }

      sink = file.openWrite();
      await response.pipe(sink);
      sink = null;

      await writeLog('ANDROID APK DOWNLOAD DONE: ${file.path}');
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      await writeLog(
        'ANDROID APK INSTALL INTENT RESULT: ${result.type} ${result.message}',
      );
    } finally {
      await sink?.close();
      client?.close(force: true);
      _installingAndroidApk = false;
    }
  }

  Future<void> _checkInstallerUpdate() async {
    if (!Platform.isWindows && !Platform.isMacOS) {
      await writeLog('INSTALLER UPDATE SKIPPED: unsupported platform');
      return;
    }

    try {
      await writeLog('INSTALLER UPDATE CHECK START: $_appcastUrl');
      final info = await _fetchInstallerUpdateInfo();
      if (info == null) {
        await writeLog('INSTALLER UPDATE SKIPPED: invalid xml');
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final currentVersion = packageInfo.version;
      await writeLog(
        'INSTALLER UPDATE VERSION: current=$currentVersion+$currentBuild, '
        'remote=${info.version}+${info.buildNumber}',
      );

      if (info.buildNumber <= currentBuild && info.version == currentVersion) {
        await writeLog('INSTALLER UPDATE NOT AVAILABLE');
        return;
      }

      final shouldInstall = await _confirmAndroidApkUpdate(info);
      if (shouldInstall != true) {
        await writeLog('INSTALLER UPDATE DECLINED');
        return;
      }

      await _downloadAndOpenInstaller(info);
    } catch (e, s) {
      await writeLog('INSTALLER UPDATE ERROR: $e');
      await writeLog(s);
    }
  }

  Future<_AndroidApkUpdateInfo?> _fetchInstallerUpdateInfo() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_appcastUrl));
      final response = await request.close();
      final body = await utf8.decodeStream(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await writeLog(
          'INSTALLER UPDATE HTTP ERROR: status=${response.statusCode}',
        );
        return null;
      }

      final document = XmlDocument.parse(body);
      final item = document.findAllElements('item').firstOrNull;
      if (item == null) return null;

      final enclosure = item.getElement('enclosure');
      if (enclosure == null) return null;

      final installerUrl = enclosure.getAttribute('url')?.trim() ?? '';
      final sparkleVersion = _readAttribute(enclosure, 'version').trim();
      final title = item.getElement('title')?.innerText.trim() ??
          (sparkleVersion.isEmpty ? 'Update available' : sparkleVersion);

      if (installerUrl.isEmpty || sparkleVersion.isEmpty) return null;

      final parsedVersion = _parseVersionAndBuild(sparkleVersion);
      if (parsedVersion == null) return null;

      return _AndroidApkUpdateInfo(
        title: title,
        version: parsedVersion.version,
        buildNumber: parsedVersion.buildNumber,
        apkUrl: installerUrl,
      );
    } finally {
      client.close(force: true);
    }
  }

  String _readAttribute(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) {
        return attribute.value;
      }
    }

    return '';
  }

  _ParsedVersion? _parseVersionAndBuild(String value) {
    final parts = value.split('+');
    final version = parts.first.trim();
    final buildNumber = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;

    if (version.isEmpty || buildNumber == null) return null;

    return _ParsedVersion(version: version, buildNumber: buildNumber);
  }

  Future<void> _downloadAndOpenInstaller(_AndroidApkUpdateInfo info) async {
    HttpClient? client;
    IOSink? sink;

    try {
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/pc_pos_${info.version}_${info.buildNumber}${_installerExtension(info)}',
      );

      await writeLog('INSTALLER DOWNLOAD START: ${info.apkUrl}');
      client = HttpClient();
      final request = await client.getUrl(Uri.parse(info.apkUrl));
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Download installer failed: ${response.statusCode}',
          uri: Uri.parse(info.apkUrl),
        );
      }

      sink = file.openWrite();
      await response.pipe(sink);
      sink = null;

      await writeLog('INSTALLER DOWNLOAD DONE: ${file.path}');
      final result = await OpenFilex.open(file.path);
      await writeLog(
        'INSTALLER OPEN RESULT: ${result.type} ${result.message}',
      );
    } finally {
      await sink?.close();
      client?.close(force: true);
    }
  }

  String _installerExtension(_AndroidApkUpdateInfo info) {
    final lower = info.apkUrl.toLowerCase();
    if (lower.endsWith('.msi')) return '.msi';
    if (lower.endsWith('.exe')) return '.exe';
    if (lower.endsWith('.dmg')) return '.dmg';
    return '';
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
}

class _AndroidApkUpdateInfo {
  const _AndroidApkUpdateInfo({
    required this.title,
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
  });

  final String title;
  final String version;
  final int buildNumber;
  final String apkUrl;
}

class _ParsedVersion {
  const _ParsedVersion({
    required this.version,
    required this.buildNumber,
  });

  final String version;
  final int buildNumber;
}
