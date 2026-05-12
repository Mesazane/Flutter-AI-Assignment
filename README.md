# EcoSort AI — Flutter Edge AI Waste Sorter

## Screenshot:
<img width="1440" height="3088" alt="Screenshot_20260512_090308" src="https://github.com/user-attachments/assets/e73e449e-cd24-4a80-b0e8-21c9ae85048f" />
<img width="3088" height="1440" alt="Screenshot_20260512_090519" src="https://github.com/user-attachments/assets/05619a3a-b5a6-4da0-ba21-b810cfc94f5d" />


Aplikasi Flutter yang memakai **YOLO (TensorFlow Lite)** secara **lokal di
perangkat (edge computing)** untuk mengenali objek lewat kamera dan
mengklasifikasikannya ke dalam **3 kategori sampah Indonesia**:

| Kategori | Warna | Contoh |
| --- | --- | --- |
| Organik | hijau | sisa makanan, buah, sayur |
| Anorganik | biru | plastik, kaca, kertas, logam |
| B3 (Bahan Berbahaya & Beracun) | merah | elektronik, baterai, bola lampu |

Tidak ada data yang dikirim ke server — inferensi 100% di HP.

## Arsitektur

```
lib/
├── main.dart                  # entry point + enumerasi kamera
├── models/
│   ├── detection.dart         # representasi 1 hasil deteksi
│   └── waste_category.dart    # enum 3 kategori + mapping label → kategori
├── services/
│   └── yolo_detector.dart     # load TFLite, letterbox, NMS, post-process
├── utils/
│   └── image_converter.dart   # YUV420/BGRA → image.Image
├── widgets/
│   ├── bounding_box_painter.dart
│   └── category_legend.dart
└── screens/
    ├── home_screen.dart       # landing page + legend
    └── camera_screen.dart     # live kamera + overlay deteksi
```

## Cara menjalankan

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Siapkan model YOLO

Kamu **wajib** menambahkan file model TFLite sendiri — file ini tidak ikut
dalam repository karena ukurannya besar.

Cara paling cepat (Python 3.10+):

```bash
pip install ultralytics
```

```python
from ultralytics import YOLO
YOLO("yolov8n.pt").export(format="tflite", imgsz=640)
```

Salin hasilnya:

```
runs/detect/.../weights/yolov8n_float32.tflite
        ↓
assets/models/yolov8n_float32.tflite
```

Detail lebih lengkap (termasuk cara training custom dataset sampah) ada
di `assets/models/README.md`.

### 3. Jalankan di Android

```bash
flutter run
```

> Minimal Android SDK 24. Hidupkan USB debugging atau jalankan di emulator
> dengan kamera virtual aktif.

## Cara kerja singkat

1. **Camera plugin** men-stream frame dari kamera belakang dalam format YUV420.
2. Tiap frame dikonversi ke RGB pakai `image_converter.dart`.
3. Frame di-**letterbox** ke 640×640 (jaga aspect ratio, padding abu-abu)
   dan dinormalisasi 0..1.
4. **TFLite Interpreter** (`tflite_flutter`) menjalankan inferensi —
   output: tensor `[1, 84, 8400]`.
5. Output di-decode (cx,cy,w,h → x1,y1,x2,y2), difilter dengan
   confidence threshold, lalu di-**NMS** untuk membuang box duplikat.
6. Setiap label COCO (mis. `bottle`, `apple`, `cell phone`) dipetakan ke
   **Organik / Anorganik / B3** lewat tabel di `waste_category.dart`.
7. Bounding box digambar di atas `CameraPreview` dengan `CustomPainter`.

## Kustomisasi

- **Ganti threshold**: edit `confidenceThreshold` & `iouThreshold` di
  `YoloDetector()` (default 0.35 dan 0.45).
- **Tambah/ubah kelas sampah**: edit map `_labelToCategory` di
  `lib/models/waste_category.dart`.
- **Pakai model custom**: ekspor `.tflite` kamu, taruh di `assets/models/`,
  dan ganti `modelAsset` / `labelsAsset` di constructor `YoloDetector`.

## Catatan performa

- Resolusi kamera dipasang `ResolutionPreset.medium` untuk seimbang
  antara akurasi dan FPS.
- Frame baru di-drop selama frame sebelumnya masih diproses
  (lihat `_isDetecting` di `camera_screen.dart`) — mencegah backlog.
- Untuk meningkatkan FPS, kamu bisa: pakai model `yolov8n` (sudah default),
  ekspor model ke `int8` quantization, atau pindahkan preprocessing ke
  `Isolate` (TODO).

## Lisensi

Lisensi model dan label mengikuti lisensi Ultralytics YOLO & dataset COCO.
Kode aplikasi ini bebas dipakai untuk keperluan tugas / pembelajaran.
