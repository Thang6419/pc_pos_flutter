import 'dart:async';
import 'dart:typed_data'; // Đã sửa thành typed_data chuẩn
import 'package:flutter/material.dart';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

// Giữ lại hàm chuyển đổi này để "mớm" đúng loại byte máy in cần, tránh làm crash firmware của máy
Uint8List encodeCP1258(String text) {
  const unicode = 'áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđÁÀẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬÉÈẺẼẸÊẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢÚÙỦŨỤƯỨỪỬỮỰÝỲỶỸYĐ';
  const cp1258  = [
    0xe1, 0xe0, 0xec, 0xe3, 0xf2, 0xe2, 0xe1, 0xe0, 0xec, 0xe3, 0xf2, 0xe2, 0xe5, 0xe4, 0xec, 0xe3, 0xf2, 0xe2,
    0xe9, 0xe8, 0xec, 0xe3, 0xf2, 0xea, 0xe9, 0xe8, 0xec, 0xe3, 0xf2, 0xed, 0xee, 0xec, 0xe3, 0xf2, 0xf3, 0xf2,
    0xec, 0xe3, 0xf2, 0xf4, 0xf3, 0xf2, 0xec, 0xe3, 0xf2, 0xf5, 0xf3, 0xf2, 0xec, 0xe3, 0xf2, 0xfa, 0xf9, 0xec,
    0xe3, 0xf2, 0xfb, 0xfa, 0xf9, 0xec, 0xe3, 0xf2, 0xfd, 0xef, 0xec, 0xe3, 0xf2, 0xfc, 0xc1, 0xc0, 0xec, 0xe3,
    0xf2, 0xc2, 0xc1, 0xc0, 0xec, 0xe3, 0xf2, 0xc2, 0xc5, 0xc4, 0xec, 0xe3, 0xf2, 0xc2, 0xc9, 0xc8, 0xec, 0xe3,
    0xf2, 0xca, 0xc9, 0xc8, 0xec, 0xe3, 0xf2, 0xcd, 0xce, 0xec, 0xe3, 0xf2, 0xd3, 0xd2, 0xec, 0xe3, 0xf2, 0xd4,
    0xd3, 0xd2, 0xec, 0xe3, 0xf2, 0xd5, 0xd3, 0xd2, 0xec, 0xe3, 0xf2, 0xda, 0xd9, 0xec, 0xe3, 0xf2, 0xdb, 0xda,
    0xd9, 0xec, 0xe3, 0xf2, 0xdc
  ];

  List<int> result = [];
  for (int i = 0; i < text.length; i++) {
    String char = text[i];
    int index = unicode.indexOf(char);
    if (index != -1 && index < cp1258.length) {
      result.add(cp1258[index]);
    } else {
      result.add(text.codeUnitAt(i));
    }
  }
  return Uint8List.fromList(result);
}

class PrinterFloatingAction extends StatefulWidget {
  const PrinterFloatingAction({super.key});

  @override
  State<PrinterFloatingAction> createState() => _PrinterFloatingActionState();
}

class _PrinterFloatingActionState extends State<PrinterFloatingAction> {
  final TextEditingController ipController = TextEditingController(text: '10.10.30.252');
  final TextEditingController portController = TextEditingController(text: '9100');
  bool isPrinting = false;

  @override
  void dispose() {
    ipController.dispose();
    portController.dispose();
    super.dispose();
  }

  // VẪN DÙNG LUỒNG NETWORK PRINTER CỦA THƯ VIỆN NHƯ CŨ
  Future<void> _printTest({
    required String ip,
    required int port,
  }) async {
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(PaperSize.mm80, profile);

    final result = await printer.connect(ip, port: port).timeout(
      const Duration(seconds: 4),
      onTimeout: () => PosPrintResult.timeout,
    );

    if (result != PosPrintResult.success) {
      throw Exception('Lỗi kết nối: ${result.msg}');
    }

    try {
      // 1. Tiêu đề tiếng Anh thường
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

      // Dùng textEncoded phối hợp với encodeCP1258()
      printer.textEncoded(
        encodeCP1258('HÓA ĐƠN BÁN HÀNG'),
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );

      printer.textEncoded(encodeCP1258('Địa chỉ: 123 Đường Chu Văn An, Hà Nội'));
      printer.textEncoded(encodeCP1258('Điện thoại: 0987654321'));
      printer.text('Printer IP: $ip');

      printer.hr();

      // Chia hàng cột bằng Lib cũ thoải mái
      printer.row([
        PosColumn(
          textEncoded: encodeCP1258('Tên món'),
          width: 8,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          textEncoded: encodeCP1258('T.Tiền'),
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);

      printer.row([
        PosColumn(textEncoded: encodeCP1258('Cà phê đen đá'), width: 8),
        PosColumn(text: '25,000', width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);

      printer.row([
        PosColumn(textEncoded: encodeCP1258('Trà sữa trân châu'), width: 8),
        PosColumn(text: '35,000', width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);

      printer.hr();

      printer.row([
        PosColumn(textEncoded: encodeCP1258('TỔNG CỘNG:'), width: 6, styles: const PosStyles(bold: true)),
        PosColumn(text: '60,000 VND', width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);

      printer.hr();

      printer.textEncoded(
        encodeCP1258('Cảm ơn quý khách. Hẹngặp lại!'),
        styles: const PosStyles(align: PosAlign.center),
      );

      printer.feed(3);
      printer.cut();

    } catch (e) {
      rethrow;
    } finally {
      printer.disconnect(); // Ngắt kết nối sạch sẽ
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

              setModalState(() { isPrinting = true; });
              setState(() { isPrinting = true; });

              try {
                await _printTest(ip: ip, port: port);

                if (!mounted) return;
                Navigator.pop(dialogContext);
                _showMessage('In test thành công');
              } catch (e) {
                if (!mounted) return;
                _showMessage('In thất bại:\n$e');
              } finally {
                if (mounted) {
                  setModalState(() { isPrinting = false; });
                  setState(() { isPrinting = false; });
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
                  onPressed: isPrinting ? null : () => Navigator.pop(dialogContext),
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
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
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