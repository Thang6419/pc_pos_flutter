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
        body: Stack(
          children: [
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.storefront,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Customer Display',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      'Table: $tableNo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                padding: const EdgeInsets.all(18),
                color: Colors.white.withValues(alpha: 0.94),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Order List',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: items.isEmpty
                          ? const Center(
                              child: Text(
                                'No items',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = items[index];

                                final name = '${item['name'] ?? '-'}';
                                final qty = item['qty'] ?? 0;
                                final price = item['price'] ?? 0;

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: const [
                                      BoxShadow(
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                        color: Color(0x12000000),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'x$qty',
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: 110,
                                        child: Text(
                                          formatMoney(price),
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontSize: 16,
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
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      color: Colors.black,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'TOTAL',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatMoney(total),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
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
          ],
        ),
      ),
    );
  }
}
