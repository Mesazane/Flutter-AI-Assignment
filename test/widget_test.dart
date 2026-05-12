// Smoke test: pastikan home screen ter-render dengan benar.
//
// Catatan: kita TIDAK boot `EcoSortApp` di sini karena `main()` di runtime
// memanggil `availableCameras()` (channel kamera platform yang tidak ada di
// lingkungan test). Sebagai gantinya, kita render `HomeScreen` langsung.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_assignment/screens/home_screen.dart';

void main() {
  testWidgets('Home screen menampilkan judul & tombol mulai',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );

    expect(find.text('EcoSort AI'), findsOneWidget);
    expect(find.text('Mulai Deteksi Sampah'), findsOneWidget);
    expect(find.text('Organik'), findsOneWidget);
    expect(find.text('Anorganik'), findsOneWidget);
    expect(find.text('B3'), findsOneWidget);
  });
}
