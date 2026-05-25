import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class PrinterFloatingAction extends StatefulWidget {
  const PrinterFloatingAction({super.key});

  @override
  State<PrinterFloatingAction> createState() => _PrinterFloatingActionState();
}

class _PrinterFloatingActionState extends State<PrinterFloatingAction> {
  final TextEditingController ipController = TextEditingController(
    text: '10.10.30.252',
  );

  final TextEditingController portController = TextEditingController(
    text: '9100',
  );

  @override
  void dispose() {
    ipController.dispose();
    portController.dispose();
    super.dispose();
  }

  Future<bool> _canConnect(String ip, int port) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );

      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _printTest({
    required String ip,
    required int port,
  }) async {
    final canConnect = await _canConnect(ip, port);

    if (!canConnect) {
      throw Exception('PRINTER_NOT_FOUND');
    }

    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(PaperSize.mm80, profile);

    final result = await printer
        .connect(
          ip,
          port: port,
        )
        .timeout(const Duration(seconds: 5));

    if (result != PosPrintResult.success) {
      throw Exception(result.msg);
    }

    try {
      printer.text(
        'PC POS',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );

      printer.hr();

      printer.text(
        'TEST PRINT',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
        ),
      );

      printer.text('Printer IP: $ip');
      printer.text('Printer Port: $port');

      printer.hr();

      printer.row([
        PosColumn(
          text: 'Item',
          width: 8,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: 'Price',
          width: 4,
          styles: const PosStyles(
            align: PosAlign.right,
            bold: true,
          ),
        ),
      ]);

      printer.row([
        PosColumn(text: 'Cafe den', width: 8),
        PosColumn(
          text: '25,000',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      printer.row([
        PosColumn(text: 'Tra sua', width: 8),
        PosColumn(
          text: '35,000',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      printer.hr();

      printer.text(
        'Total: 60,000 VND',
        styles: const PosStyles(
          align: PosAlign.right,
          bold: true,
        ),
      );

      printer.feed(2);
      printer.cut();
    } finally {
      printer.disconnect();
    }
  }

  void _openPrinterModal() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        bool isPrinting = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> handlePrint() async {
              final ip = ipController.text.trim();
              final port = int.tryParse(portController.text.trim()) ?? 9100;

              if (ip.isEmpty) {
                _showMessage('Vui lòng nhập IP máy in');
                return;
              }

              setModalState(() {
                isPrinting = true;
              });

              try {
                await _printTest(
                  ip: ip,
                  port: port,
                );

                if (!mounted) return;

                Navigator.pop(dialogContext);

                _showMessage('In test thành công');
              } catch (e) {
                final errorText = e.toString();

                String message = 'In thất bại';

                if (errorText.contains('PRINTER_NOT_FOUND')) {
                  message =
                      'Không tìm thấy máy in.\nKiểm tra IP, port, mạng LAN hoặc máy in đã bật chưa.';
                } else if (errorText.contains('TimeoutException') ||
                    errorText.toLowerCase().contains('timeout')) {
                  message =
                      'Kết nối máy in bị timeout.\nKiểm tra IP, port hoặc mạng LAN.';
                } else if (errorText.contains('Connection refused')) {
                  message =
                      'Máy in từ chối kết nối.\nKiểm tra port, thường là 9100.';
                } else if (errorText.contains('Network is unreachable')) {
                  message =
                      'Không truy cập được mạng.\nKiểm tra kết nối WiFi/LAN.';
                } else {
                  message = 'In thất bại:\n$errorText';
                }

                if (!mounted) return;

                _showMessage(message);
              } finally {
                if (context.mounted) {
                  setModalState(() {
                    isPrinting = false;
                  });
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
                    decoration: const InputDecoration(
                      labelText: 'IP máy in',
                      hintText: '10.10.30.252',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: portController,
                    enabled: !isPrinting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '9100',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isPrinting
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Đóng'),
                ),
                ElevatedButton(
                  onPressed: isPrinting ? null : handlePrint,
                  child: isPrinting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
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