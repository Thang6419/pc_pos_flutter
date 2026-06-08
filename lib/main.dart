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
  if (args.isNotEmpty && args[0] == 'multi_window') {
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
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    skipTaskbar: false,
    alwaysOnTop: false,
  );

  await windowManager.waitUntilReadyToShow(windowOptions);

  await windowManager.show();
  await windowManager.focus();

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
      ),
      home: const WebViewPage(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future.delayed(const Duration(milliseconds: 500));
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
  Map<String, dynamic>? _latestCustomerDisplayData;

  String? deviceId;
  bool isLoading = false;

  WindowController? secondWindow;
  int? secondWindowId;

  @override
  void initState() {
    super.initState();
    init();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this); // 3. Hủy lắng nghe khi hủy widget
    super.dispose();
  }

  @override
  @override
  void onWindowClose() async {
    if (secondWindowId != null) {
      // Lấy danh sách các window phụ đang chạy
      final subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
      // Nếu ID lưu trữ không còn nằm trong danh sách subWindowIds nữa tức là đã bị user tắt
      if (!subWindowIds.contains(secondWindowId)) {
        setState(() {
          secondWindow = null;
          secondWindowId = null;
        });
        await writeLog('SECOND WINDOW CLOSED BY USER - RESET STATE');
      }
    }
  }

  Future<void> init() async {
    await writeLog('INIT WEBVIEW PAGE');

    final result = await createWebViewEnv();

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

  Future<void> openSecondWindow({
    Map<String, dynamic>? initialData,
  }) async {
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
      print('gfdfgdfgdfgdfgdfgdfg: $e');
    }
  }

  Future<void> openMaximumWindow() async {
    await windowManager.maximize();
  }

  Future<void> openMinimizeWindow() async {
    await windowManager.minimize();
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
    await windowManager.close();
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
                title: 'Machine GUID',
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
          onWebViewCreated: (controller) {
            webViewController = controller;

            controller.addJavaScriptHandler(
              handlerName: HandlerNames.sendToCustomerDisplay,
              callback: (args) async {
                final data = args.isNotEmpty ? args[0] : {};
                await sendToCustomerDisplay(data);
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
          },
        ),
      ),
    );
  }
}
