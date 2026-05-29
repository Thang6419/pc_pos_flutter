import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

class LocalImageGallery extends StatefulWidget {
  const LocalImageGallery({super.key});

  @override
  State<LocalImageGallery> createState() => _LocalImageGalleryState();
}

class _LocalImageGalleryState extends State<LocalImageGallery> {
  // ===== ĐẶT FOLDER Ở ĐÂY =====
  final String folderPath = r'D:\PC_POS_IMAGES';

  List<File> images = [];

  StreamSubscription? watchSubscription;

  @override
  void initState() {
    super.initState();

    loadImages();
    watchFolder();
  }

  @override
  void dispose() {
    watchSubscription?.cancel();
    super.dispose();
  }

  Future<void> loadImages() async {
    final dir = Directory(folderPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final files = dir.listSync(recursive: true);

    final scannedImages = files.whereType<File>().where((file) {
      final path = file.path.toLowerCase();

      return path.endsWith('.png') ||
          path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.webp');
    }).toList();

    scannedImages.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );

    if (!mounted) return;

    setState(() {
      images = scannedImages;
    });
  }

  void watchFolder() {
    final dir = Directory(folderPath);

    watchSubscription = dir.watch().listen((event) async {
      await Future.delayed(const Duration(milliseconds: 300));

      loadImages();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Center(
        child: Text(
          'Không có ảnh\n$folderPath',
          textAlign: TextAlign.center,
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (_, index) {
        final image = images[index];

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Container(
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.broken_image),
                  );
                },
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    image.path.split('\\').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
