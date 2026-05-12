import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Konversi [CameraImage] (output dari kamera Android, format YUV420) menjadi
/// [img.Image] RGB yang siap diumpankan ke YOLO.
///
/// Hanya YUV420 (Android default) yang didukung di sini. Kalau platform iOS
/// dipakai, format-nya adalah BGRA8888 — fungsi kedua di bawah menanganinya.
img.Image cameraImageToImage(CameraImage image) {
  switch (image.format.group) {
    case ImageFormatGroup.yuv420:
      return _yuv420ToImage(image);
    case ImageFormatGroup.bgra8888:
      return _bgra8888ToImage(image);
    default:
      throw UnsupportedError(
        'Format kamera tidak didukung: ${image.format.group}',
      );
  }
}

img.Image _yuv420ToImage(CameraImage image) {
  final width = image.width;
  final height = image.height;

  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final yBuffer = yPlane.bytes;
  final uBuffer = uPlane.bytes;
  final vBuffer = vPlane.bytes;

  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  final out = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
      final yIndex = y * yRowStride + x;

      final yp = yBuffer[yIndex];
      final up = uBuffer[uvIndex];
      final vp = vBuffer[uvIndex];

      // BT.601 YUV→RGB
      int r = (yp + 1.402 * (vp - 128)).round();
      int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round();
      int b = (yp + 1.772 * (up - 128)).round();

      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);

      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

img.Image _bgra8888ToImage(CameraImage image) {
  final plane = image.planes[0];
  return img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: plane.bytes.buffer,
    order: img.ChannelOrder.bgra,
  );
}
