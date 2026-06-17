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
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pc_pos/customer.dart';
import 'package:pc_pos/printer.dart';
import 'package:pc_pos/services/app_update_service.dart';
import 'package:pc_pos/utils/common.dart';
import 'package:pc_pos/utils/contanst.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart'
    as wv;
import 'package:webview_win_floating/webview.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

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
  final FocusScopeNode _webViewFocusScopeNode = FocusScopeNode(
    debugLabel: 'pc_pos_webview_scope',
  );
  final FocusNode _webViewFocusNode = FocusNode(debugLabel: 'pc_pos_webview');

  WebViewEnvironment? env;
  InAppWebViewController? webViewController;
  WinWebViewController? _windowsWebViewController;
  bool _isOpeningSecondWindow = false;
  bool _isClosingApp = false;
  bool _isWebViewReady = false;
  bool _useWindowsWebView = false;
  String? _windowsWebViewError;
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
    _webViewFocusNode.dispose();
    _webViewFocusScopeNode.dispose();
    unawaited(_windowsWebViewController?.dispose());
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(closeApp());
  }

  Future<void> init() async {
    await writeLog('INIT WEBVIEW PAGE');

    if (_supportsWindowControls) {
      await _initWindowsWebView();
      return;
    }

    await _initInAppWebView();
  }

  Future<void> _initInAppWebView() async {
    final result = Platform.isWindows ? await createWebViewEnv() : null;
    await writeLog('WEBVIEW ENV RESULT: ${result == null ? 'null' : 'ready'}');

    if (!mounted) return;

    setState(() {
      env = result;
      _useWindowsWebView = false;
      _windowsWebViewError = null;
      _isWebViewReady = true;
    });
  }

  Future<void> _initWindowsWebView() async {
    final controller = WinWebViewController();
    _windowsWebViewController = controller;

    try {
      await writeLog('INIT WEBVIEW_WIN_FLOATING START');
      await controller.setJavaScriptMode(wv.JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'pcPosWindowsBridge',
        callback: (message) {
          unawaited(_handleWindowsWebMessage(message.message));
        },
      );
      await controller.setNavigationDelegate(
        WinNavigationDelegate(
          onPageStarted: (url) {
            unawaited(writeLog('WEBVIEW_WIN_FLOATING LOAD START: $url'));
          },
          onPageFinished: (url) {
            unawaited(writeLog('WEBVIEW_WIN_FLOATING LOAD STOP: $url'));
            unawaited(_requestWebViewFocus());
            unawaited(_injectWindowsBridge());
            unawaited(_injectWindowsTouchInputFocusFix());
          },
          onWebResourceError: (error) {
            unawaited(
              writeLog(
                'WEBVIEW_WIN_FLOATING LOAD ERROR: '
                'url=${error.url}, code=${error.errorCode}, '
                'desc=${error.description}',
              ),
            );
          },
        ),
      );
      await controller.loadRequest(Uri.parse(baseUrl));
      await writeLog('WEBVIEW_WIN_FLOATING READY');
    } catch (e, s) {
      await writeLog('WEBVIEW_WIN_FLOATING INIT ERROR: $e');
      await writeLog(s);
      if (!mounted) return;
      setState(() {
        env = null;
        _useWindowsWebView = true;
        _windowsWebViewError = e.toString();
        _isWebViewReady = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      env = null;
      _useWindowsWebView = true;
      _windowsWebViewError = null;
      _isWebViewReady = true;
    });
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

  void _showDeviceIdAlert({String id = '', String title = 'Device ID'}) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(id),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

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
      print('PRINTERRRssssssssssssssssss: $e');
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
      await writeLog('SEND TO CUSTOMER DISPLAY START: ${jsonEncode(data)}');
      _latestCustomerDisplayData = data;

      if (_isOpeningSecondWindow) {
        await writeLog('SEND TO CUSTOMER DISPLAY WAIT: window is opening');
        return;
      }

      if (secondWindowId == null ||
          !(await DesktopMultiWindow.getAllSubWindowIds())
              .contains(secondWindowId)) {
        await openSecondWindow();
      }

      if (secondWindowId == null) {
        await writeLog('SEND TO CUSTOMER DISPLAY SKIPPED: no second window');
        return;
      }

      final latest = _latestCustomerDisplayData;
      if (latest == null) {
        await writeLog('SEND TO CUSTOMER DISPLAY SKIPPED: no latest data');
        return;
      }

      await DesktopMultiWindow.invokeMethod(
        secondWindowId!,
        'update_customer_display',
        jsonEncode(latest),
      );
      await writeLog('SEND TO CUSTOMER DISPLAY DONE: window=$secondWindowId');
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
        webViewController = null;
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
      webViewController = null;

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

  Future<void> _printViaPureSocket({
    required String ip,
    required String html,
    int port = 9100,
  }) async {
    final printer = HtmlReceiptPrinter(
      context: context,
      receiptWidth: 576,
      paperSize: PaperSize.mm80,
    );

    await printer.printHtml(
      html: html,
      ip: ip,
      port: port,
    );
  }

  String get _windowsTouchInputFocusFixScript => r"""
    (function() {
      function forceFocus(e) {
        if (!e.target || !e.target.tagName) return;
        var tagName = e.target.tagName.toUpperCase();
        if (tagName === 'INPUT' || tagName === 'TEXTAREA') {
          setTimeout(function() {
            e.target.focus();
            var val = e.target.value;
            e.target.value = '';
            e.target.value = val;
          }, 30);
        }
      }

      if (window.__pcPosTouchInputFocusFixInstalled) return;
      window.__pcPosTouchInputFocusFixInstalled = true;
      document.addEventListener('touchstart', forceFocus, true);
      document.addEventListener('pointerdown', forceFocus, true);
      document.addEventListener('mousedown', forceFocus, true);
    })();
  """;

  String get _windowsBridgeScript => r"""
    (function() {
      if (window.__pcPosWindowsBridgeInstalled) return;
      window.__pcPosWindowsBridgeInstalled = true;

      var callbacks = {};
      window.addEventListener('__pcPosHandlerResult', function(event) {
        var detail = event.detail || {};
        var callback = callbacks[detail.id];
        if (!callback) return;
        delete callbacks[detail.id];
        if (detail.error) {
          callback.reject(detail.error);
        } else {
          callback.resolve(detail.result);
        }
      });

      window.flutter_inappwebview = window.flutter_inappwebview || {};
      window.flutter_inappwebview.callHandler = function(handlerName) {
        var args = Array.prototype.slice.call(arguments, 1);
        var id = Date.now().toString(36) + Math.random().toString(36).slice(2);
        return new Promise(function(resolve, reject) {
          callbacks[id] = { resolve: resolve, reject: reject };
          if (!window.pcPosWindowsBridge || !window.pcPosWindowsBridge.postMessage) {
            delete callbacks[id];
            reject('pcPosWindowsBridge is not available');
            return;
          }
          window.pcPosWindowsBridge.postMessage(JSON.stringify({
            __pcPosHandler: true,
            id: id,
            handlerName: handlerName,
            args: args
          }));
        });
      };
    })();
  """;

  Future<void> _injectWindowsBridge() async {
    final controller = _windowsWebViewController;
    if (controller == null) return;
    try {
      await controller.runJavaScript(_windowsBridgeScript);
    } catch (e) {
      await writeLog('INJECT WINDOWS BRIDGE ERROR: $e');
    }
  }

  Future<void> _injectWindowsTouchInputFocusFix() async {
    final controller = _windowsWebViewController;
    if (controller == null) return;
    try {
      await controller.runJavaScript(_windowsTouchInputFocusFixScript);
    } catch (e) {
      await writeLog('INJECT WINDOWS TOUCH INPUT FOCUS FIX ERROR: $e');
    }
  }

  Future<void> _injectTouchInputFocusFix(
    InAppWebViewController controller,
  ) async {
    try {
      await controller.evaluateJavascript(source: """
    function forceFocus(e) {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
        // Tạo một khoảng delay cực ngắn để đợi hệ thống blur xong thì mình focus lại
        setTimeout(() => {
          e.target.focus();
          // Thử thêm dòng này để ép con trỏ chuột/touch nhảy vào cuối text
          let val = e.target.value;
          e.target.value = '';
          e.target.value = val;
        }, 30);
      }
    }

    // Lắng nghe cả 3 loại sự kiện touch/pointer của Windows
    document.addEventListener('touchstart', forceFocus, true);
    document.addEventListener('pointerdown', forceFocus, true);
    document.addEventListener('mousedown', forceFocus, true);
  """);
    } catch (e) {
      await writeLog('INJECT TOUCH INPUT FOCUS FIX ERROR: $e');
    }
  }

  Future<void> _requestWebViewFocus([Offset? localPosition]) async {
    _webViewFocusNode.requestFocus();
    final windowsController = _windowsWebViewController;
    if (_supportsWindowControls && windowsController != null) {
      try {
        await windowsController.requestFocus();
        await windowsController.runJavaScript("""
          (function() {
            var element = document.activeElement;
            if (element && element.focus) element.focus();
          })();
        """);
      } catch (e) {
        await writeLog('WEBVIEW_WINDOWS REQUEST FOCUS ERROR: $e');
      }
      return;
    }

    final controller = webViewController;
    if (controller == null) return;

    try {
      final focusScript = localPosition == null
          ? """
            (function() {
              var element = document.activeElement;
              if (element && element.focus) element.focus();
            })();
          """
          : """
            (function() {
              var element = document.elementFromPoint(
                ${localPosition.dx.toStringAsFixed(2)},
                ${localPosition.dy.toStringAsFixed(2)}
              );
              if (!element) return;

              var focusTarget = element.closest
                ? element.closest('input, textarea, [contenteditable="true"]')
                : element;

              if (focusTarget && focusTarget.focus) {
                setTimeout(function() {
                  focusTarget.focus();
                }, 0);
              }
            })();
          """;

      await controller.evaluateJavascript(source: focusScript);
    } catch (e) {
      await writeLog('WEBVIEW REQUEST FOCUS ERROR: $e');
    }
  }

  Future<void> _handleWindowsWebMessage(dynamic rawMessage) async {
    await writeLog('WEBVIEW_WIN_FLOATING MESSAGE: $rawMessage');
    final message = rawMessage is String ? jsonDecode(rawMessage) : rawMessage;
    if (message is! Map || message['__pcPosHandler'] != true) return;

    final id = message['id']?.toString();
    final handlerName = message['handlerName']?.toString();
    final args = message['args'] is List ? message['args'] as List : const [];

    dynamic result;
    Object? error;

    try {
      switch (handlerName) {
        case HandlerNames.sendToCustomerDisplay:
          final data = args.isNotEmpty && args.first is Map
              ? Map<String, dynamic>.from(args.first as Map)
              : <String, dynamic>{};
          await sendToCustomerDisplay(data);
          result = true;
          break;
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
          result = true;
          break;
        case HandlerNames.requestDeviceId:
          result = await loadDeviceId();
          break;
        case HandlerNames.closeApp:
          await closeApp();
          result = true;
          break;
        case HandlerNames.getPlatform:
          result = _platformName();
          break;
        case HandlerNames.toggleFullScreen:
          result = await toggleFullScreen();
          break;
        case HandlerNames.openMaximumWindow:
          await openMaximumWindow();
          result = true;
          break;
        case HandlerNames.openMinimizeWindow:
          await openMinimizeWindow();
          result = true;
          break;
        case HandlerNames.print:
          result = await _handlePrintArgs(args);
          break;
        case HandlerNames.printImage:
          result = await _handlePrintImageArgs(args);
          break;
        default:
          result = null;
      }
    } catch (e) {
      error = e;
      await writeLog('WEBVIEW_WINDOWS HANDLER ERROR: $handlerName $e');
    }

    if (id != null) {
      await _sendWindowsHandlerResult(id: id, result: result, error: error);
    }
  }

  Future<void> _sendWindowsHandlerResult({
    required String id,
    dynamic result,
    Object? error,
  }) async {
    final controller = _windowsWebViewController;
    if (controller == null) return;

    final payload = jsonEncode({
      'id': id,
      'result': result,
      'error': error?.toString(),
    });
    final script = """
      window.dispatchEvent(new CustomEvent('__pcPosHandlerResult', {
        detail: $payload
      }));
    """;
    await controller.runJavaScript(script);
  }

  String _platformName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isFuchsia) return 'fuchsia';
    return 'unknown';
  }

  Future<Map<String, dynamic>> _handlePrintArgs(List args) async {
    final data = Map<String, dynamic>.from(args.first as Map);
    final ip = data['ip']?.toString() ?? '';
    final port = int.tryParse(data['port'].toString()) ?? 9100;
    final html = data['html']?.toString() ?? '';

    if (ip.isEmpty || html.isEmpty) {
      return {'success': false, 'message': 'Thiếu ip hoặc html'};
    }

    final printer = HtmlReceiptPrinter(
      context: context,
      receiptWidth: 576,
      paperSize: PaperSize.mm80,
    );

    await printer.printHtml(ip: ip, port: port, html: html);
    return {'success': true};
  }

  Future<Map<String, dynamic>> _handlePrintImageArgs(List args) async {
    final data = Map<String, dynamic>.from(args.first as Map);
    final ip = data['ip']?.toString() ?? '';
    final port = int.tryParse(data['port'].toString()) ?? 9100;
    final imageBase64 =
        data['imageBase64']?.toString() ?? data['image']?.toString() ?? '';

    if (ip.isEmpty || imageBase64.isEmpty) {
      return {'success': false, 'message': 'Thiếu ip hoặc imageBase64'};
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
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || !_isWebViewReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_supportsWindowControls && _windowsWebViewError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Windows WebView init failed',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _windowsWebViewError!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _isWebViewReady = false;
                      _windowsWebViewError = null;
                    });
                    unawaited(_initWindowsWebView());
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'print_test',
            onPressed: () => _printViaPureSocket(
              ip: '192.168.0.240', // Replace with actual IP
              html: ReceiptTemplate.receiptHtml, // Replace with actual HTML
            ),
            child: const Icon(Icons.print),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'open_second_window',
            onPressed: () => openSecondWindow(),
            child: const Icon(Icons.open_in_new),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'toggle_fullscreen',
            onPressed: () => toggleFullScreen(),
            child: const Icon(Icons.fullscreen),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'close_app',
            onPressed: () => closeApp(),
            child: const Icon(Icons.close),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'get_machine_guid',
            onPressed: () async {
              _showDeviceIdAlert(
                id: await getMachineGuid() ?? "Unknown Machine GUID",
                title: 'Machine GUIDS555',
              );
            },
            child: const Icon(Icons.memory),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'load_device_id',
            onPressed: () async {
              _showDeviceIdAlert(
                id: await loadDeviceId(),
                title: 'Device ID',
              );
            },
            child: const Icon(Icons.device_hub),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'show_qr',
            onPressed: () async {
              showCustomerQr('https://example.com');
            },
            child: const Icon(Icons.qr_code),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'close_qr',
            onPressed: () async {
              showCustomerQr('');
            },
            child: const Icon(Icons.qr_code),
          ),
        ],
      ),
      body: SafeArea(
        child: FocusScope(
          node: _webViewFocusScopeNode,
          autofocus: true,
          child: Focus(
            autofocus: true,
            canRequestFocus: true,
            descendantsAreFocusable: true,
            descendantsAreTraversable: true,
            focusNode: _webViewFocusNode,
            child: _supportsWindowControls || _useWindowsWebView
                ? WinWebViewWidget(controller: _windowsWebViewController!)
                : InAppWebView(
                    key: webViewKey,
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                    webViewEnvironment: _supportsWindowControls ? env : null,
                    initialUrlRequest: URLRequest(url: WebUri(baseUrl)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      useOnLoadResource: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                    ),
                    onWebViewCreated: (controller) async {
                      await writeLog('WEBVIEW CREATED');
                      webViewController = controller;
                      await _requestWebViewFocus();

                      controller.addJavaScriptHandler(
                        handlerName: HandlerNames.sendToCustomerDisplay,
                        callback: (args) async {
                          final data = args.isNotEmpty ? args[0] : {};
                          await sendToCustomerDisplay(data);
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: HandlerNames.showCustomerQr,
                        callback: (args) async {
                          String? value;
                          if (args.isNotEmpty) {
                            final first = args[0];
                            if (first is Map) {
                              value = first['qrContent']?.toString();
                            } else {
                              value = first?.toString();
                            }
                          }
                          await showCustomerQr(value);
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: HandlerNames.requestDeviceId,
                        callback: (args) async {
                          return await loadDeviceId();
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: HandlerNames.closeApp,
                        callback: (args) async {
                          await closeApp();
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: HandlerNames.getPlatform,
                        callback: (args) async {
                          if (Platform.isWindows) return 'windows';
                          if (Platform.isAndroid) return 'android';
                          if (Platform.isIOS) return 'ios';
                          if (Platform.isMacOS) return 'macos';
                          if (Platform.isLinux) return 'linux';
                          if (Platform.isFuchsia) return 'fuchsia';
                          return 'unknown';
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: HandlerNames.toggleFullScreen,
                        callback: (args) async {
                          return await toggleFullScreen();
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: HandlerNames.openMaximumWindow,
                        callback: (args) async {
                          return await openMaximumWindow();
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: HandlerNames.openMinimizeWindow,
                        callback: (args) async {
                          return await openMinimizeWindow();
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: HandlerNames.print,
                        callback: (args) async {
                          final data =
                              Map<String, dynamic>.from(args.first as Map);

                          final ip = data['ip']?.toString() ?? '';
                          final port =
                              int.tryParse(data['port'].toString()) ?? 9100;
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

                          return {
                            'success': true,
                          };
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: HandlerNames.printImage,
                        callback: (args) async {
                          final data =
                              Map<String, dynamic>.from(args.first as Map);

                          final ip = data['ip']?.toString() ?? '';
                          final port =
                              int.tryParse(data['port'].toString()) ?? 9100;
                          final imageBase64 = data['imageBase64']?.toString() ??
                              data['image']?.toString() ??
                              '';

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

                          return {
                            'success': true,
                          };
                        },
                      );
                    },
                    onLoadStart: (controller, url) async {
                      await writeLog('WEBVIEW LOAD START: $url');
                    },
                    onLoadStop: (controller, url) async {
                      await writeLog('WEBVIEW LOAD STOP: $url');
                      await _requestWebViewFocus();
                      await _injectTouchInputFocusFix(controller);
                    },
                    onReceivedError: (controller, request, error) async {
                      await writeLog(
                        'WEBVIEW LOAD ERROR: url=${request.url}, '
                        'code=${error.type}, desc=${error.description}',
                      );
                    },
                    onReceivedHttpError:
                        (controller, request, errorResponse) async {
                      await writeLog(
                        'WEBVIEW HTTP ERROR: url=${request.url}, '
                        'status=${errorResponse.statusCode}, '
                        'reason=${errorResponse.reasonPhrase}',
                      );
                    },
                    onConsoleMessage: (controller, consoleMessage) async {
                      await writeLog(
                        'WEBVIEW CONSOLE: ${consoleMessage.messageLevel} '
                        '${consoleMessage.message}',
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
