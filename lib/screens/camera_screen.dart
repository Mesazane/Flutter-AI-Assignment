import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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

  // Throttling: skip frames bila inferensi sebelumnya belum selesai.
  bool _isDetecting = false;
  // Throttling tambahan: jangan mulai inferensi baru lebih cepat dari N ms
  // setelah frame terakhir di-PROSES (bukan frame terakhir di-RECEIVE).
  DateTime _lastInferenceEnd = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minInterval = Duration(milliseconds: 100);

  List<Detection> _detections = const [];

  // FPS counter: rata-rata dari beberapa frame terakhir.
  final List<int> _frameTimesMs = [];
  int _fps = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // === KEEP SCREEN AWAKE selama deteksi aktif ===
    WakelockPlus.enable();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // 1. Permission kamera
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _errorMessage =
              'Akses kamera ditolak. Aktifkan di Pengaturan agar deteksi sampah bisa berjalan.';
          _initializing = false;
        });
        return;
      }

      // 2. Load model YOLO
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
    // 1. Skip kalau inferensi sebelumnya masih jalan.
    if (_isDetecting) return;

    // 2. Skip kalau jeda dari inferensi terakhir terlalu singkat — beri waktu
    //    isolate UI untuk render frame & responsif terhadap touch.
    final sinceLast = DateTime.now().difference(_lastInferenceEnd);
    if (sinceLast < _minInterval) return;

    _isDetecting = true;
    final inferStart = DateTime.now();

    try {
      final converted = cameraImageToImage(image);
      final results = await _detector.detect(converted);

      if (!mounted) return;

      // Update FPS rata-rata (window 10 frame).
      final dt = DateTime.now().difference(inferStart).inMilliseconds;
      _frameTimesMs.add(dt);
      if (_frameTimesMs.length > 10) _frameTimesMs.removeAt(0);
      final avg = _frameTimesMs.reduce((a, b) => a + b) / _frameTimesMs.length;
      final newFps = avg > 0 ? (1000 / avg).round() : 0;

      // 3. Hanya setState kalau hasil benar-benar berubah ATAU FPS berubah —
      //    mencegah rebuild + repaint yang sia-sia tiap frame.
      final changed = !_sameDetections(results, _detections) ||
          (newFps - _fps).abs() >= 2;
      if (changed) {
        setState(() {
          _detections = results;
          _fps = newFps;
        });
      }
    } catch (e) {
      debugPrint('Inference error: $e');
    } finally {
      _lastInferenceEnd = DateTime.now();
      _isDetecting = false;
    }
  }

  /// Cek dua list deteksi "sama" cukup berdasarkan jumlah & class id
  /// (geometri box sengaja diabaikan supaya tidak rebuild tiap pergerakan kecil).
  bool _sameDetections(List<Detection> a, List<Detection> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].classId != b[i].classId) return false;
    }
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.stopImageStream();
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed) {
      controller.startImageStream(_onFrame);
      WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // === Pulihkan layar normal (boleh dim lagi) saat keluar screen ===
    WakelockPlus.disable();
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
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CustomPaint(
              painter: BoundingBoxPainter(detections: _detections),
            ),
          ),
        ),
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
