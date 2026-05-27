import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pc_pos/printer.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'device_id_service.dart';

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
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewPage(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future.delayed(const Duration(milliseconds: 500));
    await windowManager.setResizable(true);
    await windowManager.setMaximizable(true);
    await windowManager.maximize();
    await windowManager.setFullScreen(true);

    await Future.delayed(const Duration(milliseconds: 500));
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
    _showDeviceIdAlert(id);
    return id;
  }

  void _showDeviceIdAlert(String id) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device ID'),
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

    setState(() {
      secondWindow = window;
      secondWindowId = window.windowId;
    });

    // 4. Áp khung hình chuẩn đã tính toán
    await window.setFrame(frame);

    // 5. Hiển thị màn hình phụ
    await window.show();

    await writeLog('SECOND WINDOW FORCED FULLSCREEN WITH SCALE: $scaleFactor');
  }

  Future<void> sendToCustomerDisplay(Map<String, dynamic> data) async {
    if (secondWindowId == null) {
      await openSecondWindow(initialData: data);
      return;
    }

    try {
      await DesktopMultiWindow.invokeMethod(
        secondWindowId!,
        'update_customer_display',
        data,
      );
    } catch (_) {
      secondWindow = null;
      secondWindowId = null;
      await openSecondWindow(initialData: data);
    }
  }

  Future<void> toggleFullScreen() async {
    // 1. Kiểm tra xem hiện tại có đang fullscreen không
    await windowManager.maximize();

    bool isFull = await windowManager.isFullScreen();

    // 2. Set trạng thái ngược lại
    if (isFull) {
      await windowManager.setFullScreen(false);
    } else {
      await windowManager.setFullScreen(!isFull);
    }
  }

  Future<void> closeApp() async {
    // Hàm này sẽ đóng cửa sổ ứng dụng ngay lập tức
    await windowManager.close();
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
          const PrinterFloatingAction(),
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
            heroTag: 'load_device_id',
            onPressed: () => loadDeviceId(),
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
              handlerName: 'sendToCustomerDisplay',
              callback: (args) async {
                if (args.isEmpty) return {'ok': false};

                final data = Map<String, dynamic>.from(args.first as Map);

                await sendToCustomerDisplay(data);

                return {'ok': true};
              },
            );

            writeLog('WEBVIEW CREATED');
          },
        ),
      ),
    );
  }
}

class CustomerDisplayApp extends StatefulWidget {
  final Map<String, dynamic> initialData;

  const CustomerDisplayApp({
    super.key,
    required this.initialData,
  });

  @override
  State<CustomerDisplayApp> createState() => _CustomerDisplayAppState();
}

class _CustomerDisplayAppState extends State<CustomerDisplayApp> {
  Map<String, dynamic> data = {};

  @override
  void initState() {
    super.initState();

    data = Map<String, dynamic>.from(widget.initialData['data'] ?? {});

    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'update_customer_display') {
        setState(() {
          data = Map<String, dynamic>.from(call.arguments as Map);
        });
      }

      return null;
    });
  }

  List<Map<String, dynamic>> get items {
    final rawItems = data['items'];

    if (rawItems is! List) return [];

    return rawItems
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  int get total {
    final value = data['total'];
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  String get tableNo => '${data['tableNo'] ?? '-'}';

  String formatMoney(dynamic value) {
    final number = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return '${number.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
        )} VND';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long, size: 42),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Customer Display',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    Text(
                      'Table: $tableNo',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Text(
                            'No items',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = items[index];

                            final name = '${item['name'] ?? '-'}';
                            final qty = item['qty'] ?? 0;
                            final price = item['price'] ?? 0;

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 18,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                    color: Color(0x14000000),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'x$qty',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 40),
                                  SizedBox(
                                    width: 180,
                                    child: Text(
                                      formatMoney(price),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'TOTAL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        formatMoney(total),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
