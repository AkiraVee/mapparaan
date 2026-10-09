import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MapparaanApp());
}

class MapparaanApp extends StatelessWidget {
  final bool enableMap;

  const MapparaanApp({
    super.key,
    this.enableMap = true,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mapparaan',
      debugShowCheckedModeBanner: false,
      home: enableMap ? const HomeScreen() : const _TestHomePlaceholder(),
    );
  }
}

class _TestHomePlaceholder extends StatelessWidget {
  const _TestHomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Mapparaan'),
      ),
    );
  }
}