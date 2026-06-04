import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:pc_pos/local_image_gallery.dart';

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
        final newData =
            jsonDecode(jsonEncode(call.arguments)) as Map<String, dynamic>;

        print('RECEIVED UPDATE: $newData');
        setState(() {
          data = newData;
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
    final headers = List<String>.from(data['ordersHeaderTable'] ?? []);
    final orders = List<Map<String, dynamic>>.from(data['orders'] ?? []);
    final subFooter = List<Map<String, dynamic>>.from(data['subFooter'] ?? []);
    final footer = Map<String, dynamic>.from(data['footer'] ?? {});

    return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Roboto',
        ),
        home: Scaffold(
            backgroundColor: const Color(0xFFF7F7F7),
            body: Stack(children: [
              // BACKGROUND: Gallery full màn hình
              const Positioned.fill(
                child: LocalImageGallery(),
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
