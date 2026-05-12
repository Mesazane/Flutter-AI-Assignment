import 'package:flutter/material.dart';

/// Tiga kategori sampah sesuai standar pemilahan di Indonesia.
enum WasteCategory {
  organik,
  anorganik,
  b3,
  unknown,
}

extension WasteCategoryX on WasteCategory {
  String get label {
    switch (this) {
      case WasteCategory.organik:
        return 'Organik';
      case WasteCategory.anorganik:
        return 'Anorganik';
      case WasteCategory.b3:
        return 'B3';
      case WasteCategory.unknown:
        return 'Tidak Dikenal';
    }
  }

  String get description {
    switch (this) {
      case WasteCategory.organik:
        return 'Sisa makanan, daun, kayu — bisa dijadikan kompos.';
      case WasteCategory.anorganik:
        return 'Plastik, kertas, logam, kaca — bisa didaur ulang.';
      case WasteCategory.b3:
        return 'Bahan Berbahaya & Beracun (baterai, elektronik, bola lampu).';
      case WasteCategory.unknown:
        return 'Objek belum dapat diklasifikasikan.';
    }
  }

  /// Warna bounding-box & chip kategori.
  Color get color {
    switch (this) {
      case WasteCategory.organik:
        return const Color(0xFF43A047); // hijau
      case WasteCategory.anorganik:
        return const Color(0xFF1E88E5); // biru
      case WasteCategory.b3:
        return const Color(0xFFE53935); // merah
      case WasteCategory.unknown:
        return const Color(0xFF757575); // abu-abu
    }
  }

  IconData get icon {
    switch (this) {
      case WasteCategory.organik:
        return Icons.eco;
      case WasteCategory.anorganik:
        return Icons.recycling;
      case WasteCategory.b3:
        return Icons.warning_amber_rounded;
      case WasteCategory.unknown:
        return Icons.help_outline;
    }
  }
}

/// Mapping label COCO (yolov8 default) → kategori sampah.
///
/// Kalau kamu sudah melatih model custom dengan kelas-kelas sampah sendiri,
/// kamu bisa ganti seluruh map ini supaya nama kelas custom kamu langsung
/// dipetakan ke kategori yang tepat.
class WasteClassifier {
  static const Map<String, WasteCategory> _labelToCategory = {
    // ------ ORGANIK ------
    'banana': WasteCategory.organik,
    'apple': WasteCategory.organik,
    'orange': WasteCategory.organik,
    'broccoli': WasteCategory.organik,
    'carrot': WasteCategory.organik,
    'sandwich': WasteCategory.organik,
    'hot dog': WasteCategory.organik,
    'pizza': WasteCategory.organik,
    'donut': WasteCategory.organik,
    'cake': WasteCategory.organik,

    // ------ ANORGANIK ------
    'bottle': WasteCategory.anorganik,
    'wine glass': WasteCategory.anorganik,
    'cup': WasteCategory.anorganik,
    'fork': WasteCategory.anorganik,
    'knife': WasteCategory.anorganik,
    'spoon': WasteCategory.anorganik,
    'bowl': WasteCategory.anorganik,
    'book': WasteCategory.anorganik,
    'vase': WasteCategory.anorganik,
    'scissors': WasteCategory.anorganik,
    'backpack': WasteCategory.anorganik,
    'handbag': WasteCategory.anorganik,
    'suitcase': WasteCategory.anorganik,

    // ------ B3 ------
    'cell phone': WasteCategory.b3,
    'laptop': WasteCategory.b3,
    'tv': WasteCategory.b3,
    'remote': WasteCategory.b3,
    'mouse': WasteCategory.b3,
    'keyboard': WasteCategory.b3,
    'microwave': WasteCategory.b3,
    'toaster': WasteCategory.b3,
    'refrigerator': WasteCategory.b3,
    'hair drier': WasteCategory.b3,
    'oven': WasteCategory.b3,
  };

  /// Klasifikasikan nama label menjadi kategori sampah. Default ke `unknown`.
  static WasteCategory classify(String label) {
    return _labelToCategory[label.toLowerCase()] ?? WasteCategory.unknown;
  }
}
