import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:image/image.dart' as img;
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

  double _webViewHeight = 2000;
  OverlayEntry? _overlayEntry;
  InAppWebViewController? _controller;
  Completer<void>? _loadCompleter;

  Future<void> printHtml({
    required String html,
    required String ip,
    int port = 9100,
  }) async {
    Socket? socket;

    try {
      final image = await _buildImageFromHtml(html);
      final bytes = await _buildImageBytes(image);

      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );

      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.add(bytes);
      await socket.flush();

      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      throw Exception('Loi in HTML: $e');
    } finally {
      await socket?.close();
      socket?.destroy();
      dispose();
    }
  }

  Future<void> printImage({
    required String imageBase64,
    required String ip,
    int port = 9100,
  }) async {
    Socket? socket;

    try {
      final bytes = await _buildImagePrintBytes(imageBase64);

      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );

      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.add(bytes);
      await socket.flush();

      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      throw Exception('Loi in anh: $e');
    } finally {
      await socket?.close();
      socket?.destroy();
      dispose();
    }
  }

  Future<void> printImageByPrinterName({
    required String imageBase64,
    required String printerName,
  }) async {
    if (!Platform.isWindows) {
      throw Exception('printImageByPrinterName only supports Windows');
    }

    try {
      final bytes = await _buildImagePrintBytes(imageBase64);

      await _writeRawBytesToWindowsPrinter(
        printerName: printerName,
        bytes: bytes,
        documentName: 'Alliex image receipt',
      );
    } catch (e) {
      throw Exception('Loi in anh theo printerName: $e');
    } finally {
      dispose();
    }
  }

  Future<List<int>> _buildImagePrintBytes(String imageBase64) async {
    final imageBytes = base64Decode(_normalizeBase64Image(imageBase64));
    final decoded = img.decodeImage(imageBytes);

    if (decoded == null) {
      throw Exception('Khong decode duoc anh');
    }

    final image = img.copyResize(
      decoded,
      width: receiptWidth,
      interpolation: img.Interpolation.nearest,
    );

    return _buildImageBytes(image);
  }

  Future<List<int>> _buildImageBytes(img.Image image) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    return <int>[
      ...generator.reset(),
      ...generator.imageRaster(image),
      ...generator.feed(4),
      ...generator.cut(),
    ];
  }

  Future<void> _writeRawBytesToWindowsPrinter({
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

    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);

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

      final printerHandle = PRINTER_HANDLE(printerHandlePtr.value);

      docInfo.ref.pDocName = PWSTR(documentNamePtr);
      docInfo.ref.pOutputFile = PWSTR(nullptr.cast<Utf16>());
      docInfo.ref.pDatatype = PWSTR(dataTypePtr);

      final docId = StartDocPrinter(printerHandle, 1, docInfo);
      if (docId == 0) {
        throw Exception('Khong start duoc print document');
      }
      docStarted = true;

      if (!StartPagePrinter(printerHandle)) {
        throw Exception('Khong start duoc print page');
      }
      pageStarted = true;

      if (!WritePrinter(
        printerHandle,
        buffer.cast(),
        bytes.length,
        written,
      )) {
        throw Exception('Ghi du lieu vao printer that bai');
      }

      if (written.value != bytes.length) {
        throw Exception(
          'Ghi thieu du lieu vao printer: ${written.value}/${bytes.length}',
        );
      }
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
    return value.replaceFirst(RegExp(r'^data:image/[^;]+;base64,'), '').trim();
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

      _webViewHeight = receiptHeight + 20;
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
