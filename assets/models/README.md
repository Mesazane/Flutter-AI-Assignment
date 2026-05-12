# Folder Model YOLO

Folder ini menampung file model TFLite yang dipakai aplikasi.

## File yang harus ada

```
assets/models/yolov8n_float32.tflite
```

(Nama file dirujuk di `lib/services/yolo_detector.dart` — kalau kamu pakai nama lain, ubah parameter `modelAsset` di sana.)

## Cara mendapatkan file model

### Opsi 1 — Export sendiri dari Ultralytics (paling fleksibel)

Butuh Python 3.10+.

```bash
pip install ultralytics
```

```python
from ultralytics import YOLO

# 1. Load model pre-trained (nano = paling ringan, cocok untuk HP)
model = YOLO("yolov8n.pt")

# 2. Export ke TFLite float32
model.export(format="tflite", imgsz=640)
```

Hasilnya ada di `runs/detect/.../weights/yolov8n_float32.tflite`.
Salin file itu ke folder `assets/models/`.

### Opsi 2 — Download model pre-converted

Banyak repo di GitHub menyediakan `yolov8n.tflite` siap pakai (cari kata kunci
"yolov8 tflite flutter"). Pastikan modelnya:

- input: `[1, 640, 640, 3]` float32 ternormalisasi 0..1
- output: `[1, 84, 8400]` (4 box + 80 kelas COCO)

Kalau jumlah kelas berbeda dari 80, sesuaikan `assets/labels.txt`.

### Opsi 3 — Custom training (untuk dataset sampah)

Train YOLO dengan dataset sampah seperti TACO, TrashNet, atau dataset
sendiri (anotasi pakai Roboflow / CVAT).

```python
model = YOLO("yolov8n.pt")
model.train(data="data.yaml", epochs=50, imgsz=640)
model.export(format="tflite", imgsz=640)
```

Lalu ganti isi `assets/labels.txt` dengan urutan kelas dataset kamu, dan
perbarui mapping di `lib/models/waste_category.dart` supaya tiap kelas
custom langsung dipetakan ke Organik / Anorganik / B3.
