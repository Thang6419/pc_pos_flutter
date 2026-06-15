import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:image/image.dart' as img;

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

      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );

      socket.setOption(SocketOption.tcpNoDelay, true);

      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);

      final bytes = <int>[
        ...generator.reset(),
        ...generator.imageRaster(image),
        ...generator.feed(4),
        ...generator.cut(),
      ];

      socket.add(bytes);
      await socket.flush();

      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      throw Exception('Lỗi in HTML: $e');
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
      final imageBytes = base64Decode(_normalizeBase64Image(imageBase64));
      final decoded = img.decodeImage(imageBytes);

      if (decoded == null) {
        throw Exception('Không decode được ảnh');
      }

      final image = img.copyResize(
        decoded,
        width: receiptWidth,
        interpolation: img.Interpolation.nearest,
      );

      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );

      socket.setOption(SocketOption.tcpNoDelay, true);

      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);

      final bytes = <int>[
        ...generator.reset(),
        ...generator.imageRaster(image),
        ...generator.feed(4),
        ...generator.cut(),
      ];

      socket.add(bytes);
      await socket.flush();

      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      throw Exception('Lỗi in ảnh: $e');
    } finally {
      await socket?.close();
      socket?.destroy();
      dispose();
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
        throw Exception('Print WebView chưa sẵn sàng');
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
        throw Exception('Không chụp được ảnh hóa đơn');
      }

      final decoded = img.decodeImage(screenshot);
      if (decoded == null) {
        throw Exception('Không decode được ảnh hóa đơn');
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
