import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pc_pos/customer.dart';
import 'package:pc_pos/printer.dart';
import 'package:pc_pos/services/app_update_service.dart';
import 'package:pc_pos/utils/common.dart';
import 'package:pc_pos/utils/contanst.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_win_floating/webview_win_floating.dart';

import 'utils/device_id_service.dart';

const _customerDisplayTitle = 'Customer Display';
int _customerDisplayHwndAddress = 0;

bool get _supportsWindowControls => Platform.isWindows;

int _enumCustomerDisplayWindow(Pointer hwndPointer, int lParam) {
  final hwnd = HWND(hwndPointer);
  final processId = calloc<Uint32>();
  final className = wsalloc(256);
  final title = wsalloc(256);

  try {
    GetWindowThreadProcessId(hwnd, processId);
    if (processId.value != pid) return TRUE;

    GetClassName(hwnd, className, 256);
    GetWindowText(hwnd, title, 256);

    if (className.toDartString() == 'FlutterMultiWindow' ||
        title.toDartString() == _customerDisplayTitle) {
      _customerDisplayHwndAddress = hwnd.address;
      return FALSE;
    }

    return TRUE;
  } finally {
    calloc.free(processId);
    free(className);
    free(title);
  }
}

HWND _findCustomerDisplayHwnd() {
  _customerDisplayHwndAddress = 0;
  final enumProc = Pointer.fromFunction<WNDENUMPROC>(
    _enumCustomerDisplayWindow,
    FALSE,
  );
  EnumWindows(enumProc, const LPARAM(0));
  return HWND(Pointer.fromAddress(_customerDisplayHwndAddress));
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

// WINDOW PHỤ - Flutter UI only
  if (_supportsWindowControls && args.isNotEmpty && args[0] == 'multi_window') {
    WidgetsFlutterBinding.ensureInitialized();
    // BỎ TOÀN BỘ windowManager ở đây để tránh lỗi MissingPluginException

    final argument = args.length > 2 && args[2].isNotEmpty ? args[2] : '{}';
    final data = jsonDecode(argument) as Map<String, dynamic>;
    runApp(
      CustomerDisplayApp(
        initialData: data,
      ),
    );

    return;
  }

  final ok = await ensureSingleInstance();

  if (!ok) {
    exit(0);
  }
  // WINDOW CHÍNH
  if (_supportsWindowControls) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      skipTaskbar: false,
      alwaysOnTop: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions);

    await windowManager.show();
    await windowManager.focus();
    await windowManager.setPreventClose(true);
  }

  runApp(
    MaterialApp(
      navigatorKey: appUpdateNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
      ),
      home: const WebViewPage(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future.delayed(const Duration(milliseconds: 500));
    await AppUpdateService.instance.start();
    if (_supportsWindowControls) {
      await windowManager.setResizable(true);
      await windowManager.setMaximizable(true);
      // await windowManager.maximize();
      await windowManager.setFullScreen(true);
    }
  });
}

Future<void> forceCustomerDisplayFullScreen(Display targetDisplay) async {
  if (!Platform.isWindows) return;

  final scaleFactor = (targetDisplay.scaleFactor ?? 1.0).toDouble();
  final logicalPosition = targetDisplay.visiblePosition ?? Offset.zero;
  final logicalSize = targetDisplay.size;

  final monitorPoint = calloc<POINT>();
  final monitorInfo = calloc<MONITORINFO>();

  try {
    monitorPoint.ref.x =
        (logicalPosition.dx * scaleFactor + logicalSize.width * scaleFactor / 2)
            .round();
    monitorPoint.ref.y = (logicalPosition.dy * scaleFactor +
            logicalSize.height * scaleFactor / 2)
        .round();

    final hwnd = _findCustomerDisplayHwnd();
    if (hwnd.address == 0) {
      await writeLog('CUSTOMER DISPLAY HWND NOT FOUND');
      return;
    }
    await writeLog('CUSTOMER DISPLAY HWND: ${hwnd.address}');

    final style = GetWindowLongPtr(hwnd, GWL_STYLE).value;
    SetWindowLongPtr(
      hwnd,
      GWL_STYLE,
      (style &
              ~(WS_CAPTION |
                  WS_THICKFRAME |
                  WS_MINIMIZEBOX |
                  WS_MAXIMIZEBOX |
                  WS_SYSMENU)) |
          WS_POPUP,
    );

    final exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE).value;
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle | WS_EX_TOPMOST);

    monitorInfo.ref.cbSize = sizeOf<MONITORINFO>();
    final monitor =
        MonitorFromPoint(monitorPoint.ref, MONITOR_DEFAULTTONEAREST);
    if (!GetMonitorInfo(monitor, monitorInfo)) {
      await writeLog('CUSTOMER DISPLAY MONITOR INFO FAILED');
      return;
    }

    final rect = monitorInfo.ref.rcMonitor;
    SetWindowPos(
      hwnd,
      HWND_TOPMOST,
      rect.left,
      rect.top,
      rect.right - rect.left,
      rect.bottom - rect.top,
      SWP_FRAMECHANGED,
    );
  } catch (e) {
    await writeLog('FORCE CUSTOMER DISPLAY FULLSCREEN ERROR: $e');
  } finally {
    calloc.free(monitorPoint);
    calloc.free(monitorInfo);
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> with WindowListener {
  static const String baseUrl = 'http://103.159.59.15:8082/';

  final GlobalKey webViewKey = GlobalKey();

  iaw.WebViewEnvironment? env;
  iaw.InAppWebViewController? androidWebViewController;
  WebViewController? windowsWebViewController;

  bool _isOpeningSecondWindow = false;
  bool _isClosingApp = false;
  bool _isWebViewReady = false;
  Map<String, dynamic>? _latestCustomerDisplayData;

  String? deviceId;
  bool isLoading = false;

  WindowController? secondWindow;
  int? secondWindowId;

  @override
  void initState() {
    super.initState();
    init();
    if (_supportsWindowControls) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (_supportsWindowControls) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(closeApp());
  }

  Future<void> init() async {
    await writeLog('INIT WEBVIEW PAGE');

    if (Platform.isWindows) {
      await _initWindowsWebView();
    } else {
      final result = await createWebViewEnv();
      await writeLog(
          'WEBVIEW ENV RESULT: ${result == null ? 'null' : 'ready'}');

      if (!mounted) return;

      setState(() {
        env = result;
        _isWebViewReady = true;
      });
    }
  }

  Future<void> _initWindowsWebView() async {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final userDataFolder =
        localAppData != null ? '$localAppData\\PC_POS\\WebView2' : null;

    final params = WindowsWebViewControllerCreationParams(
      userDataFolder: userDataFolder,
      profileName: 'main',
    );

    final controller = WebViewController.fromPlatformCreationParams(params);

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

    await controller.addJavaScriptChannel(
      'NativeBridge',
      onMessageReceived: (JavaScriptMessage message) async {
        await _handleWindowsNativeMessage(message.message);
      },
    );

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) async {
          await writeLog('WINDOWS WEBVIEW LOAD START: $url');
        },
        onPageFinished: (url) async {
          await writeLog('WINDOWS WEBVIEW LOAD STOP: $url');
          await _injectWindowsBridge();
        },
        onWebResourceError: (error) async {
          await writeLog(
            'WINDOWS WEBVIEW ERROR: code=${error.errorCode}, desc=${error.description}',
          );
        },
      ),
    );

    await controller.loadRequest(Uri.parse(baseUrl));

    if (!mounted) return;

    setState(() {
      windowsWebViewController = controller;
      _isWebViewReady = true;
    });
  }

  Future<void> _injectWindowsBridge() async {
    final controller = windowsWebViewController;
    if (controller == null) return;

    const js = r'''
(function () {
  if (window.__PC_POS_NATIVE_BRIDGE__) return;

  window.__PC_POS_NATIVE_BRIDGE__ = true;
  window.__nativeBridgeSeq = 0;
  window.__nativeBridgeCallbacks = {};

  window.__nativeBridgeResolve = function (id, ok, payload) {
    var cb = window.__nativeBridgeCallbacks[id];
    if (!cb) return;

    delete window.__nativeBridgeCallbacks[id];

    if (ok) {
      cb.resolve(payload);
    } else {
      cb.reject(payload);
    }
  };

  window.flutter_inappwebview = window.flutter_inappwebview || {};

  window.flutter_inappwebview.callHandler = function (handlerName) {
    var args = Array.prototype.slice.call(arguments, 1);

    return new Promise(function (resolve, reject) {
      var id = String(++window.__nativeBridgeSeq);

      window.__nativeBridgeCallbacks[id] = {
        resolve: resolve,
        reject: reject
      };

      NativeBridge.postMessage(JSON.stringify({
        id: id,
        handlerName: handlerName,
        args: args
      }));
    });
  };
})();
''';

    await controller.runJavaScript(js);
  }

  Future<dynamic> _handleNativeCall(
      String handlerName, List<dynamic> args) async {
    switch (handlerName) {
      case HandlerNames.sendToCustomerDisplay:
        final data = args.isNotEmpty && args.first is Map
            ? Map<String, dynamic>.from(args.first as Map)
            : <String, dynamic>{};

        await sendToCustomerDisplay(data);
        return {'success': true};

      case HandlerNames.showCustomerQr:
        String? value;

        if (args.isNotEmpty) {
          final first = args.first;

          if (first is Map) {
            value = first['qrContent']?.toString();
          } else {
            value = first?.toString();
          }
        }

        await showCustomerQr(value);
        return {'success': true};

      case HandlerNames.requestDeviceId:
        return await loadDeviceId();

      case HandlerNames.closeApp:
        await closeApp();
        return {'success': true};

      case HandlerNames.getPlatform:
        if (Platform.isWindows) return 'windows';
        if (Platform.isAndroid) return 'android';
        if (Platform.isIOS) return 'ios';
        if (Platform.isMacOS) return 'macos';
        if (Platform.isLinux) return 'linux';
        if (Platform.isFuchsia) return 'fuchsia';
        return 'unknown';

      case HandlerNames.toggleFullScreen:
        return await toggleFullScreen();

      case HandlerNames.openMaximumWindow:
        await openMaximumWindow();
        return {'success': true};

      case HandlerNames.openMinimizeWindow:
        await openMinimizeWindow();
        return {'success': true};

      case HandlerNames.print:
        final data = args.isNotEmpty && args.first is Map
            ? Map<String, dynamic>.from(args.first as Map)
            : <String, dynamic>{};

        final ip = data['ip']?.toString() ?? '';
        final port = int.tryParse(data['port']?.toString() ?? '') ?? 9100;
        final html = data['html']?.toString() ?? '';

        if (ip.isEmpty || html.isEmpty) {
          return {
            'success': false,
            'message': 'Thiếu ip hoặc html',
          };
        }

        final printer = HtmlReceiptPrinter(
          context: context,
          receiptWidth: 576,
          paperSize: PaperSize.mm80,
        );

        await printer.printHtml(
          ip: ip,
          port: port,
          html: html,
        );

        return {'success': true};

      case HandlerNames.printImage:
        final data = args.isNotEmpty && args.first is Map
            ? Map<String, dynamic>.from(args.first as Map)
            : <String, dynamic>{};

        final ip = data['ip']?.toString() ?? '';
        final port = int.tryParse(data['port']?.toString() ?? '') ?? 9100;
        final imageBase64 =
            data['imageBase64']?.toString() ?? data['image']?.toString() ?? '';

        if (ip.isEmpty || imageBase64.isEmpty) {
          return {
            'success': false,
            'message': 'Thiếu ip hoặc imageBase64',
          };
        }

        final printer = HtmlReceiptPrinter(
          context: context,
          receiptWidth: 576,
          paperSize: PaperSize.mm80,
        );

        await printer.printImage(
          ip: ip,
          port: port,
          imageBase64: imageBase64,
        );

        return {'success': true};

      case HandlerNames.sendBytesToNetworkPrinter:
        final data = args.isNotEmpty && args.first is Map
            ? Map<String, dynamic>.from(args.first as Map)
            : <String, dynamic>{};

        return await sendBytesToNetworkPrinter(data);

      default:
        return {
          'success': false,
          'message': 'Unknown handler: $handlerName',
        };
    }
  }

  Future<void> _handleWindowsNativeMessage(String rawMessage) async {
    String? id;

    try {
      final decoded = jsonDecode(rawMessage) as Map<String, dynamic>;

      id = decoded['id']?.toString();
      final handlerName = decoded['handlerName']?.toString() ?? '';
      final args = decoded['args'] is List
          ? List<dynamic>.from(decoded['args'] as List)
          : <dynamic>[];

      final result = await _handleNativeCall(handlerName, args);

      await _resolveWindowsCall(
        id: id,
        ok: true,
        payload: result,
      );
    } catch (e) {
      await writeLog('WINDOWS NATIVE BRIDGE ERROR: $e');

      await _resolveWindowsCall(
        id: id,
        ok: false,
        payload: {
          'success': false,
          'message': e.toString(),
        },
      );
    }
  }

  Future<void> _resolveWindowsCall({
    required String? id,
    required bool ok,
    required dynamic payload,
  }) async {
    final controller = windowsWebViewController;
    if (controller == null || id == null || id.isEmpty) return;

    final js = '''
window.__nativeBridgeResolve(
  ${jsonEncode(id)},
  $ok,
  ${jsonEncode(payload)}
);
''';

    await controller.runJavaScript(js);
  }

  void _registerAndroidHandlers(iaw.InAppWebViewController controller) {
    final handlerNames = [
      HandlerNames.sendToCustomerDisplay,
      HandlerNames.showCustomerQr,
      HandlerNames.requestDeviceId,
      HandlerNames.closeApp,
      HandlerNames.getPlatform,
      HandlerNames.toggleFullScreen,
      HandlerNames.openMaximumWindow,
      HandlerNames.openMinimizeWindow,
      HandlerNames.print,
      HandlerNames.printImage,
      HandlerNames.sendBytesToNetworkPrinter,
    ];

    for (final name in handlerNames) {
      controller.addJavaScriptHandler(
        handlerName: name,
        callback: (args) async {
          return await _handleNativeCall(name, args);
        },
      );
    }
  }

  Future<Map<String, dynamic>> sendBytesToNetworkPrinter(
    Map<String, dynamic> data,
  ) async {
    final ip = data['ip']?.toString().trim() ?? '';
    final port = int.tryParse(data['port']?.toString() ?? '') ?? 9100;
    final rawBytes = data['bytes'];

    if (ip.isEmpty) {
      return {'success': false, 'message': 'Thiếu ip'};
    }

    if (rawBytes is! List) {
      return {'success': false, 'message': 'bytes phải là mảng số'};
    }

    final bytes = <int>[];
    for (final value in rawBytes) {
      final byte = value is num ? value.toInt() : int.tryParse('$value');
      if (byte == null || byte < 0 || byte > 255) {
        return {
          'success': false,
          'message': 'bytes chỉ nhận giá trị 0-255',
        };
      }
      bytes.add(byte);
    }

    if (bytes.isEmpty) {
      return {'success': false, 'message': 'bytes rỗng'};
    }

    Socket? socket;
    try {
      await writeLog(
        'SEND BYTES TO NETWORK PRINTER START: ip=$ip, port=$port, '
        'bytes=${bytes.length}',
      );
      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      socket.add(bytes);
      await socket.flush();
      await writeLog('SEND BYTES TO NETWORK PRINTER DONE: ip=$ip');
      return {'success': true};
    } catch (e) {
      await writeLog('SEND BYTES TO NETWORK PRINTER ERROR: $e');
      return {'success': false, 'message': e.toString()};
    } finally {
      socket?.destroy();
    }
  }

  Future<String> loadDeviceId() async {
    final id = await DeviceIdService.getDeviceId();
    return id;
  }

  Future<String?> getMachineGuid() async {
    if (!Platform.isWindows) {
      return null;
    }

    final result = await Process.run(
      'powershell',
      ['(Get-CimInstance Win32_ComputerSystemProduct).UUID'],
    );

    if (result.exitCode != 0) {
      return null;
    }
    final id = result.stdout.toString().trim();
    return id;
  }

  Future<String> getPhysicalId() async {
    return await getMachineGuid() ?? await loadDeviceId();
  }

  // void _showDeviceIdAlert({String id = '', String title = 'Device ID'}) {
  //   showDialog<void>(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       title: Text(title),
  //       content: SelectableText(id),
  //       actions: [
  //         FilledButton(
  //           onPressed: () => Navigator.pop(context),
  //           child: const Text('OK'),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Future<Display?> _getOtherDisplay() async {
    if (!_supportsWindowControls) {
      await writeLog('GET OTHER DISPLAY SKIPPED: unsupported platform');
      return null;
    }

    final displays = await screenRetriever.getAllDisplays();
    await writeLog('DISPLAY COUNT: ${displays.length}');
    for (final display in displays) {
      await writeLog(
        'DISPLAY: id=${display.id}, name=${display.name}, '
        'visiblePosition=${display.visiblePosition}, size=${display.size}, '
        'visibleSize=${display.visibleSize}, scale=${display.scaleFactor}',
      );
    }

    if (displays.length < 2) return null;

    final mainBounds = await windowManager.getBounds();
    await writeLog('MAIN WINDOW BOUNDS: $mainBounds');
    final mainCenter = Offset(
      mainBounds.left + mainBounds.width / 2,
      mainBounds.top + mainBounds.height / 2,
    );

    Display? currentDisplay;

    for (final display in displays) {
      final pos = display.visiblePosition ?? Offset.zero;
      final size = display.size;

      final rect = Rect.fromLTWH(
        pos.dx,
        pos.dy,
        size.width,
        size.height,
      );

      if (rect.contains(mainCenter)) {
        currentDisplay = display;
        break;
      }
    }

    if (currentDisplay == null) {
      await writeLog('CURRENT DISPLAY NOT FOUND, FALLBACK DISPLAY[1]');
      return displays[1];
    }

    final otherDisplay = displays.firstWhere(
      (display) => display.id != currentDisplay!.id,
      orElse: () => displays[1],
    );
    await writeLog(
        'CURRENT DISPLAY: ${currentDisplay.id}, OTHER DISPLAY: ${otherDisplay.id}');
    return otherDisplay;
  }

  Future<void> openSecondWindow({
    Map<String, dynamic>? initialData,
  }) async {
    if (!_supportsWindowControls) {
      await writeLog('OPEN SECOND WINDOW SKIPPED: unsupported platform');
      return;
    }

    if (_isOpeningSecondWindow) {
      await writeLog('OPEN SECOND WINDOW SKIPPED: already opening');
      return;
    }

    _isOpeningSecondWindow = true;

    try {
      await writeLog('OPEN SECOND WINDOW START');
      final targetDisplay = await _getOtherDisplay();
      if (targetDisplay == null) {
        await writeLog('NO SECOND DISPLAY');
        return;
      }
      await writeLog(
        'TARGET DISPLAY: id=${targetDisplay.id}, name=${targetDisplay.name}, '
        'visiblePosition=${targetDisplay.visiblePosition}, '
        'size=${targetDisplay.size}, visibleSize=${targetDisplay.visibleSize}, '
        'scale=${targetDisplay.scaleFactor}',
      );

      if (secondWindowId != null) {
        final subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
        await writeLog(
            'EXISTING SECOND WINDOW: id=$secondWindowId, subWindows=$subWindowIds');
        if (subWindowIds.contains(secondWindowId)) {
          try {
            await secondWindow!.show();
            await Future.delayed(const Duration(milliseconds: 300));
            await forceCustomerDisplayFullScreen(targetDisplay);
            await writeLog('EXISTING SECOND WINDOW SHOWN');
            return;
          } catch (e) {
            await writeLog('EXISTING SECOND WINDOW SHOW ERROR: $e');
            secondWindow = null;
            secondWindowId = null;
          }
        }
      }

      // 1. Lấy vị trí và kích thước gốc của màn hình phụ
      final pos = targetDisplay.visiblePosition ?? Offset.zero;
      final size = targetDisplay.size;
      final scaleFactor = (targetDisplay.scaleFactor ?? 1.0).toDouble();
      final frame = Rect.fromLTWH(
        pos.dx * scaleFactor,
        pos.dy * scaleFactor,
        size.width * scaleFactor,
        size.height * scaleFactor,
      );
      await writeLog('CREATE SECOND WINDOW FRAME: $frame SCALE: $scaleFactor');

      final window = await DesktopMultiWindow.createWindow(
        jsonEncode({
          'type': 'customer_display',
          'data': initialData ?? {},
        }),
      );
      await writeLog('SECOND WINDOW CREATED: id=${window.windowId}');
      await window.setTitle('Customer Display');

      setState(() {
        secondWindow = window;
        secondWindowId = window.windowId;
      });

      await window.setFrame(frame);
      await writeLog('SECOND WINDOW SET FRAME DONE');

      await window.show();
      await writeLog('SECOND WINDOW SHOW DONE');

      await Future.delayed(const Duration(milliseconds: 300));
      await forceCustomerDisplayFullScreen(targetDisplay);
      await Future.delayed(const Duration(milliseconds: 300));
      await forceCustomerDisplayFullScreen(targetDisplay);
      await Future.delayed(const Duration(milliseconds: 700));

      await writeLog(
          'SECOND WINDOW FULLSCREEN FRAME: $frame SCALE: $scaleFactor');
    } catch (e) {
      await writeLog('OPEN SECOND WINDOW ERROR: $e');
    } finally {
      _isOpeningSecondWindow = false;
    }
  }

  Future<void> sendToCustomerDisplay(Map<String, dynamic> data) async {
    if (!_supportsWindowControls) {
      await writeLog('SEND TO CUSTOMER DISPLAY SKIPPED: unsupported platform');
      return;
    }

    try {
      _latestCustomerDisplayData = data;

      if (_isOpeningSecondWindow) return;

      if (secondWindowId == null ||
          !(await DesktopMultiWindow.getAllSubWindowIds())
              .contains(secondWindowId)) {
        await openSecondWindow();
      }

      if (secondWindowId == null) return;

      final latest = _latestCustomerDisplayData;
      if (latest == null) return;

      await DesktopMultiWindow.invokeMethod(
        secondWindowId!,
        'update_customer_display',
        jsonEncode(latest),
      );
    } catch (e) {
      await writeLog('SEND TO CUSTOMER DISPLAY ERROR: $e');
    }
  }

  Future<void> showCustomerQr(String? value) async {
    if (!_supportsWindowControls) {
      await writeLog('SHOW CUSTOMER QR SKIPPED: unsupported platform');
      return;
    }

    final qrValue = value?.trim() ?? '';

    try {
      if (qrValue.isNotEmpty &&
          (secondWindowId == null ||
              !(await DesktopMultiWindow.getAllSubWindowIds())
                  .contains(secondWindowId))) {
        await openSecondWindow();
      }

      if (secondWindowId == null) return;

      await DesktopMultiWindow.invokeMethod(
        secondWindowId!,
        'show_customer_qr',
        qrValue,
      );
    } catch (e) {
      await writeLog('SHOW CUSTOMER QR ERROR: $e');
    }
  }

  Future<void> openMaximumWindow() async {
    if (!_supportsWindowControls) return;
    await windowManager.maximize();
  }

  Future<void> openMinimizeWindow() async {
    if (!_supportsWindowControls) return;
    await windowManager.minimize();
  }

  Future<bool> toggleFullScreen() async {
    if (!_supportsWindowControls) return false;

    bool isFull = await windowManager.isFullScreen();
    if (isFull) {
      await windowManager.setFullScreen(false);
    } else {
      await windowManager.setFullScreen(!isFull);
    }
    return await windowManager.isFullScreen();
  }

  Future<void> closeApp() async {
    // Hàm này sẽ đóng cửa sổ ứng dụng ngay lập tức
    if (_isClosingApp) return;
    _isClosingApp = true;

    await writeLog('APP CLOSE START');

    try {
      if (!_supportsWindowControls) {
        androidWebViewController = null;
        windowsWebViewController = null;
        await SystemNavigator.pop();
        return;
      }

      windowManager.removeListener(this);

      final subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
      await writeLog('APP CLOSE SUB WINDOWS: $subWindowIds');

      for (final id in subWindowIds) {
        try {
          await WindowController.fromWindowId(id).close();
          await writeLog('APP CLOSE SUB WINDOW DONE: $id');
        } catch (e) {
          await writeLog('APP CLOSE SUB WINDOW ERROR: id=$id, error=$e');
        }
      }

      secondWindow = null;
      secondWindowId = null;

      await Future.delayed(const Duration(milliseconds: 300));
      await writeLog('APP CLOSE PROCESS EXIT');
      exit(0);
    } catch (e) {
      await writeLog('APP CLOSE ERROR: $e');
      if (_supportsWindowControls) {
        exit(0);
      }
    }
  }

  // Future<void> _printViaPureSocket({
  //   required String ip,
  //   required String html,
  //   int port = 9100,
  // }) async {
  //   final printer = HtmlReceiptPrinter(
  //     context: context,
  //     receiptWidth: 576,
  //     paperSize: PaperSize.mm80,
  //   );

  //   await printer.printHtml(
  //     html: html,
  //     ip: ip,
  //     port: port,
  //   );
  // }

  Widget _buildWindowsWebView() {
    final controller = windowsWebViewController;

    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return WebViewWidget(controller: controller);
  }

  Widget _buildAndroidWebView() {
    return iaw.InAppWebView(
      key: webViewKey,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(
          () => EagerGestureRecognizer(),
        ),
      },
      webViewEnvironment: env,
      initialUrlRequest: iaw.URLRequest(url: iaw.WebUri(baseUrl)),
      initialSettings: iaw.InAppWebViewSettings(
        javaScriptEnabled: true,
        useOnLoadResource: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
      ),
      onWebViewCreated: (controller) async {
        await writeLog('ANDROID WEBVIEW CREATED');

        androidWebViewController = controller;
        _registerAndroidHandlers(controller);
      },
      onLoadStart: (controller, url) async {
        await writeLog('ANDROID WEBVIEW LOAD START: $url');
      },
      onLoadStop: (controller, url) async {
        await writeLog('ANDROID WEBVIEW LOAD STOP: $url');
      },
      onReceivedError: (controller, request, error) async {
        await writeLog(
          'ANDROID WEBVIEW LOAD ERROR: url=${request.url}, '
          'code=${error.type}, desc=${error.description}',
        );
      },
      onReceivedHttpError: (controller, request, errorResponse) async {
        await writeLog(
          'ANDROID WEBVIEW HTTP ERROR: url=${request.url}, '
          'status=${errorResponse.statusCode}, '
          'reason=${errorResponse.reasonPhrase}',
        );
      },
      onConsoleMessage: (controller, consoleMessage) async {
        await writeLog(
          'ANDROID WEBVIEW CONSOLE: ${consoleMessage.messageLevel} '
          '${consoleMessage.message}',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || !_isWebViewReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Platform.isWindows
            ? _buildWindowsWebView()
            : _buildAndroidWebView(),
      ),
    );
  }
}
