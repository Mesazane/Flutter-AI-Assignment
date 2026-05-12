import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart' show availableCamerasList;
import '../models/detection.dart';
import '../models/waste_category.dart';
import '../services/yolo_detector.dart';
import '../utils/image_converter.dart';
import '../widgets/bounding_box_painter.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final YoloDetector _detector = YoloDetector();

  bool _initializing = true;
  String? _errorMessage;
  bool _isDetecting = false;
  List<Detection> _detections = const [];
  int _fps = 0;
  DateTime _lastFrameTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // 1. Minta permission kamera
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _errorMessage =
              'Akses kamera ditolak. Aktifkan di Pengaturan agar deteksi sampah bisa berjalan.';
          _initializing = false;
        });
        return;
      }

      // 2. Load model YOLO (edge AI)
      await _detector.loadModel();

      // 3. Inisialisasi kamera belakang
      if (availableCamerasList.isEmpty) {
        setState(() {
          _errorMessage = 'Tidak ada kamera yang ditemukan di perangkat ini.';
          _initializing = false;
        });
        return;
      }

      final backCamera = availableCamerasList.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => availableCamerasList.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;

      // 4. Stream frame untuk deteksi real-time
      await controller.startImageStream(_onFrame);

      setState(() => _initializing = false);
    } catch (e) {
      setState(() {
        _errorMessage = 'Gagal memulai deteksi: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    // Drop frame jika inferensi sebelumnya belum selesai supaya tidak menumpuk.
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final converted = cameraImageToImage(image);
      final results = _detector.detect(converted);

      if (!mounted) return;

      final now = DateTime.now();
      final dt = now.difference(_lastFrameTime).inMilliseconds;
      _lastFrameTime = now;

      setState(() {
        _detections = results;
        _fps = dt > 0 ? (1000 / dt).round() : 0;
      });
    } catch (e) {
      debugPrint('Inference error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      controller.startImageStream(_onFrame);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.stopImageStream();
    _controller?.dispose();
    _detector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Deteksi Sampah'),
        actions: [
          if (_fps > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  label: Text('$_fps FPS'),
                  backgroundColor: Colors.white12,
                  labelStyle: const TextStyle(color: Colors.white),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Memuat model YOLO...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 56),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _initializing = true;
                    _errorMessage = null;
                  });
                  _bootstrap();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller!;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview kamera
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),

        // Bounding boxes
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CustomPaint(
              painter: BoundingBoxPainter(detections: _detections),
            ),
          ),
        ),

        // Panel hasil di bawah
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _ResultPanel(detections: _detections),
        ),
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final List<Detection> detections;
  const _ResultPanel({required this.detections});

  @override
  Widget build(BuildContext context) {
    // Ringkasan: hitung per-kategori.
    final counts = <WasteCategory, int>{};
    for (final d in detections) {
      counts[d.category] = (counts[d.category] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: Colors.lightGreenAccent, size: 18),
              const SizedBox(width: 6),
              Text(
                detections.isEmpty
                    ? 'Arahkan kamera ke objek sampah'
                    : '${detections.length} objek terdeteksi',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (counts.isEmpty)
            const Text(
              'Belum ada hasil deteksi. Coba dekatkan objek & pastikan pencahayaan cukup.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: counts.entries.map((e) {
                final cat = e.key;
                return Chip(
                  avatar: Icon(cat.icon, color: Colors.white, size: 16),
                  label: Text('${cat.label} · ${e.value}'),
                  backgroundColor: cat.color,
                  labelStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
