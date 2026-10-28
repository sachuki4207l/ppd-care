import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const PpdCareApp());
}

class PpdCareApp extends StatelessWidget {
  const PpdCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PPD Care',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF527C73)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
