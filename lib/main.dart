import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pc_pos/customer.dart';
import 'package:pc_pos/printer.dart';
import 'package:pc_pos/utils/common.dart';
import 'package:pc_pos/utils/contanst.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'utils/device_id_service.dart';

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

    if (displays.length < 2) return null;

    final mainBounds = await windowManager.getBounds();
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
      return displays[1];
    }

    return displays.firstWhere(
      (display) => display.id != currentDisplay!.id,
      orElse: () => displays[1],
    );
  }

  Future<void> openSecondWindow({
    Map<String, dynamic>? initialData,
  }) async {
    if (_isOpeningSecondWindow) return;

    _isOpeningSecondWindow = true;

    try {
      if (secondWindowId != null) {
        final subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
        if (subWindowIds.contains(secondWindowId)) {
          try {
            await secondWindow!.show();
            return;
          } catch (_) {
            secondWindow = null;
            secondWindowId = null;
          }
        }
      }

      final targetDisplay = await _getOtherDisplay();
      if (targetDisplay == null) {
        await writeLog('NO SECOND DISPLAY');
        return;
      }

      // 1. Lấy vị trí và kích thước gốc của màn hình phụ
      final pos = targetDisplay.visiblePosition ?? Offset.zero;
      final size = targetDisplay.size;

      // 2. Lấy tỉ lệ Scale (DPI) thực tế của màn hình phụ (Mặc định là 1.0 nếu lỗi)
// Thêm .toDouble() vào cuối để ép kiểu sang double một cách an toàn
      final double scaleFactor = (targetDisplay.scaleFactor ?? 1.0).toDouble();
      // 3. Tính toán bù trừ phần hụt (Do thanh Titlebar ẩn kích thước khoảng 32px-40px)
      // Nếu màn hình bị scale, ta phải chia tọa độ cho scaleFactor để ép Windows kéo dãn đúng tỉ lệ
      final double titleBarHeight =
          40.0; // Tăng lên 40px để che triệt để thanh tiêu đề
      final double extraEdge =
          8.0; // Phần rìa bóng ẩn của Windows (Drop Shadow border)

      final frame = Rect.fromLTWH(
        pos.dx - extraEdge, // Tràn sang trái một chút để khít viền
        pos.dy -
            titleBarHeight, // Đẩy hẳn thanh tiêu đề lên trên out khỏi màn hình
        size.width + (extraEdge * 2), // Bù chiều rộng tràn sang 2 bên
        size.height +
            titleBarHeight +
            extraEdge, // Bù chiều cao để đẩy sát xuống đáy màn hình
      );

      final window = await DesktopMultiWindow.createWindow(
        jsonEncode({
          'type': 'customer_display',
          'data': initialData ?? {},
        }),
      );
      await window.setTitle('Customer Display');

      setState(() {
        secondWindow = window;
        secondWindowId = window.windowId;
      });

      // 4. Áp khung hình chuẩn đã tính toán
      await window.setFrame(frame);

      // 5. Hiển thị màn hình phụ
      await window.show();

      await Future.delayed(const Duration(seconds: 1));

      await writeLog(
          'SECOND WINDOW FORCED FULLSCREEN WITH SCALE: $scaleFactor');
    } catch (e) {
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
