import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
// import 'package:flutter/foundation.dart';

class DeviceIdService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static Future<String> getDeviceId() async {
    if (kIsWeb) {
      final info = await _deviceInfo.webBrowserInfo;
      return '${info.browserName.name}_${info.vendor}_${info.userAgent?.hashCode ?? 0}';
    }

    if (Platform.isAndroid) {
      return (await _deviceInfo.androidInfo).id;
    }
    if (Platform.isIOS) {
      return (await _deviceInfo.iosInfo).identifierForVendor ?? 'unknown-ios';
    }
    if (Platform.isWindows) {
      return (await _deviceInfo.windowsInfo).deviceId;
    }
    if (Platform.isMacOS) {
      return (await _deviceInfo.macOsInfo).systemGUID ?? 'unknown-macos';
    }
    if (Platform.isLinux) {
      return (await _deviceInfo.linuxInfo).machineId ?? 'unknown-linux';
    }

    return 'unknown';
  }
}
