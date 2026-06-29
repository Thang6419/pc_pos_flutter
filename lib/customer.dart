import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:pc_pos/local_image_gallery.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  Map<String, dynamic>? previewResponse;
  String? previewDomain;
  String? qrValue;
  Map<String, dynamic> _asStringKeyMap(dynamic value) {
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      return _asStringKeyMap(decoded);
    }

    if (value is Map) {
      return value.map(
        (key, value) => MapEntry('$key', _normalizeJsonValue(value)),
      );
    }

    return {};
  }

  dynamic _normalizeJsonValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry('$key', _normalizeJsonValue(value)),
      );
    }

    if (value is List) {
      return value.map(_normalizeJsonValue).toList();
    }

    return value;
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return [];

    return value.map(_asStringKeyMap).toList();
  }

  @override
  void initState() {
    super.initState();

    data = _asStringKeyMap(widget.initialData['data']);
    previewResponse = _asStringKeyMap(data['previewResponse']);
    final initialPreviewDomain = data['previewDomain']?.toString().trim();
    previewDomain = initialPreviewDomain == null || initialPreviewDomain.isEmpty
        ? null
        : initialPreviewDomain;

    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'update_customer_display') {
        final newData = _asStringKeyMap(call.arguments);
        setState(() {
          data = newData;
        });
      }
      if (call.method == 'update_customer_gallery') {
        final newData = _asStringKeyMap(call.arguments);
        final nextPreviewDomain = newData['previewDomain']?.toString().trim();
        setState(() {
          previewResponse = _asStringKeyMap(newData['previewResponse']);
          previewDomain = nextPreviewDomain == null || nextPreviewDomain.isEmpty
              ? null
              : nextPreviewDomain;
        });
      }
      if (call.method == 'show_customer_qr') {
        final value = call.arguments?.toString().trim() ?? '';
        setState(() {
          qrValue = value.isEmpty ? null : value;
        });
      }
      return null;
    });
  }

  List<Map<String, dynamic>> get items {
    final rawItems = data['items'];

    if (rawItems is! List) return [];

    return _asMapList(rawItems);
  }

  List<Map<String, dynamic>>? get previewItems {
    final response = previewResponse;

    if (response != null && response['data'] is List) {
      return _asMapList(response['data']);
    }

    return null;
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
    final headers =
        (data['ordersHeaderTable'] as List?)?.map((item) => '$item').toList() ??
            [];
    final orders = _asMapList(data['orders']);
    final subFooter = _asMapList(data['subFooter']);
    final footer = _asStringKeyMap(data['footer']);
    final mediaItems = previewItems;

    return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Roboto',
        ),
        home: Scaffold(
            backgroundColor: const Color(0xFFF7F7F7),
            body: Stack(children: [
              // BACKGROUND: Gallery full màn hình
              Positioned.fill(
                child: LocalImageGallery(
                  remoteItems: mediaItems,
                  remoteDomain: previewDomain,
                  useRemoteItems: mediaItems != null,
                ),
              ),

              // HEADER overlay
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 56,
                child: Container(
                  color: const Color(0xFF01102A),
                  child: Center(
                    child: Image.asset(
                      'assets/headerLogo.png',
                      height: 36,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              // RIGHT ORDER LIST overlay
              if (orders.isNotEmpty)
                Positioned(
                  top: 56,
                  right: 0,
                  bottom: 0,
                  width: 440,
                  child: Container(
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(headers),
                          Expanded(
                            flex: 1,
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: orders.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 0,
                                thickness: 0,
                                color: Color(0xFFE5E7EB),
                              ),
                              itemBuilder: (context, index) {
                                final order = orders[index];

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(4),
                                    ),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Color(0xFFE5E8EB),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        child: Text(
                                          '${index + 1}.',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            height: 16 / 12,
                                            color: Color(0xFF191919),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 12,
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${order['name'] ?? ''}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            height: 16 / 12,
                                            color: Color(0xFF191919),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 12,
                                      ),
                                      SizedBox(
                                        width: 30,
                                        child: Text(
                                          'x${order['qty'] ?? ''}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            height: 16 / 12,
                                            color: Color(0xFF191919),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 12,
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          '${order['price'] ?? ''}',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            height: 16 / 12,
                                            color: Color(0xFF1672DF),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          _summary(subFooter, footer),
                        ],
                      )),
                ),
              if (qrValue != null)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.58),
                    child: Center(
                      child: Container(
                        width: 360,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            QrImageView(
                              data: qrValue!,
                              version: QrVersions.auto,
                              size: 280,
                              backgroundColor: Colors.white,
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Scan to pay',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF191919),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ])));
  }

  Widget _header(List<String> headers) {
    return Container(
      height: 40,
      color: const Color(0xFFF2F2F2),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              headers.isNotEmpty ? headers[0] : '',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF191919)),
            ),
          ),
          SizedBox(
            width: 12,
          ),
          SizedBox(
            width: 30,
            child: Text(
              headers.length > 1 ? headers[1] : '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF191919)),
            ),
          ),
          SizedBox(
            width: 12,
          ),
          SizedBox(
            width: 80,
            child: Text(
              headers.length > 2 ? headers[2] : '',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF191919)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(
    List<Map<String, dynamic>> subFooter,
    Map<String, dynamic> footer,
  ) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE5E8EB)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        children: [
          ...subFooter.map(
            (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _summaryRow(
                  '${item['title'] ?? ''}',
                  '${item['value'] ?? ''}',
                )),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 16),
          _summaryRow(
            '${footer['title'] ?? ''}',
            '${footer['value'] ?? ''}',
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool isTotal = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 13 : 12,
              fontWeight: FontWeight.w400,
              color:
                  isTotal ? const Color(0xFF191919) : const Color(0xFF4C4C4C),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 14 : 12,
            fontWeight: isTotal ? FontWeight.w500 : FontWeight.w400,
            color: const Color(0xFF191919),
          ),
        ),
      ],
    );
  }
}
