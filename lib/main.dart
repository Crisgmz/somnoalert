import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/drowsy/view/drowsy_page.dart';

void main() {
  runApp(const ProviderScope(child: DrowsyApp()));
}

class DrowsyApp extends StatelessWidget {
  const DrowsyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Somnoalert',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF404C8C),
        useMaterial3: true,
      ),
      home: const DrowsyPage(),
    );
  }
}
