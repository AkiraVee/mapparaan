import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MapparaanApp());
}

class MapparaanApp extends StatelessWidget {
  const MapparaanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mapparaan',
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}