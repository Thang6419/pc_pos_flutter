import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';

enum _RemoteMediaStatus {
  unchecked,
  checking,
  available,
  unavailable,
}

class LocalImageGallery extends StatefulWidget {
  final List<Map<String, dynamic>>? remoteItems;
  final String? remoteDomain;
  final bool useRemoteItems;

  const LocalImageGallery({
    super.key,
    this.remoteItems,
    this.remoteDomain,
    this.useRemoteItems = false,
  });

  @override
  State<LocalImageGallery> createState() => _LocalImageGalleryState();
}

class _LocalImageGalleryState extends State<LocalImageGallery> {
  static const Duration _imageHoldDuration = Duration(seconds: 5);
  static const Duration _slideAnimationDuration = Duration(milliseconds: 600);

  final String folderPath = r'D:\PC_POS_IMAGES';
  final CarouselSliderController carouselController =
      CarouselSliderController();

  List<File> images = [];
  int currentIndex = 0;

  StreamSubscription<FileSystemEvent>? watchSubscription;
  Timer? slideTimer;
  _RemoteMediaStatus remoteStatus = _RemoteMediaStatus.unchecked;
  int remoteCheckToken = 0;

  List<_RemoteMediaItem> get remoteMediaItems {
    if (!widget.useRemoteItems) return [];

    return (widget.remoteItems ?? [])
        .map((item) => _RemoteMediaItem.fromJson(item, widget.remoteDomain))
        .where((item) => item.url.isNotEmpty)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    loadImages();
    watchFolder();
    _checkRemoteAvailability();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleCurrentSlide();
    });
  }

  @override
  void didUpdateWidget(covariant LocalImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.remoteItems != widget.remoteItems ||
        oldWidget.remoteDomain != widget.remoteDomain ||
        oldWidget.useRemoteItems != widget.useRemoteItems) {
      setState(() {
        currentIndex = 0;
        remoteStatus = _RemoteMediaStatus.unchecked;
      });
      _checkRemoteAvailability();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleCurrentSlide();
      });
    }
  }

  @override
  void dispose() {
    slideTimer?.cancel();
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

      if (currentIndex >= images.length) {
        currentIndex = 0;
      }
    });

    _scheduleCurrentSlide();
  }

  void watchFolder() async {
    final dir = Directory(folderPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    watchSubscription = dir.watch(recursive: true).listen((event) async {
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        await loadImages();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = remoteMediaItems;

    if (_shouldUseRemote(items)) {
      return _buildRemoteCarousel(items);
    }

    if (images.isEmpty) {
      if (widget.useRemoteItems) {
        return _buildNoNetwork();
      }

      return const SizedBox.expand();
    }

    return _buildLocalCarousel();
  }

  bool _shouldUseRemote(List<_RemoteMediaItem> items) {
    return widget.useRemoteItems &&
        items.isNotEmpty &&
        remoteStatus == _RemoteMediaStatus.available;
  }

  Future<void> _checkRemoteAvailability() async {
    final token = ++remoteCheckToken;
    final items = remoteMediaItems;

    if (!widget.useRemoteItems || items.isEmpty) {
      if (!mounted) return;
      setState(() {
        remoteStatus = _RemoteMediaStatus.unavailable;
      });
      _scheduleCurrentSlide();
      return;
    }

    setState(() {
      remoteStatus = _RemoteMediaStatus.checking;
    });

    final isAvailable = await _canReachRemoteMedia(items.first.url);

    if (!mounted || token != remoteCheckToken) return;

    setState(() {
      remoteStatus = isAvailable
          ? _RemoteMediaStatus.available
          : _RemoteMediaStatus.unavailable;
      currentIndex = 0;
    });
    _scheduleCurrentSlide();
  }

  Future<bool> _canReachRemoteMedia(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);

    try {
      final request = await client.headUrl(uri).timeout(
            const Duration(seconds: 3),
          );
      final response = await request.close().timeout(
            const Duration(seconds: 3),
          );
      await response.drain<void>().timeout(const Duration(seconds: 1));

      if (response.statusCode >= 200 && response.statusCode < 400) {
        return true;
      }
    } catch (_) {
      // Some static file servers do not support HEAD; retry with a tiny GET.
    }

    try {
      final request = await client.getUrl(uri).timeout(
            const Duration(seconds: 3),
          );
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final response = await request.close().timeout(
            const Duration(seconds: 3),
          );
      await response.drain<void>().timeout(const Duration(seconds: 1));

      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void _markRemoteUnavailable() {
    if (!mounted || remoteStatus == _RemoteMediaStatus.unavailable) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || remoteStatus == _RemoteMediaStatus.unavailable) return;

      setState(() {
        remoteStatus = _RemoteMediaStatus.unavailable;
        currentIndex = 0;
      });
      _scheduleCurrentSlide();
    });
  }

  void _scheduleCurrentSlide() {
    slideTimer?.cancel();

    if (!mounted) return;

    final items = remoteMediaItems;

    if (_shouldUseRemote(items)) {
      if (items.length <= 1 || currentIndex >= items.length) return;
      if (items[currentIndex].isVideo) return;
      slideTimer = Timer(_imageHoldDuration, () => _goToNext(items.length));
      return;
    }

    if (images.length <= 1) return;
    slideTimer = Timer(_imageHoldDuration, () => _goToNext(images.length));
  }

  Future<void> _goToNext(int itemCount) async {
    if (!mounted || itemCount <= 1) return;

    await carouselController.nextPage(
      duration: _slideAnimationDuration,
      curve: Curves.easeInOut,
    );
  }

  Widget _buildLocalCarousel() {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CarouselSlider.builder(
              carouselController: carouselController,
              itemCount: images.length,
              options: CarouselOptions(
                viewportFraction: 1,
                height: double.infinity,
                autoPlay: false,
                enableInfiniteScroll: images.length > 1,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index, reason) {
                  if (!mounted) return;

                  setState(() {
                    currentIndex = index;
                  });
                  _scheduleCurrentSlide();
                },
              ),
              itemBuilder: (_, index, __) {
                return SizedBox.expand(
                    child: Image.file(
                  images[index],
                  fit: BoxFit.cover, // hoặc contain nếu muốn hiện full ảnh
                  errorBuilder: (_, __, ___) {
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
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRemoteCarousel(List<_RemoteMediaItem> items) {
    if (items.isEmpty) {
      return const SizedBox.expand();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CarouselSlider.builder(
              carouselController: carouselController,
              itemCount: items.length,
              options: CarouselOptions(
                viewportFraction: 1,
                height: double.infinity,
                autoPlay: false,
                enableInfiniteScroll: items.length > 1,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index, reason) {
                  if (!mounted) return;

                  setState(() {
                    currentIndex = index;
                  });
                  _scheduleCurrentSlide();
                },
              ),
              itemBuilder: (_, index, __) {
                final item = items[index];

                if (item.isVideo) {
                  if (index != currentIndex) {
                    return const SizedBox.expand(
                      child: ColoredBox(color: Colors.black),
                    );
                  }

                  return RemoteVideoSlide(
                    key: ValueKey(item.url),
                    url: item.url,
                    onEnded: () {
                      if (!mounted || currentIndex != index) return;
                      _goToNext(items.length);
                    },
                    onError: _markRemoteUnavailable,
                  );
                }

                return SizedBox.expand(
                  child: Image.network(
                    item.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) {
                      _markRemoteUnavailable();
                      return Container(
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image,
                          size: 60,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
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
        if (items.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                items.length,
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
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNoNetwork() {
    return const SizedBox.expand(
      child: ColoredBox(
        color: Color(0xFF111827),
        child: Center(
          child: Text(
            'Không có mạng',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteMediaItem {
  final String url;
  final String mediaType;

  const _RemoteMediaItem({
    required this.url,
    required this.mediaType,
  });

  bool get isVideo {
    final lowerType = mediaType.toLowerCase();

    if (lowerType.isNotEmpty) {
      return lowerType == 'video' || lowerType.contains('video');
    }

    final lowerUrl = url.toLowerCase();

    return lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.webm') ||
        lowerUrl.endsWith('.mov') ||
        lowerUrl.endsWith('.m4v');
  }

  factory _RemoteMediaItem.fromJson(
    Map<String, dynamic> item,
    String? domain,
  ) {
    final rawUrl = (item['fileUrl'] ??
            item['fileUri'] ??
            item['url'] ??
            item['path'] ??
            item['src'] ??
            '')
        .toString()
        .trim();

    return _RemoteMediaItem(
      url: _resolveUrl(rawUrl, domain),
      mediaType: (item['mediaType'] ?? item['type'] ?? '').toString(),
    );
  }

  static String _resolveUrl(String rawUrl, String? domain) {
    if (rawUrl.isEmpty) return '';

    final uri = Uri.tryParse(rawUrl);
    if (uri != null && uri.hasScheme) {
      return rawUrl;
    }

    final base = Uri.tryParse(domain ?? '');
    if (base == null || !base.hasScheme) {
      return rawUrl;
    }

    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final mediaPath = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';

    return base.replace(path: '$basePath$mediaPath').toString();
  }
}

class RemoteVideoSlide extends StatefulWidget {
  final String url;
  final VoidCallback onEnded;
  final VoidCallback onError;

  const RemoteVideoSlide({
    super.key,
    required this.url,
    required this.onEnded,
    required this.onError,
  });

  @override
  State<RemoteVideoSlide> createState() => _RemoteVideoSlideState();
}

class _RemoteVideoSlideState extends State<RemoteVideoSlide> {
  InAppWebViewController? controller;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant RemoteVideoSlide oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.url != widget.url) {
      unawaited(controller?.loadData(data: _videoHtml(widget.url)));
    }
  }

  @override
  void dispose() {
    controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: InAppWebView(
        initialData: InAppWebViewInitialData(
          data: _videoHtml(widget.url),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          transparentBackground: false,
          disableContextMenu: true,
        ),
        onWebViewCreated: (webViewController) {
          controller = webViewController;
          webViewController.addJavaScriptHandler(
            handlerName: 'VideoBridge',
            callback: (args) {
              final message = args.isNotEmpty ? args.first?.toString() : '';

              if (message == 'ended') {
                widget.onEnded();
              }
              if (message == 'error') {
                widget.onError();
              }

              return null;
            },
          );
        },
      ),
    );
  }

  String _videoHtml(String url) {
    final escapedUrl = const HtmlEscape().convert(url);

    return '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <style>
    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: #000;
    }
    video {
      width: 100%;
      height: 100%;
      object-fit: cover;
      background: #000;
    }
  </style>
</head>
<body>
  <video id="video" src="$escapedUrl" autoplay muted playsinline></video>
  <script>
    const video = document.getElementById('video');
    let notified = false;
    function notify(message) {
      if (notified) return;
      notified = true;
      VideoBridge.postMessage(message);
    }
    video.muted = true;
    video.volume = 0;
    video.controls = false;
    video.preload = 'auto';
    video.addEventListener('ended', function () {
      window.flutter_inappwebview.callHandler('VideoBridge', 'ended');
    });
    video.addEventListener('error', function () {
      window.flutter_inappwebview.callHandler('VideoBridge', 'error');
    });
    video.play().catch(function () {});
  </script>
</body>
</html>
''';
  }
}
