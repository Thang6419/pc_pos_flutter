import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pc_pos/customer.dart';
import 'package:pc_pos/printer.dart';
import 'package:pc_pos/services/app_update_service.dart';
import 'package:pc_pos/utils/common.dart';
import 'package:pc_pos/utils/contanst.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import 'utils/device_id_service.dart';

const _customerDisplayTitle = 'Customer Display';
int _customerDisplayHwndAddress = 0;

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

    if (title.toDartString() == _customerDisplayTitle) {
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
  if (args.isNotEmpty && args[0] == 'multi_window') {
    WidgetsFlutterBinding.ensureInitialized();
    // BỎ TOÀN BỘ windowManager ở đây để tránh lỗi MissingPluginException

    final windowId = args.length > 1 ? int.tryParse(args[1]) ?? -1 : -1;
    Map<String, dynamic> data = {};
    try {
      final argument = args.length > 2 && args[2].isNotEmpty ? args[2] : '{}';
      final decoded = jsonDecode(argument);
      if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      } else {
        await writeLog('CUSTOMER ENTRY ARGUMENT NOT MAP: $decoded');
      }
    } catch (e, s) {
      await writeLog('CUSTOMER ENTRY JSON ERROR: $e');
      await writeLog(s);
    }

    runApp(
      CustomerDisplayApp(
        windowId: windowId,
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
    await windowManager.setResizable(true);
    await windowManager.setMaximizable(true);
    // await windowManager.maximize();
    await windowManager.setFullScreen(true);
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

  WebViewEnvironment? env;
  InAppWebViewController? webViewController;
  bool _isOpeningSecondWindow = false;
  bool _isClosingApp = false;
  Map<String, dynamic>? _latestCustomerDisplayData;

  String? deviceId;
  bool isLoading = false;

  WindowController? secondWindow;
  int? secondWindowId;
  final Set<int> _readyCustomerDisplayWindowIds = {};

  @override
  void initState() {
    super.initState();
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'customer_display_ready') {
        final args = call.arguments;
        final windowId =
            args is Map ? int.tryParse('${args['windowId']}') : null;
        if (windowId != null) {
          _readyCustomerDisplayWindowIds.add(windowId);
        }
      }
      return null;
    });
    init();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    DesktopMultiWindow.setMethodHandler(null);
    windowManager.removeListener(this); // 3. Hủy lắng nghe khi hủy widget
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(closeApp());
  }

  Future<void> init() async {
    await writeLog('INIT WEBVIEW PAGE');

    final result = await createWebViewEnv();
    await writeLog('WEBVIEW ENV RESULT: ${result == null ? 'null' : 'ready'}');

    if (!mounted) return;

    setState(() {
      env = result;
    });
  }

  Future<String> loadDeviceId() async {
    final id = await DeviceIdService.getDeviceId();
    return id;
  }

  Future<String?> getMachineGuid() async {
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

  Future<bool> _hasSecondDisplay() async {
    final displays = await screenRetriever.getAllDisplays();
    return displays.length >= 2;
  }

  Future<void> openSecondWindow({
    Map<String, dynamic>? initialData,
    int retryAttempt = 0,
  }) async {
    if (_isOpeningSecondWindow) {
      await writeLog('OPEN SECOND WINDOW SKIPPED: already opening');
      return;
    }

    _isOpeningSecondWindow = true;

    try {
      await writeLog('OPEN SECOND WINDOW START');
      if (!await _hasSecondDisplay()) {
        await writeLog('OPEN SECOND WINDOW SKIPPED: no second display');
        secondWindow = null;
        secondWindowId = null;
        _readyCustomerDisplayWindowIds.clear();
        return;
      }

      final targetDisplay = await _getOtherDisplay();
      if (targetDisplay == null) {
        await writeLog('NO SECOND DISPLAY');
        secondWindow = null;
        secondWindowId = null;
        _readyCustomerDisplayWindowIds.clear();
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
            final isReady = await _waitForCustomerDisplayReady(secondWindowId!);
            if (isReady) {
              await writeLog('EXISTING SECOND WINDOW SHOWN');
              return;
            }

            await writeLog(
              'EXISTING SECOND WINDOW NOT READY, RECREATE: id=$secondWindowId',
            );
            await secondWindow!.close();
            _readyCustomerDisplayWindowIds.remove(secondWindowId);
            secondWindow = null;
            secondWindowId = null;
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
      _readyCustomerDisplayWindowIds.remove(window.windowId);
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

      final isReady = await _waitForCustomerDisplayReady(window.windowId);
      if (!isReady) {
        await writeLog(
          'CUSTOMER DISPLAY READY TIMEOUT: id=${window.windowId}, '
          'retryAttempt=$retryAttempt',
        );
        try {
          await window.close();
          await writeLog(
            'CUSTOMER DISPLAY STALE WINDOW CLOSED: id=${window.windowId}',
          );
        } catch (e) {
          await writeLog(
            'CUSTOMER DISPLAY STALE WINDOW CLOSE ERROR: '
            'id=${window.windowId}, error=$e',
          );
        }

        secondWindow = null;
        secondWindowId = null;
        _readyCustomerDisplayWindowIds.remove(window.windowId);

        if (retryAttempt < 2) {
          _isOpeningSecondWindow = false;
          await Future.delayed(const Duration(milliseconds: 300));
          return openSecondWindow(
            initialData: initialData,
            retryAttempt: retryAttempt + 1,
          );
        }

        await writeLog('CUSTOMER DISPLAY READY RETRY EXHAUSTED');
        return;
      }

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
    try {
      _latestCustomerDisplayData = data;

      if (!await _hasSecondDisplay()) {
        secondWindow = null;
        secondWindowId = null;
        _readyCustomerDisplayWindowIds.clear();
        return;
      }

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
      await writeLog('SEND CUSTOMER DISPLAY ERROR: $e');
    }
  }

  Future<void> showCustomerQr(String? value) async {
    final qrValue = value?.trim() ?? '';

    try {
      if (!await _hasSecondDisplay()) {
        secondWindow = null;
        secondWindowId = null;
        _readyCustomerDisplayWindowIds.clear();
        return;
      }

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
    await windowManager.maximize();
  }

  Future<void> openMinimizeWindow() async {
    await windowManager.minimize();
  }

  Future<bool> _waitForCustomerDisplayReady(int windowId) async {
    for (var i = 0; i < 30; i++) {
      if (_readyCustomerDisplayWindowIds.contains(windowId)) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return false;
  }

  Future<bool> toggleFullScreen() async {
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
      exit(0);
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

  @override
  Widget build(BuildContext context) {
    if (isLoading || env == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
                title: 'Machine GUIDS',
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
        child: InAppWebView(
          key: webViewKey,
          webViewEnvironment: env,
          initialUrlRequest: URLRequest(url: WebUri(baseUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useOnLoadResource: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
          ),
          onWebViewCreated: (controller) async {
            await writeLog('WEBVIEW CREATED');
            webViewController = controller;

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
                final value = args.isNotEmpty ? args[0]?.toString() : null;
                await showCustomerQr(value);
              },
            );
            controller.addJavaScriptHandler(
              handlerName: HandlerNames.requestDeviceId,
              callback: (args) async {
                return await getPhysicalId();
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
                final data = Map<String, dynamic>.from(args.first as Map);

                final ip = data['ip']?.toString() ?? '';
                final port = int.tryParse(data['port'].toString()) ?? 9100;
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
                final data = Map<String, dynamic>.from(args.first as Map);

                final ip = data['ip']?.toString() ?? '';
                final port = int.tryParse(data['port'].toString()) ?? 9100;
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
          },
          onReceivedError: (controller, request, error) async {
            await writeLog(
              'WEBVIEW LOAD ERROR: url=${request.url}, '
              'code=${error.type}, desc=${error.description}',
            );
          },
          onReceivedHttpError: (controller, request, errorResponse) async {
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
    );
  }
}
