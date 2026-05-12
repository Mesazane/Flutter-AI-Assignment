import 'package:flutter/material.dart';

import '../models/detection.dart';
import '../models/waste_category.dart';

/// Menggambar bounding-box hasil deteksi YOLO di atas preview kamera.
///
/// [detections] berisi box dalam koordinat ternormalisasi (0..1). Painter ini
/// akan men-skala-nya ke ukuran canvas. Param [rotateQuarterTurns] berguna
/// kalau frame dari kamera berorientasi berbeda dari preview.
class BoundingBoxPainter extends CustomPainter {
  final List<Detection> detections;

  BoundingBoxPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    for (final det in detections) {
      final rect = Rect.fromLTRB(
        det.box.left * size.width,
        det.box.top * size.height,
        det.box.right * size.width,
        det.box.bottom * size.height,
      );

      final color = det.category.color;

      // Box
      final boxPaint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect, boxPaint);

      // Label background
      final text = '${det.category.label} · ${det.label} '
          '${(det.score * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelBg = Rect.fromLTWH(
        rect.left,
        rect.top - tp.height - 6,
        tp.width + 12,
        tp.height + 6,
      );
      canvas.drawRect(labelBg, Paint()..color = color);
      tp.paint(canvas, Offset(rect.left + 6, rect.top - tp.height - 3));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
