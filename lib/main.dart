import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/screens/dashboard_screen.dart';

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
      debugShowCheckedModeBanner: false,
      home: const DashboardScreen(),
    );
  }
}
