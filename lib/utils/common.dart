import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

int? _singleInstanceMutexHandle;

typedef CreateMutexWNative = IntPtr Function(
  Pointer<Void>,
  Int32,
  Pointer<Utf16>,
);

typedef CreateMutexWDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Utf16>,
);

typedef GetLastErrorNative = Uint32 Function();
typedef GetLastErrorDart = int Function();

const int ERROR_ALREADY_EXISTS = 183;

Future<bool> ensureSingleInstance() async {
  final logFile = File(
      '${Platform.environment['LOCALAPPDATA']}\\PC_POS_single_instance.log');

  final kernel32 = DynamicLibrary.open('kernel32.dll');

  final createMutex =
      kernel32.lookupFunction<CreateMutexWNative, CreateMutexWDart>(
    'CreateMutexW',
  );

  final getLastError =
      kernel32.lookupFunction<GetLastErrorNative, GetLastErrorDart>(
    'GetLastError',
  );

  // DÙNG Local, đừng dùng Global
  final mutexName = 'Local\\PC_POS_SINGLE_INSTANCE_MUTEX'.toNativeUtf16();

  final handle = createMutex(
    nullptr,
    0,
    mutexName,
  );

  final error = getLastError();

  calloc.free(mutexName);

  await logFile.writeAsString(
    'pid=$pid, handle=$handle, error=$error, exe=${Platform.resolvedExecutable}\n',
    mode: FileMode.append,
  );

  if (handle == 0) {
    // tạo mutex lỗi thì coi như không cho mở thêm để an toàn
    return false;
  }

  _singleInstanceMutexHandle = handle;

  if (error == ERROR_ALREADY_EXISTS) {
    return false;
  }

  return true;
}

Future<void> writeLog(Object? message) async {
  final dir =
      Directory('${Platform.environment['LOCALAPPDATA']}\\PC_POS\\logs');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final file = File('${dir.path}\\app.log');

  await file.writeAsString(
    '[${DateTime.now()}] $message\n',
    mode: FileMode.append,
    flush: true,
  );
}

Future<WebViewEnvironment?> createWebViewEnv() async {
  try {
    final version = await WebViewEnvironment.getAvailableVersion();

    if (version == null) {
      await writeLog('WEBVIEW2 NOT INSTALLED');
      return null;
    }

    return await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder:
            '${Platform.environment['LOCALAPPDATA']}\\PC_POS\\webview',
      ),
    );
  } catch (e, s) {
    await writeLog('WEBVIEW ENV ERROR: $e');
    await writeLog(s);
    return null;
  }
}
