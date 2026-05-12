import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

/// Daftar kamera yang tersedia di device (diisi sekali saat startup).
late List<CameraDescription> availableCamerasList;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enumerasi kamera di awal supaya tidak blocking saat user buka screen.
  try {
    availableCamerasList = await availableCameras();
  } catch (e) {
    availableCamerasList = const [];
    debugPrint('Gagal mengambil daftar kamera: $e');
  }

  runApp(const EcoSortApp());
}

class EcoSortApp extends StatelessWidget {
  const EcoSortApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoSort AI - Pemilah Sampah',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
