import 'dart:async';
import 'dart:io';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:pc_pos/utils/common.dart';

class LocalImageGallery extends StatefulWidget {
  const LocalImageGallery({super.key});

  @override
  State<LocalImageGallery> createState() => _LocalImageGalleryState();
}

class _LocalImageGalleryState extends State<LocalImageGallery> {
  final String folderPath = r'D:\PC_POS_IMAGES';

  List<File> images = [];
  int currentIndex = 0;

  StreamSubscription<FileSystemEvent>? watchSubscription;

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
    try {
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

        if (currentIndex >= images.length) {
          currentIndex = 0;
        }
      });
    } catch (e, s) {
      await writeLog('LOCAL IMAGE GALLERY LOAD ERROR: $e');
      await writeLog(s);
    }
  }

  void watchFolder() async {
    try {
      final dir = Directory(folderPath);

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      watchSubscription = dir.watch(recursive: true).listen(
        (event) async {
          await Future.delayed(const Duration(milliseconds: 300));

          if (mounted) {
            await loadImages();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          unawaited(writeLog('LOCAL IMAGE GALLERY WATCH ERROR: $error'));
          unawaited(writeLog(stackTrace));
        },
      );
    } catch (e, s) {
      await writeLog('LOCAL IMAGE GALLERY WATCH START ERROR: $e');
      await writeLog(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return const SizedBox.expand();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CarouselSlider.builder(
              itemCount: images.length,
              options: CarouselOptions(
                viewportFraction: 1,
                height: double.infinity,
                autoPlay: images.length > 1,
                autoPlayInterval: const Duration(seconds: 3),
                autoPlayAnimationDuration: const Duration(milliseconds: 600),
                enableInfiniteScroll: images.length > 1,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index, reason) {
                  if (!mounted) return;

                  setState(() {
                    currentIndex = index;
                  });
                },
              ),
              itemBuilder: (_, index, __) {
                return SizedBox.expand(
                    child: Image.file(
                  images[index],
                  fit: BoxFit.cover, // hoặc contain nếu muốn hiện full ảnh
                  errorBuilder: (_, error, stackTrace) {
                    unawaited(writeLog(
                      'LOCAL IMAGE GALLERY IMAGE ERROR: '
                      'path=${images[index].path}, error=$error',
                    ));
                    if (stackTrace != null) {
                      unawaited(writeLog(stackTrace));
                    }
                    return Container(
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image,
                        size: 60,
                      ),
                    );
                  },
                ));
              },
            ),
          ),
        ),

        // gradient dưới cho dễ nhìn dot
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 120,
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x88000000),
                  ],
                ),
              ),
            ),
          ),
        ),

        // dots overlay
        if (images.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                images.length,
                (index) {
                  final isActive = currentIndex == index;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: isActive ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: isActive
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
