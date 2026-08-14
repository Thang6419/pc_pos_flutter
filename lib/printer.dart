import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:image/image.dart' as img;
import 'package:pc_pos/utils/common.dart';
import 'package:win32/win32.dart';

class HtmlReceiptPrinter {
  HtmlReceiptPrinter({
    required this.context,
    this.receiptWidth = 576,
    this.paperSize = PaperSize.mm80,
  });

  final BuildContext context;
  final int receiptWidth;
  final PaperSize paperSize;

  static final Map<String, Future<void>> _printQueues = {};
  static const Duration _minPostCutDelay = Duration(milliseconds: 1200);
  static const Duration _maxPostCutDelay = Duration(milliseconds: 6000);
  static int _jobSequence = 0;

  double _webViewHeight = 2000;
  OverlayEntry? _overlayEntry;
  InAppWebViewController? _controller;
  Completer<void>? _loadCompleter;

  Future<void> printHtml({
    required String html,
    required String ip,
    int port = 9100,
  }) async {
    final jobId = _nextJobId('html');
    final target = 'network:$ip:$port';

    await _logPrint(
      'PRINT_HTML_REQUEST job=$jobId target=$target htmlChars=${html.length} '
      'receiptWidth=$receiptWidth paperSize=$paperSize',
    );

    await _enqueuePrint(jobId, target, () async {
      try {
        final image = await _buildImageFromHtml(html);
        await _logPrint(
          'PRINT_HTML_IMAGE_READY job=$jobId width=${image.width} '
          'height=${image.height}',
        );
        final bytes = await _buildImageBytes(
          image,
          jobId: jobId,
          source: 'html',
        );

        await _sendNetworkBytes(
          jobId: jobId,
          ip: ip,
          port: port,
          bytes: bytes,
        );
      } catch (e) {
        throw Exception('Loi in HTML: $e');
      } finally {
        dispose();
      }
    });
  }

  Future<void> printImage({
    required String imageBase64,
    required String ip,
    int port = 9100,
  }) async {
    final jobId = _nextJobId('image');
    final target = 'network:$ip:$port';

    await _logPrint(
      'PRINT_IMAGE_REQUEST job=$jobId target=$target '
      'base64Chars=${imageBase64.length} receiptWidth=$receiptWidth '
      'paperSize=$paperSize',
    );

    await _enqueuePrint(jobId, target, () async {
      try {
        final bytes = await _buildImagePrintBytes(
          imageBase64,
          jobId: jobId,
        );

        await _sendNetworkBytes(
          jobId: jobId,
          ip: ip,
          port: port,
          bytes: bytes,
        );
      } catch (e) {
        throw Exception('Loi in anh: $e');
      } finally {
        dispose();
      }
    });
  }

  Future<void> printImageByPrinterName({
    required String imageBase64,
    required String printerName,
  }) async {
    if (!Platform.isWindows) {
      throw Exception('printImageByPrinterName only supports Windows');
    }

    final jobId = _nextJobId('image-win');
    final target = 'windows:${printerName.toLowerCase()}';

    await _logPrint(
      'PRINT_IMAGE_WIN_REQUEST job=$jobId target="$target" '
      'printerName="$printerName" base64Chars=${imageBase64.length} '
      'receiptWidth=$receiptWidth paperSize=$paperSize',
    );

    await _enqueuePrint(jobId, target, () async {
      try {
        final bytes = await _buildImagePrintBytes(
          imageBase64,
          jobId: jobId,
        );

        await _writeRawBytesToWindowsPrinter(
          jobId: jobId,
          printerName: printerName,
          bytes: bytes,
          documentName: 'Alliex image receipt',
        );
      } catch (e) {
        throw Exception('Loi in anh theo printerName: $e');
      } finally {
        dispose();
      }
    });
  }

  Future<T> _enqueuePrint<T>(
    String jobId,
    String key,
    Future<T> Function() action,
  ) {
    final previous = _printQueues[key] ?? Future<void>.value();
    final hadPendingJob = _printQueues.containsKey(key);
    final queuedAt = DateTime.now();
    final completer = Completer<T>();

    unawaited(
      _logPrint(
        'PRINT_QUEUE_WAIT job=$jobId target=$key pending=$hadPendingJob',
      ),
    );

    late final Future<void> current;
    current = previous.catchError((_) {}).then((_) async {
      final waitMs = DateTime.now().difference(queuedAt).inMilliseconds;
      final stopwatch = Stopwatch()..start();
      await _logPrint('PRINT_QUEUE_RUN job=$jobId target=$key waitMs=$waitMs');

      try {
        final result = await action();
        stopwatch.stop();
        await _logPrint(
          'PRINT_QUEUE_DONE job=$jobId target=$key '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
        );
        completer.complete(result);
      } catch (e, stackTrace) {
        stopwatch.stop();
        await _logPrint(
          'PRINT_QUEUE_ERROR job=$jobId target=$key '
          'elapsedMs=${stopwatch.elapsedMilliseconds} error=$e',
        );
        completer.completeError(e, stackTrace);
      }
    }).whenComplete(() {
      if (identical(_printQueues[key], current)) {
        _printQueues.remove(key);
      }
    });

    _printQueues[key] = current;

    return completer.future;
  }

  Future<void> _sendNetworkBytes({
    required String jobId,
    required String ip,
    required int port,
    required List<int> bytes,
  }) async {
    Socket? socket;
    final stopwatch = Stopwatch()..start();

    try {
      await _logPrint(
        'PRINT_SOCKET_CONNECT_START job=$jobId ip=$ip port=$port '
        'bytes=${bytes.length}',
      );
      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );
      await _logPrint(
        'PRINT_SOCKET_CONNECTED job=$jobId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );

      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.add(bytes);
      await socket.flush();
      await _logPrint(
        'PRINT_SOCKET_FLUSHED job=$jobId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      final postCutDelay = _postCutDelayForBytes(bytes.length);
      await _logPrint(
        'PRINT_POST_CUT_WAIT job=$jobId bytes=${bytes.length} '
        'delayMs=${postCutDelay.inMilliseconds}',
      );
      await Future.delayed(postCutDelay);
    } finally {
      await socket?.close();
      socket?.destroy();
      await _logPrint(
        'PRINT_SOCKET_CLOSED job=$jobId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
    }
  }

  Future<List<int>> _buildImagePrintBytes(
    String imageBase64, {
    required String jobId,
  }) async {
    final normalized = _normalizeBase64Image(imageBase64);
    final imageBytes = base64Decode(normalized);
    final decoded = img.decodeImage(imageBytes);

    if (decoded == null) {
      throw Exception('Khong decode duoc anh');
    }

    await _logPrint(
      'PRINT_IMAGE_DECODED job=$jobId base64Chars=${imageBase64.length} '
      'normalizedChars=${normalized.length} imageBytes=${imageBytes.length} '
      'sourceWidth=${decoded.width} sourceHeight=${decoded.height}',
    );

    final image = img.copyResize(
      decoded,
      width: receiptWidth,
      interpolation: img.Interpolation.nearest,
    );

    await _logPrint(
      'PRINT_IMAGE_RESIZED job=$jobId width=${image.width} '
      'height=${image.height}',
    );

    return _buildImageBytes(
      image,
      jobId: jobId,
      source: 'image',
    );
  }

  Future<List<int>> _buildImageBytes(
    img.Image image, {
    required String jobId,
    required String source,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    final bytes = <int>[
      ...generator.reset(),
      ...generator.imageRaster(image),
      ..._fullCut(),
      ...generator.reset(),
    ];

    await _logPrint(
      'PRINT_ESC_POS_BYTES job=$jobId source=$source bytes=${bytes.length} '
      'cutMode=gs-v-0x00 hasCut=${_containsCutCommand(bytes)} '
      'tailHex="${_tailHex(bytes)}"',
    );

    return bytes;
  }

  Future<void> _writeRawBytesToWindowsPrinter({
    required String jobId,
    required String printerName,
    required List<int> bytes,
    required String documentName,
  }) async {
    final printerNamePtr = printerName.toNativeUtf16();
    final printerHandlePtr = calloc<Pointer>();
    final docInfo = calloc<DOC_INFO_1>();
    final documentNamePtr = documentName.toNativeUtf16();
    final dataTypePtr = 'RAW'.toNativeUtf16();
    final written = calloc<Uint32>();
    final buffer = calloc<Uint8>(bytes.length);

    var docStarted = false;
    var pageStarted = false;
    final stopwatch = Stopwatch()..start();

    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      await _logPrint(
        'PRINT_WIN_OPEN_START job=$jobId printerName="$printerName" '
        'bytes=${bytes.length}',
      );

      final openResult = OpenPrinter(
        PCWSTR(printerNamePtr),
        printerHandlePtr,
        nullptr,
      );

      if (!openResult.value) {
        throw Exception(
          'Khong mo duoc printer "$printerName": ${openResult.error}',
        );
      }
      await _logPrint(
        'PRINT_WIN_OPENED job=$jobId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );

      final printerHandle = PRINTER_HANDLE(printerHandlePtr.value);

      docInfo.ref.pDocName = PWSTR(documentNamePtr);
      docInfo.ref.pOutputFile = PWSTR(nullptr.cast<Utf16>());
      docInfo.ref.pDatatype = PWSTR(dataTypePtr);

      final docId = StartDocPrinter(printerHandle, 1, docInfo);
      if (docId == 0) {
        throw Exception('Khong start duoc print document');
      }
      docStarted = true;
      await _logPrint(
        'PRINT_WIN_DOC_STARTED job=$jobId docId=$docId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );

      if (!StartPagePrinter(printerHandle)) {
        throw Exception('Khong start duoc print page');
      }
      pageStarted = true;
      await _logPrint(
        'PRINT_WIN_PAGE_STARTED job=$jobId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );

      if (!WritePrinter(
        printerHandle,
        buffer.cast(),
        bytes.length,
        written,
      )) {
        throw Exception('Ghi du lieu vao printer that bai');
      }
      await _logPrint(
        'PRINT_WIN_WRITTEN job=$jobId written=${written.value} '
        'expected=${bytes.length} elapsedMs=${stopwatch.elapsedMilliseconds}',
      );

      if (written.value != bytes.length) {
        throw Exception(
          'Ghi thieu du lieu vao printer: ${written.value}/${bytes.length}',
        );
      }

      EndPagePrinter(printerHandle);
      pageStarted = false;
      await _logPrint(
        'PRINT_WIN_PAGE_ENDED job=$jobId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      EndDocPrinter(printerHandle);
      docStarted = false;
      await _logPrint(
        'PRINT_WIN_DOC_ENDED job=$jobId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );

      final postCutDelay = _postCutDelayForBytes(bytes.length);
      await _logPrint(
        'PRINT_POST_CUT_WAIT job=$jobId bytes=${bytes.length} '
        'delayMs=${postCutDelay.inMilliseconds}',
      );
      await Future.delayed(postCutDelay);
    } finally {
      final printerHandle = PRINTER_HANDLE(printerHandlePtr.value);

      if (printerHandle.address != 0) {
        if (pageStarted) {
          EndPagePrinter(printerHandle);
        }
        if (docStarted) {
          EndDocPrinter(printerHandle);
        }
        ClosePrinter(printerHandle);
      }
      await _logPrint(
        'PRINT_WIN_CLOSED job=$jobId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );

      calloc.free(printerNamePtr);
      calloc.free(printerHandlePtr);
      calloc.free(docInfo);
      calloc.free(documentNamePtr);
      calloc.free(dataTypePtr);
      calloc.free(written);
      calloc.free(buffer);
    }
  }

  String _normalizeBase64Image(String value) {
    final trimmed = value.trim();
    final dataPrefixEnd = trimmed.indexOf(';base64,');

    if (trimmed.startsWith('data:image/') && dataPrefixEnd != -1) {
      return trimmed.substring(dataPrefixEnd + ';base64,'.length).trim();
    }

    return trimmed;
  }

  static String _nextJobId(String prefix) {
    _jobSequence += 1;
    return '$prefix-${DateTime.now().millisecondsSinceEpoch}-$_jobSequence';
  }

  Future<void> _logPrint(String message) async {
    try {
      await writeLog(message);
    } catch (_) {
      // Logging is diagnostic only and must never affect printing.
    }
  }

  String _tailHex(List<int> bytes, {int length = 32}) {
    final start = bytes.length > length ? bytes.length - length : 0;

    return bytes
        .skip(start)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  bool _containsCutCommand(List<int> bytes) {
    for (var index = 0; index < bytes.length - 2; index++) {
      if (bytes[index] == 0x1D && bytes[index + 1] == 0x56) {
        return true;
      }
    }

    return false;
  }

  List<int> _fullCut() {
    return const <int>[
      0x1D,
      0x56,
      0x00,
    ];
  }

  Duration _postCutDelayForBytes(int byteCount) {
    final extraChunks = (byteCount / 30000).ceil();
    final delayMs = _minPostCutDelay.inMilliseconds + (extraChunks * 800);

    return Duration(
      milliseconds: delayMs.clamp(
        _minPostCutDelay.inMilliseconds,
        _maxPostCutDelay.inMilliseconds,
      ),
    );
  }

  Future<img.Image> _buildImageFromHtml(String html) async {
    try {
      await _showWebView(html);

      final controller = _controller;
      if (controller == null) {
        throw Exception('Print WebView chua san sang');
      }

      await _waitForImages(controller);

      final heightResult = await controller.evaluateJavascript(
        source: '''
          (() => {
            const receipt = document.querySelector('.receipt') || document.body;
            return Math.ceil(receipt.getBoundingClientRect().height);
          })();
        ''',
      );

      final receiptHeight =
          double.tryParse(heightResult.toString()) ?? _webViewHeight;

      _webViewHeight = receiptHeight;
      _overlayEntry?.markNeedsBuild();

      await Future.delayed(const Duration(milliseconds: 500));

      final screenshot = await controller.takeScreenshot();

      if (screenshot == null) {
        throw Exception('Khong chup duoc anh hoa don');
      }

      final decoded = img.decodeImage(screenshot);
      if (decoded == null) {
        throw Exception('Khong decode duoc anh hoa don');
      }

      return img.copyResize(
        decoded,
        width: receiptWidth,
        interpolation: img.Interpolation.nearest,
      );
    } finally {
      _removeWebView();
    }
  }

  Future<void> _showWebView(String html) async {
    _removeWebView();

    _controller = null;
    _loadCompleter = Completer<void>();
    _webViewHeight = 2000;

    _overlayEntry = OverlayEntry(
      builder: (_) {
        return Positioned(
          left: -10000,
          top: -10000,
          width: receiptWidth.toDouble(),
          height: _webViewHeight,
          child: InAppWebView(
            initialData: InAppWebViewInitialData(data: html),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              verticalScrollBarEnabled: false,
              horizontalScrollBarEnabled: false,
              supportZoom: false,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
            },
            onLoadStop: (_, __) {
              final completer = _loadCompleter;
              if (completer != null && !completer.isCompleted) {
                completer.complete();
              }
            },
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);

    await _loadCompleter!.future.timeout(
      const Duration(seconds: 8),
    );
  }

  Future<void> _waitForImages(InAppWebViewController controller) async {
    await controller.evaluateJavascript(
      source: '''
        Promise.all(
          Array.from(document.images).map((img) => {
            if (img.complete) return Promise.resolve();
            return new Promise((resolve) => {
              img.onload = resolve;
              img.onerror = resolve;
            });
          })
        );
      ''',
    );

    await Future.delayed(const Duration(milliseconds: 300));
  }

  void _removeWebView() {
    _overlayEntry?.remove();
    _overlayEntry = null;

    _controller = null;
    _loadCompleter = null;
  }

  void dispose() {
    _removeWebView();
  }
}
