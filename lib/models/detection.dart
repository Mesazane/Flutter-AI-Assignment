import 'dart:ui';

import 'waste_category.dart';

/// Hasil deteksi 1 objek dari YOLO.
class Detection {
  /// Bounding box dalam koordinat input model (0..1, relatif terhadap frame).
  final Rect box;

  /// Indeks kelas hasil deteksi.
  final int classId;

  /// Nama label asli (mis. "bottle").
  final String label;

  /// Skor confidence (0..1).
  final double score;

  /// Hasil mapping label → kategori sampah Indonesia.
  final WasteCategory category;

  Detection({
    required this.box,
    required this.classId,
    required this.label,
    required this.score,
    required this.category,
  });

  @override
  String toString() =>
      '$label (${(score * 100).toStringAsFixed(1)}%) → ${category.label}';
}
