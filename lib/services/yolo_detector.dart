import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';
import '../models/waste_category.dart';

/// Service inferensi YOLOv8 berjalan SEPENUHNYA di device (edge computing).
///
/// Optimasi performa yang diterapkan:
///   * `IsolateInterpreter` — inferensi TFLite jalan di worker isolate,
///     thread UI tidak ter-block (FPS jauh lebih stabil).
///   * Konversi pixel pakai `getBytes()` flat buffer (1 loop typed) — jauh
///     lebih cepat dibanding `getPixel()` per-pixel.
///
/// Format model yang didukung:
///   - File   : `assets/models/yolov8n_float32.tflite` (default)
///   - Input  : float32 [1, 640, 640, 3], normalisasi 0..1, urutan RGB
///   - Output : float32 [1, 84, 8400]  (4 box + 80 kelas, format YOLOv8)
class YoloDetector {
  YoloDetector({
    this.modelAsset = 'assets/models/yolov8n_float32.tflite',
    this.labelsAsset = 'assets/labels.txt',
    this.confidenceThreshold = 0.35,
    this.iouThreshold = 0.45,
    this.inputSize = 640,
  });

  final String modelAsset;
  final String labelsAsset;
  final double confidenceThreshold;
  final double iouThreshold;
  final int inputSize;

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  List<String> _labels = const [];
  late int _numClasses;
  late int _numAnchors;

  bool get isReady => _isolateInterpreter != null;
  List<String> get labels => _labels;

  /// Load model + labels. Panggil sekali sebelum [detect].
  Future<void> loadModel() async {
    // 1. Labels
    final raw = await rootBundle.loadString(labelsAsset);
    _labels = raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // 2. Interpreter "biasa" — hanya dipakai untuk membaca metadata tensor.
    final options = InterpreterOptions()..threads = 4;
    try {
      _interpreter = await Interpreter.fromAsset(
        modelAsset,
        options: options,
      );
    } catch (e) {
      throw Exception(
        'Gagal memuat model TFLite dari "$modelAsset". '
        'Pastikan file model sudah ada di folder assets/models/ '
        'dan terdaftar di pubspec.yaml. Detail: $e',
      );
    }

    // 3. Cek shape output untuk menentukan jumlah kelas & anchor.
    final outShape = _interpreter!.getOutputTensor(0).shape;
    if (outShape.length != 3) {
      throw Exception(
        'Bentuk output model tidak dikenal: $outShape. '
        'Diharapkan [1, 4+numClasses, numAnchors].',
      );
    }
    _numClasses = outShape[1] - 4;
    _numAnchors = outShape[2];

    // 4. Bungkus interpreter dengan IsolateInterpreter supaya `run()` async
    //    dan dieksekusi di isolate terpisah — thread UI tidak ter-block.
    _isolateInterpreter = await IsolateInterpreter.create(
      address: _interpreter!.address,
    );
  }

  /// Tutup interpreter & isolate.
  Future<void> dispose() async {
    await _isolateInterpreter?.close();
    _interpreter?.close();
    _isolateInterpreter = null;
    _interpreter = null;
  }

  /// Jalankan deteksi pada [image].
  ///
  /// Mengembalikan list [Detection] dengan koordinat box ternormalisasi
  /// (0..1) relatif terhadap ukuran [image] aslinya.
  Future<List<Detection>> detect(img.Image image) async {
    final isolateInterp = _isolateInterpreter;
    if (isolateInterp == null) {
      throw StateError('Interpreter belum di-load. Panggil loadModel() dulu.');
    }

    // === 1. Letterbox resize ke 640×640 (jaga aspect ratio) ===
    final letterboxed = _letterbox(image, inputSize);

    // === 2. Konversi ke Float32 [1, 640, 640, 3], normalisasi 0..1 ===
    final inputBuffer = _imageToFloat32(letterboxed.image);
    final input = inputBuffer.reshape([1, inputSize, inputSize, 3]);

    // === 3. Siapkan output buffer ===
    final output = List.generate(
      1,
      (_) => List.generate(
        4 + _numClasses,
        (_) => List<double>.filled(_numAnchors, 0),
      ),
    );

    // === 4. Inference ASYNC di worker isolate (non-blocking UI) ===
    await isolateInterp.run(input, output);

    // === 5. Parse output → list Detection sebelum NMS ===
    final raw = <_RawDet>[];
    final result = output[0];
    for (int i = 0; i < _numAnchors; i++) {
      double bestScore = 0;
      int bestClass = -1;
      for (int c = 0; c < _numClasses; c++) {
        final s = result[4 + c][i];
        if (s > bestScore) {
          bestScore = s;
          bestClass = c;
        }
      }
      if (bestScore < confidenceThreshold || bestClass < 0) continue;

      final cx = result[0][i];
      final cy = result[1][i];
      final w = result[2][i];
      final h = result[3][i];

      raw.add(_RawDet(
        x1: cx - w / 2,
        y1: cy - h / 2,
        x2: cx + w / 2,
        y2: cy + h / 2,
        score: bestScore,
        classId: bestClass,
      ));
    }

    // === 6. Non-Max Suppression ===
    final kept = _nms(raw, iouThreshold);

    // === 7. Map ke koordinat citra asli, normalisasi 0..1 ===
    final detections = <Detection>[];
    for (final r in kept) {
      final origRect = _unletterbox(
        Rect.fromLTRB(r.x1, r.y1, r.x2, r.y2),
        letterboxed.scale,
        letterboxed.padX,
        letterboxed.padY,
        image.width,
        image.height,
      );

      final normalized = Rect.fromLTRB(
        (origRect.left / image.width).clamp(0.0, 1.0),
        (origRect.top / image.height).clamp(0.0, 1.0),
        (origRect.right / image.width).clamp(0.0, 1.0),
        (origRect.bottom / image.height).clamp(0.0, 1.0),
      );

      final label = r.classId < _labels.length ? _labels[r.classId] : '?';
      detections.add(Detection(
        box: normalized,
        classId: r.classId,
        label: label,
        score: r.score,
        category: WasteClassifier.classify(label),
      ));
    }

    return detections;
  }

  // ------------------------- Preprocessing helpers -------------------------

  _LetterboxResult _letterbox(img.Image src, int targetSize) {
    final iw = src.width;
    final ih = src.height;
    final scale = math.min(targetSize / iw, targetSize / ih);
    final nw = (iw * scale).round();
    final nh = (ih * scale).round();
    final padX = ((targetSize - nw) / 2).floor();
    final padY = ((targetSize - nh) / 2).floor();

    final resized = img.copyResize(
      src,
      width: nw,
      height: nh,
      interpolation: img.Interpolation.linear,
    );

    final canvas = img.Image(width: targetSize, height: targetSize);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    return _LetterboxResult(
      image: canvas,
      scale: scale,
      padX: padX.toDouble(),
      padY: padY.toDouble(),
    );
  }

  Rect _unletterbox(
    Rect r,
    double scale,
    double padX,
    double padY,
    int origW,
    int origH,
  ) {
    final x1 = (r.left - padX) / scale;
    final y1 = (r.top - padY) / scale;
    final x2 = (r.right - padX) / scale;
    final y2 = (r.bottom - padY) / scale;
    return Rect.fromLTRB(
      x1.clamp(0.0, origW.toDouble()),
      y1.clamp(0.0, origH.toDouble()),
      x2.clamp(0.0, origW.toDouble()),
      y2.clamp(0.0, origH.toDouble()),
    );
  }

  /// Konversi `img.Image` (RGB) → Float32List ternormalisasi 0..1.
  ///
  /// PENTING: pakai `getBytes()` untuk akses buffer flat — satu loop typed-list
  /// jauh lebih cepat dibanding `image.getPixel(x,y).r/.g/.b` per-pixel.
  /// Untuk 640×640 px, perbedaan kecepatan bisa ~10×.
  Float32List _imageToFloat32(img.Image image) {
    final bytes = image.getBytes(order: img.ChannelOrder.rgb);
    final buffer = Float32List(bytes.length);
    const inv255 = 1.0 / 255.0;
    for (int i = 0; i < bytes.length; i++) {
      buffer[i] = bytes[i] * inv255;
    }
    return buffer;
  }

  // ------------------------- NMS -------------------------

  List<_RawDet> _nms(List<_RawDet> dets, double iouThr) {
    dets.sort((a, b) => b.score.compareTo(a.score));
    final picked = <_RawDet>[];
    final suppressed = List<bool>.filled(dets.length, false);

    for (int i = 0; i < dets.length; i++) {
      if (suppressed[i]) continue;
      picked.add(dets[i]);
      for (int j = i + 1; j < dets.length; j++) {
        if (suppressed[j]) continue;
        if (dets[i].classId != dets[j].classId) continue;
        if (_iou(dets[i], dets[j]) > iouThr) {
          suppressed[j] = true;
        }
      }
    }
    return picked;
  }

  double _iou(_RawDet a, _RawDet b) {
    final ix1 = math.max(a.x1, b.x1);
    final iy1 = math.max(a.y1, b.y1);
    final ix2 = math.min(a.x2, b.x2);
    final iy2 = math.min(a.y2, b.y2);
    final iw = math.max(0.0, ix2 - ix1);
    final ih = math.max(0.0, iy2 - iy1);
    final inter = iw * ih;
    final areaA = math.max(0.0, a.x2 - a.x1) * math.max(0.0, a.y2 - a.y1);
    final areaB = math.max(0.0, b.x2 - b.x1) * math.max(0.0, b.y2 - b.y1);
    final union = areaA + areaB - inter;
    if (union <= 0) return 0;
    return inter / union;
  }
}

class _LetterboxResult {
  final img.Image image;
  final double scale;
  final double padX;
  final double padY;
  _LetterboxResult({
    required this.image,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}

class _RawDet {
  final double x1, y1, x2, y2;
  final double score;
  final int classId;
  _RawDet({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
    required this.classId,
  });
}
