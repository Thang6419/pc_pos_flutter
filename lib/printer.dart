import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';

class PrinterFloatingAction extends StatefulWidget {
  const PrinterFloatingAction({super.key});

  @override
  State<PrinterFloatingAction> createState() => _PrinterFloatingActionState();
}

class _PrinterFloatingActionState extends State<PrinterFloatingAction> {
  final TextEditingController ipController =
      TextEditingController(text: '192.168.0.240');
  final TextEditingController portController =
      TextEditingController(text: '9100');

  bool isPrinting = false;

  @override
  void dispose() {
    ipController.dispose();
    portController.dispose();
    super.dispose();
  }

  Future<img.Image> _buildVietnameseReceiptImage() async {
    const double width = 576;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Nền trắng tuyệt đối, tránh line đen cuối bill
    canvas.drawColor(Colors.white, BlendMode.src);

    double currentY = 20;

    TextStyle textStyle({
      double fontSize = 28,
      FontWeight fontWeight = FontWeight.normal,
    }) {
      return TextStyle(
        color: Colors.black,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: 'Roboto',
      );
    }

    void drawCenterText(
      String text, {
      double fontSize = 28,
      FontWeight fontWeight = FontWeight.normal,
      double bottom = 10,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: textStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 3,
      );

      tp.layout(maxWidth: width - 40);

      tp.paint(
        canvas,
        Offset((width - tp.width) / 2, currentY),
      );

      currentY += tp.height + bottom;
    }

    double drawTextAt(
      String text,
      double x,
      double y, {
      double fontSize = 26,
      FontWeight fontWeight = FontWeight.normal,
      TextAlign textAlign = TextAlign.left,
      double maxWidth = 200,
      int maxLines = 1,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: textStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: textAlign,
        maxLines: maxLines,
        ellipsis: maxLines == 1 ? '...' : null,
      );

      tp.layout(maxWidth: maxWidth);
      tp.paint(canvas, Offset(x, y));

      return tp.height;
    }

    void drawDivider({double gapTop = 8, double gapBottom = 14}) {
      currentY += gapTop;

      final paint = Paint()
        ..color = Colors.black
        ..strokeWidth = 1;

      canvas.drawLine(
        Offset(20, currentY),
        Offset(width - 20, currentY),
        paint,
      );

      currentY += gapBottom;
    }

    void drawItemRow({
      required String qty,
      required String item,
      required String price,
      required String total,
      double fontSize = 25,
    }) {
      final rowY = currentY;

      final h1 = drawTextAt(qty, 45, rowY, fontSize: fontSize, maxWidth: 40);
      final h2 = drawTextAt(
        item,
        90,
        rowY,
        fontSize: fontSize,
        maxWidth: 250,
        maxLines: 2,
      );
      final h3 = drawTextAt(
        price,
        380,
        rowY,
        fontSize: fontSize,
        textAlign: TextAlign.right,
        maxWidth: 70,
      );
      final h4 = drawTextAt(
        total,
        490,
        rowY,
        fontSize: fontSize,
        textAlign: TextAlign.right,
        maxWidth: 70,
      );

      final rowHeight = [h1, h2, h3, h4].reduce((a, b) => a > b ? a : b);

      currentY += rowHeight + 10;
    }
    // =========================
    // LOGO IMAGE
    // =========================

    final logoData = await rootBundle.load('assets/logo.jpg');

    final logoCodec = await ui.instantiateImageCodec(
      logoData.buffer.asUint8List(),
      targetWidth: 180,
      targetHeight: 180,
    );

    final logoFrame = await logoCodec.getNextFrame();
    final logoImage = logoFrame.image;

    canvas.drawImage(
      logoImage,
      Offset((width - 180) / 2, currentY),
      Paint(),
    );

    currentY += 205;

    // =========================
    // STORE INFO
    // =========================

    drawCenterText(
      'GROCERYLY',
      fontSize: 44,
      fontWeight: FontWeight.bold,
      bottom: 28,
    );

    drawCenterText('889 Watson Lane', fontSize: 26, bottom: 4);
    drawCenterText('New Braunfels, TX', fontSize: 26, bottom: 4);
    drawCenterText('Tel: 830-221-1234', fontSize: 26, bottom: 4);
    drawCenterText('Web: www.example.com', fontSize: 26, bottom: 22);

    drawDivider(gapTop: 8, gapBottom: 16);

    // =========================
    // TABLE HEADER
    // =========================

    drawTextAt(
      'Qty',
      45,
      currentY,
      fontSize: 25,
      fontWeight: FontWeight.bold,
      maxWidth: 50,
    );

    drawTextAt(
      'Item',
      90,
      currentY,
      fontSize: 25,
      fontWeight: FontWeight.bold,
      maxWidth: 180,
    );

    drawTextAt(
      'Price',
      365,
      currentY,
      fontSize: 25,
      fontWeight: FontWeight.bold,
      textAlign: TextAlign.right,
      maxWidth: 90,
    );

    drawTextAt(
      'Total',
      480,
      currentY,
      fontSize: 25,
      fontWeight: FontWeight.bold,
      textAlign: TextAlign.right,
      maxWidth: 90,
    );

    currentY += 36;

    // =========================
    // ITEMS
    // =========================

    drawItemRow(qty: '2', item: 'ONION RINGS', price: '0.99', total: '1.98');
    drawItemRow(qty: '1', item: 'PIZZA', price: '3.45', total: '3.45');
    drawItemRow(qty: '1', item: 'SPRING ROLLS', price: '2.99', total: '2.99');
    drawItemRow(qty: '3', item: 'CRUNCHY STICKS', price: '0.85', total: '2.55');
    drawItemRow(
        qty: '3',
        item: 'Bánh mì sài gòn, 1 ngàn 1 ổ',
        price: '0.85',
        total: '2.55');

    drawDivider(gapTop: 8, gapBottom: 16);

    // =========================
    // TOTAL
    // =========================

    final totalY = currentY;

    drawTextAt(
      'TOTAL',
      45,
      totalY,
      fontSize: 48,
      fontWeight: FontWeight.bold,
      maxWidth: 220,
    );

    drawTextAt(
      r'$10.97',
      330,
      totalY,
      fontSize: 48,
      fontWeight: FontWeight.bold,
      textAlign: TextAlign.right,
      maxWidth: 210,
    );

    currentY += 66;

    drawDivider(gapTop: 4, gapBottom: 36);

    // =========================
    // PAYMENT
    // =========================

    drawTextAt(
      'Cash',
      270,
      currentY,
      fontSize: 34,
      fontWeight: FontWeight.bold,
      textAlign: TextAlign.right,
      maxWidth: 130,
    );

    drawTextAt(
      r'$15.00',
      420,
      currentY,
      fontSize: 34,
      fontWeight: FontWeight.bold,
      textAlign: TextAlign.right,
      maxWidth: 130,
    );

    currentY += 42;

    drawTextAt(
      'Change',
      240,
      currentY,
      fontSize: 34,
      fontWeight: FontWeight.bold,
      textAlign: TextAlign.right,
      maxWidth: 160,
    );

    drawTextAt(
      r'$4.03',
      420,
      currentY,
      fontSize: 34,
      fontWeight: FontWeight.bold,
      textAlign: TextAlign.right,
      maxWidth: 130,
    );

    currentY += 90;

    // =========================
    // FOOTER
    // =========================

    drawCenterText(
      'Thank you!',
      fontSize: 32,
      fontWeight: FontWeight.bold,
      bottom: 4,
    );

    drawCenterText(
      '03/16/2020 16:44',
      fontSize: 28,
      bottom: 40,
    );

    // =========================
    // QR REAL
    // =========================

    const double qrSize = 190;

    final qrPainter = QrPainter(
      data: 'https://example.com',
      version: QrVersions.auto,
      gapless: true,
      color: Colors.black,
      emptyColor: Colors.white,
    );

    final qrUiImage = await qrPainter.toImage(qrSize);

    canvas.drawImage(
      qrUiImage,
      Offset((width - qrSize) / 2, currentY),
      Paint(),
    );

    currentY += qrSize + 90;

    // thêm trắng cuối bill để máy không quét ra line đen
    currentY += 120;

    // =========================
    // EXPORT IMAGE
    // =========================

    final picture = recorder.endRecording();

    final uiImage = await picture.toImage(
      width.toInt(),
      currentY.toInt(),
    );

    final byteData = await uiImage.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (byteData == null) {
      throw Exception('Không tạo được byteData từ hóa đơn');
    }

    final pngBytes = byteData.buffer.asUint8List();

    final decoded = img.decodePng(pngBytes);

    if (decoded == null) {
      throw Exception('Không decode được ảnh hóa đơn');
    }

    // ép về đúng width máy in
    final resized = img.copyResize(
      decoded,
      width: width.toInt(),
      interpolation: img.Interpolation.nearest,
    );

    return resized;
  }

  Future<void> _printViaPureSocket({
    required String ip,
    required int port,
  }) async {
    Socket? socket;

    try {
      socket =
          await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
      socket.setOption(SocketOption.tcpNoDelay, true);

      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);

      final receiptImage = await _buildVietnameseReceiptImage();

      final bytes = <int>[];
      bytes.addAll(generator.reset());
      bytes.addAll(generator.imageRaster(receiptImage));
      bytes.addAll(generator.feed(4));
      bytes.addAll(generator.cut());

      socket.add(bytes);
      await socket.flush();

      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      throw Exception('Lỗi in: $e');
    } finally {
      if (socket != null) {
        await socket.close();
        socket.destroy();
      }
    }
  }

  void _openPrinterModal() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> handlePrint() async {
              if (isPrinting) return;

              final ip = ipController.text.trim();
              final port = int.tryParse(portController.text.trim()) ?? 9100;

              if (ip.isEmpty) {
                _showMessage('Vui lòng nhập IP máy in');
                return;
              }

              setModalState(() => isPrinting = true);
              setState(() => isPrinting = true);

              try {
                await _printViaPureSocket(ip: ip, port: port);
                await _printViaPureSocket(ip: ip, port: port);
                await _printViaPureSocket(ip: ip, port: port);
                if (!mounted) return;
                Navigator.pop(dialogContext);
                _showMessage('In test thành công');
              } catch (e) {
                if (!mounted) return;
                _showMessage('Lỗi in:\n$e');
              } finally {
                if (mounted) {
                  setModalState(() => isPrinting = false);
                  setState(() => isPrinting = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('Test máy in'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ipController,
                    enabled: !isPrinting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'IP máy in'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: portController,
                    enabled: !isPrinting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isPrinting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Đóng'),
                ),
                ElevatedButton(
                  onPressed: isPrinting ? null : handlePrint,
                  child: isPrinting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('In test'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: _openPrinterModal,
      child: const Icon(Icons.print),
    );
  }
}
